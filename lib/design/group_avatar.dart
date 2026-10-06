import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/app_shell.dart' show BotAvatar;
import '../domain/entity/entity_ref.dart';
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
  }) {
    final faces = <GroupFace>[];
    var total = 0;
    if (membersJson != null && membersJson.isNotEmpty) {
      try {
        final raw = (jsonDecode(membersJson) as List).whereType<Map>();
        total = raw.length;
        for (final m in raw) {
          final member = GroupMember.fromJson(m.cast<String, Object?>());
          final face = _faceOf(member, faceByConvId, connIdByInstallId);
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

  static GroupFace? _faceOf(
    GroupMember m,
    Map<String, GroupFace> faceByConvId,
    Map<String, String> connIdByInstallId,
  ) {
    final connId = m.installId == null ? null : connIdByInstallId[m.installId];
    if (connId == null) return null;
    for (final name in {
      if (m.name != null) m.name!,
      ...m.previousNames,
    }) {
      final f = faceByConvId['$connId/bot/$name'];
      if (f != null) return f;
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
      seed: '$connectionId/${EntityKind.bot.name}/$gatewayId',
      label: title,
      imageUrl: avatarUrl,
      avatarMetaJson: botAvatarMeta,
    );
  }
}

