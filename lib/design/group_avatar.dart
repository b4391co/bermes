import 'dart:convert';

import 'package:flutter/material.dart';

export '../features/conversations/group_rooms.dart' show GroupMember;

import '../data/database/app_database.dart';
import '../features/app_shell.dart' show BotAvatar;
import '../features/conversations/group_rooms.dart';

/// Icono de grupo = las caras de los bots dentro (máx. 3) + badge «+N» si
/// hay más miembros. Los miembros se resuelven contra los bots reales del
/// gateway (`GroupMember` del espejo → perfil+installId → avatar meta del
/// bot), no contra iniciales inventadas.
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
          if (face != null) faces.add(face);
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
            >= 3 => _layout3(shown),
            2 => _layout2(shown),
            _ => _layout1(shown.first),
          },
          if (extra > 0)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: size * 0.20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _layout1(GroupFace f) => BotAvatar(
    seed: f.seed,
    label: f.label,
    size: size,
    imageUrl: f.imageUrl,
    avatarMetaJson: f.avatarMetaJson,
  );

  Widget _layout2(List<GroupFace> fs) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final f in fs)
        BotAvatar(
          seed: f.seed,
          label: f.label,
          size: size * 0.52,
          imageUrl: f.imageUrl,
          avatarMetaJson: f.avatarMetaJson,
        ),
    ],
  );

  // 1 grande arriba-izquierda + 2 pequeñas abajo (esquina derecha).
  Widget _layout3(List<GroupFace> fs) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: 0,
        top: 0,
        child: BotAvatar(
          seed: fs[0].seed,
          label: fs[0].label,
          size: size * 0.68,
          imageUrl: fs[0].imageUrl,
          avatarMetaJson: fs[0].avatarMetaJson,
        ),
      ),
      Positioned(
        right: 0,
        bottom: 0,
        child: BotAvatar(
          seed: fs[1].seed,
          label: fs[1].label,
          size: size * 0.44,
          imageUrl: fs[1].imageUrl,
          avatarMetaJson: fs[1].avatarMetaJson,
        ),
      ),
      Positioned(
        right: size * 0.10,
        top: 0,
        child: BotAvatar(
          seed: fs[2].seed,
          label: fs[2].label,
          size: size * 0.34,
          imageUrl: fs[2].imageUrl,
          avatarMetaJson: fs[2].avatarMetaJson,
        ),
      ),
    ],
  );
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
      ]) {
        if (key == null || key.isEmpty) continue;
        out.putIfAbsent(key, () => face);
      }
    }
    return out;
  }
}
