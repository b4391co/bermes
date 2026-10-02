import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Utilidades de imagen de avatar del bot (editor de icono).
///
/// El reencuadre replica `normalizeAvatarImage` de Hermes Desktop
/// (`apps/desktop/src/plugins/hermes-bots/avatar-image.ts:17-36`): recorte al
/// cuadrado CENTRAL + reescalado a 256 px + recodificación a PNG, para que
/// `profiles.set_asset` acepte siempre (tope 2 MB y mágia
/// PNG/JPEG/WebP sniffada en el gateway,
/// `tui_gateway/methods_profiles.py:426-438`).
///
/// La decodificación se apoya en `dart:ui` (`instantiateImageCodec` +
/// `Canvas`), disponible en los dos targets —Android y Windows— sin traer una
/// dependencia de imagen: el paquete `image` sólo es transitivo aquí
/// (flutter_launcher_icons) y no se declara como directa.
class AvatarImage {
  /// Tope real del gateway (`methods_profiles.py:431`): 2 MB sobre los BYTES,
  /// no sobre el base64 del data-URL.
  static const maxBytes = 2_000_000;

  /// Lado del cuadro resultante (Desktop usa 256).
  static const edge = 256;

  /// Formatos que el gateway acepta por mágia. La extensión la ofrece el
  /// selector; la validación definitiva la hace el gateway.
  static const acceptedExtensions = ['png', 'jpg', 'jpeg', 'webp'];

  /// Elige un fichero de imagen y devuelve sus bytes.
  ///
  /// En Android el picker entrega un `content://` (sin `path` local): se leen
  /// con `readAsBytes()` de `PlatformFile`, que resuelve el SAF. En Windows
  /// devuelve `file://` y el mismo camino funciona.
  static Future<Uint8List?> pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: acceptedExtensions,
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      // SAF revoked / fichero movido: la UI informa y no guarda.
      return null;
    }
  }

  /// Bytes -> PNG recortado/encajado a [edge] px. Null si no decodifica
  /// (entonces la UI avisa: no se sube basura al gateway).
  static Future<Uint8List?> normalize(
    Uint8List bytes, {
    int edge = AvatarImage.edge,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final side = image.width < image.height ? image.width : image.height;
      final sx = ((image.width - side) / 2).round().toDouble();
      final sy = ((image.height - side) / 2).round().toDouble();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(sx, sy, side.toDouble(), side.toDouble()),
        ui.Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final out = await recorder.endRecording().toImage(edge, edge);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      out.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Data-URL -> bytes; null si no lo es o no decodifica.
  static Uint8List? fromDataUrl(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// Los bytes del asset viajan como data-URL PNG (el gateway sniffá la
  /// mágia; `methods_profiles.py:426` sólo acepta png/jpeg/webp).
  static String toDataUrl(Uint8List bytes) =>
      'data:image/png;base64,${base64Encode(bytes)}';
}
