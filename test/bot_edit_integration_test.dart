// Test de integración del guardado de ficha de bot contra el fake gateway:
// profileRosterMeta → configureBot (CAS) → rechazo CAS sin lanzar. Reproduce
// el flujo de `_save` en `bot_editor_sheet.dart`. Requiere el fake en
// 127.0.0.1:9120; si no, SKIP.
import 'dart:io';

import 'package:test/test.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';
import 'package:hermes_pocket/clients/hermes/bot_meta.dart';
import 'package:hermes_pocket/domain/connection/connection_profile.dart';

ConnectionProfile _profile() => const ConnectionProfile(
  id: 'test-edit',
  name: 'EditGW',
  scheme: 'http',
  host: '127.0.0.1',
  port: 9120,
  authKind: HermesAuthKind.password,
);

Future<bool> _fakeReady() async {
  // El fake puede quedar en modo session_token (otro flujo E2E lo activa
  // para la app del emulador). Este test entra por cookie+ticket: forzar el
  // modo ticket ANTES de conectar.
  try {
    final c = await HttpClient().getUrl(
      Uri.parse('http://127.0.0.1:9120/api/mode?session_token=0'),
    );
    await c.close();
  } catch (_) {}
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

void main() {
  test('ficha de bot: leer meta → configure con CAS → ok', () async {
    if (!await _fakeReady()) {
      // ignore: avoid_print
      print('SKIP: fake gateway no disponible en 127.0.0.1:9120');
      return;
    }
    final http = HermesHttpClient(_profile());
    final login = await http.login('test', 'hermespass');
    expect(login.ok, isTrue, reason: 'login fake: ${login.detail}');
    final gw = HermesGatewayClient(_profile(), http);
    await gw.connect();
    await gw.readyOrTimeout(const Duration(seconds: 15));

    final found = await gw.profileRosterMeta('default', withAvatar: true);
    expect(found.meta, isNotNull, reason: 'meta del default disponible');
    // El CAS usa la revisión LEÍDA; con 0 no leída el fake rechaza.
    final ok = await gw.configureBot(
      'default',
      title: 'Compi',
      description: 'Bot con meta hermes-mobile',
      avatar: BotAvatarMeta(shape: 'squircle', color: 'hsl(120 68% 58%)'),
      // Igual que el sheet (fix 0.1.26): reenviar las groups leídas, o el
      // reemplazo de sección las borra y Desktop pierde al miembro.
      groups: found.meta?.groups ?? const [],
      expectedRevision: found.revision,
    );
    expect(ok, isTrue, reason: 'configure con la revisión leída debe aplicar');

    // La pertenencia sobrevive a la escritura (contrato de reemplazo).
    final after = await gw.profileRosterMeta('default', withAvatar: false);
    expect(after.meta?.groups, found.meta?.groups,
        reason: 'groups no debe borrarse al guardar la ficha');

    // La revisión avanzó: una segunda escritura con la revisión VIEJA falla
    // (conflicto CAS, aplicado.ui_meta=false) — y NO debe lanzar.
    // ignore: unused_local_variable
    final okStale = await gw.configureBot(
      'default',
      title: 'Compi',
      avatar: const BotAvatarMeta(shape: 'circle'),
      groups: found.meta?.groups ?? const [],
      expectedRevision: found.revision,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
