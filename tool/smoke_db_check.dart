import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:hermes_pocket/data/database/app_database.dart';

Future<void> main() async {
  final db = AppDatabase(NativeDatabase.memory());
  // Insertar conversación + mensajes + borrador como lo haría la UI.
  await db.into(db.conversations).insert(ConversationsCompanion.insert(
    id: 'conn1/bot/default',
    connectionId: 'conn1',
    kind: 'bot',
    gatewayId: 'default',
    title: 'default',
    avatarSeed: const Value('default'),
    isGroup: const Value(false),
    gatewayLabel: const Value('Mi gateway'),
    lastActivity: Value(DateTime.now()),
  ));
  for (var i = 0; i < 5; i++) {
    await db.into(db.messages).insert(MessagesCompanion.insert(
      id: 'm$i',
      conversationId: 'conn1/bot/default',
      connectionId: 'conn1',
      role: i.isEven ? 'user' : 'assistant',
      text_: Value(i.isEven ? 'hola $i' : '**markdown** respuesta'),
      timestamp: Value(DateTime.now().subtract(Duration(minutes: 10 - i))),
      sendState: const Value('sent'),
      origin: const Value('history'),
    ));
  }
  await db.into(db.drafts).insert(DraftsCompanion.insert(
    conversationId: 'conn1/bot/default',
    text_: const Value('borrador pendiente'),
  ));

  // Consultas equivalentes a las de las pantallas.
  final convs = await db.select(db.conversations).watch().first;
  assert(convs.length == 1, 'watch de conversaciones');
  assert(convs.first.title == 'default');
  assert(convs.first.gatewayLabel == 'Mi gateway');

  final msgs = await (db.select(db.messages)
        ..where((m) =>
            m.conversationId.equals('conn1/bot/default') &
            m.origin.equals('history'))
        ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
        ..limit(61))
      .get();
  assert(msgs.length == 5, 'historial paginado');
  assert(msgs.first.text_.contains('respuesta'),
      'orden por timestamp desc');

  final older = await (db.select(db.messages)
        ..where((m) =>
            m.conversationId.equals('conn1/bot/default') &
            m.origin.equals('history') &
            m.timestamp.isSmallerThanValue(
                msgs.first.timestamp ?? DateTime.now()))
        ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
        ..limit(61))
      .get();
  assert(older.length == 4, 'paginación hacia arriba');

  final draft = await (db.select(db.drafts)
        ..where((d) => d.conversationId.equals('conn1/bot/default')))
      .getSingleOrNull();
  assert(draft != null && draft.text_ == 'borrador pendiente', 'borrador');

  // Upsert idempotente del borrador (lo que hace _flushDraft).
  await db.into(db.drafts).insertOnConflictUpdate(DraftsCompanion.insert(
    conversationId: 'conn1/bot/default',
    text_: const Value('nuevo texto'),
  ));
  final draft2 = await (db.select(db.drafts)
        ..where((d) => d.conversationId.equals('conn1/bot/default')))
      .getSingleOrNull();
  assert(draft2!.text_ == 'nuevo texto', 'upsert borrador');

  // Batch delete+insert live (lo que hace _persistLive).
  await db.batch((b) {
    b.deleteWhere<$MessagesTable, Message>(db.messages,
        ($MessagesTable m) => m.conversationId.equals('conn1/bot/default') & m.origin.equals('live'));
    b.insertAll(db.messages, [
      MessagesCompanion.insert(
        id: 'live1',
        conversationId: 'conn1/bot/default',
        connectionId: 'conn1',
        role: 'assistant',
        text_: const Value('streaming...'),
        sendState: const Value('sent'),
        origin: const Value('live'),
      ),
    ]);
  });
  final live = await (db.select(db.messages)
        ..where((m) => m.origin.equals('live')))
      .get();
  assert(live.length == 1, 'bloque live');

  await db.close();
  print('SMOKE OK');
}
