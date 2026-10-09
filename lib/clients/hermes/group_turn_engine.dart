import 'dart:async';

import '../../core/logger.dart';
import '../../domain/entity/entity_ref.dart';
import '../../domain/message/chat_models.dart';
import 'chat_session_controller.dart';
import 'connection_manager.dart';

/// Motor de turnos de grupos de Desktop para salas espejo (clave `name:`,
/// sin room hospedado).
///
/// CONTRATO REAL de Hermes Desktop (repo NousResearch/hermes-agent,
/// apps/desktop/src/plugins/hermes-bots):
/// - Desktop NO usa `groups.*` para su UI (0 llamadores en apps/ — audit
///   2026-09-29); el espejo `ui_meta['hermes-bots-groups']` es storage
///   cliente-a-cliente. La ORQUESTACIÓN de turnos vive en el cliente:
///   `group-rounds.ts` (quién habla) + `group-turns.ts` (prompt.submit a la
///   sesión del miembro) + `group-round-prompt.ts` (formato del prompt).
/// - Por eso un grupo de Desktop NO recibe menciones desde Pocket sin este
///   motor: el gateway no hospeda sala y nadie interpreta el `@`.
///
/// Alcance v1 (honesto, documentado): un mensaje de usuario → mención parse
/// idéntico a Desktop → cada miembro mencionado recibe UN turno
/// (`prompt.submit` a su sesión canónica "Bot Chat" en SU gateway) con el
/// prompt de sala de Desktop; la respuesta se streamea por los eventos de
/// esa sesión. Sin rondas múltiples (round-robin/pass) todavía: el bot
/// contesta una vez; Desktop puede seguir la conversación después.
class GroupTurnEngine {
  final _log = Logger('GroupTurnEngine');

  /// Formas de mención por bot — espejo de `mentionNameForms` +
  /// `botHandle` + `botFriendlyNames` (data.ts:1170-1236). Case-insensitive:
  /// `parseGroupChatMentions` baja todo a minúsculas; `@([a-z0-9][a-z0-9._-]*)`
  /// y acepta la forma colapsada sin espacios.
  static Set<String> mentionForms(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return const {};
    final slug = n.replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    final collapsed = n.replaceAll(RegExp(r'[^a-z0-9_-]+'), '');
    final reserved = {'all', 'everyone', 'user', 'default', 'hermes'};
    return {
      for (final f in {slug, collapsed})
        if (f.isNotEmpty && RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(f) && !reserved.contains(f)) f,
    };
  }

  /// Parse de menciones — espejo de `parseGroupChatMentions`
  /// (group-rounds.ts:50-143): nombres de perfil, título Bot Mode,
  /// display_name y sus formas colapsadas; `@everyone`/`@all` = todos;
  /// `@user` se ignora (es el humano).
  ///
  /// [members] = lista de (profile, títulos visibles) + [handles] opcionales
  /// (el `handle`/portable del espejo: `hermes-this-webapp`). Devuelve
  /// perfiles mencionados (vacío ⇒ el llamador decide: todos o nadie).
  static ({Set<String> mentioned, bool everyone}) parseMentions(
    String text,
    List<({String profile, List<String> titles, String? handle})> members,
  ) {
    final source = text.toLowerCase();
    final mentioned = <String>{};
    var everyone = false;
    final handles = <String, String>{};
    for (final m in members) {
      final forms = <String>{...mentionForms(m.profile)};
      for (final t in m.titles) {
        if (t.isEmpty) continue;
        forms.addAll(mentionForms(t));
        // `title.split(/\s+/)[0].toLowerCase()` del original.
        final first = t.trim().toLowerCase().split(RegExp(r'\s+')).first;
        if (first.isNotEmpty) forms.add(first);
      }
      // 0.1.61: en grupos espejo multi-gateway el usuario escribe el NOMBRE
      // visible (`@CLAUDIO`, `@Boneca`) — y ése es, de hecho, el `handle`
      // canónico de Desktop (`RelayAgentRow.handle`, el que el motor de
      // turnos de sala hosted enruta). Se registran SUS formas: sin esto el
      // `@` de la UI no coincidía con nada y "las menciones sólo van en
      // claudio" (donde el título bate con el nombre de gateway por suerte).
      final h = m.handle?.trim() ?? '';
      if (h.isNotEmpty) forms.addAll(mentionForms(h));
      for (final f in forms) {
        if (f.isNotEmpty) handles[f] = m.profile;
      }
    }
    final re = RegExp(r'@([a-z0-9][a-z0-9._-]*)', caseSensitive: false);
    for (final match in re.allMatches(source)) {
      final h = match.group(1)!.toLowerCase();
      if (h == 'everyone' || h == 'all') {
        everyone = true;
        continue;
      }
      if (h == 'user') continue;
      final resolved = handles[h] ?? handles[h.replaceAll(RegExp(r'[._-]+'), '')];
      if (resolved != null) mentioned.add(resolved);
    }
    return (mentioned: mentioned, everyone: everyone);
  }

