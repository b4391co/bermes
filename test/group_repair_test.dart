import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/features/conversations/group_repair.dart';

/// Regresión de la reparación EN SITIO de grupos zombis (salas creadas por
/// 0.1.48–0.1.50 que nunca quedaron hosted porque faltaba `member_id`).
/// `groups.create` con el MISMO room_id + roster correcto es idempotente
/// (sonda real: misma sala; 4110 si el contenido difiere), así que reparar
/// no duplica ni pierde el historial del espejo.
///
/// Aquí se cubren las GUARDAS sin red: filas inservibles no llegan a tocar
/// ningún gateway (runtimes vacío ⇒ cualquier llamada de red fallaría).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertGroup(String membersJson) {
    return db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'conn/group/room-zombi',
            connectionId: 'conn',
            kind: 'group',
            gatewayId: 'room-zombi',
            title: 'Zombi',
            groupRoomId: const Value('room-zombi'),
            groupMembersJson: Value(membersJson),
          ),
        );
  }

  test('sin miembros persistidos: no repara y no toca la red', () async {
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: 'conn/group/room-zombi',
            connectionId: 'conn',
            kind: 'group',
            gatewayId: 'room-zombi',
            title: 'Zombi',
            groupRoomId: const Value('room-zombi'),
          ),
        );
    final row = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conn/group/room-zombi'))).getSingle();
    // fila sin groupMembersJson
    final res = await repairGroupRoom(
      database: db,
      runtimes: const {},
      conv: row,
      roomId: 'room-zombi',
      name: 'Zombi',
    );
    expect(res.repaired, isFalse);
    expect(res.error, contains('sin miembros'));
  });

  test('JSON ilegible de miembros: no repara y no toca la red', () async {
    await insertGroup('{no-json');
    final row = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conn/group/room-zombi'))).getSingle();
    final res = await repairGroupRoom(
      database: db,
      runtimes: const {},
      conv: row,
      roomId: 'room-zombi',
      name: 'Zombi',
    );
    expect(res.repaired, isFalse);
    expect(res.error, contains('ilegibles'));
  });

  test('grupo con un solo bot: no repara y no toca la red', () async {
    await insertGroup('[{"name":"default","connectionId":"c1"}]');
    final row = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conn/group/room-zombi'))).getSingle();
    final res = await repairGroupRoom(
      database: db,
      runtimes: const {},
      conv: row,
      roomId: 'room-zombi',
      name: 'Zombi',
    );
    expect(res.repaired, isFalse);
    expect(res.error, contains('menos de 2'));
  });

  test('con 2 bots y sin runtimes disponibles: error, sin tocar la red', () async {
    await insertGroup(
      '[{"name":"default","connectionId":"c1"},{"name":"parker","connectionId":"c2"}]',
    );
    final row = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conn/group/room-zombi'))).getSingle();
    final res = await repairGroupRoom(
      database: db,
      runtimes: const {},
      conv: row,
      roomId: 'room-zombi',
      name: 'Zombi',
    );
    expect(res.repaired, isFalse);
    expect(res.error, isNotNull);
  });
}
