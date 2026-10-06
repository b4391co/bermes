import 'package:http_parser/http_parser.dart';
import 'package:dio/dio.dart';
import 'dart:io';

// Probe: POST password-login with WRONG creds but capture ALL response headers
// the way dio exposes them — verifying set-cookie visibility and login 200 path shape.
void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'http://10.20.20.67:9113',
    followRedirects: false,
    validateStatus: (c) => c != null && c < 600,
  ));
  final r = await dio.post('/auth/password-login', data: {
    'provider': 'basic', 'username': 'probe-user', 'password': 'probe-pass', 'next': '/',
  });
  print('status: ${r.statusCode}');
  print('set-cookie headers: ${r.headers[HttpHeaders.setCookieHeader]}');
  print('all header keys: ${r.headers.map.keys.toList()}');
}
