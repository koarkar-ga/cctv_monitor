import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/nvr_model.dart';
import '../providers/nvr_provider.dart';

class IsapiImageViewer extends StatefulWidget {
  final NvrGroupModel nvr;
  final int channel;
  final StreamQuality streamQuality;

  const IsapiImageViewer({
    super.key,
    required this.nvr,
    required this.channel,
    required this.streamQuality,
  });

  @override
  _IsapiImageViewerState createState() => _IsapiImageViewerState();
}

class _IsapiImageViewerState extends State<IsapiImageViewer> {
  final http.Client _client = http.Client();
  Uint8List? _currentImage;
  bool _isLoading = false;
  String? _errorMessage;
  int _pathIndex = 0;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _fetchImage() async {
    if (!mounted) return;
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final String trackId = widget.streamQuality == StreamQuality.hd
          ? '01'
          : '02';
      final List<String> paths = [
        '/ISAPI/Streaming/channels/${widget.channel}$trackId/picture',
        '/ISAPI/Streaming/channels/${widget.channel}/picture',
        '/Streaming/channels/${widget.channel}$trackId/picture',
      ];

      final String currentPath = paths[_pathIndex % paths.length];

      // Smart Port Discovery: Cycle through 80, 81 and configured port on failure
      final List<String> commonPorts = [
        widget.nvr.isapiPort,
        '80',
        '81',
        '8000',
      ];
      final String port = commonPorts[_retryCount % commonPorts.length];
      final url = 'http://${widget.nvr.host}:$port$currentPath';

      final auth =
          'Basic ${base64Encode(utf8.encode('${widget.nvr.username}:${widget.nvr.password}'))}';

      final response = await _client
          .get(Uri.parse(url), headers: {'Authorization': auth})
          .timeout(
            const Duration(milliseconds: 1500),
          ); // Lower timeout for snappier failure

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _currentImage = response.bodyBytes;
            _errorMessage = null;
            _isLoading = false;
            _retryCount = 0;
          });
          // Use user-defined FPS from settings
          final delayMs = (1000 / widget.nvr.snapshotFps).round();
          Future.delayed(Duration(milliseconds: delayMs), _fetchImage);
        }
      } else if (response.statusCode == 404 || response.statusCode == 400) {
        _cyclePath();
        throw Exception('Path not found (${response.statusCode})');
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _retryCount++;
          if (_retryCount > 6) {
            _errorMessage = 'Snapshot Error: $e\nCheck HTTP Port 80';
          }
        });
        // Fast retry on error (100ms instead of 1000ms)
        Future.delayed(const Duration(milliseconds: 100), _fetchImage);
      }
    }
  }

  void _cyclePath() {
    _pathIndex++;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null && _currentImage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: Set HTTP Web Port to 80 in Settings',
                style: TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentImage == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: Current Image (Keep it while next one loads)
        if (_currentImage != null)
          Image.memory(_currentImage!, fit: BoxFit.fill, gaplessPlayback: true),

        // Foreground: New Image with cross-fade
        if (_currentImage != null)
          AnimatedOpacity(
            opacity: _isLoading ? 0.8 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Image.memory(
              _currentImage!,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),

        if (_isLoading && _currentImage != null)
          Positioned(
            top: 40,
            right: 12,
            child: SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
          ),
      ],
    );
  }
}