  /// Prompt de turno — byte-por-byte el formato de Desktop
  /// (`buildGroupChatTurnPrompt`, group-round-prompt.ts:214-243) para que el
  /// bot se comporte en Pocket EXACTAMENTE igual que en Desktop (participa
  /// con las mismas reglas de sala y puede seguir luego en Desktop).
  static String buildTurnPrompt({
    required String groupName,
    required String viewerProfile,
    required String viewerTag,
    required String viewerTitle,
    required List<({String profile, String tag, String title, String connectionLabel})> peers,
    required List<String> deltaLines,
  }) {
    final peerNames = peers
        .map((m) =>
            '${m.tag.isEmpty ? '@${m.profile.toLowerCase()}' : '@${m.tag}'}'
            '${m.connectionLabel.isEmpty ? '' : ' [on ${m.connectionLabel}]'}')
        .join(', ');
    return [
      '[Group chat: "$groupName"] You are @$viewerTag, one participant in a group chat with ${peerNames.isEmpty ? 'no one else yet' : peerNames} and the user.',
      '',
      'New messages in the room since your last turn (oldest first):',
      for (final l in deltaLines) '  $l',
      '',
      'Rules for this room:',
      '- Reply with ONE conversational message ONLY if you have something new worth adding: build on what was just said, claim or hand off work, answer a question aimed at you, or report a real result. Keep chatter short (1-3 sentences) — but when you are delivering a result, an answer the user asked for, or substantive work, give it at full quality and length; never thin out real content to fit the room.',
      '- If you have nothing new to add, reply with exactly "(pass)". Passing is good — it lets the conversation settle.',
      '- Mention a teammate as @name to pull them in; mention @user only for a judgment call or a result the user needs. Do not repeat points already made.',
      '- Never reveal content from your private 1:1 chats. Your reply text goes to the room verbatim — no preamble, no meta-commentary.',
    ].join('\n');
  }

  /// Línea de transcript — `formatGroupChatLine` (group-round-prompt.ts:42-70):
  /// `Name (user): …` para el humano, `Name: …` para bots; los marcos de
  /// control de los miembros se re-etiquetan (frontera de confianza).
  static String formatLine({
    required String text,
    required String author,
    required bool isUser,
    required bool isSelf,
  }) {
    String safe(String t) => t.replaceAll(
        RegExp(
          r'\[(?=\/?OUT-OF-BAND USER MESSAGE|CONTEXT COMPACTION|CONTEXT SUMMARY\]|PRIOR CONTEXT|Runtime note:|System note:|System:|SYSTEM\]|IMPORTANT:|Planning state preserved|ASYNC DELEGATION)',
          caseSensitive: false,
        ),
        '[member-quoted ');
    if (isUser) return '${author.isEmpty ? 'User' : author} (user): ${safe(text)}';
    return '${isSelf ? '$author (you)' : author}: ${safe(text)}';
  }
}

