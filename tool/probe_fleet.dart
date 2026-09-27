import 'dart:io';
import '../lib/clients/herdr/herdr_fleet.dart';

Future<void> main() async {
  final pem = File('/tmp/herdr_ssh/id_test').readAsStringSync();
  final host = SshHostInfo(
      id: 't',
      name: 'test-herdr',
      host: '127.0.0.1',
      port: 2222,
      username: 'root',
      knownFingerprint: null);
  final fleet = HerdrFleet();
  await for (final r in fleet.probeAll([host],
      (_) async => HerdrCredentials(privateKeyPem: pem),
      onFingerprint: (_, __) async {})) {
    print('HOST=${r.host.name} agents=${r.agents.map((a) => a.name).toList()} notFound=${r.notFound} error=${r.error}');
    if (r.notFound || r.error != null) exit(1);
    exit(0);
  }
}
