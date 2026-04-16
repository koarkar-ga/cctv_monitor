import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'http://mdy4-server.netbird.cloud:81/ISAPI/System/deviceInfo';
  
  try {
    final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 5));
    print('Status: ${response.statusCode}');
    print('Headers: ${response.headers}');
    
    if (response.headers['www-authenticate'] != null) {
      print('Auth Type: ${response.headers['www-authenticate']}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
