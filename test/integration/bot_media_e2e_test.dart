/// Prueba E2E del pipeline de medios ENTREGADOS POR EL BOT:
///  - el historial (`GET /api/sessions/{id}/messages`) puede traer filas de
///    asistente con etiquetas `MEDIA:` (contrato de Desktop, parts.ts);
///  - `splitAssistantMedia` las convierte en adjuntos (text limpio + path);
///  - `GET /api/fs/read-data-url` (files.py:901-922, same route Desktop uses)
///    devuelve `{dataUrl}` con los bytes reales bajo autenticación.
/// Corre contra el gateway LOCAL `claudio` (127.0.0.1:19110) si está vivo;
/// si no, SKIPS (es una prueba de integración, no de unidad).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';
import 'package:hermes_pocket/domain/connection/connection_profile.dart';
import 'package:hermes_pocket/domain/message/media_tags.dart';

void main() {
  test('historial del bot con MEDIA: → adjuntos + bytes reales del gateway', () async {
    final profile = const ConnectionProfile(
      id: 'home',
      name: 'claudio',
      scheme: 'http',
      host: '127.0.0.1',
      port: 19110,
      username: 'breo',
    );
    final http = HermesHttpClient(profile);
    final r = await http.login('breo', _envPass());
    if (!r.ok) {
      markTestSkipped('gateway local no accesible (${r.detail})');
      return;
    }
    // Un PNG real en las raíces de entregables del perfil default.
    // Primero: pedir al gateway su propio archivo de avatar (siempre existe
    // bajo HERMES_HOME de `default`): profiles.get_asset → data URL base64.
    // Para read-data-url usamos una ruta relativa al HOME del perfil que el
    // gateway SÍ sirve: el archivo de config `config.yaml` es sensible?
    // (NO lo pedimos). Elegir `sessions` JSON público del propio chat:
    // en su lugar, usamos una imagen que NOSOTROS acabamos de subir por
    // session.upload → queda en <HERMES_HOME>/images (raíz de /api/media).
    // Paso 1: subir un PNG 1x1 vía el método REAL de adjuntos
    // (`image.attach_bytes` → <HERMES_HOME>/images/...; el mismo que usa el
    // envío de imágenes desde la burbuja).
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final gateway = HermesGatewayClient(profile, http);
    await gateway.connect();
    if (gateway.state != GatewayLinkState.ready) {
      markTestSkipped('el gateway no aceptó la sesión WS (${gateway.state})');
      return;
    }
    final sessionId = await gateway.resumeCanonicalSession('default');
    if (sessionId == null) {
      markTestSkipped('sin sesión canónica para default');
      return;
    }
    // `image.attach_bytes` habla con el runtime RESUMIDO (4001 si se le da
    // la id duradera — contrato verificado aquí mismo en vivo).
    final runtimeId = await gateway.resumeSession(sessionId, profile: 'default');
    final up = await gateway.rawCall(
      'image.attach_bytes',
      params: {
        'session_id': runtimeId,
        'profile': 'default',
        'content_base64': base64Encode(png),
        'filename': 'pocket_media_e2e.png',
      },
    );
    final upMap = up is Map ? Map<String, Object?>.from(up) : const <String, Object?>{};
    if (upMap['attached'] != true) {
      markTestSkipped('image.attach_bytes rechazado: ${upMap['message']}');
      return;
    }
    final upPath = upMap['path'] as String? ?? '';
    // Paso 2: el mismo camino que la burbuja: splitAssistantMedia del texto
    // del bot → attachment.path → read-data-url → bytes idénticos.
    final split = splitAssistantMedia(
      'imagen pedida:\nMEDIA: $upPath\n',
    );
    expect(split.media, hasLength(1));
    expect(split.text, 'imagen pedida:');
    final res = await http.fetchFsDataUrl(
      split.media.first.path,
      profile: 'default',
    );
    if (res == null) {
      markTestSkipped('read-data-url no servido en esta versión');
      return;
    }
    expect(res.bytes, equals(png));
    expect(res.mime, startsWith('image/'));
  });
}

String _envPass() =>
    const String.fromEnvironment('POCKET_TEST_PASS', defaultValue: '');
