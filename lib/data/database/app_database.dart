import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Connections, Conversations, Messages, Drafts, SshHosts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Migraciones versionadas: añadir casos en orden ascendente.
      if (from < 2) {
        await m.createTable(sshHosts);
      }
      if (from < 3) {
        await m.addColumn(conversations, conversations.avatarUrl);
      }
      if (from < 4) {
        await m.addColumn(conversations, conversations.canonicalSession);
      }
      if (from < 5) {
        await m.addColumn(conversations, conversations.botAvatarMeta);
      }
      if (from < 6) {
        await m.addColumn(conversations, conversations.pinned);
        await m.addColumn(conversations, conversations.pinnedGateway);
        await m.addColumn(connections, connections.displayOrder);
      }
      if (from < 7) {
        await m.addColumn(conversations, conversations.groupRoomId);
        await m.addColumn(conversations, conversations.groupSyncRevision);
        await m.addColumn(conversations, conversations.groupSyncName);
      }
      if (from < 8) {
        await m.addColumn(connections, connections.installId);
      }
      if (from < 9) {
        // Adjuntos de imagen: JSON de rutas/nombres (los bytes se
        // re-resuelven contra el gateway; ver MessageAttachment + fetchMedia).
        await m.addColumn(messages, messages.attachmentsJson);
      }
      if (from < 10) {
        // Miembros de grupo serializados (ficha + menciones de salas name:).
        await m.addColumn(conversations, conversations.groupMembersJson);
      }
      if (from < 11) {
        // Sala hosted: el gateway la hospeda vía groups.create (turnos
        // reales). false = sala sólo-espejo (legada de Desktop o gateway
        // sin groups.*).
        await m.addColumn(conversations, conversations.groupHosted);
      }
    },
  );

  /// Fila de conversación por id, o null. Incluye las marcadas como grupos
  /// ocultos (`kind='group-hidden'`), que la lista no muestra.
  Future<Conversation?> groupConversationRow(String id) =>
      (select(conversations)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Preserva la organización LOCAL de una fila de conversación a través de
  /// un re-alta (el re-sync del roster borra y vuelve a insertar).
  ///
  /// `pinned`/`pinnedGateway`/`sortOrder` son preferencia del usuario y NUNCA
  /// viajan al gateway — igual que en Desktop, donde el pin de sala vive en el
  /// registro local y se deja fuera del espejo (`group-pin.ts:4-8`,
  /// `types.ts:222-225`). Si la fila no existía, valores por defecto.
  Future<({bool pinned, bool pinnedGateway, int sortOrder})> localConvPrefs(
    String id,
  ) async {
    final prior = await (select(
      conversations,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return (
      pinned: prior?.pinned ?? false,
      pinnedGateway: prior?.pinnedGateway ?? false,
      sortOrder: prior?.sortOrder ?? 0,
    );
  }

  /// Estado durable del espejo de grupos de una conexión: `id` (forma
  /// `<connectionId>/group/<roomId>`) → roomId + revisión + nombre sincronizado.
  /// Incluye los marcadores ocultos (`group-hidden`), porque un tombstone del
  /// espejo también debe retirarlos de la BD. Permite detectar renames.
  Future<Map<String, ({String? roomId, int revision, String? syncName})>>
  groupSyncState(String connectionId) async {
    final rows = await (select(
      conversations,
    )..where((c) => c.kind.isIn(const ['group', 'group-hidden']))).get();
    return {
      for (final r in rows)
        r.id: (
          roomId: r.groupRoomId,
          revision: r.groupSyncRevision,
          syncName: r.groupSyncName,
        ),
    };
  }

  /// Fija/desfija una conversación (pin global y pin dentro de su gateway).
  Future<void> setPinned(
    String id, {
    required bool pinned,
    required bool pinnedGateway,
  }) => (update(conversations)..where((c) => c.id.equals(id))).write(
    ConversationsCompanion(
      pinned: Value(pinned),
      pinnedGateway: Value(pinnedGateway),
    ),
  );

  /// Nuevo orden de las conexiones (secciones de gateway en la lista).
  Future<void> setConnectionOrders(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (update(connections)..where((c) => c.id.equals(orderedIds[i])))
          .write(ConnectionsCompanion(displayOrder: Value(i)));
    }
  }
}
