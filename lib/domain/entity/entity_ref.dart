/// Identidad estable de entidades en Hermes Pocket.
///
/// REGLA: nunca usar nombres visibles como identidad. Dos bots llamados
/// "default" en gateways distintos son bots distintos.
///
/// - [connectionId]: UUID local persistente de la conexión (this app).
/// - [EntityKey]: clave de entidad según el gateway (estable entre installs).
///
/// Los grupos viven en el gateway (hosted rooms con room_id), así que dos
/// instalaciones ven el mismo room_id: no hay duplicación posible.
/// Los perfiles (bots) se identifican por su `name` dentro del gateway.
library;

enum EntityKind { bot, group, session }

class EntityRef {
  final String connectionId;
  final EntityKind kind;
  final String
  key; // bot:<profile_name> | group:<room_id> | session:<session_id>

  const EntityRef({
    required this.connectionId,
    required this.kind,
    required this.key,
  });

  factory EntityRef.bot(String connectionId, String profileName) => EntityRef(
    connectionId: connectionId,
    kind: EntityKind.bot,
    key: 'bot:$profileName',
  );

  factory EntityRef.group(String connectionId, String roomId) => EntityRef(
    connectionId: connectionId,
    kind: EntityKind.group,
    key: 'group:$roomId',
  );

  factory EntityRef.session(String connectionId, String sessionId) => EntityRef(
    connectionId: connectionId,
    kind: EntityKind.session,
    key: 'session:$sessionId',
  );

  String get storageId => '$connectionId/$key';

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.storageId == storageId;

  @override
  int get hashCode => storageId.hashCode;

  @override
  String toString() => 'EntityRef($storageId)';
}
