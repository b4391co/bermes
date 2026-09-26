import 'package:drift/drift.dart';

/// Tabla de conexiones Hermes (secrets NUNCA aquí: van a secure storage).
class Connections extends Table {
  TextColumn get id => text()(); // UUID local
  TextColumn get name => text()();
  TextColumn get scheme => text()(); // http | https
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get basePath => text().withDefault(const Constant(''))();
  TextColumn get authKind => text()(); // password | bearerToken
  TextColumn get username => text().withDefault(const Constant(''))();
  BoolColumn get allowInsecureTls =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache de conversaciones (bots + grupos) por conexión.
/// El source of truth de grupos es el gateway; esto es caché de presentación.
class Conversations extends Table {
  TextColumn get id => text()(); // connectionId/kind/gatewayId
  TextColumn get connectionId => text()();
  TextColumn get kind => text()(); // bot | group | session
  TextColumn get gatewayId => text()(); // profile name | room_id | session_id
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get avatarSeed => text().nullable()();
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();
  TextColumn get gatewayLabel => text().nullable()();
  DateTimeColumn get lastActivity => dateTime().nullable()();
  TextColumn get preview => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache local de mensajes (historial paginado + live).
class Messages extends Table {
  TextColumn get id => text()(); // storageId + row local
  TextColumn get conversationId => text()(); // FK lógico a Conversations.id
  TextColumn get connectionId => text()();
  TextColumn get role => text()(); // user | assistant | system | tool
  TextColumn get authorName => text().nullable()();
  TextColumn get authorConnectionId => text().nullable()();
  TextColumn get text_ => text().withDefault(const Constant(''))();
  DateTimeColumn get timestamp => dateTime().nullable()();
  TextColumn get sendState => text().withDefault(const Constant('sent'))();
  TextColumn get origin => text().withDefault(const Constant('history'))();
  TextColumn get toolsJson => text().nullable()(); // ToolActivity serializados
  IntColumn get gatewayRowId =>
      integer().nullable()(); // row_id del gateway si existe
  IntColumn get seq => integer().nullable()(); // seq de eventos para replay

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {conversationId, gatewayRowId},
  ];
}

/// Borradores por conversación (persistente).
class Drafts extends Table {
  TextColumn get conversationId => text()();
  TextColumn get text_ => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {conversationId};
}

/// Hosts SSH para la pestaña Terminal (sesiones interactivas + Herdr).
/// Secretos (password, passphrase, private key) NUNCA aquí: van a SecureStore.
class SshHosts extends Table {
  TextColumn get id => text()(); // UUID local
  TextColumn get name => text()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text()();
  TextColumn get authKind => text()(); // password | key
  TextColumn get knownFingerprint =>
      text().nullable()(); // huella aceptada (TOFU): SHA256:<b64>
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
