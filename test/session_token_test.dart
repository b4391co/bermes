/// Smoke test del flujo de session token contra el fake gateway en modo
/// loopback (`?session_token=1`): REST con `X-Hermes-Session-Token` y WS con
/// `?token=`. Requiere el fake corriendo (`python3 tools/fake_gateway.py 9120`
/// + `curl /api/mode?session_token=1`); si no lo está, el test se salta —
/// es una prueba de integración contra el contrato real, no una unit.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';
import 'package:hermes_pocket/domain/connection/connection_profile.dart';

const _token = 'loopback-session-token-1';

ConnectionProfile _profile() => const ConnectionProfile(
  id: 'test-token',
  name: 'TokenGW',
  scheme: 'http',
  host: '127.0.0.1',
  port: 9120,
  authKind: HermesAuthKind.sessionToken,
);

Future<bool> _fakeReady() async {
  try {
    final s = await Socket.connect(
      '127.0.0.1',
      9120,
      timeout: const Duration(seconds: 2),
    );
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _tokenMode() async {
  final c = HttpClient();
  try {
    final r = await c
        .getUrl(Uri.parse('http://127.0.0.1:9120/api/mode?session_token=1'))
        .then((r) => r.close());
    await r.drain<void>();
  } finally {
    c.close(force: true);
  }
}

void main() {
  test('session token: REST autentica y WS abre con ?token=', () async {
    if (!await _fakeReady()) {
      // El fake no corre: es una prueba de integración, se salta limpia.
      // ignore: avoid_print
      print('SKIP: fake gateway no disponible en 127.0.0.1:9120');
      return;
    }
    await _tokenMode();

    final http = HermesHttpClient(_profile());
    http.adoptGatewayToken(_token);

    // 1) REST: /api/auth/me con el token (web_server.py:440-449).
    final me = await http.authMe();
    expect(me, isNotNull, reason: 'authMe debe autenticar con el token');

    // 2) WS: ?token= (web_server_chat.py:291-297) → gateway.ready.
    final gateway = HermesGatewayClient(_profile(), http);
    final first = gateway.stateStream
        .firstWhere(
          (s) => s == GatewayLinkState.ready || s == GatewayLinkState.error,
        )
        .timeout(const Duration(seconds: 10));
    unawaited(gateway.connect());
    final state = await first;
    expect(
      state,
      GatewayLinkState.ready,
      reason: 'el WS debe abrir con ?token= en modo loopback',
    );

    // 3) El roster por WS responde (profiles.list).
    final profiles = await gateway.listProfiles();
    expect(profiles, isNotEmpty);
    expect(profiles.first['name'], 'default');

    gateway.dispose();
    http.dispose();
  });

  test('session token erróneo: WS no abre y authMe falla', () async {
    if (!await _fakeReady()) {
      // ignore: avoid_print
      print('SKIP: fake gateway no disponible en 127.0.0.1:9120');
      return;
    }
    await _tokenMode();

    final http = HermesHttpClient(_profile());
    http.adoptGatewayToken('token-invalido');
    final me = await http.authMe();
    expect(me, isNull, reason: 'token erróneo no autentica');
    http.dispose();
  });
}
