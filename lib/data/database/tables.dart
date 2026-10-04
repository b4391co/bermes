import 'package:drift/drift.dart';

/// Tabla de conexiones Hermes (secrets NUNCA aquí: van a secure storage).
class Connections extends Table {
  TextColumn get id => text()(); // UUID local
  TextColumn get name => text()();
  TextColumn get scheme => text()(); // http | https
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get basePath => text().withDefault(const Constant(''))();
  TextColumn get authKind => text()(); // password | bearerToken | sessionToken
  TextColumn get username => text().withDefault(const Constant(''))();
  BoolColumn get allowInsecureTls =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  // Orden de las secciones de gateway en la lista de chats (v6).
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  // Identidad estable del backend (/api/status `install_id`): portable entre
  // clientes, la usa el descriptor de miembro de grupo (types.ts:103-106). v8.
  TextColumn get installId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache de conversaciones (bots + grupos de Desktop) por conexión.
///
/// Los grupos que esta app muestra son el espejo
/// `ui_meta['hermes-bots-groups']` del gateway (lo escribe Hermes Desktop);
/// esto es caché de presentación, nunca autoritativa. `id` es
/// `<connectionId>/<kind>/<gatewayId>` y `gatewayId` es el roomId durable del
/// grupo cuando lo hay — jamás un nombre visible.
class Conversations extends Table {
  TextColumn get id => text()(); // connectionId/kind/gatewayId
  TextColumn get connectionId => text()();
  TextColumn get kind => text()(); // bot | group | session
  TextColumn get gatewayId => text()(); // profile name | room_id | session_id
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get avatarSeed => text().nullable()();
  TextColumn get avatarUrl => text().nullable()(); // data-url o http(s)
  TextColumn get botAvatarMeta =>
      text().nullable()(); // JSON hermes-bots.avatar
  TextColumn get canonicalSession =>
      text().nullable()(); // sesión canónica Bot Chat
  BoolColumn get isGroup => boolean().withDefault(const Constant(false))();
  TextColumn get gatewayLabel => text().nullable()();
  DateTimeColumn get lastActivity => dateTime().nullable()();
  TextColumn get preview => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // Organización local de la lista (nunca viaja al gateway):
  // pinned global (arriba de todo) y pinnedGateway (destacado dentro de
  // la sección de su gateway). v6.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get pinnedGateway =>
      boolean().withDefault(const Constant(false))();
  // Espejo de grupos de Desktop (`ui_meta['hermes-bots-groups']` del perfil
  // `default`): roomId inmutable de la sala (null en salas legacy sin id),
  // revisión del gateway que la proyectó, y nombre que tenía al sincronizarla
  // — permite detectar un rename remoto sin pisar el título local. v7.
  TextColumn get groupRoomId => text().nullable()();
  IntColumn get groupSyncRevision => integer().withDefault(const Constant(0))();
  TextColumn get groupSyncName => text().nullable()();
  // Descriptores de miembros del grupo (GroupRoom.members serializados):
  // ficha de miembros y autocompletado `@` de salas sin roomId — el gateway
  // no las hospeda (groups.state → 4112) y el roster del chat no alcanza.
  TextColumn get groupMembersJson => text().nullable()();

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
  // JSON [{path,name,bytes}] de las imágenes del turno (MessageAttachment);
  // los bytes se re-resuelven contra el gateway (ver fetchMedia).
  TextColumn get attachmentsJson => text().nullable()();

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
