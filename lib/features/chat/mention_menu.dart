import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../app_shell.dart' show BotAvatar;

/// Mención de un miembro en el autocompletado `@` del grupo.
class MentionCandidate {
  final String name;
  final String? avatarUrl;
  final String? avatarMeta; // JSON hermes-bots.avatar (color/icon)

  /// 0.1.61: en salas HOSTED el gateway enruta el turno por el token
  /// `@<handle>` (`hermes-this-webapp`), no por el título visible. El menú
  /// debe mostar NOMBRE AMIGABLE e insertar el token que funciona: [label]
  /// es lo que se pinta; [name] es lo que se inserta. Iguales en espejos
  /// (ahí el motor de turnos entiende el título).
  final String label;

  const MentionCandidate({
    required this.name,
    this.label = '',
    this.avatarUrl,
    this.avatarMeta,
  });

  String get display => label.isEmpty ? name : label;
}

/// Menú flotante de menciones: se muestra sobre el composer, anclado a la
/// posición del cursor, y reemplaza el trozo `@texto` en cuanto se elige.
///
/// Contrato de identificación de Hermes: en un grupo los bots se nombran por
/// su HANDLE/PROFILE (`RelayAgentRow {profile, handle}`;
/// `groups.send` resuelve el turno por miembro). El nombre visible es lo que
/// el backend escucha en el texto, así que eso es lo que se inserta.
class MentionMenu extends StatelessWidget {
  final List<MentionCandidate> candidates;
  final void Function(MentionCandidate) onPick;

  const MentionMenu({
    super.key,
    required this.candidates,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(Hp.rMd),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in candidates)
            ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -1),
              // El icono REAL del bot (avatar de Hermes Desktop / blob /
              // imagen), no la inicial suelta: mismo BotAvatar que en la
              // lista y el chat.
              leading: BotAvatar(
                seed: c.display,
                label: c.display,
                size: 28,
                imageUrl: c.avatarUrl,
                avatarMetaJson: c.avatarMeta,
              ),
              title: Text(c.name == c.display ? '@${c.display}' : '@${c.display} · ${c.name}'),
              onTap: () => onPick(c),
            ),
        ],
      ),
    );
  }
}

/// Utilidades del token `@` en un texto + caret.
class MentionToken {
  /// Índice de `@` que gobierna el caret, o null si el caret no está dentro
  /// de un token de mención (sin espacios dentro del token).
  static int? mentionStart(String text, int caret) {
    if (caret <= 0 || caret > text.length) return null;
    final upto = text.substring(0, caret);
    final at = upto.lastIndexOf('@');
    if (at < 0) return null;
    // `@` ha de estar al inicio o tras un separador (no emails, no "a@b").
    // `\w` es unicode-aware en Dart: letras con acento (ñ, é…) cuentan como palabra.
    if (at > 0) {
      final prev = text[at - 1];
      if (RegExp(r"[\w\-]").hasMatch(prev)) return null;
    }
    final token = upto.substring(at + 1);
    // El query no puede contener espacios: si los hay, el token ya se cerró.
    if (token.contains(RegExp(r'\s'))) return null;
    return at;
  }

  /// Reemplaza `@query` (desde [start] hasta el caret) por `@name ` y
  /// devuelve el nuevo texto con la posición del caret.
  static (String, int) replace(String text, int start, int caret, String name) {
    final out = '${text.substring(0, start)}@$name ${text.substring(caret)}';
    return (out, start + name.length + 2);
  }
}
