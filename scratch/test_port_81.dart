import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const host = 'mdy4-server.netbird.cloud';
  const username = 'admin';
  const password = r'm$DVRpwd';
  
  final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  
  // Focused test on Port 81 and 8000
  final ports = ['81', '8000']; 
  final endpoints = [
    '/ISAPI/ContentMgmt/search',
    '/ISAPI/ContentMgmt/search/v1',
    '/ISAPI/ContentMgmt/record/search',
    '/ISAPI/System/deviceInfo',
  ];

  print('--- Focused ISAPI Diagnostic Test ---');
  print('Host: $host');

  for (var port in ports) {
    print('\n[Testing Port: $port]');
    for (var endpoint in endpoints) {
      final url = 'http://$host:$port$endpoint';
      try {
        final uri = Uri.parse(url);
        final response = await http.post(
          uri,
          headers: {'Authorization': auth, 'Content-Type': 'application/xml'},
          body: '<?xml version="1.0" encoding="UTF-8"?><CMSearchDescription version="2.0" xmlns="http://www.isapi.org/ver20/XMLSchema"><searchID>test</searchID><trackIDList><trackID>101</trackID></trackIDList><timeSpanList><timeSpan><startTime>2026-04-14T00:00:00Z</startTime><endTime>2026-04-14T23:59:59Z</endTime></timeSpan></timeSpanList><maxResults>10</maxResults><searchResultPostion>0</searchResultPostion><metadataList><metadataDescriptor>MOTION</metadataDescriptor></metadataList></CMSearchDescription>',
        ).timeout(Duration(seconds: 4));
        
        print('  $endpoint -> Status: ${response.statusCode}');
        if (response.statusCode == 200) {
          print('  [SUCCESS] Port $port is working properly!');
        } else if (response.statusCode == 401) {
          print('  [AUTH] Port $port is reachable but AUTH FAILED (401).');
        } else {
          print('  [OTHER] Status ${response.statusCode}');
        }
      } catch (e) {
        print('  $endpoint -> Error: $e');
        if (e.toString().contains('Connection refused')) {
          print('  !! Port $port is REFUSED.');
          break;
        }
      }
    }
  }
}
