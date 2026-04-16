import 'dart:convert';

class CameraModel {
  final String id;
  final String name;
  final String url;
  final String nvrId;
  final int channelIndex;

  CameraModel({
    required this.id,
    required this.name,
    required this.url,
    required this.nvrId,
    required this.channelIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'nvrId': nvrId,
      'channelIndex': channelIndex,
    };
  }

  factory CameraModel.fromMap(Map<String, dynamic> map) {
    return CameraModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      nvrId: map['nvrId'] ?? '',
      channelIndex: map['channelIndex']?.toInt() ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory CameraModel.fromJson(String source) => CameraModel.fromMap(json.decode(source));
}
