import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../providers/nvr_provider.dart';
import '../models/nvr_model.dart';
import '../utils/rtsp_helper.dart';
import '../services/recording_service.dart';
import '../services/hikvision_service.dart';
import '../widgets/advanced_seeker.dart';
import '../widgets/recording_calendar.dart';
import '../providers/task_provider.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final RecordingService _recordingService = RecordingService();

  NvrGroupModel? _selectedNvr;
  int _selectedChannel = 1;
  DateTime _startDate = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _endDate = DateTime.now();

  bool _isLoading = false;
  String? _errorMessage;
  bool _searchSuccess = false;
  bool _isPlaybackActive = false;
  List<RecordingSegment> _recordedSegments = [];
  bool _clipSearchLoading = false;
  bool _useLocalTime =
      false; // Use local time for RTSP parameters instead of UTC
  Set<int> _recordedDays = {};
  bool _isLoadingRecordings = false;

  // New: Persist search range for seeker global bounds
  DateTime? _searchStart;
  DateTime? _searchEnd;
  RecordingSegment? _activeSegment;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<NvrProvider>(context, listen: false);
    if (provider.selectedNvrId != null) {
      _selectedNvr = provider.nvrs.firstWhere(
        (n) => n.id == provider.selectedNvrId,
        orElse: () => provider.nvrs.isNotEmpty ? provider.nvrs.first : provider.nvrs.first, // Fallback if not found
      );
    } else if (provider.nvrs.isNotEmpty) {
      _selectedNvr = provider.nvrs.first;
    }
    
    if (_selectedNvr != null) {
      _loadRecordingAvailability();
    }
  }

  Future<void> _loadRecordingAvailability() async {
    if (_selectedNvr == null) return;
    setState(() => _isLoadingRecordings = true);
    try {
      final days = await HikvisionService.fetchRecordingAvailability(
        nvr: _selectedNvr!,
        channel: _selectedChannel,
        month: _startDate,
      );
      if (mounted) {
        setState(() {
          _recordedDays = days;
          _isLoadingRecordings = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRecordings = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _recordingService.stopRecording();
    super.dispose();
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    setState(() {
      _searchSuccess = false;
      _isPlaybackActive = false;
      _recordedSegments = [];
    });
  }

  Future<void> _startPlayback() async {
    if (_selectedNvr == null) return;

    setState(() {
      _isLoading = true;
      _clipSearchLoading = true;
      _errorMessage = null;
      _searchSuccess = false;
      _isPlaybackActive = false;
      _recordedSegments = [];
      // Initialize global search bounds for the seeker
      _searchStart = _startDate;
      _searchEnd = _endDate;
      _activeSegment = null;
    });

    try {
      // 1. Fetch actual recording chunks from NVR
      final segments = await HikvisionService.fetchRecordings(
        nvr: _selectedNvr!,
        channel: _selectedChannel,
        start: _startDate,
        end: _endDate,
      );

      if (!mounted) return;

      setState(() {
        _recordedSegments = segments;
        _isLoading = false;
        _clipSearchLoading = false;
        _searchSuccess = segments.isNotEmpty;
        if (!_searchSuccess) {
          _errorMessage = "No recordings found for the selected time range.";
        }
      });

      // 2. Automatically play the first segment found for immediate feedback
      if (segments.isNotEmpty && mounted) {
        _playSegment(segments.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _clipSearchLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _playSegment(RecordingSegment segment) async {
    setState(() => _isLoading = true);

    final url = RtspHelper.getPlaybackUrl(
      nvr: _selectedNvr!,
      channel: _selectedChannel,
      start: segment.start,
      end: segment.end,
      useLocalTime: _useLocalTime,
    );

    try {
      if (_player.platform is NativePlayer) {
        await (_player.platform as NativePlayer).setProperty(
          'rtsp_transport',
          'tcp',
        );
      }
      await _player.open(Media(url));
      await _player.play();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaybackActive = true;
          _activeSegment = segment;
          // DON'T synchronize _startDate/_endDate here, we want to keep global seeker bounds
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Playback failed: $e";
        });
      }
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? _startDate : _endDate),
      initialEntryMode: TimePickerEntryMode.dial,
    );

    if (time == null) return;

    if (!mounted) return;
    setState(() {
      final newDt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        final bool monthChanged =
            date.month != _startDate.month || date.year != _startDate.year;
        _startDate = newDt;
        if (monthChanged) {
          _loadRecordingAvailability();
        }
      } else {
        _endDate = newDt;
      }
    });
  }

  Future<void> _pickOnlyTime(bool isStart) async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(isStart ? _startDate : _endDate),
      initialEntryMode: TimePickerEntryMode.dial,
    );

    if (time == null) return;

    setState(() {
      final old = isStart ? _startDate : _endDate;
      final newDt = DateTime(
        old.year,
        old.month,
        old.day,
        time.hour,
        time.minute,
      );
      if (isStart)
        _startDate = newDt;
      else
        _endDate = newDt;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: AppBar(
        title: const Text('Playback Control'),
        backgroundColor: const Color(0xFF252538),
        actions: [
          if (isMobile)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.search, color: Colors.blueAccent),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                tooltip: 'Search Recordings',
              ),
            ),
          if (_recordingService.isRecording)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.circle, color: Colors.red, size: 12),
            ),
        ],
      ),
      endDrawer: isMobile ? Drawer(child: _buildExpandedSidebar(isDrawer: true)) : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(child: _buildPlayerArea()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return _buildExpandedSidebar();
  }


  Widget _buildExpandedSidebar({bool isDrawer = false}) {
    return Container(
      width: isDrawer ? null : 300,
      decoration: const BoxDecoration(
        color: Color(0xFF161621),
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'SEARCH PARAMETERS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdowns(),
                  const SizedBox(height: 24),
                  _buildTimePickers(),
                  const SizedBox(height: 24),
                  _buildSearchButton(context),
                  const SizedBox(height: 24),
                  _buildAdvancedOptions(),
                  if (_searchSuccess && _recordedSegments.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildRecordingClips(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingClips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECORDED CLIPS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recordedSegments.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final segment = _recordedSegments[index];
            final duration = segment.end.difference(segment.start);
            final durationStr =
                "${duration.inMinutes}m ${duration.inSeconds % 60}s";

            return InkWell(
              onTap: () => _playSegment(segment),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.movie_creation_outlined,
                        color: Colors.blueAccent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('HH:mm:ss').format(segment.start),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Duration: $durationStr",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white24,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDropdowns() {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
    );

    return Column(
      children: [
        // Show Currently Selected NVR instead of a dropdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACTIVE DEVICE',
                style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedNvr?.name ?? 'No Device Selected',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _selectedChannel,
          disabledHint: Text(
            'Channel $_selectedChannel',
            style: const TextStyle(color: Colors.grey),
          ),
          dropdownColor: const Color(0xFF1E1E2C),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: inputDecoration.copyWith(labelText: 'Camera Channel'),
          items:
              List.generate(_selectedNvr?.numberOfChannels ?? 1, (i) => i + 1)
                  .map(
                    (c) =>
                        DropdownMenuItem(value: c, child: Text('Channel $c')),
                  )
                  .toList(),
          onChanged: _searchSuccess
              ? null
              : (c) => setState(() {
                  _selectedChannel = c!;
                  _loadRecordingAvailability();
                }),
        ),
      ],
    );
  }

  Widget _buildTimePickers() {
    return Column(
      children: [
        RecordingCalendar(
          selectedDate: _startDate,
          recordedDays: _recordedDays,
          isLoading: _isLoadingRecordings,
          onDateSelected: (date) {
            setState(() {
              _startDate = DateTime(
                date.year,
                date.month,
                date.day,
                _startDate.hour,
                _startDate.minute,
              );
              _endDate = DateTime(
                date.year,
                date.month,
                date.day,
                _endDate.hour,
                _endDate.minute,
              );
            });
          },
          onMonthChanged: (month) {
            if (_selectedNvr == null) return;
            // Need to fetch availability for the new month view
            HikvisionService.fetchRecordingAvailability(
              nvr: _selectedNvr!,
              channel: _selectedChannel,
              month: month,
            ).then((days) {
              if (mounted) setState(() => _recordedDays = days);
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildTimeTileSmall('START', _startDate, true)),
            const SizedBox(width: 8),
            Expanded(child: _buildTimeTileSmall('END', _endDate, false)),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeTileSmall(String title, DateTime dt, bool isStart) {
    return InkWell(
      onTap: _searchSuccess ? null : () => _pickOnlyTime(isStart),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('HH:mm').format(dt),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile(String title, DateTime dt, bool isStart) {
    return InkWell(
      onTap: _searchSuccess ? null : () => _pickDateTime(isStart),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _searchSuccess
              ? Colors.white.withOpacity(0.01)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _searchSuccess ? Colors.transparent : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  RtspHelper.formatDateTime(dt),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const Icon(
                  Icons.calendar_month,
                  color: Colors.blueAccent,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          shadowColor: Colors.blueAccent.withOpacity(0.3),
        ),
        onPressed: _isLoading 
            ? null 
            : () {
                _startPlayback();
              },
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.search_rounded, size: 28),
        label: Text(
          _isLoading ? 'SEARCHING...' : 'SEARCH',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchSuccess)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stop playback to change settings',
                    style: TextStyle(
                      color: Colors.orangeAccent.withOpacity(0.8),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'ADVANCED SETTINGS',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        _buildCheckboxTile(
          'Sync with NVR Local Time',
          'Leave CHECKED to fix 6.5h shift (Myanmar/S.E.A)',
          _useLocalTime,
          (v) => setState(() => _useLocalTime = v ?? false),
        ),
        if (!_useLocalTime)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Warning: Unchecking this may cause a 6.5-hour time shift in playback.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildCheckboxTile(
    String title,
    String sub,
    bool val,
    Function(bool?) onCh,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CheckboxListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        subtitle: Text(
          sub,
          style: const TextStyle(color: Colors.white24, fontSize: 9),
        ),
        value: val,
        onChanged: _searchSuccess ? null : onCh,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _speedButton(1),
              const SizedBox(width: 8),
              _speedButton(2),
              const SizedBox(width: 8),
              _speedButton(4),
              const SizedBox(width: 8),
              _speedButton(8),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                icon: _recordingService.isRecording
                    ? Icons.stop
                    : Icons.fiber_manual_record,
                label: _recordingService.isRecording ? 'STOP' : 'REC',
                onPressed: () async {
                  if (_recordingService.isRecording) {
                    await _recordingService.stopRecording();
                  } else {
                    if (_selectedNvr == null) return;
                    final url = RtspHelper.getPlaybackUrl(
                      nvr: _selectedNvr!,
                      channel: _selectedChannel,
                      start: _startDate,
                      end: _endDate,
                    );
                    final provider = Provider.of<NvrProvider>(context, listen: false);
                    await _recordingService.startRecording(url, customPath: provider.recordingPath);
                  }
                  if (mounted) setState(() {});
                },
                color: _recordingService.isRecording
                    ? Colors.red
                    : Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlineButton(
            icon: Icons.download_rounded,
            label: 'DOWNLOAD CLIP',
            onPressed: () {
              if (_selectedNvr == null) return;
              final url = RtspHelper.getPlaybackUrl(
                nvr: _selectedNvr!,
                channel: _selectedChannel,
                start: _startDate,
                end: _endDate,
              );
              final timeRange =
                  "${DateFormat('HH:mm').format(_startDate)} - ${DateFormat('HH:mm').format(_endDate)}";
              Provider.of<TaskProvider>(context, listen: false).addTask(
                "${_selectedNvr!.name} Ch$_selectedChannel",
                timeRange,
                url,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Download task added to queue')),
              );
            },
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _speedButton(double speed) {
    bool isSel = _player.state.rate == speed;
    return InkWell(
      onTap: () => setState(() => _player.setRate(speed)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? Colors.blueAccent : Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${speed.toInt()}x',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildPlayerArea() {
    return Column(children: [_buildVideoArea(), _buildAdvancedSeekerRow()]);
  }

  Widget _buildVideoArea() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isPlaybackActive ||
                _player.state.playing ||
                _player.state.duration != Duration.zero)
              Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: BoxFit.fill,
              )
            else
              _buildPlaceholder(),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 16),
                      Text(
                        'Preparing Stream...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _errorMessage != null
                ? Icons.error_outline
                : Icons.slow_motion_video_rounded,
            size: 80,
            color: _errorMessage != null
                ? Colors.redAccent.withOpacity(0.5)
                : Colors.white10,
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else if (!_searchSuccess)
            const Text(
              'Select Date & Channel then click SEARCH\nto browse footage',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 16),
            )
          else
            Column(
              children: [
                const Text(
                  'Recordings Found',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_recordedSegments.length} clips available in the selected range',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _playSegment(_recordedSegments.first),
                  icon: const Icon(Icons.play_circle_filled_rounded),
                  label: const Text('PLAY FIRST CLIP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _getWallClockTime(Duration pos) {
    if (_activeSegment != null) {
      final wallTime = _activeSegment!.start.add(pos);
      return DateFormat('HH:mm:ss').format(wallTime);
    }
    final wallTime = (_searchStart ?? _startDate).add(pos);
    return DateFormat('HH:mm:ss').format(wallTime);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return hours == "00" ? "$minutes:$seconds" : "$hours:$minutes:$seconds";
  }

  Widget _buildAdvancedSeekerRow() {
    if (!_searchSuccess) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161621),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              const SizedBox(height: 60), // Space for floating bubble
              AdvancedSeeker(
                player: _player,
                events: _recordedSegments,
                startTime: _searchStart ?? _startDate,
                endTime: _searchEnd ?? _endDate,
                activeSegment: _activeSegment,
                onSeekUpdate: _onSeekUpdate,
                onHoverUpdate: _onHoverUpdate,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  builder: (context, snapshot) {
                    final pos = snapshot.data ?? Duration.zero;
                    final dur = _player.state.duration;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              _getWallClockTime(pos),
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(Rel: ${_formatDuration(pos)})',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _formatDuration(dur),
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.replay_10,
                      color: Colors.white70,
                      size: 24,
                    ),
                    onPressed: () => _player.seek(
                      _player.state.position - const Duration(seconds: 10),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _controlButton(
                    icon: Icons.pause_rounded,
                    color: _player.state.playing
                        ? Colors.orangeAccent
                        : Colors.white24,
                    onPressed: () async {
                      await _player.pause();
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  _controlButton(
                    icon: Icons.play_arrow_rounded,
                    color: !_player.state.playing
                        ? Colors.blueAccent
                        : Colors.white24,
                    size: 56,
                    onPressed: () async {
                      if (_player.state.duration == Duration.zero) {
                        await _startPlayback();
                      } else {
                        await _player.play();
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  _controlButton(
                    icon: Icons.stop_rounded,
                    color: Colors.redAccent.withOpacity(0.8),
                    onPressed: _stopPlayback,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(
                      Icons.forward_10,
                      color: Colors.white70,
                      size: 24,
                    ),
                    onPressed: () => _player.seek(
                      _player.state.position + const Duration(seconds: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _buildPreviewWindow(),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 42,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: color, size: size * 0.6),
        onPressed: onPressed,
      ),
    );
  }

  Uint8List? _previewImage;
  String _previewTime = "";
  Offset _hoverOffset = Offset.zero;
  bool _showPreview = false;
  DateTime? _lastFetchTime;

  Widget _buildPreviewWindow() {
    if (!_showPreview || _previewImage == null) return const SizedBox.shrink();

    const double bubbleWidth = 160;
    const double bubbleHeight = 110;

    // Position the bubble horizontally centered on the hover offset
    return Positioned(
      top: -40, // Float above the seeker bar
      left: _hoverOffset.dx - (bubbleWidth / 2),
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 90,
              width: bubbleWidth,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.8),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
                image: DecorationImage(
                  image: MemoryImage(_previewImage!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                _previewTime,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onHoverUpdate(double relativePosition, Offset offset) async {
    if (relativePosition < 0) {
      setState(() => _showPreview = false);
      return;
    }

    // Calculate actual time at this position
    final start = _searchStart ?? _startDate;
    final end = _searchEnd ?? _endDate;
    final totalRange = end.difference(start);
    final hoverTime = start.add(totalRange * relativePosition);
    final timeStr = DateFormat('HH:mm:ss').format(hoverTime);

    setState(() {
      _previewTime = timeStr;
      _hoverOffset = offset;
      _showPreview = true;
    });

    // Throttle snapshot fetching (max once per 500ms)
    final now = DateTime.now();
    if (_lastFetchTime == null ||
        now.difference(_lastFetchTime!).inMilliseconds > 500) {
      _lastFetchTime = now;
      if (_selectedNvr != null) {
        final bytes = await HikvisionService.fetchSnapshot(
          nvr: _selectedNvr!,
          channel: _selectedChannel,
          time: hoverTime,
        );
        if (bytes != null && mounted) {
          setState(() => _previewImage = Uint8List.fromList(bytes));
        }
      }
    }
  }

  void _onSeekUpdate(double relativePosition) {
    if (relativePosition < 0) return;

    // 1. Update the floating bubble preview
    _onHoverUpdate(relativePosition, Offset.zero);

    // 2. Map global relative position to wall-clock time
    final start = _searchStart ?? _startDate;
    final end = _searchEnd ?? _endDate;
    final totalRange = end.difference(start);
    final seekTime = start.add(totalRange * relativePosition);

    // 3. Find the segment that contains this time
    RecordingSegment? targetSegment;
    for (var seg in _recordedSegments) {
      // Use a small buffer to handle boundary issues
      if (seekTime.isAfter(seg.start.subtract(const Duration(seconds: 1))) &&
          seekTime.isBefore(seg.end.add(const Duration(seconds: 1)))) {
        targetSegment = seg;
        break;
      }
    }

    if (targetSegment != null) {
      final offset = seekTime.difference(targetSegment.start);
      if (_activeSegment != null &&
          _activeSegment!.start == targetSegment.start &&
          _activeSegment!.end == targetSegment.end) {
        // Same segment, just seek
        _player.seek(offset);
      } else {
        // Different segment, switch and seek
        _playSegment(targetSegment).then((_) {
          _player.seek(offset);
        });
      }
    }
  }
}

class OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const OutlineButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.3)),
          backgroundColor: color.withOpacity(0.05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
