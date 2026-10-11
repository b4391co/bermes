import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

export '../features/conversations/group_rooms.dart' show GroupMember;

import '../data/database/app_database.dart';
import '../features/app_shell.dart' show BotAvatar;
import '../features/conversations/group_rooms.dart';

/// Icono de grupo = las caras de los bots dentro (máx. 3) + badge «+N» si
/// hay más miembros. Estilo mensajería (Grok Bot / iMessage): círculos
/// solapados con anillo de superficie, no iniciales sueltas del grupo.
class GroupAvatarStack extends StatelessWidget {
  /// Cara de cada miembro a dibujar (orden del espejo; se muestran las 3
  /// primeras).
  final List<GroupFace> faces;
  final int totalMembers;
  final double size;

  const GroupAvatarStack({
    super.key,
    required this.faces,
    required this.totalMembers,
    this.size = 42,
  });

  /// Construye la pila desde `conversations.groupMembersJson` + el roster de
  /// bots (id → fila de conversación bot). [connIdByInstallId] traduce la
  /// identidad del espejo (`installId` del backend) a la conexión local.
  static Widget fromMembersJson({
    required String? membersJson,
    required Map<String, GroupFace> faceByConvId,
    required Map<String, String> connIdByInstallId,
    required String fallbackTitle,
    required double size,
    String? preferredConnectionId,
  }) {
    final faces = <GroupFace>[];
    var total = 0;
    if (membersJson != null && membersJson.isNotEmpty) {
      try {
        final raw = (jsonDecode(membersJson) as List).whereType<Map>();
        total = raw.length;
        for (final m in raw) {
          final member = GroupMember.fromJson(m.cast<String, Object?>());
          final face = faceFor(
            member,
            faceByConvId,
            connIdByInstallId,
            preferredConnectionId: preferredConnectionId,
          );
          // 0.1.64: miembro SIN cara resuelta ya no se descarta — acababa en
          // el blob de iniciales del grupo («se ven letras, no los bots de
          // dentro»). Con identidad PROPIA (nombre visible/handle/perfil) se
          // pinta su avatar individual: semilla/color del bot, y su letra si
          // no hay imagen. Letra correcta de CADA bot mejor que una inicial
          // suelta del grupo.
          final ownName = member.title ??
              member.displayName ??
              member.handle ??
              member.name;
          faces.add(
            face ??
                GroupFace(
                  seed: ownName ?? '?',
                  label: ownName ?? '?',
                ),
          );
        }
      } catch (_) {
        // JSON corrupto: se cae al fallback de iniciales sin romper la fila.
      }
    }
    if (faces.isEmpty) {
      // Sin miembros resolubles (roster aún no sincronizado): iniciales del
      // grupo, honesto y estable.
      return BotAvatar(seed: fallbackTitle, label: fallbackTitle, size: size);
    }
    return GroupAvatarStack(
      faces: faces,
      totalMembers: total,
      size: size,
    );
  }

