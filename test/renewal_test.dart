/// Renovación automática de sesión: el fake gateway en :9122 (lanzado con
/// FAKE_WS_REJECT=1 o tras `curl /api/mode?ws_reject=1`) cierra el WS con
//
library;
/// 4401 antes de `gateway.ready` — la misma señal que el gate real usa para
/// credencial muerta (chat_ws.py:139-151). El gestor debe re-autenticarse
/// con la contraseña recordada y reconectar, sin bucle (enfriamiento 2 min).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_pocket/clients/hermes/gateway_client.dart';

import 'renew_harness.dart';

void main() {
  test('renovación automática tras close 4401', () async {
    // El arnés necesita el fake real: python3 tools/fake_gateway.py 9122
    try {
      final sock = await Socket.connect('127.0.0.1', 9122,
          timeout: const Duration(seconds: 2));
      sock.destroy();
    } catch (_) {
      markTestSkipped('fake gateway no activo en :9122');
    }

    // Activar el cierre 4401 en el fake y neutralizar modos de otros tests.
    final modeReq = await HttpClient()
        .getUrl(Uri.parse(
            'http://127.0.0.1:9122/api/mode?ws_reject=1&session_token=0&canonical=1'));
    await modeReq.close();

    final h = RenewHarness(connectionPort: 9122);
    await h.setUp();
    addTearDown(h.tearDown);
    addTearDown(() async {
      // ws_reject es estado GLOBAL del proceso del fake: se apaga al salir.
      final reset = await HttpClient().getUrl(Uri.parse(
          'http://127.0.0.1:9122/api/mode?ws_reject=0&session_token=0&canonical=1'));
      await reset.close();
    });

    await h.manager.bootstrap(h.rows, secrets: h.secrets, db: h.db);
    final runtime = h.manager.runtimeFor('renew-1')!;
    // bootstrap: login ok → WS cierra 4401 → authExpired → renovación
    // (re-login) → reconexión → 4401 → el enfriamiento evita el bucle.
    await Future<void>.delayed(const Duration(seconds: 8));
    expect(
      runtime.gateway.state,
      anyOf(
        GatewayLinkState.authExpired, // enfriado tras 1 renovación
        GatewayLinkState.reconnecting, // backoff tras el 2º 4401
      ),
    );
    // readRememberedPassword: 1 lectura en bootstrap + 1 por renovación.
    expect(h.secrets.readCount, greaterThanOrEqualTo(2),
        reason: 'bootstrap + renovación leen la contraseña recordada');
    // El enfriamiento de 2 min impide el bucle: en 8 s como mucho una
    // segunda renovación (bootstrap + 2 lecturas, nunca más).
    expect(h.secrets.readCount, lessThanOrEqualTo(3),
        reason: 'el enfriamiento de 2 min evita el bucle de re-login');
  });
}
