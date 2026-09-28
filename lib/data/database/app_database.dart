import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Connections, Conversations, Messages, Drafts, SshHosts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

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
    },
  );

  /// Fija/desfija una conversación (pin global y pin dentro de su gateway).
  Future<void> setPinned(
    String id, {
    required bool pinned,
    required bool pinnedGateway,
  }) =>
      (update(conversations)..where((c) => c.id.equals(id))).write(
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
