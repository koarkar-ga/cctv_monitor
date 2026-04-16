import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nvr_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/camera_view_widget.dart';
import '../widgets/nvr_form_dialog.dart';
import '../widgets/download_tasks_dialog.dart';
import 'playback_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text('CCTV Command Center'),
        backgroundColor: const Color(0xFF252538),
        elevation: 0,
        actions: [
          _buildQualityToggle(context),
          const SizedBox(width: 12),
          _buildBatchControls(context),
          const SizedBox(width: 8),
          _buildGridSelector(context),
          const SizedBox(width: 8),
          Consumer<TaskProvider>(
            builder: (context, taskProvider, _) => Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.download_for_offline, color: Colors.greenAccent),
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
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '${taskProvider.activeTaskCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_to_queue),
            tooltip: 'Add NVR',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const NvrFormDialog(),
              );
            },
          ),
          const SizedBox(width: 16),
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
                    const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No NVRs Configured', style: TextStyle(color: Colors.grey, fontSize: 18)),
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
                    )
                  ],
                ),
              );
            }

            final displayCameras = provider.displayCameras;
            int crossAxisCount = _calcCrossAxisCount(provider.gridSize);
            int itemCount = provider.gridSize;

            // Fix: If a solo camera is selected, force it to 1x1 full screen
            if (provider.selectedCameraId != null) {
              crossAxisCount = 1;
              itemCount = 1;
            } else if (displayCameras.length > provider.gridSize) {
              itemCount = displayCameras.length;
              crossAxisCount = _calcCrossAxisCount(itemCount);
            }

            return GridView.builder(
              itemCount: itemCount,
              padding: const EdgeInsets.only(bottom: 20),
              physics: provider.selectedCameraId != null 
                ? const NeverScrollableScrollPhysics() 
                : const BouncingScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 16 / 9,
              ),
              itemBuilder: (context, index) {
                if (index < displayCameras.length) {
                  final camera = displayCameras[index];
                  return GestureDetector(
                    onDoubleTap: () => provider.toggleSoloCamera(camera.id),
                    child: CameraViewWidget(key: ValueKey(camera.id), camera: camera),
                  );
                } else {
                  return _buildEmptySlot(context);
                }
              },
            );
          },
        ),
      ),
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
                decoration: BoxDecoration(
                  color: Color(0xFF1E1E2C),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard, size: 48, color: Colors.blueAccent),
                      SizedBox(height: 12),
                      Text('NVR Groups', style: TextStyle(color: Colors.white, fontSize: 18)),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.white),
                title: const Text('All Cameras', style: TextStyle(color: Colors.white)),
                selected: provider.selectedNvrId == null,
                selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                onTap: () {
                  provider.selectNvr(null);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.orangeAccent),
                title: const Text('Video Playback', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaybackScreen()),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.nvrs.length,
                  itemBuilder: (context, index) {
                    final nvr = provider.nvrs[index];
                    return ListTile(
                      leading: const Icon(Icons.video_camera_back, color: Colors.blueAccent),
                      title: Text(nvr.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${nvr.numberOfChannels} Channels', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      selected: provider.selectedNvrId == nvr.id,
                      selectedTileColor: Colors.blueAccent.withOpacity(0.2),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.grey, size: 18),
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
                leading: const Icon(Icons.file_download, color: Colors.green),
                title: const Text('Export Config', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  bool success = await provider.exportConfig();
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exported Successfully')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_upload, color: Colors.orange),
                title: const Text('Import Config', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  bool success = await provider.importConfig();
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imported Successfully')));
                  }
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
              Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 48),
              SizedBox(height: 8),
              Text('Add NVR Group', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityToggle(BuildContext context) {
    final provider = Provider.of<NvrProvider>(context);
    final isHd = provider.quality == StreamQuality.hd;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qualityButton(
            context, 
            'SMOOTH', 
            !isHd, 
            Colors.greenAccent, 
            () => provider.setQuality(StreamQuality.smooth)
          ),
          _qualityButton(
            context, 
            'HD', 
            isHd, 
            Colors.blueAccent, 
            () => provider.setQuality(StreamQuality.hd)
          ),
        ],
      ),
    );
  }

  Widget _qualityButton(BuildContext context, String label, bool isActive, Color activeColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: activeColor.withOpacity(0.5)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? activeColor : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBatchControls(BuildContext context) {
    final provider = Provider.of<NvrProvider>(context, listen: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: provider.playAll,
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.blueAccent),
          label: const Text('PLAY ALL', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: provider.stopAll,
          icon: const Icon(Icons.stop_rounded, color: Colors.orangeAccent),
          label: const Text('STOP ALL', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)),
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
