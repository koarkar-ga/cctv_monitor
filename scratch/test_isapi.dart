import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const host = 'mdy4-server.netbird.cloud';
  const username = 'admin';
  const password = r'm$DVRpwd';
  
  final auth = 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  
  final ports = ['80', '8080', '8000', '443', '9000'];
  final endpoints = [
    '/ISAPI/ContentMgmt/search',
    '/ISAPI/ContentMgmt/search/v1',
    '/ISAPI/ContentMgmt/record/search',
    '/ISAPI/System/deviceInfo', // Simple test endpoint
  ];

  print('--- Starting ISAPI Diagnostic Test ---');
  print('Host: $host');

  for (var port in ports) {
    print('\n[Testing Port: $port]');
    for (var endpoint in endpoints) {
      final protocol = port == '443' ? 'https' : 'http';
      final url = '$protocol://$host:$port$endpoint';
      
      try {
        final uri = Uri.parse(url);
        final response = await http.get(
          uri,
          headers: {'Authorization': auth},
        ).timeout(Duration(seconds: 3));
        
        print('  $endpoint -> Status: ${response.statusCode}');
        if (response.statusCode == 200 || response.statusCode == 405) {
          print('  >> Found potential working endpoint! status: ${response.statusCode}');
        }
      } catch (e) {
        print('  $endpoint -> Error: $e');
        if (e.toString().contains('Connection refused') || e.toString().contains('Connection failed')) {
          print('  !! Port $port appears to be CLOSED. Skipping endpoints...');
          break; // Skip other endpoints for this port
        }
      }
    }
  }
  print('\n--- Diagnostic Complete ---');
}
