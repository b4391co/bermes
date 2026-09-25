import 'package:flutter/material.dart';

/// Tokens del sistema visual de Hermes Pocket.
///
/// Dirección: mensajería cuidada tipo Grok Bot — fondo claro dominante,
/// texto oscuro con jerarquía precisa, burbujas del usuario oscuras,
/// respuestas sobre superficies suaves, ornamentación mínima.
abstract final class Hp {
  // ── Espaciado (escala 4) ──────────────────────────────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // ── Radios ────────────────────────────────────────────────────────────
  static const double rSm = 10;
  static const double rMd = 16;
  static const double rLg = 22;
  static const double rBubble = 20;

  // ── Tipografía ────────────────────────────────────────────────────────
  static const String fontFallback = 'Roboto';

  // ── Avatares: paleta con personalidad (determinista por semilla) ─────
  static const avatarPalette = <Color>[
    Color(0xFF5B6CFF), // índigo eléctrico
    Color(0xFF00A98F), // verde jade
    Color(0xFFE8618C), // rosa frambuesa
    Color(0xFF8B5CF6), // violeta
    Color(0xFFF59E0B), // ámbar
    Color(0xFF0EA5E9), // cielo
    Color(0xFFF97316), // naranja
    Color(0xFF14B8A6), // turquesa
  ];

  static Color avatarColor(String seed) {
    var h = 0;
    for (final cu in seed.codeUnits) {
      h = (h * 31 + cu) & 0x7fffffff;
    }
    return avatarPalette[h % avatarPalette.length];
  }

  // ── Estados (no solo color: siempre acompañados de icono/texto) ──────
  static const online = Color(0xFF22C55E);
  static const connecting = Color(0xFFF59E0B);
  static const offline = Color(0xFF94A3B8);
  static const error = Color(0xFFEF4444);
}
