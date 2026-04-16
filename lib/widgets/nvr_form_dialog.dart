import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/nvr_model.dart';
import '../providers/nvr_provider.dart';

class NvrFormDialog extends StatefulWidget {
  final NvrGroupModel? nvr;

  const NvrFormDialog({super.key, this.nvr});

  @override
  _NvrFormDialogState createState() => _NvrFormDialogState();
}

class _NvrFormDialogState extends State<NvrFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _channelsController;
  late TextEditingController _isapiPortController;
  late TextEditingController _streamKeyController;
  int _selectedStreamType = 2; // Default to Sub Stream (SD)
  bool _useSnapshot = false;
  int _snapshotFps = 10;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.nvr?.name ?? '');
    _hostController = TextEditingController(text: widget.nvr?.host ?? '');
    _portController = TextEditingController(text: widget.nvr?.port.toString() ?? '554');
    _userController = TextEditingController(text: widget.nvr?.username ?? 'admin');
    _passController = TextEditingController(text: widget.nvr?.password ?? '');
    _channelsController = TextEditingController(text: widget.nvr?.numberOfChannels.toString() ?? '16');
    _isapiPortController = TextEditingController(text: widget.nvr?.isapiPort ?? '8000');
     _streamKeyController = TextEditingController(text: widget.nvr?.streamKey ?? '');
    _selectedStreamType = widget.nvr?.streamType ?? 2;
    _useSnapshot = widget.nvr?.useSnapshot ?? false;
    _snapshotFps = widget.nvr?.snapshotFps ?? 10;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    _channelsController.dispose();
    _isapiPortController.dispose();
    _streamKeyController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<NvrProvider>(context, listen: false);

      final newNvr = NvrGroupModel(
        id: widget.nvr?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 554,
        username: _userController.text.trim(),
        password: _passController.text.trim(),
        numberOfChannels: int.tryParse(_channelsController.text.trim()) ?? 16,
        streamType: _selectedStreamType,
        isapiPort: _isapiPortController.text.trim().isEmpty ? '80' : _isapiPortController.text.trim(),
        streamKey: _streamKeyController.text.trim(),
        useSnapshot: _useSnapshot,
        snapshotFps: _snapshotFps,
      );

      if (widget.nvr == null) {
        provider.addNvr(newNvr);
      } else {
        provider.updateNvr(newNvr);
      }

      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.nvr == null ? 'Add NVR Group' : 'Edit NVR Group'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'NVR Name (e.g. Main Branch)', border: OutlineInputBorder()),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(labelText: 'IP / Domain', border: OutlineInputBorder()),
                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'RTSP Port', 
                        border: OutlineInputBorder(),
                        helperText: 'Usually 554',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _isapiPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'HTTP/Web Port', 
                        border: OutlineInputBorder(),
                        helperText: '80, 81, 8000, etc.',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _userController,
                      decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _passController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _streamKeyController,
                decoration: const InputDecoration(
                  labelText: 'Stream Key (Verification Code)', 
                  border: OutlineInputBorder(),
                  helperText: 'Required if Mandalay 5 shows green screen.',
                ),
              ),
              const SizedBox(height: 12),
              if (_streamKeyController.text.isNotEmpty)
                SwitchListTile(
                  title: const Text('Use Snapshot Mode (Mandalay 5)'),
                  subtitle: const Text('Bypasses encryption using snapshot API.'),
                  value: _useSnapshot,
                  onChanged: (val) => setState(() => _useSnapshot = val),
                  activeColor: Colors.greenAccent,
                  contentPadding: EdgeInsets.zero,
                ),
              if (_streamKeyController.text.isNotEmpty && _useSnapshot)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                  child: Row(
                    children: [
                      const Text('Snapshot FPS:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Slider(
                          value: _snapshotFps.toDouble(),
                          min: 1,
                          max: 15,
                          divisions: 14,
                          label: '$_snapshotFps FPS',
                          onChanged: (val) => setState(() => _snapshotFps = val.toInt()),
                          activeColor: Colors.greenAccent,
                        ),
                      ),
                      Text('$_snapshotFps fps', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _selectedStreamType,
                decoration: const InputDecoration(labelText: 'Stream Quality', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Main Stream (HD - Clearer)')),
                  DropdownMenuItem(value: 2, child: Text('Sub Stream (SD - Faster)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedStreamType = val);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _channelsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of Channels', 
                  border: OutlineInputBorder(),
                  helperText: 'App will auto-generate RTSP streams for all channels.',
                ),
                validator: (value) => value == null || int.tryParse(value) == null ? 'Enter a valid number' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save NVR'),
        ),
      ],
    );
  }
}