/// Estado de un turno grupal en vuelo: controlador por miembro mencionado
/// cuyos eventos alimentan la línea viva del chat grupal.
class GroupMemberTurn {
  final ChatSessionController controller;
  final String profile;
  final String title;
  final String connectionId;
  GroupMemberTurn({
    required this.controller,
    required this.profile,
    required this.title,
    required this.connectionId,
  });
}

/// Resuelve los miembros del espejo a runtimes reales. Devuelve null para un
/// miembro sin conexión viva (se reporta, no se bloquea).
Future<List<GroupMemberTurn>> startMentionTurns({
  required String groupName,
  required String userText,
  required List<
    ({String profile, String title, String connectionId, String? handle})
  >
  members,
  required List<String> transcriptLines, // ya formateadas
  required ConnectionManager connections,
  required void Function(GroupMemberTurn turn) onTurn,
}) async {
  final engine = GroupTurnEngine();
  final parsed = GroupTurnEngine.parseMentions(
    userText,
    [
      for (final m in members)
        (profile: m.profile, titles: [m.title], handle: m.handle),
    ],
  );
  final targets = parsed.everyone || parsed.mentioned.isEmpty
      ? members
      : [for (final m in members) if (parsed.mentioned.contains(m.profile)) m];
  final turns = <GroupMemberTurn>[];
  for (final m in targets) {
    final runtime = connections.runtimeFor(m.connectionId);
    if (runtime == null) {
      engine._log.warning('miembro sin runtime: ${m.profile}@${m.connectionId}');
      continue;
    }
    final sessionId = await runtime.gateway.resumeCanonicalSession(m.profile);
    if (sessionId == null || sessionId.isEmpty) {
      throw GroupTurnException(
        'La sesión "Bot Chat" de ${m.title.isEmpty ? m.profile : m.title} no '
        'existe todavía en su gateway. Ábrela una vez en Hermes Desktop.',
      );
    }
    final forms = GroupTurnEngine.mentionForms(m.title.isNotEmpty ? m.title : m.profile).toList();
    final tag = forms.isNotEmpty ? forms.first : null;
    final viewerTag = tag ?? (m.profile.toLowerCase() == 'default' ? 'hermes' : m.profile.toLowerCase());
    final peers = [
      for (final other in members)
        if (other.profile != m.profile)
          (
            profile: other.profile,
            tag: _firstForm(other.title.isNotEmpty ? other.title : other.profile) ?? other.profile.toLowerCase(),
            title: other.title,
            connectionLabel: other.connectionId,
          ),
    ];
    final prompt = GroupTurnEngine.buildTurnPrompt(
      groupName: groupName,
      viewerProfile: m.profile,
      viewerTag: viewerTag,
      viewerTitle: m.title,
      peers: peers,
      deltaLines: transcriptLines,
    );
    final controller = ChatSessionController(
      EntityRefPath(
        connectionId: m.connectionId,
        kind: EntityKind.bot,
        gatewayId: m.profile,
      ),
      runtime.gateway,
      sessionId,
      profile: m.profile,
    );
    final turn = GroupMemberTurn(
      controller: controller,
      profile: m.profile,
      title: m.title,
      connectionId: m.connectionId,
    );
    controller.attach();
    onTurn(turn);
    unawaited(
      controller
          .send(prompt)
          .catchError((Object e) => engine._log.warning('turn ${m.profile} failed', e)),
    );
    turns.add(turn);
  }
  return turns;
}

String? _firstForm(String name) {
  final f = GroupTurnEngine.mentionForms(name).toList();
  return f.isNotEmpty ? f.first : null;
}

class GroupTurnException implements Exception {
  final String message;
  const GroupTurnException(this.message);
  @override
  String toString() => message;
}
