import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class RecordingService {
  Process? _process;
  String? _currentFilePath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;

  Future<String> _getRecordingPath(String? customBase) async {
    Directory? downloads;
    if (customBase != null && customBase.isNotEmpty) {
      downloads = Directory(customBase);
    } else if (Platform.isMacOS) {
      downloads = Directory('${Platform.environment['HOME']}/Downloads/CCTV_Records');
    } else {
      downloads = await getDownloadsDirectory();
    }

    if (downloads != null && !await downloads.exists()) {
      await downloads.create(recursive: true);
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${downloads?.path}/recording_$timestamp.mp4';
  }

  Future<bool> startRecording(String rtspUrl, {String? customPath}) async {
    if (_isRecording) return false;

    try {
      _currentFilePath = await _getRecordingPath(customPath);
      
      // Use discovered Windows path as primary for this system, or fallback to 'ffmpeg' in PATH
      final ffmpegPath = Platform.isWindows 
          ? r'C:\Program Files\Wondershare\Wondershare UniConverter for Windows\ffmpeg.exe'
          : '/opt/homebrew/bin/ffmpeg';
          
      _process = await Process.start(
        ffmpegPath,
        [
          '-rtsp_transport', 'tcp',
          '-i', rtspUrl,
          '-c', 'copy', // Direct copy without re-encoding to save CPU
          '-f', 'mp4',
          '-y', // Overwrite if exists
          _currentFilePath!,
        ],
      );

      _isRecording = true;
      debugPrint('Recording started: $_currentFilePath');

      // Listen for exit
      _process!.exitCode.then((code) {
        debugPrint('Recording process exited with code: $code');
        _isRecording = false;
        _process = null;
      });

      return true;
    } catch (e) {
      debugPrint('Recording failed: $e');
      _isRecording = false;
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording || _process == null) return;
    
    // Send 'q' to ffmpeg for graceful stop
    _process!.stdin.write('q');
    await _process!.stdin.flush();
    
    // Give it a moment to finalize the MP4 header
    await Future.delayed(const Duration(seconds: 1));
    _process!.kill();
    _isRecording = false;
    _process = null;
    debugPrint('Recording stopped.');
  }

  /// Downloads a specific time range using ffmpeg (Timed Capture)
  Future<bool> downloadSegment(String rtspUrl, Duration duration, {String? customPath}) async {
    try {
      final path = await _getRecordingPath(customPath);
      final seconds = duration.inSeconds;

      final ffmpegPath = Platform.isWindows 
          ? r'C:\Program Files\Wondershare\Wondershare UniConverter for Windows\ffmpeg.exe'
          : '/opt/homebrew/bin/ffmpeg';

      final process = await Process.start(
        ffmpegPath,
        [
          '-rtsp_transport', 'tcp',
          '-i', rtspUrl,
          '-t', seconds.toString(),
          '-c', 'copy',
          '-f', 'mp4',
          path,
        ],
      );

      final exitCode = await process.exitCode;
      return exitCode == 0;
    } catch (e) {
      debugPrint('Download failed: $e');
      return false;
    }
  }
}
