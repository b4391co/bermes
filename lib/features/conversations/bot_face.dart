/// Cara procedural de bot (blobatar) — contrato Hermes Desktop
/// `apps/desktop/src/plugins/hermes-bots/avatar.tsx` (commit 91b1791).
///
/// Desktop renderiza `BotFace` como SVG animado: cuerpo = anillo de la forma
/// proyectada con turn/tilt/roll, ojos + catchlights con gaze del mood, y
/// para `blobatar:*` una silueta derivada del seed. Pocket renderiza la
/// versión ESTÁTICA (mood idle, sin animación): misma geometría base y
/// mismo lenguaje visual, formato nativo Flutter.
///
/// Contrato de `shape` (cadena opaca guardada en
/// `ui_meta.hermes-bots.avatar.shape`):
/// - Formas clásicas: `circle`, `blob`, `squircle`, `pill`, `triangle`,
///   `hexagon`, `cloud`, `drop` (AVATAR_PICKER_SHAPES, avatar.tsx:27).
/// - Blob: `blobatar` (auto por nombre), `blobatar:<seed>`,
///   `blobatar:<seed>:<kind>`, `blobatar::<kind>` (avatar.tsx:120-124);
///   BLOB_KINDS: round, organic, boxy, capsule, nub, cloud, droplet,
///   hexagon, sun, triangle (avatar.tsx:128-139).
/// - Legado hermes-mobile: `rounded`, `square`, `hexagon` → se mapean.
///
/// El color sigue el contrato del editor de Desktop: hex propio del usuario
/// o `hsl(H S% L%)` del hue determinista por nombre
/// (`apps/desktop/src/lib/profile-color.ts:20-34`).
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Formas clásicas del picker de Desktop (avatar.tsx:27).
const kDesktopShapes = <String>[
  'circle',
  'blob',
  'squircle',
  'pill',
  'triangle',
  'hexagon',
  'cloud',
  'drop',
];

/// Siluetas blob (BLOB_KINDS, avatar.tsx:128-139).
const kBlobKinds = <String>[
  'round',
  'organic',
  'boxy',
  'capsule',
  'nub',
  'cloud',
  'droplet',
  'hexagon',
  'sun',
  'triangle',
];

/// ¿Es una forma blobatar? (avatar.tsx:160-162).
bool isBlobShape(String? shape) =>
    shape != null && (shape == 'blobatar' || shape.startsWith('blobatar:'));

/// Hash determinista de Desktop (profile-color.ts:9-13 y avatar.tsx:108-111):
/// `hash = hash*31 + code`, uint32. Mismo algoritmo → mismo hue/cara que
/// Desktop para el mismo nombre.
int desktopHash(String value) {
  var hash = 0;
  for (final ch in value.codeUnits) {
    hash = (hash * 31 + ch) & 0xFFFFFFFF;
  }
  return hash;
}

/// Hue determinista por nombre (profile-color.ts:20-34): null para
/// default/vacío, `hsl(H 68% 58%)` para el resto.
String? desktopProfileColor(String? name) {
  final key = (name ?? '').trim();
  if (key.isEmpty || key == 'default') return null;
  return 'hsl(${desktopHash(key) % 360} 68% 58%)';
}

/// Parsea `blobatar:<seed>:<kind>` (avatar.tsx:173-175): kind válido o ''.
({String seed, String kind})? parseBlobShape(String? shape, String name) {
  if (!isBlobShape(shape)) return null;
  if (shape == 'blobatar') return (seed: name, kind: '');
  final parts = shape!.split(':');
  // [blobatar, seed?, kind?] — seed puede ser vacío (`blobatar::<kind>`).
  final seedPart = parts.length > 1 ? parts[1] : '';
  final kind = parts.length > 2 && kBlobKinds.contains(parts[2])
      ? parts[2]
      : '';
  return (seed: seedPart.isEmpty ? name : seedPart, kind: kind);
}

