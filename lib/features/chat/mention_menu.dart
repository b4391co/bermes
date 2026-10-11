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

  /// Clave estable para dedupe: el TOKEN de enrutado (name), en minúsculas.
  String get dedupeKey => name.trim().toLowerCase();
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

  /// Query activa (sin `@`) para resaltar coincidencias en la lista.
  final String query;

  const MentionMenu({
    super.key,
    required this.candidates,
    required this.onPick,
    this.query = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Opacity(
        opacity: ((scale - 0.92) / 0.08).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: Material(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Hp.rMd),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          // 0.1.64: SCROLL — antes Column seca dentro de maxHeight 220: con
          // 17+ candidatos sólo se veían ~5 (los primeros, miembros de la
          // sala) y el resto quedaba recortado e invisible («sólo salen 5
          // menciones de un gateway»).
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: candidates.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            thickness: 0.6,
            indent: 56,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          itemBuilder: (context, i) {
            final c = candidates[i];
            final title = '@${c.display}';
            final subtitle = c.name == c.display ? null : c.name;
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -1),
              // El icono REAL del bot (avatar de Hermes Desktop / blob /
              // imagen), no la inicial suelta: mismo BotAvatar que en la
              // lista y el chat.
              leading: BotAvatar(
                seed: c.display,
                label: c.display,
                size: 30,
                imageUrl: c.avatarUrl,
                avatarMetaJson: c.avatarMeta,
              ),
              title: _titleWithQuery(context, title, query),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
              onTap: () => onPick(c),
            );
          },
        ),
      ),
    );
  }

  /// Resalta el trozo de query dentro de `@Nombre` (estilo Grok).
  Widget _titleWithQuery(BuildContext context, String title, String q) {
    final base = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
    final trimmed = q.trim();
    if (trimmed.isEmpty) return Text(title, style: base);
    final lower = title.toLowerCase();
    final needle = trimmed.toLowerCase();
    final at = lower.indexOf(needle);
    if (at < 0) {
      final foldedTitle = foldMentionKey(title);
      final foldedQ = foldMentionKey(trimmed);
      final fat = foldedTitle.indexOf(foldedQ);
      if (fat < 0) return Text(title, style: base);
      // Acentos: resaltar por longitud ASCII aproximada sobre el visible.
      final end = (fat + foldedQ.length).clamp(0, title.length);
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: title.substring(0, fat)),
            TextSpan(
              text: title.substring(fat, end),
              style: base?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: title.substring(end)),
          ],
        ),
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: title.substring(0, at)),
          TextSpan(
            text: title.substring(at, at + needle.length),
            style: base?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: title.substring(at + needle.length)),
        ],
      ),
    );
  }
}

/// Fusiona candidatos de sala + roster sin duplicar el mismo token de
/// enrutado. Prioriza la primera aparición (sala / `@todos` primero).
/// Ordena: coincidencia de prefijo → contiene → resto, y dentro del mismo
/// bucket por etiqueta visible.
List<MentionCandidate> filterMentionCandidates(
  Iterable<MentionCandidate> all,
  String query,
) {
  final q = query.trim().toLowerCase();
  final foldedQ = foldMentionKey(q);
  final seen = <String>{};
  final matched = <MentionCandidate>[];
  for (final m in all) {
    if (!seen.add(m.dedupeKey)) continue;
    if (q.isEmpty) {
      matched.add(m);
      continue;
    }
    final display = m.display.toLowerCase();
    final name = m.name.toLowerCase();
    if (display.contains(q) ||
        name.contains(q) ||
        foldMentionKey(display).contains(foldedQ) ||
        foldMentionKey(name).contains(foldedQ)) {
      matched.add(m);
    }
  }
  // Query vacía: conservar el orden del llamador (sala / `@todos` primero).
  // Con query: prefijo → contains, y dentro del bucket por etiqueta.
  if (q.isEmpty) return matched;

  int rank(MentionCandidate m) {
    final d = m.display.toLowerCase();
    final n = m.name.toLowerCase();
    if (d.startsWith(q) || n.startsWith(q)) return 0;
    if (foldMentionKey(d).startsWith(foldedQ) ||
        foldMentionKey(n).startsWith(foldedQ)) {
      return 0;
    }
    return 1;
  }

  matched.sort((a, b) {
    final ra = rank(a);
    final rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    return a.display.toLowerCase().compareTo(b.display.toLowerCase());
  });
  return matched;
}

/// Pliega acentos/diacríticos a ASCII para filtrar `@José` ≈ `jose`.
String foldMentionKey(String input) {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
  final buf = StringBuffer();
  for (final cu in input.codeUnits) {
    final i = from.codeUnits.indexOf(cu);
    buf.writeCharCode(i >= 0 ? to.codeUnitAt(i) : cu);
  }
  return buf.toString().toLowerCase();
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
