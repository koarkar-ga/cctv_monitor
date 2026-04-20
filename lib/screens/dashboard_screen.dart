import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nvr_provider.dart';
import '../providers/task_provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/camera_view_widget.dart';
import '../widgets/nvr_form_dialog.dart';
import '../widgets/download_tasks_dialog.dart';
import 'playback_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  PageController? _pageController;
  String? _lastSoloId;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text('MOONSUN CCTV Monitoring Center'),
        backgroundColor: const Color(0xFF252538),
        elevation: 0,
        actions: [
          _buildVpnStatus(context),
          const SizedBox(width: 8),
          // Condense App Bar actions for mobile
          LayoutBuilder(
            builder: (context, constraints) {
              bool isMobile = MediaQuery.of(context).size.width < 600;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQualityToggle(context, compact: isMobile),
                  const SizedBox(width: 4),
                  _buildMuteToggle(context),
                  const SizedBox(width: 8),
                  _buildBatchControls(context, compact: isMobile),
                  const SizedBox(width: 4),
                  _buildGridSelector(context),
                  _buildPlaybackButton(context),
                  _buildTaskButton(context),
                  _buildAddButton(context),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<NvrProvider>(
          builder: (context, provider, child) {
            if (provider.nvrs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No NVRs Configured',
                      style: TextStyle(color: Colors.grey, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const NvrFormDialog(),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add NVR Group'),
                    ),
                  ],
                ),
              );
            }

            final displayCameras = provider.displayCameras;
            int crossAxisCount = _calcCrossAxisCount(provider.gridSize);
            int itemCount = provider.gridSize;

            if (provider.selectedCameraId != null) {
              // Full Screen Solo PageView
              final initialPage = displayCameras.indexWhere(
                (c) => c.id == provider.selectedCameraId,
              );

              if (_pageController == null ||
                  _lastSoloId != provider.selectedCameraId) {
                _pageController?.dispose();
                _pageController = PageController(
                  initialPage: initialPage >= 0 ? initialPage : 0,
                );
                _lastSoloId = provider.selectedCameraId;
              }

              return PageView.builder(
                controller: _pageController,
                itemCount: displayCameras.length,
                onPageChanged: (index) {
                  // Update the selected camera quietly to avoid unnecessary jump
                  provider.toggleSoloCamera(displayCameras[index].id);
                  _lastSoloId = displayCameras[index].id;
                },
                itemBuilder: (context, index) {
                  final camera = displayCameras[index];
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: GestureDetector(
                        onDoubleTap: () => provider.toggleSoloCamera(camera.id),
                        child: CameraViewWidget(
                          key: ValueKey(camera.id),
                          camera: camera,
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            // Normal Grid View
            _pageController?.dispose();
            _pageController = null;
            _lastSoloId = null;

            return LayoutBuilder(
              builder: (context, constraints) {
                // Adaptive Column Logic
                int effectiveCrossAxisCount = crossAxisCount;
                if (constraints.maxWidth < 600) {
                  effectiveCrossAxisCount = 1;
                } else if (constraints.maxWidth < 1100) {
                  effectiveCrossAxisCount = crossAxisCount > 2
                      ? 2
                      : crossAxisCount;
                }

                return GridView.builder(
                  itemCount: itemCount,
                  padding: const EdgeInsets.only(bottom: 20),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: effectiveCrossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 16 / 9,
                  ),
                  itemBuilder: (context, index) {
                    if (index < displayCameras.length) {
                      final camera = displayCameras[index];
                      return GestureDetector(
                        onDoubleTap: () => provider.toggleSoloCamera(camera.id),
                        child: CameraViewWidget(
                          key: ValueKey(camera.id),
                          camera: camera,
                        ),
                      );
                    } else {
                      return _buildEmptySlot(context);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildVpnStatus(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        final status = vpn.status;
        return IconButton(
          icon: Icon(
            status.isConnected ? Icons.vpn_lock : Icons.vpn_lock_outlined,
            color: status.isConnected ? Colors.greenAccent : Colors.white24,
            size: 20,
          ),
          tooltip: 'Netbird VPN: ${status.management}',
          onPressed: () => _showVpnDialog(context, vpn),
        );
      },
    );
  }

  void _showVpnDialog(BuildContext context, VpnProvider vpn) {
    showDialog(
      context: context,
      builder: (context) => Consumer<VpnProvider>(
        builder: (context, vpn, _) {
          final s = vpn.status;
          return AlertDialog(
            backgroundColor: const Color(0xFF252538),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.security, color: Colors.blueAccent),
                const SizedBox(width: 12),
                const Text(
                  'Netbird VPN Status',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _vpnInfoItem(
                  'Status',
                  s.management,
                  s.isConnected ? Colors.greenAccent : Colors.redAccent,
                ),
                _vpnInfoItem('Netbird IP', s.ip, Colors.white),
                _vpnInfoItem('Profile', s.profile, Colors.white),
                _vpnInfoItem('Peers', s.peers, Colors.blueAccent),
                if (s.lastError.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    s.lastError,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: s.isConnected
                          ? Colors.redAccent.withOpacity(0.8)
                          : Colors.greenAccent.withOpacity(0.8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: vpn.isToggling ? null : () => vpn.toggleVpn(),
                    child: vpn.isToggling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            s.isConnected ? 'DISCONNECT VPN' : 'CONNECT VPN',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vpnInfoItem(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskButton(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, taskProvider, _) => Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(
              Icons.download_for_offline,
              color: Colors.greenAccent,
            ),
            tooltip: 'Download Tasks',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const DownloadTasksDialog(),
              );
            },
          ),
          if (taskProvider.activeTaskCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  '${taskProvider.activeTaskCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.add_to_queue),
      tooltip: 'Add NVR',
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => const NvrFormDialog(),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF252538),
      child: Consumer<NvrProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF1E1E2C)),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard, size: 48, color: Colors.blueAccent),
                      SizedBox(height: 12),
                      Text(
                        'NVR Groups',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.white),
                title: const Text(
                  'All Cameras',
                  style: TextStyle(color: Colors.white),
                ),
                selected: provider.selectedNvrId == null,
                selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                onTap: () {
                  provider.selectNvr(null);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.nvrs.length,
                  itemBuilder: (context, index) {
                    final nvr = provider.nvrs[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.video_camera_back,
                        color: Colors.blueAccent,
                      ),
                      title: Text(
                        nvr.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${nvr.numberOfChannels} Channels',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      selected: provider.selectedNvrId == nvr.id,
                      selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.grey,
                          size: 18,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => NvrFormDialog(nvr: nvr),
                          );
                        },
                      ),
                      onTap: () {
                        provider.selectNvr(nvr.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(
                  Icons.settings_rounded,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Recording path, Config Export/Import',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGridSelector(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.grid_view),
      tooltip: 'Grid Layout',
      onSelected: (size) {
        Provider.of<NvrProvider>(context, listen: false).setGridSize(size);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 1, child: Text('Solo (1x1)')),
        const PopupMenuItem(value: 4, child: Text('Quad (2x2)')),
        const PopupMenuItem(value: 9, child: Text('Nine (3x3)')),
        const PopupMenuItem(value: 16, child: Text('16 View (4x4)')),
        const PopupMenuItem(value: 25, child: Text('25 View (5x5)')),
        const PopupMenuItem(value: 36, child: Text('36 View (6x6)')),
        const PopupMenuItem(value: 49, child: Text('49 View (7x7)')),
        const PopupMenuItem(value: 64, child: Text('64 View (8x8)')),
      ],
    );
  }

  Widget _buildEmptySlot(BuildContext context) {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => const NvrFormDialog(),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252538),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: Colors.blueAccent,
                size: 48,
              ),
              SizedBox(height: 8),
              Text('Add NVR Group', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackButton(BuildContext context) {
    return IconButton(
      icon: const Icon(
        Icons.slow_motion_video_rounded,
        color: Colors.orangeAccent,
        size: 20,
      ),
      tooltip: 'Video Playback',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PlaybackScreen()),
        );
      },
    );
  }

  Widget _buildMuteToggle(BuildContext context) {
    final provider = Provider.of<NvrProvider>(context);
    final isMuted = provider.isGlobalMuted;

    return IconButton(
      icon: Icon(
        isMuted ? Icons.volume_off : Icons.volume_up,
        color: isMuted ? Colors.white24 : Colors.blueAccent,
        size: 20,
      ),
      tooltip: isMuted ? 'UNMUTE ALL' : 'CLOSE ALL SPEAKER',
      onPressed: () => provider.setGlobalMute(!isMuted),
    );
  }

  Widget _buildQualityToggle(BuildContext context, {bool compact = false}) {
    final provider = Provider.of<NvrProvider>(context);
    final isHd = provider.quality == StreamQuality.hd;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qualityButton(
            context,
            compact ? 'SM' : 'SMOOTH',
            !isHd,
            Colors.greenAccent,
            () => provider.setQuality(StreamQuality.smooth),
            compact: compact,
          ),
          _qualityButton(
            context,
            'HD',
            isHd,
            Colors.blueAccent,
            () => provider.setQuality(StreamQuality.hd),
            compact: compact,
          ),
        ],
      ),
    );
  }

  Widget _qualityButton(
    BuildContext context,
    String label,
    bool isActive,
    Color activeColor,
    VoidCallback onTap, {
    bool compact = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? activeColor : Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBatchControls(BuildContext context, {bool compact = false}) {
    final provider = Provider.of<NvrProvider>(context, listen: false);
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: provider.playAll,
            icon: const Icon(Icons.play_circle_fill, color: Colors.blueAccent),
            tooltip: 'PLAY ALL',
          ),
          IconButton(
            onPressed: provider.stopAll,
            icon: const Icon(Icons.stop_circle, color: Colors.orangeAccent),
            tooltip: 'STOP ALL',
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: provider.playAll,
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.blueAccent),
          label: const Text(
            'PLAY ALL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.05),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: provider.stopAll,
          icon: const Icon(Icons.stop_rounded, color: Colors.orangeAccent),
          label: const Text(
            'STOP ALL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  int _calcCrossAxisCount(int gridSize) {
    if (gridSize <= 1) return 1;
    if (gridSize <= 4) return 2;
    if (gridSize <= 9) return 3;
    if (gridSize <= 16) return 4;
    if (gridSize <= 25) return 5;
    return 4;
  }
}
