import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/message/chat_models.dart';

/// Caché multimedia local de las imágenes del chat.
///
/// Por qué existe (contratos verificados en main):
/// - `GET /api/media?path=…` (files.py:301-339) devuelve JSON `{data_url}` y
///   está restringido a `<HERMES_HOME>/{images,screenshots,cache}` del proceso
///   dashboard; en multiperfil la imagen de OTRO perfil vive fuera de esa raíz
///   → 403 sin segunda ruta de lectura.
/// - el historial proyecta las imágenes como `@image:<ruta>` SIN bytes, así
///   que la única forma de verlas tras reiniciar la app es o bien la red o
///   esta caché.
///
/// Clave: sha1-safe de la ruta gateway (nunca el nombre: dos gateways pueden
/// repetir nombre; el path del gateway es lo que se serializa en la fila).
/// Límite blando: 32 MB; al pasar, se purga la mitad más antigua por mtime.
/// Ponytail: un solo mapa de ficheros en app-cache; si crece demasiado, el
/// upgrade es SQLite FTS o un LRU indexado — no hace falta hoy.
class MediaCache {
  MediaCache._();

  static const _maxBytes = 32 * 1024 * 1024;

  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/hermes-media');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _key(String gatewayPath) {
    final re = RegExp(r'[^A-Za-z0-9._-]');
    final cleaned = gatewayPath.replaceAll(re, '_');
    // Sufijo corto derivado del largo+ruta: evita colisiones tras el filtrado.
    var h = 0x811c9dc5;
    for (final c in gatewayPath.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return '${cleaned}_${h.toRadixString(16)}';
  }

  /// Guarda los bytes bajo `path` y devuelve el adjunto con `localBytes`
  /// rellenos (el que se persiste/usa en la burbuja).
  static Future<MessageAttachment> put(
    MessageAttachment a,
    List<int> bytes,
  ) async {
    if (a.path.isEmpty) return a;
    try {
      final f = File('${(await _dir()).path}/${_key(a.path)}');
      await f.writeAsBytes(bytes, flush: true);
      unawaitedPurge();
      return a.withLocalBytes(bytes);
    } on Object {
      // Disco lleno / permisos: se pinta vía gateway sin caché. No es un
      // fallo de envío: el turno ya está en el gateway.
      return a;
    }
  }

  /// Carga síncrona desde la caché (no bloqueante en el sentido de red;
  /// `readAsBytesSync` sobre ficheros pequeños de miniatura es aceptable en
  /// el frame de construcción de la lista). null si no está en caché.
  static MessageAttachment? load(String gatewayPath) {
    if (gatewayPath.isEmpty) return null;
    try {
      final f = File('${_dirSync().path}/${_key(gatewayPath)}');
      if (!f.existsSync()) return null;
      final bytes = f.readAsBytesSync();
      if (bytes.isEmpty) return null;
      return MessageAttachment(
        path: gatewayPath,
        name: gatewayPath.split('/').last,
        bytes: bytes.length,
        localBytes: bytes,
      );
    } on Object {
      return null;
    }
  }

  static Directory _dirSync() {
    // path_provider no tiene versión síncrona; se resuelve una vez y se
    // cachea el path. El primer load() del frame puede perder la carrera y
    // devolver null → la burbuja usa la ruta de red (correcto, no roto).
    return _cachedDir ?? Directory.systemTemp;
  }

  static Directory? _cachedDir;

  /// Calienta el directorio en el arranque del chat (await antes de la
  /// primera página de historial).
  static Future<void> warm() async => _cachedDir ??= await _dir();

  static void unawaitedPurge() {
    // fuego-y-olvida: purgar no debe bloquear el guardado siguiente.
    purge().ignore();
  }

  static Future<void> purge() async {
    try {
      final d = await _dir();
      final files = d
          .listSync()
          .whereType<File>()
          .map((f) => (f, f.statSync()))
          .toList();
      var total = files.fold<int>(0, (s, e) => s + e.$2.size);
      if (total <= _maxBytes) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (f, st) in files) {
        if (total <= _maxBytes) break;
        total -= st.size;
        await f.delete();
      }
    } on Object {
      // La caché es optimización: si falla, la app sigue leyendo del gateway.
    }
  }
}
