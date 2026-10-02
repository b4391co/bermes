import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/features/conversations/group_rooms.dart';
import 'package:hermes_pocket/features/conversations/group_sync.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  ConnectionGroupState connWith(
    String id, {
    required DateTime createdAt,
    String? roomName,
    String roomId = 'room-1',
    List<String> members = const ['default'],
  }) {
    final room = GroupRoom(
      key: 'id:$roomId',
      roomId: roomId,
      name: roomName ?? 'Equipo',
      revision: 1,
      members: [
        for (final m in members)
          GroupMember(
            name: m,
            displayName: m,
            connectionLabel: null,
            installId: null,
          ),
      ],
    );
    return ConnectionGroupState(
      id: id,
      label: id,
      createdAt: createdAt,
      displayOrder: 0,
      profiles: [
        GatewayProfileSnapshot(
          name: 'default',
          groups: GroupSyncSnapshot(rooms: {'id:$roomId': room}),
        ),
      ],
      titles: const {},
    );
  }

  test('empate de displayOrder: la conexión más antigua es la dueña', () async {
    final older = connWith('older-conn', createdAt: DateTime(2026, 1, 1));
    final newer = connWith('newer-conn', createdAt: DateTime(2026, 2, 1));
    await syncGroupMirrors(db: db, connections: [newer, older]);

    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows, hasLength(1), reason: 'UNA fila por sala, sin duplicados');
    expect(rows.single.connectionId, 'older-conn');
  });

  test('displayOrder gana al createdAt', () async {
    final first = connWith('first', createdAt: DateTime(2026, 2, 1));
    final second = connWith('second', createdAt: DateTime(2026, 1, 1));
    await syncGroupMirrors(
      db: db,
      connections: [second, first]
          .map(
            (c) => ConnectionGroupState(
              id: c.id,
              label: c.label,
              profiles: c.profiles,
              titles: c.titles,
              createdAt: c.createdAt,
              displayOrder: c.id == 'first' ? -1 : 1,
            ),
          )
          .toList(),
    );
    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.connectionId, 'first');
  });

  test('fila huérfana en conexión caída se limpia', () async {
    // Sala viva proyectada por old-conn; la dueña new-conn la materializa y
    // la fila vieja (de un ciclo anterior) debe desaparecer aunque old-conn
    // no participe.
    final room = GroupRoom(
      key: 'id:room-1',
      roomId: 'room-1',
      name: 'Equipo',
      revision: 1,
      members: const [],
    );
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'old-conn/group/room-1',
            connectionId: 'old-conn',
            kind: 'group',
            gatewayId: 'room-1',
            title: 'Equipo',
            groupRoomId: const Value('room-1'),
            groupSyncRevision: const Value(1),
            isGroup: const Value(true),
          ),
        );
    final owner = ConnectionGroupState(
      id: 'new-conn',
      label: 'new',
      createdAt: DateTime(2026, 1, 1),
      profiles: [
        GatewayProfileSnapshot(
          name: 'default',
          groups: GroupSyncSnapshot(rooms: {'id:room-1': room}),
        ),
      ],
      titles: const {},
    );
    await syncGroupMirrors(db: db, connections: [owner]);
    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows.map((r) => r.connectionId), ['new-conn']);
  });
}
