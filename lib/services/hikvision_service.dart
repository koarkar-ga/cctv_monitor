import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import '../models/nvr_model.dart';

class RecordingSegment {
  final DateTime start;
  final DateTime end;
  final String type;

  RecordingSegment({required this.start, required this.end, required this.type});
}

class HikvisionService {
  /// Searches for motion events on the NVR for a specific channel and time range
  static Future<List<RecordingSegment>> fetchMotionEvents({
    required NvrGroupModel nvr,
    required int channel,
    required DateTime start,
    required DateTime end,
  }) async {
    final searchId = const Uuid().v4();
    final startTimeStr = start.toUtc().toIso8601String().split('.')[0] + 'Z';
    final endTimeStr = end.toUtc().toIso8601String().split('.')[0] + 'Z';

    // Track ID format: Hikvision usually uses {channel}01 for the main stream tracks
    final trackId = "${channel}01";

    final xmlBody =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<CMSearchDescription version="2.0" xmlns="http://www.isapi.org/ver20/XMLSchema">
  <searchID>$searchId</searchID>
  <trackIDList>
    <trackID>$trackId</trackID>
  </trackIDList>
  <timeSpanList>
    <timeSpan>
      <startTime>$startTimeStr</startTime>
      <endTime>$endTimeStr</endTime>
    </timeSpan>
  </timeSpanList>
  <maxResults>100</maxResults>
  <searchResultPostion>0</searchResultPostion>
  <metadataList>
    <metadataDescriptor>MOTION</metadataDescriptor>
  </metadataList>
</CMSearchDescription>
''';

    final auth =
        'Basic ${base64Encode(utf8.encode('${nvr.username}:${nvr.password}'))}';
    final List<String> endpoints = [
      '/ISAPI/ContentMgmt/search',
      '/ISAPI/ContentMgmt/search/v1',
      '/ISAPI/ContentMgmt/record/search',
    ];

    // Smart Port Discovery: Try configured port(s), then common fallbacks
    // Supports multi-port strings like "81/8000"
    final List<String> inputPorts = nvr.isapiPort
        .split(RegExp(r'[/\s,]+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final List<String> tryPorts = inputPorts
        .toSet()
        .toList(); // Only use user-specified ports

    String lastError = "No search result";

    for (var port in tryPorts) {
      bool portRefused = false;
      bool isPrimary = inputPorts.contains(port);

      for (var endpoint in endpoints) {
        if (portRefused) break; // Skip other endpoints if port is closed

        try {
          final uri = Uri.parse('http://${nvr.cleanHost}:$port$endpoint');
          print('Trying ISAPI Search at: $uri');

          var response = await http
              .post(
                uri,
                headers: {
                  'Authorization': auth,
                  'Content-Type': 'application/xml',
                },
                body: xmlBody,
              )
              .timeout(Duration(seconds: isPrimary ? 5 : 2));

          // Handle Digest Auth if 401
          if (response.statusCode == 401 &&
              response.headers.containsKey('www-authenticate')) {
            final authHeader = response.headers['www-authenticate']!;
            if (authHeader.contains('Digest')) {
              print(
                'Digest Auth Challenge detected on port $port. Handling...',
              );
              final digestHeader = _generateDigestHeader(
                method: 'POST',
                uri: endpoint,
                authHeader: authHeader,
                username: nvr.username,
                password: nvr.password,
              );

              if (digestHeader != null) {
                response = await http
                    .post(
                      uri,
                      headers: {
                        'Authorization': digestHeader,
                        'Content-Type': 'application/xml',
                      },
                      body: xmlBody,
                    )
                    .timeout(Duration(seconds: isPrimary ? 5 : 2));
              }
            }
          }

          if (response.statusCode == 200) {
            print('Success! ISAPI found on port $port at $endpoint');
            return _parseSearchResponse(response.body);
          } else if (response.statusCode == 401) {
            throw Exception(
              "Authentication Failed (Check username/password or NVR Security settings)",
            );
          } else if (response.statusCode == 404) {
            lastError = "API Not Found (404) on port $port, path $endpoint";
            continue;
          } else {
            lastError = "Search Failed: ${response.statusCode} on port $port";
          }
        } catch (e) {
          final errStr = e.toString();
          lastError = "Connection Error on port $port: $e";

          if (errStr.contains("401")) rethrow;

          // If port is refused or timed out, don't bother with other endpoints for this port
          if (errStr.contains("Connection refused") ||
              errStr.contains("TimeoutException") ||
              errStr.contains("errno = 61")) {
            print('Port $port is unreachable or refused. Skipping...');
            portRefused = true;
            break;
          }
        }
      }
    }

    throw Exception(lastError);
  }

  /// Searches for ALL recording segments on the NVR
  static Future<List<RecordingSegment>> fetchRecordings({
    required NvrGroupModel nvr,
    required int channel,
    required DateTime start,
    required DateTime end,
  }) async {
    final searchId = const Uuid().v4();
    final startTimeStr = start.toUtc().toIso8601String().split('.')[0] + 'Z';
    final endTimeStr = end.toUtc().toIso8601String().split('.')[0] + 'Z';
    final trackId = "${channel}01";

    final xmlBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<CMSearchDescription version="2.0" xmlns="http://www.isapi.org/ver20/XMLSchema">
  <searchID>$searchId</searchID>
  <trackIDList>
    <trackID>$trackId</trackID>
  </trackIDList>
  <timeSpanList>
    <timeSpan>
      <startTime>$startTimeStr</startTime>
      <endTime>$endTimeStr</endTime>
    </timeSpan>
  </timeSpanList>
  <maxResults>100</maxResults>
  <searchResultPostion>0</searchResultPostion>
</CMSearchDescription>
''';

    final auth =
        'Basic ${base64Encode(utf8.encode('${nvr.username}:${nvr.password}'))}';
    final port = nvr.isapiPort.split(RegExp(r'[/\s,]+')).first.trim();

    try {
      final uri = Uri.parse('http://${nvr.cleanHost}:$port/ISAPI/ContentMgmt/search');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': auth,
          'Content-Type': 'application/xml',
        },
        body: xmlBody,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 &&
          response.headers.containsKey('www-authenticate')) {
        final authHeader = response.headers['www-authenticate']!;
        if (authHeader.contains('Digest')) {
          final digestHeader = _generateDigestHeader(
            method: 'POST',
            uri: '/ISAPI/ContentMgmt/search',
            authHeader: authHeader,
            username: nvr.username,
            password: nvr.password,
          );

          if (digestHeader != null) {
            response = await http.post(
              uri,
              headers: {
                'Authorization': digestHeader,
                'Content-Type': 'application/xml',
              },
              body: xmlBody,
            ).timeout(const Duration(seconds: 10));
          }
        }
      }

