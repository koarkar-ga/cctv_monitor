import 'dart:convert';
import 'camera_model.dart';

class NvrGroupModel {
  String id;
  String name;
  String host;
  int port;
  String username;
  String password;
  int streamType;
  int numberOfChannels;
  String isapiPort;
  String? streamKey; // Hikvision Verification Code for encrypted streams
  bool useSnapshot;  // Whether to use ISAPI Image Viewer (Bypass encryption)
  int snapshotFps;   // Target FPS for snapshot mode (1-15)

  NvrGroupModel({
    required this.id,
    required this.name,
    required this.host,
    this.port = 554,
    required this.username,
    required this.password,
    this.streamType = 2,
    this.numberOfChannels = 4,
    this.isapiPort = '80',
    this.streamKey,
    this.useSnapshot = false,
    this.snapshotFps = 10,
  });

  /// Returns the host part without any port if it was included in the string
  String get cleanHost {
    if (host.contains(':')) {
      return host.split(':').first;
    }
    return host;
  }

  String getRtspUrl(int channel) {
    String encodedPass = Uri.encodeComponent(password);
    String base =
        'rtsp://$username:$encodedPass@$cleanHost:$port/Streaming/Channels/${channel}0$streamType';
    if (streamKey != null && streamKey!.isNotEmpty) {
      return '$base?verificationCode=$streamKey';
    }
    return base;
  }

  List<CameraModel> get generateCameras {
    return List.generate(numberOfChannels, (index) {
      int channelNum = index + 1;
      return CameraModel(
        id: '${id}_$channelNum',
        name: '$name - CH${channelNum.toString().padLeft(2, '0')}',
        url: getRtspUrl(channelNum),
        nvrId: id,
        channelIndex: index,
      );
    });
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'streamType': streamType,
      'numberOfChannels': numberOfChannels,
      'isapiPort': isapiPort,
      'streamKey': streamKey,
      'useSnapshot': useSnapshot,
      'snapshotFps': snapshotFps,
    };
  }

  factory NvrGroupModel.fromMap(Map<String, dynamic> map) {
    return NvrGroupModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      host: map['host'] ?? '',
      port: map['port']?.toInt() ?? 554,
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      streamType: map['streamType']?.toInt() ?? 2,
      numberOfChannels: map['numberOfChannels']?.toInt() ?? 4,
      isapiPort: map['isapiPort'] ?? '80',
      streamKey: map['streamKey'],
      useSnapshot: map['useSnapshot'] ?? false,
      snapshotFps: map['snapshotFps']?.toInt() ?? 10,
    );
  }

  String toJson() => json.encode(toMap());
  factory NvrGroupModel.fromJson(String source) =>
      NvrGroupModel.fromMap(json.decode(source));

  NvrGroupModel copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    int? streamType,
    int? numberOfChannels,
    String? isapiPort,
    String? streamKey,
    bool? useSnapshot,
    int? snapshotFps,
  }) {
    return NvrGroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      streamType: streamType ?? this.streamType,
      numberOfChannels: numberOfChannels ?? this.numberOfChannels,
      isapiPort: isapiPort ?? this.isapiPort,
      streamKey: streamKey ?? this.streamKey,
      useSnapshot: useSnapshot ?? this.useSnapshot,
      snapshotFps: snapshotFps ?? this.snapshotFps,
    );
  }
}