/// Color aplicable: hex del meta, hsl del meta, o hue determinista.
Color resolveAvatarColor(String? colorSpec, String name) {
  final spec = colorSpec?.trim() ?? '';
  if (spec.startsWith('#') && spec.length >= 7) {
    final v = int.tryParse(spec.substring(1, 7), radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  final hsl = RegExp(r'hsl\((\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)%\)')
      .firstMatch(spec);
  if (hsl != null) {
    return HSLColor.fromAHSL(
      1,
      double.parse(hsl.group(1)!),
      double.parse(hsl.group(2)!) / 100,
      double.parse(hsl.group(3)!) / 100,
    ).toColor();
  }
  // Sin color propio: hue determinista por nombre (68/58 como Desktop);
  // default → verde hermes neutro.
  final auto = desktopProfileColor(name);
  if (auto != null) return resolveAvatarColor(auto, name);
  return const Color(0xFF1A7F5A);
}

/// Cara estática de bot. Trazado equivalente al SVG de Desktop:
/// cuerpo desde el anillo de la forma, dos ojos elípticos con catchlight,
/// proporciones del viewBox 40×40 de avatar.tsx (ojos cx 15.4/24.6, cy 17.2,
/// avatar.tsx:710-713).
class BotFace extends StatelessWidget {
  final String name;
  final String? shape;
  final String? color;
  final double size;

  const BotFace({
    super.key,
    required this.name,
    this.shape,
    this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BotFacePainter(
          name: name,
          shape: shape,
          colorSpec: color,
        ),
      ),
    );
  }
}

class _BotFacePainter extends CustomPainter {
  final String name;
  final String? shape;
  final String? colorSpec;

  _BotFacePainter({
    required this.name,
    required this.shape,
    required this.colorSpec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = resolveAvatarColor(colorSpec, name);
    final body = _bodyPath(shape, size);
    final fill = Paint()..color = color;

    // Cuerpo con sombra suave (Desktop pinta una sombra bajo el anillo).
    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.4), 2, false);
    canvas.drawPath(body, fill);

    // Ojos: gaze neutral (mood idle), posiciones relativas 40×40.
    final sx = size.width / 40;
    final sy = size.height / 40;
    final eyeY = (shape == 'cloud' ? 22.0 : 17.2) * sy;
    final eyePaint = Paint()..color = Colors.white;
    final r = 2.1 * math.min(sx, sy);
    for (final ex in [15.4, 24.6]) {
      final oval = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(ex * sx, eyeY),
          width: r * 1.55,
          height: r * 2.6,
        ),
        Radius.circular(r),
      );
      canvas.drawRRect(oval, eyePaint);
      // Catchlight (avatar.tsx:717-724): punto blanco arriba-izquierda del
      // ojo; sobre ojo blanco Desktop usa el color del cuerpo aquí.
      canvas.drawCircle(
        Offset(ex * sx - r * 0.35, eyeY - r * 0.75),
        r * 0.42,
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }
  }

  /// Anillo del cuerpo por forma. Geometrías alineadas con el viewBox 40×40:
  /// cloud usa el path fijo de Desktop (avatar.tsx:697-699).
  Path _bodyPath(String? shape, Size size) {
    final w = size.width, h = size.height;
    final rect = Rect.fromLTWH(2, 2, w - 4, h - 4);
    Path path;
    switch (shape) {
      case 'circle':
        path = Path()..addOval(rect);
      case 'square':
        path = Path()..addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        );
      case 'rounded' || 'squircle':
        path = Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(w * 0.3)),
        );
      case 'pill':
        path = Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(h / 2)),
        );
      case 'triangle':
        path = Path()
          ..moveTo(w / 2, 2)
          ..lineTo(w - 2, h - 2)
          ..lineTo(2, h - 2)
          ..close();
      case 'hexagon':
        path = Path()..addPolygon(_ring(_hexagonRing, w, h), true);
      case 'cloud':
        path = Path()
          ..moveTo(11 / 40 * w, 32 / 40 * h)
          ..relativeArcToPoint(
            Offset(-1 / 40 * w, 17.1 / 40 * h),
            radius: Radius.circular(7.5 / 40 * w),
            clockwise: false,
          )
          ..relativeArcToPoint(
            Offset(19 / 40 * w, -4.6 / 40 * h),
            radius: Radius.circular(9.5 / 40 * w),
            clockwise: false,
          )
          ..relativeArcToPoint(
            Offset(1 / 40 * w, 19.5 / 40 * h),
            radius: Radius.circular(7 / 40 * w),
            clockwise: false,
          )
          ..close();
      case 'drop':
        path = Path()
          ..moveTo(w / 2, 2)
          ..quadraticBezierTo(w - 2, h * 0.62, w / 2, h - 2)
          ..quadraticBezierTo(2, h * 0.62, w / 2, 2)
          ..close();
      case 'blob':
        path = Path()..addPolygon(_ring(_blobRing, w, h), true);
      default:
        if (isBlobShape(shape)) {
          path = Path()..addPolygon(_ring(_blobRingFor(shape), w, h), true);
        } else {
          // Fallback: rounded.
          path = Path()..addRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(w * 0.3)),
          );
        }
    }
    return path;
  }

  static const _hexagonRing = <(double, double)>[
    (0.5, 0.04), (0.93, 0.27), (0.93, 0.73), (0.5, 0.96), (0.07, 0.73), (0.07, 0.27),
  ];
  static const _blobRing = <(double, double)>[
    (0.5, 0.06), (0.78, 0.12), (0.94, 0.4), (0.86, 0.72), (0.6, 0.95),
    (0.3, 0.9), (0.08, 0.62), (0.14, 0.3), (0.3, 0.1),
  ];

  /// Silueta blob variada por seed/kind: desplaza vértices con el hash para
  /// que cada seed produzca una silueta distinta pero estable.
  List<Offset> _ring(_BlobRing ring, double w, double h) =>
      [for (final (x, y) in ring) Offset(x * w, y * h)];

  List<(double, double)> _blobRingFor(String? shape) {
    final parsed = parseBlobShape(shape, name)!;
    final jitter = desktopHash(parsed.seed) % 1000 / 1000 * 0.08;
    return [
      for (final (x, y) in _blobRing)
        (
          (x + (y < 0.5 ? jitter : -jitter)).clamp(0.05, 0.95),
          (y + (x < 0.5 ? jitter : -jitter) * 0.6).clamp(0.05, 0.95),
        ),
    ];
  }

  @override
  bool shouldRepaint(_BotFacePainter old) =>
      old.name != name || old.shape != shape || old.colorSpec != colorSpec;
}

typedef _BlobRing = List<(double, double)>;