  /// Resuelve la cara de un miembro probando sus claves de identidad en
  /// orden: `installId` → `connectionId` (puede ser id local de Desktop) →
  /// `name` de perfil (con los nombres previos) → `handle`. El índice de
  /// caras se construye con todas esas claves, así que un miembro del espejo
  /// enlaza con su bot aunque Desktop lo referencie por otra clave.
  ///
  /// Público para los tests de identidad: dos miembros con el MISMO `name`
  /// de perfil en gateways distintos NO pueden resolver contra la misma cara.
  static GroupFace? faceFor(
    GroupMember m,
    Map<String, GroupFace> faceByConvId,
    Map<String, String> connIdByInstallId, {
    String? preferredConnectionId,
  }) {
    // `connectionId` del espejo puede ser el installId del backend (Pocket)
    // o una clave propia de Desktop: se prueban BOTH routes antes de caer a
    // claves ambiguas.
    final connIds = <String>{
      if (m.installId != null) ?connIdByInstallId[m.installId!],
      if (m.connectionId != null) ?connIdByInstallId[m.connectionId!],
      if (m.connectionId != null) m.connectionId!,
    };
    for (final key in <String?>[
      for (final c in connIds)
        if (m.name != null) '$c/bot/${m.name}',
      for (final prev in m.previousNames)
        for (final c in connIds) '$c/bot/$prev',
      for (final c in connIds)
        if (m.handle != null) '$c/bot/${m.handle}',
      // Ambiguo entre homónimos sólo SI el nombre de perfil es único en el
      // índice: se resuelve abajo, no a ciegas por clave.
      m.handle,
      m.installId,
      m.connectionId,
      // Espejos de Desktop sin perfil: el nombre visible (title/display_name)
      // indexado como `title:` — única ruta para miembros proyectados sin
      // identidad de conexión local.
      if (m.title != null) 'title:${m.title}',
      if (m.displayName != null) 'title:${m.displayName}',
    ]) {
      if (key == null) continue;
      final f = faceByConvId[key];
      if (f != null) return f;
    }
    // Fallback sin identidad de conexión: si el perfil del miembro es ÚNICO
    // en el índice, esa cara es la suya. Con homónimos (p. ej. `default` en
    // 4 gateways) se DESAMBIGÚA con la conexión de la FILA del grupo: si
    // exactamente un hit cuelga de esa conexión, es el suyo — el roster del
    // grupo apunta a bots de esa conexión. Sólo queda null si ni aun así se
    // distingue: iniciales honestas antes que una cara equivocada.
    if (m.name != null) {
      final hits = faceByConvId.entries
          .where((e) => e.key.endsWith('/bot/${m.name}'))
          .toList();
      if (hits.length == 1) return hits.first.value;
      if (preferredConnectionId != null && hits.length > 1) {
        final own = hits
            .where((e) => e.key.startsWith('$preferredConnectionId/bot/'))
            .toList();
        if (own.length == 1) return own.first.value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final shown = faces.take(3).toList();
    final extra = totalMembers - shown.length;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          switch (shown.length) {
            >= 3 => _layout3(context, shown),
            2 => _layout2(context, shown),
            _ => _layout1(context, shown.first),
          },
          if (extra > 0)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: math.max(9, size * 0.20),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Cara en círculo con anillo: lee como icono de grupo de mensajería,
  /// no como iniciales sueltas sobre el fondo de la fila.
  Widget _framedFace(BuildContext context, GroupFace f, double faceSize) {
    final cs = Theme.of(context).colorScheme;
    final ring = math.max(1.5, size * 0.035);
    return Container(
      width: faceSize,
      height: faceSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.surface, width: ring),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 2.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: BotAvatar(
          seed: f.seed,
          label: f.label,
          size: faceSize * 0.88,
          imageUrl: f.imageUrl,
          avatarMetaJson: f.avatarMetaJson,
        ),
      ),
    );
  }

  Widget _layout1(BuildContext context, GroupFace f) =>
      _framedFace(context, f, size);

  /// Dos caras solapadas (~32 %), como Grok Bot / WhatsApp.
  Widget _layout2(BuildContext context, List<GroupFace> fs) {
    final face = size * 0.72;
    final overlap = face * 0.32;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: (size - face) / 2,
          child: _framedFace(context, fs[0], face),
        ),
        Positioned(
          left: face - overlap,
          top: (size - face) / 2,
          child: _framedFace(context, fs[1], face),
        ),
      ],
    );
  }

  /// Tres caras en racimo: dos arriba solapadas + una abajo centrada.
  Widget _layout3(BuildContext context, List<GroupFace> fs) {
    final face = size * 0.58;
    final topY = size * 0.02;
    final bottomY = size - face - size * 0.02;
    final leftX = size * 0.02;
    final rightX = size - face - size * 0.02;
    final midX = (size - face) / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: leftX,
          top: topY,
          child: _framedFace(context, fs[0], face),
        ),
        Positioned(
          left: rightX,
          top: topY,
          child: _framedFace(context, fs[1], face),
        ),
        Positioned(
          left: midX,
          top: bottomY,
          child: _framedFace(context, fs[2], face),
        ),
      ],
    );
  }
}

/// Datos de cara de un bot (avatar real del roster).
class GroupFace {
  final String seed;
  final String label;
  final String? imageUrl;
  final String? avatarMetaJson;

  const GroupFace({
    required this.seed,
    required this.label,
    this.imageUrl,
    this.avatarMetaJson,
  });

  static GroupFace ofConversation({
    required String connectionId,
    required String gatewayId,
    required String title,
    String? avatarUrl,
    String? botAvatarMeta,
  }) {
    return GroupFace(
      seed: '$connectionId/bot/$gatewayId',
      label: title,
      imageUrl: avatarUrl,
      avatarMetaJson: botAvatarMeta,
    );
  }
}

/// Índice de caras de bots para resolver miembros del espejo. Indexa cada bot
/// por TODAS las claves con las que un miembro puede referenciarlo:
/// `installId`, `gatewayId`, `connectionId`, id de conversación, y
/// `<connId>/bot/<name>` (incluidos nombres previos del perfil).
class GroupFaceIndex {
  static Map<String, GroupFace> of(
    Iterable<Conversation> conversations,
    Map<String, String> installIdToConn,
  ) {
    final out = <String, GroupFace>{};
    for (final c in conversations) {
      if (c.isGroup || c.kind != 'bot') continue;
      final face = GroupFace(
        seed: c.avatarSeed ?? '${c.connectionId}/${c.gatewayId}',
        label: c.title,
        imageUrl: c.avatarUrl,
        avatarMetaJson: c.botAvatarMeta,
      );
      final connId = c.connectionId;
      final profileName = c.avatarSeed?.split('/').last;
      // Clave principal: `${connId}/bot/${perfil}` — la que usan las caras
      // del chat (`GroupFaceIndex` alimentado con el id de fila) y los
      // miembros del espejo vía `installId → connId`. En 0.1.48 el id de
      // fila para bots sincronizados era `${connId}/bot/${gatewayId}`… sólo
      // SI `gatewayId` era el perfil; para bots de espejo era otra cosa y
      // las caras no resolvían. Se indexa POR CONEXIÓN, siempre.
      for (final key in <String?>[
        c.id,
        '$connId/bot/${c.gatewayId}',
        if (profileName != null && profileName.isNotEmpty)
          '$connId/bot/$profileName',
        c.gatewayId,
        // 0.1.59: los miembros del espejo de Desktop llegan a veces SÓLO con
        // su nombre visible (`title`/`display_name`). Se indexa TAMBIÉN por
        // título, con PUT_IF_ABSENT para que el perfil nunca pierda su clave.
        if (c.title.isNotEmpty && c.title != c.gatewayId)
          'title:${c.title}',
      ]) {
        if (key == null || key.isEmpty) continue;
        out.putIfAbsent(key, () => face);
      }
    }
    return out;
  }
}
