import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';
import 'package:hermes_pocket/domain/connection/connection_profile.dart';

/// Adjudicación de causas de `POST /api/audio/transcribe` y de la lectura de
/// `GET /api/media?path=…` contra el contrato verificado en main:
/// web_models.py:84-86 (`{data_url, mime_type?}`), audio.py:87-141
/// (`{ok, transcript, provider}`; 400 sin STT con `detail`; 413 >25 MB),
/// files.py:301-339 (media responde JSON `{data_url}`, NUNCA binario; 403
/// fuera de raíces; 404 inexistente).
///
/// El adaptador falso responde lo que dice el contrato: si el cliente
/// volviera a leer `text` (clave equivocada) o a esperar binario, estos
/// tests fallan sin tocar la red.

/// `HttpClientAdapter.fetch` real (dio 5.11): devuelve el `ResponseBody` crudo
/// — el `Dio` de abajo decide el `Response<T>`. El adaptador responde lo que
/// dicta el contrato y deja que el pipeline de dio lo parseé.
class _FakeAdapter implements dio.HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<_FakeResp> Function(dio.RequestOptions) handler;

  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final r = await handler(options);
    return dio.ResponseBody.fromString(
      jsonEncode(r.body),
      r.status,
      headers: {
        dio.Headers.contentTypeHeader: [dio.Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeResp {
  final int status;
  final Map<String, dynamic> body;
  const _FakeResp(this.status, this.body);
}

ConnectionProfile _profile() => const ConnectionProfile(
  id: 'c1',
  name: 'test',
  scheme: 'http',
  host: '127.0.0.1',
  port: 9120,
  username: 'u',
);

/// Responde JSON al `send` del cliente como haría un gateway que habla el
/// contrato exacto (status + body).
HermesHttpClient _client(
  Future<_FakeResp> Function(dio.RequestOptions) handler,
) {
  final adapter = _FakeAdapter(handler);
  return HermesHttpClient(_profile(), adapterOverride: adapter);
}

Future<_FakeResp> _json(
  int status,
  Map<String, dynamic> body, [
  dio.RequestOptions? o,
]) async => _FakeResp(status, body);

void main() {
  group('transcribeAudio — adjudicación por contrato', () {
    test('200 con {transcript} → ok + provider', () async {
      final c = _client(
        (o) async => _json(200, {
          'ok': true,
          'transcript': 'hola desde la nota de voz',
          'provider': 'whisper',
        }, o),
      );
      final r = await c.transcribeAudio([1, 2, 3], mimeType: 'audio/mp4');
      expect(r.ok, isTrue);
      expect(r.text, 'hola desde la nota de voz');
      expect(r.provider, 'whisper');
    });

    test('200 con transcript vacío (silencio) → fail legible, no ok', () async {
      final c = _client(
        (o) async => _json(200, {'ok': true, 'transcript': ''}, o),
      );
      final r = await c.transcribeAudio([1], mimeType: 'audio/webm');
      expect(r.ok, isFalse);
      expect(r.detail, contains('ninguna palabra'));
    });

    test('400 sin STT con detail → version + detalle del proveedor', () async {
      final c = _client(
        (o) async => _json(400, {'detail': 'no STT provider configured'}, o),
      );
      final r = await c.transcribeAudio([1], mimeType: 'audio/webm');
      expect(r.ok, isFalse);
      expect(r.cause, AuthFailureCause.version);
      expect(r.detail, contains('no STT provider configured'));
    });

    test('401 → sesión caducada (badCredentials)', () async {
      final c = _client((o) async => _json(401, {'error': 'expired'}, o));
      final r = await c.transcribeAudio([1], mimeType: 'audio/webm');
      expect(r.cause, AuthFailureCause.badCredentials);
    });

    test('413 → rateLimited (límite 25 MB del gateway)', () async {
      final c = _client(
        (o) async => _json(413, {'detail': 'Audio recording is too large'}, o),
      );
      final r = await c.transcribeAudio([1], mimeType: 'audio/webm');
      expect(r.cause, AuthFailureCause.rateLimited);
    });

    test('el request manda data_url con prefijo data: y ;base64', () async {
      String? sentData;
      final c = _client((o) async {
        sentData = (o.data as Map)['data_url'] as String;
        return _json(200, {'ok': true, 'transcript': 'x', 'provider': 'p'}, o);
      });
      await c.transcribeAudio(base64.decode('AAE='), mimeType: 'audio/mp4');
      expect(sentData, startsWith('data:audio/mp4;base64,'));
    });
  });

  group('fetchMedia — JSON {data_url}, no binario', () {
    test('200 con data_url decodifica los bytes', () async {
      final png = base64.encode([0x89, 0x50, 0x4e, 0x47]);
      final c = _client(
        (o) async => _json(200, {'data_url': 'data:image/png;base64,$png'}, o),
      );
      final bytes = await c.fetchMedia('images/x.png');
      expect(bytes, [0x89, 0x50, 0x4e, 0x47]);
    });

    test('403 fuera de raíces → null (fallback UI), no excepción', () async {
      final c = _client((o) async => _json(403, {'error': 'outside roots'}, o));
      expect(await c.fetchMedia('attachments/x.bin'), isNull);
    });

    test('404 gateway antiguo sin ruta → null', () async {
      final c = _client((o) async => _json(404, {'error': 'not found'}, o));
      expect(await c.fetchMedia('images/y.png'), isNull);
    });
  });
}
