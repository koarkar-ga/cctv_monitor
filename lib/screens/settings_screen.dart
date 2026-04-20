import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/nvr_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: AppBar(
        title: const Text('SYSTEM SETTINGS'),
        backgroundColor: const Color(0xFF252538),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('RECORDING SETTINGS', Icons.video_library_rounded),
            const SizedBox(height: 16),
            _buildRecordingPathCard(context),
            const SizedBox(height: 32),
            _buildSectionHeader('CONFIGURATION MANAGEMENT', Icons.settings_backup_restore_rounded),
            const SizedBox(height: 16),
            _buildConfigManagementCard(context),
            const SizedBox(height: 48),
            Center(
              child: Text(
                'MOONSUN Monitoring Center v1.2.0',
                style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingPathCard(BuildContext context) {
    final provider = Provider.of<NvrProvider>(context);
    final path = provider.recordingPath ?? 'Default Downloads Folder';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Save Recordings To:',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Text(
              path,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  foregroundColor: Colors.blueAccent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  String? selectedDirectory = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Select Recording Folder',
                  );
                  if (selectedDirectory != null) {
                    provider.setRecordingPath(selectedDirectory);
                  }
                },
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('CHANGE FOLDER'),
              ),
              const SizedBox(width: 12),
              if (provider.recordingPath != null)
                TextButton(
                  onPressed: () => provider.setRecordingPath(null),
                  child: const Text('RESET TO DEFAULT', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigManagementCard(BuildContext context) {
    final provider = Provider.of<NvrProvider>(context, listen: false);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _buildActionButton(
            context,
            icon: Icons.upload_file_rounded,
            title: 'Export Configuration',
            subtitle: 'Save all NVR and Camera settings to a JSON file.',
            color: Colors.greenAccent,
            onTap: () async {
              bool success = await provider.exportConfig();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Configuration Exported' : 'Export Failed'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.white10),
          ),
          _buildActionButton(
            context,
            icon: Icons.file_download_rounded,
            title: 'Import Configuration',
            subtitle: 'Restore settings from a previously saved JSON file.',
            color: Colors.orangeAccent,
            onTap: () async {
              bool success = await provider.importConfig();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Configuration Imported' : 'Import Failed'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }
}
