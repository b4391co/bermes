import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:hermes_pocket/clients/hermes/connection_manager.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/features/conversations/group_rooms.dart';
import 'package:hermes_pocket/features/conversations/group_sync.dart';

/// Espejo REAL capturado de un gateway 0.21.5 (miembros/anonimizados): sala
/// `name:Dual` SIN roomId con log incrustado — el grupo del reporte
/// 2026-10-04 que el limpiador legacy borraba en cada ciclo.
Map<String, Object?> _realMirror() => {
  'version': 3,
  'updatedAt': 1791131055868,
  'rooms': {
    'id:room-a': {
      'name': 'Casa',
      'roomId': 'room-a',
      'revision': 187,
      'members': [
        {'name': 'default', 'handle': 'h1', 'connectionId': 'home'},
        {'name': 'docs', 'handle': 'h2', 'connectionId': 'home'},
      ],
    },
    'name:Dual': {
      'name': 'Dual',
      'roomId': null,
      'revision': 93,
      'members': [
        {'name': 'default', 'handle': 'default-boneca', 'connectionId': 'remote-b'},
        {'name': 'default', 'handle': 'default-claudio', 'connectionId': 'home'},
      ],
      'log': [
        {
          'id': 'ev-1',
          'from': {'kind': 'user', 'name': 'You'},
          'text': 'que tal',
          'at': 1790692508000,
        },
        {
          'id': 'ev-2',
          'from': {'kind': 'member', 'name': 'default', 'source': 'Boneca'},
          'text': 'Presente.',
          'at': 1790692635000,
        },
      ],
    },
  },
  'deleted': <String, int>{},
};

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('sala name: del espejo real persiste y NO la borra el limpiador legacy',
      () async {
    final snap = GroupSyncSnapshot.tryParse(_realMirror())!;
    expect(snap.rooms['name:Dual']!.embeddedLog, hasLength(2));
    final state = ConnectionGroupState(
      id: 'conn1',
      label: 'claudio',
      createdAt: DateTime(2026, 1, 1),
      displayOrder: 0,
      installId: 'home',
      profiles: [
        GatewayProfileSnapshot(
          name: 'default',
          groups: snap,
          membershipNames: const {'Casa', 'Dual'},
        ),
      ],
      titles: const {'default': 'CLAUDIO'},
    );
    await syncGroupMirrors(db: db, connections: [state]);
    // Dos ciclos: el limpiador legacy corre en cada uno; la sala name: debe
    // sobrevivir a ambos (0.1.28 la borraba como «superseded»).
    await syncGroupMirrors(db: db, connections: [state]);
    final rows = await (db.select(db.conversations)
          ..where((c) => c.kind.equals('group')))
        .get();
    final dual = rows.where((r) => r.gatewayId == 'Dual').toList();
    expect(dual, hasLength(1), reason: 'la sala name: sobrevive al limpiador');
    expect(dual.single.groupRoomId, isNull);
    // Historial incrustado persistido como timeline.
    final msgs = await (db.select(db.messages)
          ..where((m) => m.conversationId.equals(dual.single.id))
          ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .get();
    expect(msgs.map((m) => m.text_), ['que tal', 'Presente.']);
    expect(msgs.first.authorName, 'Tú');
    expect(msgs.last.authorName, 'default · Boneca');
  });
}
