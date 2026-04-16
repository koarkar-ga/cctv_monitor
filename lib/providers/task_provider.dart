import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum TaskStatus { pending, downloading, completed, failed }

class DownloadTask {
  final String id;
  final String cameraName;
  final String timeRange;
  final String url;
  double progress;
  TaskStatus status;
  String? filePath;

  DownloadTask({
    required this.id,
    required this.cameraName,
    required this.timeRange,
    required this.url,
    this.progress = 0.0,
    this.status = TaskStatus.pending,
    this.filePath,
  });
}

class TaskProvider with ChangeNotifier {
  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => _tasks;

  void addTask(String cameraName, String timeRange, String url) {
    final task = DownloadTask(
      id: const Uuid().v4(),
      cameraName: cameraName,
      timeRange: timeRange,
      url: url,
    );
    _tasks.add(task);
    notifyListeners();
    _startDownload(task);
  }

  void _startDownload(DownloadTask task) async {
    // This is a placeholder for the actual ffmpeg download logic
    // In a real app, this would use the DownloadService
    task.status = TaskStatus.downloading;
    notifyListeners();

    for (int i = 0; i <= 10; i++) {
      await Future.delayed(const Duration(seconds: 1));
      task.progress = i / 10;
      notifyListeners();
    }

    task.status = TaskStatus.completed;
    notifyListeners();
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  int get activeTaskCount => _tasks.where((t) => t.status == TaskStatus.downloading).length;
}
