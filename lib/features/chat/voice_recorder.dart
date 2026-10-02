import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/logger.dart';

/// Grabadora de la «nota de voz» del Pocket.
///
/// Qué es y qué NO es (contrato verificado, docs/research/
/// adjuntos-y-notas-de-voz.md §B): no existe tipo «nota de voz» en el
/// backend — la voz del gateway es STT→texto y el audio NO se persiste.
/// Esta clase produce un fichero local m4a/AAC (Android) listo para
/// `POST /api/audio/transcribe`; el audio viaja, se transcribe, y sólo el
/// TEXTO entra al chat. Nunca se anuncia «audio enviado».
///
/// Formato: `.m4a` (audio/mp4) en Android — `_AUDIO_MIME_EXTENSIONS` del
/// gateway lo acepta (aac/m4a/mp4 → tempfile con esa extensión; whisper/ffmpeg
/// lo leen). iOS no es objetivo prioritario: el `record` de iOS produce
/// `.m4a` igual, y si no compila se apaga con kIsWeb-style guard en la UI.
class VoiceRecorder {
  VoiceRecorder();

  final AudioRecorder _rec = AudioRecorder();
  final _log = Logger('Voice');
  String? _path;
  Timer? _tick;
  bool _paused = false;

  final _elapsedController = StreamController<Duration>.broadcast();

  /// Duración en vivo (según avanza la grabación).
  Stream<Duration> get elapsed => _elapsedController.stream;
  Duration lastElapsed = Duration.zero;
  bool get isRecording => _path != null;
  bool get isPaused => _paused;

  /// Pide el permiso de micrófono. `false` = denegado/permanente: la UI lo
  /// dice y ofrece el ajuste de Android, sin reintentos silenciosos.
  Future<bool> hasAccess() async {
    try {
      // record 6.x: `request: true` dispara el prompt de runtime la primera
      // vez (Android); el manifest declara RECORD_AUDIO.
      return await _rec.hasPermission(request: true);
    } on Object catch (e) {
      _log.warning('permiso de micro no consultable', e);
      return false;
    }
  }

  /// Inicia la grabación. Lanza [VoiceRecordingException] con causa legible.
  Future<void> start() async {
    if (_path != null) return;
    if (!await hasAccess()) {
      throw const VoiceRecordingException(
        'Sin permiso de micrófono. Concédelo en Ajustes de la app.',
      );
    }
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    try {
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } on Object catch (e) {
      throw VoiceRecordingException('No se pudo abrir el micrófono: $e');
    }
    _path = path;
    lastElapsed = Duration.zero;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      lastElapsed += const Duration(seconds: 1);
      if (!_elapsedController.isClosed) _elapsedController.add(lastElapsed);
    });
  }

  Future<void> pause() async {
    if (_path == null || _paused) return;
    _paused = true;
    _tick?.cancel();
    try {
      await _rec.pause();
    } on Object catch (e) {
      _log.warning('pause falló', e);
    }
  }

  Future<void> resume() async {
    if (_path == null || !_paused) return;
    _paused = false;
    try {
      await _rec.resume();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        lastElapsed += const Duration(seconds: 1);
        if (!_elapsedController.isClosed) _elapsedController.add(lastElapsed);
      });
    } on Object catch (e) {
      _log.warning('resume falló', e);
    }
  }

  /// Detiene y devuelve los bytes grabados + mime. Lanza
  /// [VoiceRecordingException] si no hay grabación o el fichero quedó vacío.
  Future<VoiceRecording> stop() async {
    final path = _path;
    _tick?.cancel();
    _tick = null;
    _path = null;
    _paused = false;
    if (path == null) {
      throw const VoiceRecordingException('No hay grabación en curso.');
    }
    String? out;
    try {
      out = await _rec.stop();
    } on Object catch (e) {
      // stop() ya liberó el recurso en algunas plataformas: se intenta leer
      // el path original antes de rendirse.
      _log.warning('stop devolvió error, leyendo path original', e);
    }
    final file = File(out ?? path);
    if (!await file.exists()) {
      throw const VoiceRecordingException('La grabación no llegó a guardarse.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 1024) {
      await file.delete().catchError((_) => file);
      throw const VoiceRecordingException(
        'La grabación quedó vacía (menos de un segundo).',
      );
    }
    unawaited(file.delete().catchError((_) => file));
    // mime real del contenedor que produce `record` en Android con
    // aacLc + path .m4a (audio/mp4); el gateway mapea mp4/m4a/aac → extensión.
    return VoiceRecording(bytes: bytes, mimeType: 'audio/mp4');
  }

  /// Cancela sin entregar nada (el usuario pulsó X). Borra el temporal.
  Future<void> cancel() async {
    final path = _path;
    _tick?.cancel();
    _tick = null;
    _path = null;
    _paused = false;
    try {
      await _rec.stop();
    } on Object catch (_) {
      /* la cancelación no propaga fallos de transporte de audio */
    }
    if (path != null) {
      await File(path).delete().catchError((_) => File(path));
    }
  }

  Future<void> dispose() async {
    _tick?.cancel();
    _tick = null;
    await _elapsedController.close();
    await _rec.dispose();
  }
}

class VoiceRecording {
  final List<int> bytes;
  final String mimeType;
  const VoiceRecording({required this.bytes, required this.mimeType});
}

class VoiceRecordingException implements Exception {
  final String message;
  const VoiceRecordingException(this.message);
  @override
  String toString() => message;
}
