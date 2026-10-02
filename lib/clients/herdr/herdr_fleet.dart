import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../core/logger.dart';
import 'herdr_client.dart';

/// Flota Herdr multi-host (patrón TermRover/Moshi): sondea cada host SSH
/// guardado con una conexión efímera (sin PTY: solo `ssh.run`) y devuelve
/// los agentes de cada uno.
///
/// El probe NO toca la UI ni la DB: recibe credenciales ya leídas.
/// Un host caído NO bloquea el resto: cada resultado lleva su propio error.
class HerdrFleet {
  final Logger _log = Logger('HerdrFleet');

  /// Sondea todos los hosts en paralelo y entrega resultados a medida que
  /// terminan (order-independent).
  Stream<FleetHostResult> probeAll(
    Iterable<SshHostInfo> hosts,
    Future<HerdrCredentials> Function(SshHostInfo host) credentialsFor, {
    required Future<void> Function(SshHostInfo host, String sha256)
    onFingerprint,
  }) {
    final controller = StreamController<FleetHostResult>();
    var pending = 0;
    var closed = false;
    void maybeClose() {
      if (!closed && pending == 0) {
        closed = true;
        controller.close();
      }
    }

    for (final host in hosts) {
      pending++;
      () async {
        FleetHostResult r;
        try {
          final creds = await credentialsFor(host);
          r = await _probeOne(host, creds, onFingerprint);
        } catch (e) {
          _log.warning('probe falló ${host.name}', e);
          r = FleetHostResult(host: host, agents: const [], error: '$e');
        }
        if (!controller.isClosed) controller.add(r);
        pending--;
        maybeClose();
      }();
    }
    maybeClose();
    return controller.stream;
  }

  Future<FleetHostResult> _probeOne(
    SshHostInfo host,
    HerdrCredentials creds,
    Future<void> Function(SshHostInfo host, String sha256) onFingerprint,
  ) async {
    final socket = await SSHSocket.connect(
      host.host,
      host.port,
    ).timeout(const Duration(seconds: 8));
    SSHClient? client;
    try {
      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: creds.password == null
            ? null
            : () => creds.password!,
        identities: creds.privateKeyPem != null
            ? [...SSHKeyPair.fromPem(creds.privateKeyPem!, creds.passphrase)]
            : null,
        // TOFU: si el host ya tiene huella conocida, exige coincidencia.
        // Si NO tiene (host recién creado que aún no conectó por shell),
        // el primer probe fija la huella (trust on first use, misma política
        // que el connect interactivo) y la persiste vía [onFingerprint].
        onVerifyHostKey: (type, Uint8List fingerprint) async {
          final sha = utf8.decode(fingerprint);
          final known = host.knownFingerprint;
          if (known == null) {
            await onFingerprint(host, sha);
            return true;
          }
          return sha == known;
        },
      );
      final herdr = HerdrClient(ssh: client);
      final outcome = await _agentsOf(
        herdr,
      ).timeout(const Duration(seconds: 40));
      if (outcome.notFound) {
        return FleetHostResult(
          host: host,
          agents: const [],
          notFound: true,
          error:
              'herdr no encontrado en la PATH de la shell SSH. '
              'Comprueba `which herdr` al conectarte por terminal.',
        );
      }
      return FleetHostResult(host: host, agents: outcome.agents);
    } finally {
      await client?.close();
    }
  }

  Future<_ProbeOutcome> _agentsOf(HerdrClient herdr) async {
    if (!await herdr.isAvailable()) return const _ProbeOutcome(notFound: true);
    return _ProbeOutcome(agents: await herdr.listAgents());
  }
}

class _ProbeOutcome {
  final List<HerdrAgent> agents;
  final bool notFound;
  const _ProbeOutcome({this.agents = const [], this.notFound = false});
}

class FleetHostResult {
  final SshHostInfo host;
  final List<HerdrAgent> agents;
  final String? error;
  final bool notFound;

  const FleetHostResult({
    required this.host,
    required this.agents,
    this.error,
    this.notFound = false,
  });
}

/// Datos mínimos de host que el probe necesita (desacoplado de la DB).
class SshHostInfo {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? knownFingerprint;

  const SshHostInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.knownFingerprint,
  });
}

/// Credenciales ya leídas de secure storage.
class HerdrCredentials {
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;

  const HerdrCredentials({this.password, this.privateKeyPem, this.passphrase});
}
