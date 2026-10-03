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

  test('sala mixta: la dueña es quien la hostea, no la primera con miembros',
      () async {
    // Escenario del usuario: room-2 vive en 'segunda' (su espejo del default
    // lleva la clave); 'primera' sólo ve un miembro por la MEMBRESÍA legacy
    // (`ui_meta.hermes-bots.groups`). Con la dueña por «primera con miembros»
    // la sala se colocaba en primera, cuyo WS no conoce room-2 → groups.log
    // vacío → «el grupo mezclado no aparece».
    final mixed = GroupRoom(
      key: 'id:room-2',
      roomId: 'room-2',
      name: 'Mezcla',
      revision: 1,
      members: const [
        GroupMember(name: 'default', displayName: 'default'),
        GroupMember(name: 'researcher', displayName: 'researcher'),
      ],
    );
    final primera = ConnectionGroupState(
      id: 'primera',
      label: 'primera',
      createdAt: DateTime(2026, 1, 1),
      displayOrder: 0,
      profiles: [
        GatewayProfileSnapshot(name: 'default', groups: GroupSyncSnapshot.empty),
        GatewayProfileSnapshot(name: 'researcher', groups: GroupSyncSnapshot.empty),
      ],
      titles: const {},
    );
    final segunda = ConnectionGroupState(
      id: 'segunda',
      label: 'segunda',
      createdAt: DateTime(2026, 2, 1),
      displayOrder: 1,
      profiles: [
        GatewayProfileSnapshot(
          name: 'default',
          groups: GroupSyncSnapshot(rooms: {'id:room-2': mixed}),
        ),
      ],
      titles: const {},
    );
    await syncGroupMirrors(db: db, connections: [primera, segunda]);
    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows, hasLength(1));
    expect(
      rows.single.connectionId,
      'segunda',
      reason: 'la dueña debe ser la que hostea la sala (su groups.log es el real)',
    );
  });

  test('espejo COMPLETO en ambos gateways (Desktop real): sala mixta aparece',
      () async {
    // Caso real del usuario: la misma Desktop publica la proyección COMPLETA
    // en el `default` de CADA gateway (`group-chat.ts:88-91`). El bot 'aa'
    // vive en la primera conexión, 'bb' en la segunda; ambas conexiones
    // proyectan la sala. Debe listarse UNA fila con miembros de ambos
    // gateways, dueña la primera por orden.
    final mixedA = GroupRoom(
      key: 'id:room-mix',
      roomId: 'room-mix',
      name: 'Mezcla',
      revision: 1,
      members: const [
        GroupMember(name: 'aa', displayName: 'Aa'),
        GroupMember(name: 'bb', displayName: 'Bb'),
      ],
    );
    ConnectionGroupState gw(String id, DateTime created) => ConnectionGroupState(
      id: id,
      label: id,
      createdAt: created,
      displayOrder: 0,
      profiles: [
        GatewayProfileSnapshot(
          name: 'default',
          groups: GroupSyncSnapshot(rooms: {'id:room-mix': mixedA}),
        ),
        GatewayProfileSnapshot(name: id == 'gwA' ? 'aa' : 'bb', groups: GroupSyncSnapshot.empty),
      ],
      titles: const {},
    );
    await syncGroupMirrors(
      db: db,
      connections: [gw('gwA', DateTime(2026, 1, 1)), gw('gwB', DateTime(2026, 2, 1))],
    );
    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows, hasLength(1), reason: 'la sala mixta real debe aparecer');
    expect(rows.single.connectionId, 'gwA');
    // 0.1.27: los miembros de la FILA son los de TODAS las conexiones que
    // los resolvieron. Antes sólo iban los de la dueña: el subtítulo
    // «1 miembro · gwA» hacía parecer que el grupo mixto no se había
    // sincronizado (reporte del usuario).
    expect(rows.single.subtitle, '2 miembros · gwA');
  });

  test('default oculto + espejo: la sala sigue materializándose', () async {
    // H2 del bug real: el `continue` por `hidden` saltaba el parse del espejo
    // del perfil `default`. Ocultar el BOT no despublica los GRUPOS.
    // Simulado a nivel syncGroupMirrors: el roster llega SIN títulos del
    // default (oculto) pero CON su espejo — la sala debe existir.
    final mixed = GroupRoom(
      key: 'id:room-h',
      roomId: 'room-h',
      name: 'Ocultos',
      revision: 1,
      members: const [GroupMember(name: 'bb', displayName: 'Bb')],
    );
    final oculta = ConnectionGroupState(
      id: 'oculta',
      label: 'oculta',
      createdAt: DateTime(2026, 1, 1),
      displayOrder: 0,
      profiles: [
        // El manager (post-fix) aporta el espejo aunque el bot esté oculto:
        // titles NO contiene 'default' (hidden salta el título).
        GatewayProfileSnapshot(
          name: 'default',
          groups: GroupSyncSnapshot(rooms: {'id:room-h': mixed}),
        ),
      ],
      titles: const {},
    );
    final otra = ConnectionGroupState(
      id: 'otra',
      label: 'otra',
      createdAt: DateTime(2026, 2, 1),
      displayOrder: 1,
      profiles: [
        GatewayProfileSnapshot(name: 'bb', groups: GroupSyncSnapshot.empty),
      ],
      titles: const {},
    );
    await syncGroupMirrors(db: db, connections: [oculta, otra]);
    final rows = await (db.select(
      db.conversations,
    )..where((c) => c.kind.equals('group'))).get();
    expect(rows, hasLength(1), reason: 'el espejo sobrevive al bot oculto');
    expect(rows.single.connectionId, 'oculta');
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
