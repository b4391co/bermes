/// Extracción de etiquetas de medios `MEDIA:` del texto del asistente.
///
/// Puerto fiel del parser de Hermes Desktop
/// (`apps/desktop/src/lib/chat-messages/parts.ts:186-296`), que a su vez se
/// alinea con `MEDIA_DELIVERY_EXTS` del gateway
/// (`gateway/platforms/base.py`). El bot DELIVERA archivos escribiendo
/// `MEDIA: /ruta/al/archivo.png` (solo o en prosa, entre comillas o
/// backticks); el Pocket debe convertirlo en una tarjeta de medio, nunca
/// mostrar el tag crudo (encargo §6: adjuntos cuando el backend los expone).
library;

import 'chat_models.dart';

/// Extensiones entregables conocidas (espejo de MEDIA_DELIVERY_EXTS en
/// parts.ts).
const List<String> mediaDeliveryExts = [
  'avi', 'bmp', 'bz2', 'csv', 'doc', 'docx', 'epub', 'flac', 'gif', 'gpx',
  'gz', 'htm', 'html', 'jpeg', 'jpg', 'json', 'key', 'kmz', 'kml', 'm2a',
  'm4a', 'md', 'mkv', 'mov', 'mp3', 'mp4', 'odp', 'ods', 'odt', 'ogg',
  'opus', 'pdf', 'png', 'pptx', 'rar', 'rtf', 'svg', 'tar', 'tgz', 'tiff',
  'txt', 'webm', 'webp', 'xls', 'xlsx', 'xml', 'xz', 'yaml', 'yml', 'zip',
  '3gp', '7z', 'geojson', 'tsv',
];

// Alternancia de extensiones: longest-first (parts.ts).
final String _extAlt = (List<String>.from(mediaDeliveryExts)
  ..sort((a, b) => b.length.compareTo(a.length)))
    .join('|');

// Grupos de captura del patrón común:
//   1 = `backtick`   2 = "doble"   3 = 'simple'
//   4 = ruta anclada (~/ | / | X:\ con espacios interiores, terminada en
//       extensión conocida)   5 = ruta bare (cualquier palabra sin espacios,
//       backtick ni comilla doble — el apóstrofo es legal dentro)
final String _captureAlternation =
    '`([^`\\n]+)`|"([^"\\n]+)"|\'([^\'\\n]+)\'|'
    '((?:~/|/|[A-Za-z]:[/\\\\])\\S+?(?:[^\\S\\n]+\\S+?)*\\.(?:$_extAlt)'
    '(?=[\\s`\'"*_,;)\\]}]|\$))|'
    '([^\\s`"]+)';

final RegExp _mediaLineRe = RegExp(
  '(^|\\n)[\\t ]*[`\'"]?MEDIA:\\s*(?:$_captureAlternation)[`\'"]?[\\t ]*(\\n|\$)',
);

final RegExp _mediaTagRe = RegExp(
  '[`\'"]?MEDIA:\\s*(?:$_captureAlternation)[`\'"]?',
);

/// Puntuación de fin de frase que puede colarse en una captura bare
/// (`MEDIA:/tmp/a.pdf.` → el punto es prosa). parts.ts
/// _MEDIA_TRAILING_PUNCTUATION.
const String _trailingPunctuation = '.,;:!?';