      if (response.statusCode == 200) {
        return _parseSearchResponse(response.body);
      } else {
        throw Exception("Failed to fetch recordings: ${response.statusCode}");
      }
    } catch (e) {
      print('Fetch recordings error: $e');
      rethrow;
    }
  }

  /// Fetches days with recordings for a specific month
  static Future<Set<int>> fetchRecordingAvailability({
    required NvrGroupModel nvr,
    required int channel,
    required DateTime month,
  }) async {
    final searchId = const Uuid().v4();
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final startTimeStr =
        startOfMonth.toUtc().toIso8601String().split('.')[0] + 'Z';
    final endTimeStr = endOfMonth.toUtc().toIso8601String().split('.')[0] + 'Z';

    final trackId = "${channel}01";

    final xmlBody =
        '''
<?xml version="1.0" encoding="UTF-8"?>
<CMSearchDescription version="1.0" xmlns="http://www.isapi.org/ver20/XMLSchema">
  <searchID>$searchId</searchID>
  <trackIDList>
    <trackID>$trackId</trackID>
  </trackIDList>
  <timeSpanList>
    <timeSpan>
      <startTime>$startTimeStr</startTime>
      <endTime>$endTimeStr</endTime>
    </timeSpan>
  </timeSpanList>
  <maxResults>50</maxResults>
</CMSearchDescription>
''';

    final auth =
        'Basic ${base64Encode(utf8.encode('${nvr.username}:${nvr.password}'))}';
    final port = nvr.isapiPort.split(RegExp(r'[/\s,]+')).first.trim();

    try {
      final uri = Uri.parse(
        'http://${nvr.cleanHost}:$port/ISAPI/ContentMgmt/search',
      );
      var response = await http
          .post(
            uri,
            headers: {'Authorization': auth, 'Content-Type': 'application/xml'},
            body: xmlBody,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 401 &&
          response.headers.containsKey('www-authenticate')) {
        final authHeader = response.headers['www-authenticate']!;
        if (authHeader.contains('Digest')) {
          final digestHeader = _generateDigestHeader(
            method: 'POST',
            uri: '/ISAPI/ContentMgmt/search',
            authHeader: authHeader,
            username: nvr.username,
            password: nvr.password,
          );
          if (digestHeader != null) {
            response = await http
                .post(
                  uri,
                  headers: {
                    'Authorization': digestHeader,
                    'Content-Type': 'application/xml',
                  },
                  body: xmlBody,
                )
                .timeout(const Duration(seconds: 10));
          }
        }
      }

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final results = document.findAllElements('searchMatchItem');
        final Set<int> recordedDays = {};
        for (var item in results) {
          final timeSpan = item.findElements('timeSpan').first;
          final startStr = timeSpan.findElements('startTime').first.text;
          final startTime = DateTime.parse(startStr).toLocal();
          recordedDays.add(startTime.day);
        }
        return recordedDays;
      }
    } catch (e) {
      print('Failed to fetch recording availability: $e');
    }
    return {};
  }

  static List<RecordingSegment> _parseSearchResponse(String xmlData) {
    final List<RecordingSegment> events = [];
    try {
      final document = XmlDocument.parse(xmlData);
      final searchResults = document.findAllElements('searchMatchItem');

      for (var item in searchResults) {
        final timeSpan = item.findElements('timeSpan').first;
        final startStr = timeSpan.findElements('startTime').first.text;
        final endStr = timeSpan.findElements('endTime').first.text;

        events.add(
          RecordingSegment(
            start: DateTime.parse(startStr).toLocal(),
            end: DateTime.parse(endStr).toLocal(),
            type: 'RECORDING',
          ),
        );
      }
    } catch (e) {
      print('XML Parse Error: $e');
    }
    return events;
  }

  /// Fetches a single JPEG snapshot from the NVR
  static Future<List<int>?> fetchSnapshot({
    required NvrGroupModel nvr,
    required int channel,
    DateTime? time,
  }) async {
    final auth =
        'Basic ${base64Encode(utf8.encode('${nvr.username}:${nvr.password}'))}';
    final List<String> ports = nvr.isapiPort
        .split(RegExp(r'[/\s,]+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    String timeParam = "";
    if (time != null) {
      // Hikvision archive snapshots often require UTC string YYYYMMDDTHHMMSSZ
      final formattedTime =
          time
              .toUtc()
              .toIso8601String()
              .replaceAll('-', '')
              .replaceAll(':', '')
              .split('.')[0] +
          'Z';
      timeParam = "?time=$formattedTime";
    }

    for (var port in ports) {
      try {
        final uriPath =
            '/ISAPI/Streaming/channels/${channel}02/picture$timeParam';
        var response = await http
            .get(
              Uri.parse('http://${nvr.cleanHost}:$port$uriPath'),
              headers: {'Authorization': auth},
            )
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 401 &&
            response.headers.containsKey('www-authenticate')) {
          final authHeader = response.headers['www-authenticate']!;
          if (authHeader.contains('Digest')) {
            final uriPath = '/ISAPI/Streaming/channels/${channel}02/picture';
            final digestHeader = _generateDigestHeader(
              method: 'GET',
              uri: uriPath,
              authHeader: authHeader,
              username: nvr.username,
              password: nvr.password,
            );
            if (digestHeader != null) {
              response = await http
                  .get(
                    Uri.parse('http://${nvr.cleanHost}:$port$uriPath'),
                    headers: {'Authorization': digestHeader},
                  )
                  .timeout(const Duration(seconds: 3));
            }
          }
        }

        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
      } catch (e) {
        // Continue to next port if one fails
      }
    }
    return null;
  }

  // --- Digest Auth Helpers ---

  static String? _generateDigestHeader({
    required String method,
    required String uri,
    required String authHeader,
    required String username,
    required String password,
  }) {
    try {
      final params = _parseAuthHeader(authHeader);
      final realm = params['realm'] ?? '';
      final nonce = params['nonce'] ?? '';
      final opaque = params['opaque'] ?? '';
      final qop = params['qop'] ?? '';
      final algorithm = params['algorithm'] ?? 'MD5';

      final cnonce = const Uuid().v4().substring(0, 8);
      const nc = '00000001';

      final ha1 = _md5Hash('$username:$realm:$password');
      final ha2 = _md5Hash('$method:$uri');

      String response;
      if (qop.isNotEmpty) {
        response = _md5Hash('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');
      } else {
        response = _md5Hash('$ha1:$nonce:$ha2');
      }

      var header =
          'Digest username="$username", realm="$realm", nonce="$nonce", uri="$uri", response="$response"';
      if (opaque.isNotEmpty) header += ', opaque="$opaque"';
      if (qop.isNotEmpty) header += ', qop=$qop, nc=$nc, cnonce="$cnonce"';
      if (algorithm.isNotEmpty) header += ', algorithm=$algorithm';

      return header;
    } catch (e) {
      print('Digest generation error: $e');
      return null;
    }
  }

  static Map<String, String> _parseAuthHeader(String header) {
    final Map<String, String> params = {};
    final parts = header.substring(7).split(RegExp(r',\s*'));
    for (var part in parts) {
      final pair = part.split('=');
      if (pair.length == 2) {
        final key = pair[0].trim();
        final value = pair[1].trim().replaceAll('"', '');
        params[key] = value;
      }
    }
    return params;
  }

  static String _md5Hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}
