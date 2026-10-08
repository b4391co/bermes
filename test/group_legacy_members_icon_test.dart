import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/design/group_avatar.dart';
import 'package:hermes_pocket/features/conversations/group_rooms.dart';
import 'package:hermes_pocket/features/conversations/group_sync.dart';

/// Causa 2 (sonda IconosProbe 2026-10-08): las filas de grupo del canal
/// legacy (`ui_meta.hermes-bots.groups`, sin espejo de salas) NO guardaban
/// `groupMembersJson` → el icono caía SIEMPRE a iniciales. Ahora la fila
/// legacy persiste los miembros con su identidad (connId + perfil).
void main() {
  test('syncGroupMirrors canal legacy escribe miembros para el icono', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: 'c1',
            name: 'Casa',
            scheme: 'http',
            host: 'x',
            port: 9110,
            authKind: 'password',
          ),
        );
    await syncGroupMirrors(
      db: db,
      connections: [
        ConnectionGroupState(
          id: 'c1',
          label: 'Casa',
          createdAt: DateTime(2026),
          profiles: [
            GatewayProfileSnapshot(
              name: 'default',
              groups: GroupSyncSnapshot.empty,
              membershipNames: const {'Equipo'},
            ),
            GatewayProfileSnapshot(
              name: 'parker',
              groups: GroupSyncSnapshot.empty,
              membershipNames: const {'Equipo'},
            ),
          ],
          titles: const {'default': 'Default', 'parker': 'Parker'},
        ),
      ],
    );
    final row = await (db.select(
      db.conversations,
    )..where((t) => t.kind.equals('group'))).getSingle();
    expect(row.groupMembersJson, isNotNull, reason: 'canal legacy sin miembros = icono de texto');
    final members = (jsonDecode(row.groupMembersJson!) as List)
        .whereType<Map>()
        .toList();
    expect(members.length, 2);
    expect(members.map((m) => m['name']), containsAll(['default', 'parker']));
    // Y con esas claves la pila de caras RESUELVE (identity: connId/bot/perfil):
    final faces = {
      'c1/bot/default': const GroupFace(seed: 'default', label: 'Default'),
      'c1/bot/parker': const GroupFace(seed: 'parker', label: 'Parker'),
    };
    for (final m in members) {
      final gm = GroupMember.fromJson(m.cast<String, Object?>());
      expect(
        GroupAvatarStack.faceFor(gm, faces, const {}),
        isNotNull,
        reason: 'miembro ${m['name']} sin cara = iniciales',
      );
    }
  });
}
