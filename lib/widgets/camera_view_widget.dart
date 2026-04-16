import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../models/camera_model.dart';
import '../models/nvr_model.dart';
import '../providers/nvr_provider.dart';
import '../services/recording_service.dart';
import '../utils/rtsp_helper.dart';
import 'isapi_image_viewer.dart';

class CameraViewWidget extends StatefulWidget {
  final CameraModel camera;

  const CameraViewWidget({super.key, required this.camera});

  @override
  _CameraViewWidgetState createState() => _CameraViewWidgetState();
}

class _CameraViewWidgetState extends State<CameraViewWidget> {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;
  String? _lastAttemptedUrl;
  final RecordingService _recordingService = RecordingService();

  int _lastPlaySignal = 0;
  int _lastStopSignal = 0;
  StreamQuality? _currentQuality;
  final TransformationController _transformationController =
      TransformationController();
  bool _isSoloMode = false;

  void _initPlayer() async {
    if (_isPlaying) return; // Already playing

    final provider = Provider.of<NvrProvider>(context, listen: false);
    final nvr = provider.nvrs.firstWhere((n) => n.id == widget.camera.nvrId);
    _currentQuality = provider.quality;

    // Auto-downgrade: use SMOOTH for grid view, HD only in solo/fullscreen.
    // This prevents overwhelming the network with 16 simultaneous HD streams.
    final isSoloNow = provider.selectedCameraId == widget.camera.id;
    final effectiveQuality = (!isSoloNow && _currentQuality == StreamQuality.hd)
        ? StreamQuality.smooth
        : _currentQuality!;

    final url = RtspHelper.getLiveUrl(
      nvr: nvr,
      channel: widget.camera.channelIndex + 1,
      quality: effectiveQuality,
    );

    final player = Player(configuration: const PlayerConfiguration());

    // mpv-specific options for RTSP stability and analog DVR compatibility
    try {
      if (player.platform is NativePlayer) {
        final platform = player.platform as NativePlayer;
        // Prioritize UDP for analog, but FORCE TCP for encrypted streams (Phase 10)
        final bool isEncrypted = widget.camera.url.contains(
          'verificationCode=',
        );
        await platform.setProperty(
          'rtsp_transport',
          isEncrypted ? 'tcp' : 'udp',
        );
        await platform.setProperty(
          'protocol_whitelist',
          'rtsp,rtp,udp,tcp,tls',
        );
        // Enforce at ffmpeg level
        await platform.setProperty(
          'ffmpeg-options',
          'rtsp_transport=${isEncrypted ? 'tcp' : 'udp'}',
        );
        await platform.setProperty('network-timeout', '30');
        await platform.setProperty('hwdec', 'no');
        await platform.setProperty('framedrop', 'vo');
        await platform.setProperty('vd-lavc-skiploopfilter', 'all');
        await platform.setProperty(
          'demuxer-max-bytes',
          '64000000',
        ); // Increase buffer to 64MB
        await platform.setProperty(
          'demuxer-readahead-secs',
          '10',
        ); // Analyze 10s of stream
        await platform.setProperty('demuxer-max-back-log', '1000000');
      }
    } catch (e) {
      debugPrint('MediaKit property error: $e');
    }

    final controller = VideoController(player);

    player.stream.error.listen((event) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = event;
      });
    });

    player.open(Media(url));
    player.play();
    debugPrint('RTSP Connection: $url');

    setState(() {
      _player = player;
      _controller = controller;
      _isPlaying = true;
      _hasError = false;
      _errorMessage = null;
      _lastAttemptedUrl = url;
    });
  }

  /// Shows a dialog prompting the user to enter a Stream Key.
  /// If [applyToAll] is checked, the key is saved to the NVR so all
  /// channels of that NVR will use it on reconnect.

  void _stopPlayer() {
    if (!_isPlaying) return;
    _recordingService.stopRecording();
    _player?.dispose();
    setState(() {
      _player = null;
      _controller = null;
      _isPlaying = false;
      _currentQuality = null;
    });
  }

  @override
  void dispose() {
    _recordingService.stopRecording();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to global signals
    final provider = Provider.of<NvrProvider>(context);
    final nvr = provider.nvrs.firstWhere((n) => n.id == widget.camera.nvrId);
    final isSolo = provider.selectedCameraId == widget.camera.id;

    // Auto-switch quality if it changes while playing
    if (_isPlaying && _currentQuality != provider.quality) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stopPlayer();
        _initPlayer();
      });
    }

    // Reset zoom if exiting solo mode
    if (_isSoloMode && !isSolo) {
      _transformationController.value = Matrix4.identity();
    }
    _isSoloMode = isSolo;

    // Detect batch play
    if (provider.globalPlaySignal > _lastPlaySignal) {
      _lastPlaySignal = provider.globalPlaySignal;
      WidgetsBinding.instance.addPostFrameCallback((_) => _initPlayer());
    }

    // Detect batch stop
    if (provider.globalStopSignal > _lastStopSignal) {
      _lastStopSignal = provider.globalStopSignal;
      WidgetsBinding.instance.addPostFrameCallback((_) => _stopPlayer());
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isSolo ? 0 : 4,
      margin: isSolo ? EdgeInsets.zero : const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isSolo ? 0 : 12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Stream Display
          Container(
            color: Colors.black,
            child: _isPlaying
                ? nvr.useSnapshot
                      ? IsapiImageViewer(
                          nvr: nvr,
                          channel: widget.camera.channelIndex + 1,
                          streamQuality: provider.quality,
                        )
                      : _buildStreamViewer()
                : _buildPlayOverlay(),
          ),

          // Technical Overlay (Diagnostics)
          if (_isPlaying && !isSolo && !_hasError)
            Positioned(bottom: 8, left: 8, child: _buildDiagnosticOverlay()),

          // Overlay UI - Camera Label & Controls
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLabel(provider.quality),
                if (_isPlaying)
                  Row(
                    children: [
                      // Quality Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: provider.quality == StreamQuality.hd
                              ? Colors.blueAccent
                              : Colors.greenAccent.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          provider.quality == StreamQuality.hd
                              ? 'HD'
                              : 'SMOOTH',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Record Button
                      IconButton(
                        icon: Icon(
                          _recordingService.isRecording
                              ? Icons.stop_circle
                              : Icons.fiber_manual_record,
                          color: _recordingService.isRecording
                              ? Colors.red
                              : Colors.white70,
                        ),
                        onPressed: () async {
                          if (_recordingService.isRecording) {
                            await _recordingService.stopRecording();
                          } else {
                            final nvr = provider.nvrs.firstWhere(
                              (n) => n.id == widget.camera.nvrId,
                            );
                            final url = RtspHelper.getLiveUrl(
                              nvr: nvr,
                              channel: widget.camera.channelIndex + 1,
                              quality: provider.quality,
                            );
                            await _recordingService.startRecording(url);
                          }
                          if (mounted) setState(() {});
                        },
                        tooltip: _recordingService.isRecording
                            ? 'Stop Recording'
                            : 'Start Recording',
                      ),
                      const SizedBox(width: 8),
                      // Zoom Controls (Only in Solo)
                      if (isSolo) ...[
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.white70),
                          onPressed: () {
                            final current = _transformationController.value;
                            _transformationController.value =
                                current *
                                Matrix4.diagonal3Values(1.2, 1.2, 1.0);
                          },
                          tooltip: 'Zoom In',
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove, color: Colors.white70),
                          onPressed: () {
                            final current = _transformationController.value;
                            _transformationController.value =
                                current *
                                Matrix4.diagonal3Values(0.8, 0.8, 1.0);
                          },
                          tooltip: 'Zoom Out',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.center_focus_strong,
                            color: Colors.white70,
                          ),
                          onPressed: () => _transformationController.value =
                              Matrix4.identity(),
                          tooltip: 'Reset Zoom',
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Exit Solo Button
                      if (isSolo)
                        IconButton(
                          icon: const Icon(
                            Icons.fullscreen_exit,
                            color: Colors.blueAccent,
                          ),
                          onPressed: () =>
                              provider.toggleSoloCamera(widget.camera.id),
                          tooltip: 'Exit Full Screen',
                        )
                      else
                        IconButton(
                          icon: const Icon(
                            Icons.stop_circle,
                            color: Colors.orangeAccent,
                          ),
                          onPressed: _stopPlayer,
                          tooltip: 'Stop Stream',
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(StreamQuality quality) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _isPlaying ? Colors.red : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.camera.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticOverlay() {
    return StreamBuilder(
      stream: _player!.stream.buffer,
      builder: (context, _) {
        final width = _player!.state.width;
        final height = _player!.state.height;

        if (width == 0 || height == 0) return const SizedBox.shrink();

        final res = "${width}x${height}";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            res,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.play_circle_fill,
              size: 64,
              color: Colors.blueAccent,
            ),
            onPressed: _initPlayer,
          ),
          const Text(
            'Click to View Live',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamViewer() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 8),
            Text(
              'Connection Error\n${widget.camera.name}',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _isPlaying = false;
                    });
                    _stopPlayer();
                    _initPlayer();
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final provider = Provider.of<NvrProvider>(context, listen: false);
    final isSolo = provider.selectedCameraId == widget.camera.id;

    Widget videoWidget = Video(
      controller: _controller!,
      controls: NoVideoControls,
      fill: Colors.transparent,
      fit: BoxFit.fill,
    );

    if (isSolo) {
      return InteractiveViewer(
        transformationController: _transformationController,
        maxScale: 5.0,
        minScale: 0.5,
        child: videoWidget,
      );
    }

    return videoWidget;
  }
}
