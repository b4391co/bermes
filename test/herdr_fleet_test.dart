import 'package:hermes_pocket/clients/herdr/herdr_fleet.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe encuentra herdr en PATH de shell no interactiva', () async {
    // Requiere el sshd falso del host (tools/sshd_test_up.sh) en 127.0.0.1:2222.
    // Se omite si el puerto no está abierto.
    final host = SshHostInfo(
      id: 'test',
      name: 'test-herdr',
      host: '127.0.0.1',
      port: 2222,
      username: 'root',
      knownFingerprint: null,
    );
    if (!File('/root/.local/bin/herdr').existsSync()) {
      markTestSkipped('fixture: requiere herdr en ~/.local/bin del host');
      return;
    }
    final pemFile = File('/tmp/herdr_ssh/id_test');
    if (!pemFile.existsSync()) {
      markTestSkipped('sshd de test no levantado (tools/sshd_test_up.sh)');
      return;
    }
    final pem = pemFile.readAsStringSync();
    final fleet = HerdrFleet();
    final results = await fleet
        .probeAll(
          [host],
          (_) async => HerdrCredentials(privateKeyPem: pem),
          onFingerprint: (_, __) async {},
        )
        .toList();
    expect(results, hasLength(1));
    final r = results.first;
    expect(r.error, isNull, reason: r.error);
    expect(r.notFound, isFalse);
    // fixture real: este host tiene herdr en ~/.local/bin (fuera del PATH
    // por defecto de ssh). El snapshot lista sus agentes reales.
    expect(r.agents, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
