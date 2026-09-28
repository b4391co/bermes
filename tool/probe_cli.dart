import 'package:hermes_pocket/clients/herdr/herdr_client.dart';
import 'package:hermes_pocket/clients/herdr/herdr_fleet.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:io';

void main(List<String> args) async {
  final h = args[0]; // user@host
  final parts = h.split('@');
  final host = SshHostInfo(id: 't', name: h, host: parts[1], port: 22, username: parts[0], knownFingerprint: null);
  final fleet = HerdrFleet();
  // credenciales: clave por defecto ~/.ssh/id_rsa (el host de prueba es esta máquina)
  final pem = File('/root/.ssh/id_ed25519').existsSync() ? File('/root/.ssh/id_rsa').readAsStringSync() : null;
  final stream = fleet.probeAll([host], (_) async => HerdrCredentials(privateKeyPem: pem), onFingerprint: (_, __) async {});
  await for (final r in stream) {
    print('HOST ${r.host.name} agents=${r.agents.length} error=${r.error}');
  }
}
