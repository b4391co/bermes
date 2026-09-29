import 'dart:io';

Future<void> main() async {
  final hc = HttpClient();
  final rq = await hc.getUrl(Uri.parse('http://127.0.0.1:9120/api/auth/me'));
  rq.headers.set('x-hermes-session-token', 'loopback-session-token-1');
  final rs = await rq.close();
  print('IO status=${rs.statusCode}');
  await rs.drain<void>();
  hc.close(force: true);
}
