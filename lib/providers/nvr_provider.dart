import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../models/nvr_model.dart';
import '../models/camera_model.dart';
import 'package:file_picker/file_picker.dart';

enum StreamQuality { hd, smooth }

class NvrProvider with ChangeNotifier {
  List<NvrGroupModel> _nvrs = [];
  int _gridSize = 4;
  String? _selectedNvrId;
  String? _selectedCameraId;
  StreamQuality _quality = StreamQuality.smooth; // Default to smooth for stability

  List<NvrGroupModel> get nvrs => _nvrs;
  int get gridSize => _gridSize;
  String? get selectedNvrId => _selectedNvrId;
  String? get selectedCameraId => _selectedCameraId;
  StreamQuality get quality => _quality;

  void setQuality(StreamQuality q) {
    _quality = q;
    notifyListeners();
  }

  List<CameraModel> get allCameras {
    return _nvrs.expand((nvr) => nvr.generateCameras).toList();
  }

  List<CameraModel> get displayCameras {
    if (_selectedCameraId != null) {
      return allCameras.where((c) => c.id == _selectedCameraId).toList();
    }

    if (_nvrs.isEmpty) return [];
    
    if (_selectedNvrId != null) {
      final selectedNvr = _nvrs.firstWhere(
        (nvr) => nvr.id == _selectedNvrId, 
        orElse: () => _nvrs.first,
      );
      return selectedNvr.generateCameras;
    }
    
    return allCameras;
  }

  NvrProvider() {
    _loadNvrs();
  }

  Future<void> _loadNvrs() async {
    final prefs = await SharedPreferences.getInstance();
    final nvrJsonList = prefs.getStringList('cctv_nvrs');
    if (nvrJsonList != null && nvrJsonList.isNotEmpty) {
      _nvrs = nvrJsonList.map((c) => NvrGroupModel.fromJson(c)).toList();
      _selectedNvrId = _nvrs.isNotEmpty ? _nvrs.first.id : null;
    }
    
    notifyListeners();
  }

  Future<void> _saveNvrs() async {
    final prefs = await SharedPreferences.getInstance();
    final nvrJsonList = _nvrs.map((c) => c.toJson()).toList();
    await prefs.setStringList('cctv_nvrs', nvrJsonList);
  }

  void addNvr(NvrGroupModel nvr) {
    _nvrs.add(nvr);
    _selectedNvrId = nvr.id; 
    _saveNvrs();
    notifyListeners();
  }

  void updateNvr(NvrGroupModel updatedNvr) {
    final index = _nvrs.indexWhere((c) => c.id == updatedNvr.id);
    if (index != -1) {
      _nvrs[index] = updatedNvr;
      _saveNvrs();
      notifyListeners();
    }
  }

  void removeNvr(String id) {
    _nvrs.removeWhere((c) => c.id == id);
    if (_selectedNvrId == id) {
      _selectedNvrId = _nvrs.isNotEmpty ? _nvrs.first.id : null;
    }
    _saveNvrs();
    notifyListeners();
  }

  void selectNvr(String? id) {
    _selectedNvrId = id;
    _selectedCameraId = null; // Clear solo view when switching NVR
    notifyListeners();
  }

  void toggleSoloCamera(String? cameraId) {
    if (_selectedCameraId == cameraId) {
      _selectedCameraId = null;
    } else {
      _selectedCameraId = cameraId;
    }
    notifyListeners();
  }

  void setGridSize(int size) {
    _gridSize = size;
    _selectedCameraId = null; // Clear solo view when changing grid
    notifyListeners();
  }

  int _globalPlaySignal = 0;
  int _globalStopSignal = 0;

  int get globalPlaySignal => _globalPlaySignal;
  int get globalStopSignal => _globalStopSignal;

  void playAll() {
    _globalPlaySignal++;
    notifyListeners();
  }

  void stopAll() {
    _globalStopSignal++;
    notifyListeners();
  }

  Future<bool> exportConfig() async {
    try {
      final jsonString = json.encode(_nvrs.map((n) => n.toMap()).toList());
      
      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Save CCTV Configuration',
        fileName: 'cctv_config.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile == null) return false;

      final file = File(outputFile);
      await file.writeAsString(jsonString);
      return true;
    } catch (e) {
      debugPrint('Export Error: $e');
      return false;
    }
  }

  Future<bool> importConfig() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        
        final List<dynamic> decodedList = json.decode(jsonString);
        _nvrs = decodedList.map((e) => NvrGroupModel.fromMap(e)).toList();
        
        if (_nvrs.isNotEmpty) {
          _selectedNvrId = _nvrs.first.id;
        }
        
        await _saveNvrs();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Import Error: $e');
      return false;
    }
  }
}
