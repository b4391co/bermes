// Diagnóstico end-to-end de grupos contra los gateways REALES del usuario.
// No hardcodea credenciales: HERMES_HOST / HERMES_USER / HERMES_PW.
// Uso: HERMES_HOST=... HERMES_USER=... HERMES_PW=... flutter test test/group_e2e_test.dart
@Tags(['real'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';
import 'package:hermes_pocket/domain/connection/connection_profile.dart';

final _host = Platform.environment['HERMES_HOST'] ?? '';
final _user = Platform.environment['HERMES_USER'] ?? '';
final _pw = Platform.environment['HERMES_PW'] ?? '';
final _ports = (Platform.environment['HERMES_PORTS'] ?? '9110,9112,9113,9119')
    .split(',')
    .map((p) => int.parse(p.trim()))
    .toList();

({HermesGatewayClient gw, HermesHttpClient http}) _conn(int port) {
  final profile = ConnectionProfile(
    id: 'e2e-$port',
    name: 'e2e-$port',
    scheme: 'http',
    host: _host,
    port: port,
    authKind: HermesAuthKind.password,
    username: _user,
  );
  final http = HermesHttpClient(profile);
  return (gw: HermesGatewayClient(profile, http), http: http);
}

Future<({bool ok, Object? res, Object? err})> _try(
  String label,
  Future<Object?> Function() f,
) async {
  try {
    final r = await f();
    // ignore: avoid_print
    print('· $label OK ${_short(r)}');
    return (ok: true, res: r, err: null);
  } catch (e) {
    // ignore: avoid_print
    print('· $label ERR $e');
    return (ok: false, res: null, err: e);
  }
}

String _short(Object? o) {
  final s = '$o';
  return s.length > 220 ? '${s.substring(0, 220)}…' : s;
}

void main() {
  if (_host.isEmpty || _user.isEmpty || _pw.isEmpty) {
    test('sin credenciales: se omite (real-gateway)', () {
      return;
    }, skip: 'falta HERMES_*');
    return;
  }

  test('diagnóstico de grupos hosted contra gateways reales', () async {
    final installs = <int, String>{};
    final bots = <({int port, String profile})>[];
    for (final p in _ports) {
      try {
        final c = _conn(p);
        final res = await c.http.login(_user, _pw);
        expect(res.ok, isTrue, reason: 'login :$p ${res.cause} ${res.detail}');
        final resp = await c.http.getJson('/api/profiles');
        final list =
            ((resp is Map ? resp['profiles'] : resp) as List? ?? const [])
                .whereType<Map>()
                .map((e) => e.cast<String, Object?>())
                .toList();
        for (final m in list) {
          final n = m['name'] as String?;
          if (n != null && n != 'default') bots.add((port: p, profile: n));
        }
        installs[p] = await c.http.installId() ?? '?';
        c.gw.dispose();
        // ignore: avoid_print
        print(':$p bots=${list.map((m) => m['name']).toList()} install=${installs[p]}');
      } catch (e) {
        // ignore: avoid_print
        print(':$p falló: $e');
      }
    }
    expect(bots.length, greaterThan(1), reason: 'hace falta ≥2 bots');
    // Dos bots del MISMO gateway (los únicos que el backend puede enrutar sin
    // registro HTTPS de pares).
    final m1 = bots.first;
    final m2b = bots.firstWhere(
      (x) => x.port == m1.port && x.profile != m1.profile,
      orElse: () => throw StateError('el gateway de ${m1.port} necesita ≥2 bots'),
    );

    final c1 = _conn(m1.port);
    await c1.http.login(_user, _pw);
    await c1.gw.connect();
    final client = RoomsClient(c1.gw);
    final roomId = RoomsClient.newRoomId();

    // Contrato REAL verificado por sonda (2026-10-07): cada miembro exige
    // member_id + profile + handle; los miembros del MISMO gateway van sin
    // `target` (el backend pone kind:local). Miembros de OTROS gateways
    // requieren `target: {kind:'peer', peer_id, installation_id,
    // capability_digest, profile}`, y los peers sólo se registran por HTTPS
    // (5120 «target_url must use https outside the local machine»): en esta
    // red LAN http://, cross-gateway NO está soportado por el backend. La
    // regresión fija el camino que SÍ funciona: dos bots del mismo gateway.
    final rid = RoomsClient.newRoomId();
    final rows = [
      {'member_id': 'm0-${rid.substring(5, 13)}', 'profile': m1.profile, 'handle': m1.profile, 'display_name': m1.profile},
      {'member_id': 'm1-${rid.substring(5, 13)}', 'profile': m2b.profile, 'handle': m2b.profile, 'display_name': m2b.profile},
    ];
    final room = await client.create(
      'e2e-${DateTime.now().millisecondsSinceEpoch}',
      rows,
      roomId: rid,
    );
    expect(room, isNotNull);
    final st = await client.roomState(rid);
    // ignore: avoid_print
    print('STATE ${_short(st?.members.map((m) => m.label).toList())}');
    final ev = RoomsClient.newClientEventId();
    final th = RoomsClient.newThreadId();
    final snd = await _try(
      'send',
      () => client.send(rid, 'hola desde e2e', clientEventId: ev, threadId: th),
    );
    expect(snd.ok, isTrue, reason: 'groups.send');
    await Future.delayed(const Duration(seconds: 3));
    final log = await client.log(rid, sinceSeq: 0);
    // ignore: avoid_print
    print('LOG ${_short(log.events.map((e) => '${e.kind}:${e.payload['text'] ?? ''}').toList())}');
    expect(log.events.any((e) => e.kind == 'message.user'), isTrue);

    c1.gw.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