/// Si una captura puede nombrar un archivo real: separador de ruta o punto
/// con contenido detrás. Cualquier otra cosa (`...`, palabra suelta) es
/// prosa (parts.ts isPlausibleMediaPath #84361).
bool isPlausibleMediaPath(String value) =>
    value.contains('/') ||
    value.contains(r'\') ||
    RegExp(r'\.[^.]').hasMatch(value);

/// Quita comillas envolventes (escape del documento para nombres raros) y
/// residuo de formato (backtick/`"` finales; el apóstrofo NO es residuo).
String _unquote(String value) {
  final t = value.trim();
  if (t.isEmpty) return t;
  final q = t[0];
  if (q == t[t.length - 1] && (q == '"' || q == "'" || q == '`')) {
    return t.substring(1, t.length - 1);
  }
  final last = t[t.length - 1];
  return (last == '`' || last == '"') ? t.substring(0, t.length - 1) : t;
}

/// Separa path y puntuación de frase colante de una captura BARE. Las
/// capturas entrecomilladas están exentas (lo que sea que dicen las comillas
/// es el nombre). parts.ts splitTrailingPunctuation.
(String path, String punctuation) _splitTrailingPunct(String value) {
  var end = value.length;
  while (end > 0 && _trailingPunctuation.contains(value[end - 1])) {
    if (!isPlausibleMediaPath(value.substring(0, end - 1))) break;
    end--;
  }
  return (value.substring(0, end), value.substring(end));
}

/// Resultado de separar los medios del texto.
class MediaSplit {
  /// Texto sin las etiquetas `MEDIA:` (ya sean líneas dedicadas o en prosa).
  final String text;

  /// Adjuntos en orden de aparición. `path` es lo que el bot escribió
  /// (ruta visible para el gateway).
  final List<MessageAttachment> media;

  const MediaSplit(this.text, this.media);
}
MediaSplit splitAssistantMedia(String text) {
  final out = <MessageAttachment>[];
  // La línea dedicada ocupa `(lead)(contenido)(trailer)`: groups 1-5 =
  // alternancia, 6 = trailer (\n o fin). Para conservar el separador
  // entre párrafos se reconstruye lead+trailer como UN salto.
  var cleaned = text.replaceAllMapped(_mediaLineRe, (m) {
    final a = _attachmentFromMatch(m);
    if (a == null) return m[0]!;
    out.add(a);
    final lead = m[1] ?? '';
    final trailer = m[6] ?? '';
    return (lead.isNotEmpty && trailer.isNotEmpty) ? '\n' : lead + trailer;
  });
  // Tags en prosa (inline).
  cleaned = cleaned.replaceAllMapped(_mediaTagRe, (m) {
    final a = _attachmentFromMatch(m);
    if (a == null) return m[0]!;
    out.add(a);
    return '';
  });
  return MediaSplit(cleaned.trimRight(), out);
}

MessageAttachment? _attachmentFromMatch(Match m) {
  // Grupos de captura (mutuamente excluyentes): 1 backtick, 2 doble, 3
  // simple, 4 anclada, 5 bare.
  String? raw;
  int quotedFrom = 0;
  for (var i = 1; i <= 5; i++) {
    final g = m[i];
    if (g != null && g.trim().isNotEmpty) {
      raw = g;
      // Los grupos 1-3 son contenido ENTRE comillas ⇒ quoted.
      quotedFrom = i <= 3 ? i : 0;
      break;
    }
  }
  if (raw == null) return null;
  final un = _unquote(raw);
  final (path, _) = quotedFrom > 0 ? (un, '') : _splitTrailingPunct(un);
  if (!isPlausibleMediaPath(path)) return null;
  return MessageAttachment(path: path, name: _baseName(path));
}

/// Nombre visible: último tramo tras `/` o `\` (mediaName en Desktop, sin
/// necesidad de URL: la ruta del bot es del gateway).
String _baseName(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Kind de presentación por extensión (espejo de MEDIA_BY_EXT/`mediaKind`
/// en Desktop; desconocida = 'file').
String mediaKindOf(String path) {
  final ext = _baseName(path).split('.').last.toLowerCase();
  const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'tiff'};
  const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};
  const audio = {'mp3', 'm2a', 'wav', 'ogg', 'opus', 'm4a', 'flac'};
  if (images.contains(ext)) return 'image';
  if (videos.contains(ext)) return 'video';
  if (audio.contains(ext)) return 'audio';
  // PDF es visor propio; md/markdown siguen como doc (texto).
  if (ext == 'pdf') return 'pdf';
  if (ext == 'md' || ext == 'markdown') return 'doc';
  return 'file';
}
