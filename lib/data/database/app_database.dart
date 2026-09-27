import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Connections, Conversations, Messages, Drafts, SshHosts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

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
    },
  );
}
