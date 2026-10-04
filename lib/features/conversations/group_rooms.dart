/// Espejo local del snapshot de grupos de Hermes Desktop:
/// `ui_meta['hermes-bots-groups']` del perfil `default` de cada gateway.
///
/// Fuente de verdad (Hermes Desktop, commit e408d36):
/// - Clave y forma del snapshot: `apps/desktop/src/plugins/hermes-bots/group-chat.ts:49`
///   (`GROUP_CHAT_SYNC_META_KEY = 'hermes-bots-groups'`), envelope v3 en
///   `group-chat.ts:68-80` (`GroupChatSyncSnapshot {version, updatedAt, rooms,
///   deleted}`), sala proyectada en `group-chat.ts:59-72` (`GroupChatSyncRoom`).
/// - Quién lo escribe: SOLO Desktop, vía `profiles.configure` sobre el perfil
///   `default` de cada gateway conectado (`group-chat.ts:1174-1192`). El backend
///   no conoce esta clave: `grep -rn "hermes-bots-groups" --include=*.py` no da
///   nada, y `_configure_ui_meta` (`tui_gateway/methods_profiles.py:600-606`)
///   la fusiona key-wise opaca. Pocket es LECTOR: NUNCA publica aquí (haría
///   perder mensajes al recorte de presupuesto de Desktop, group-chat.ts:1281).
/// - Identidad durable de sala: `id:<roomId>`, con `name:<name>` solo para
///   salas legacy sin roomId (`group-chat.ts:216-223` `groupChatRoomKey`).
///   Un rename es una edición de nombre en la MISMA clave, nunca
///   delete+create distribuido (`group-chat.ts:450-456`).
/// - Clave de merge de miembro: `botRosterKey` = `connectionId::profileName`
///   (`data.ts:1286-1288`, usado por `group-chat.ts:446-448`). El nombre
///   visible nunca es identidad.
/// - Los tombstones de salas con id son FINALES; los de nombre van por
///   revisión (`group-chat.ts:607-617`).
/// - Salas/mensajes ausentes en el remoto NO son borrado (`group-chat.ts:673-675`).
/// - El pin de sala y el orden de sala son locales y viajan fuera del espejo
///   (`group-pin.ts:4-8`, `types.ts:222-225`).
library;

/// Sala dentro del snapshot (subconjunto de `GroupChatSyncRoom`).
class GroupRoom {
  /// Clave durable del snapshot: `id:<roomId>` o `name:<name>` (legacy).
  final String key;

  /// `roomId` inmutable; null solo en salas legacy sin id.
  final String? roomId;

  /// Nombre visible actual (`name` del snapshot).
  final String name;

  /// Revisión del gateway que escribió esta proyección (`revision`).
  final int revision;

  /// Miembros descriptores (`members`, subconjunto de `GroupMember`).
  final List<GroupMember> members;

  /// Log INCORPORADO del espejo (`rooms[k].log`): Desktop guarda el historial
  /// de la sala dentro del propio espejo. Para salas sin `roomId` (clave
  /// `name:`) es la ÚNICA historia que existe — el gateway no las hospeda
  /// (groups.state/log → 4112/4114, verificado contra 0.21.5 real).
  final List<Map<String, Object?>> embeddedLog;

  const GroupRoom({
    required this.key,
    required this.roomId,
    required this.name,
    required this.revision,
    required this.members,
    this.embeddedLog = const [],
  });

  /// Id de identidad del grupo: prefiere siempre el `roomId` inmutable.
  /// Solo una sala legacy sin id se nombra por su display name (igual que
  /// Desktop, que mantiene la clave `name:` para esas salas).
  String get identity => roomId ?? name;

  /// Construcción de la clave durable a partir de roomId/nombre.
  static String roomKey({String? roomId, required String name}) =>
      (roomId != null && roomId.isNotEmpty) ? 'id:$roomId' : 'name:$name';
}

/// Miembro de una sala: descriptor parcial de `GroupMember`
/// (`types.ts:130-147`, `Pick<RosterRow, …>`).
class GroupMember {
  /// Perfil del backend (`RosterRow.name`); identidad dentro del gateway.
  final String? name;

  /// Identidad estable de la conexión: `installId` del backend (compartida
  /// entre clientes) o `connectionId` de Desktop (solo suyo) — `types.ts:103-106`.
  final String? connectionId;
  final String? installId;
  final String? connectionLabel;

  final String? handle;
  final String? displayName;
  final String? title;
  final String? targetProfile;

  /// Nombres canónicos previos del perfil (`profiles.list` → `previous_names`,
  /// `gateway-contract.generated.ts:1786`): permite re-enlazar tras un rename.
  final List<String> previousNames;

  const GroupMember({
    this.name,
    this.connectionId,
    this.installId,
    this.connectionLabel,
    this.handle,
    this.displayName,
    this.title,
    this.targetProfile,
    this.previousNames = const [],
  });

  factory GroupMember.fromJson(Map<String, Object?> j) => GroupMember(
    name: _str(j['name']),
    connectionId: _str(j['connectionId']),
    installId: _str(j['installId']),
    connectionLabel: _str(j['connectionLabel']),
    handle: _str(j['handle']),
    displayName: _str(j['display_name']),
    title: _str(j['title']),
    targetProfile: _str(j['targetProfile']),
    previousNames: _strList(j['previous_names']),
  );

  /// Clave de merge: la identidad del roster, `connectionId::profileName`
  /// (`data.ts:1287`). La usamos literal, SIN sustituir `connectionId` por
  /// `installId`: en el empate Desktop también uniona miembros por esta clave
  /// y un `installId` en ese hueco convertiría dos espejos del mismo bot en
  /// dos filas distintas (`group-chat.ts:446-448`, `l.556-569`).
  String get rosterKey => '${connectionId ?? 'legacy'}::${name ?? 'default'}';

  /// Serialización para `conversations.groupMembersJson` (ficha de miembros
  /// y autocompletado `@` de salas sin roomId). Los descriptores son
  /// parciales — se guarda el mapa crudo que envió el gateway.
  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (connectionId != null) 'connectionId': connectionId,
    if (installId != null) 'installId': installId,
    if (connectionLabel != null) 'connectionLabel': connectionLabel,
    if (handle != null) 'handle': handle,
    if (displayName != null) 'display_name': displayName,
    if (title != null) 'title': title,
    if (targetProfile != null) 'targetProfile': targetProfile,
    if (previousNames.isNotEmpty) 'previous_names': previousNames,
  };
}

/// Snapshot completo de `ui_meta['hermes-bots-groups']`.
class GroupSyncSnapshot {
  final int version;
  final Map<String, GroupRoom> rooms;

  /// Clave durable → revisión del tombstone.
  final Map<String, int> deleted;

  const GroupSyncSnapshot({
    this.version = 3,
    this.rooms = const {},
    this.deleted = const {},
  });

  static const GroupSyncSnapshot empty = GroupSyncSnapshot();

  /// Decodifica el envelope; null si la sección no existe o no es un objeto.
  /// Tolerante a v1/v2 (que no traían `rooms` con prefijo `id:`):
  /// `normalizeGroupChatSyncSnapshot` (`group-chat.ts:225-262`) reindexa las
  /// claves legacy por nombre, y aquí se hace lo mismo.
  static GroupSyncSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final body = raw['rooms'];
    if (body is! Map) return null;
    final rooms = <String, GroupRoom>{};
    body.forEach((k, v) {
      if (k is! String || v is! Map) return;
      final map = v.cast<String, Object?>();
      final roomId = _str(map['roomId']);
      final name = _str(map['name']) ?? '';
      // Clave sin prefijo (envelope antiguo) → se normaliza a `name:`.
      final hasPrefix = k.startsWith('id:') || k.startsWith('name:');
      final key = hasPrefix ? k : GroupRoom.roomKey(roomId: roomId, name: name);
      if (roomId != null && key != 'id:$roomId') {
        // El roomId manda sobre una clave `name:` rezagada.
        rooms['id:$roomId'] = _room(key, roomId, name, map);
        rooms.remove(key);
      } else {
        rooms[key] = _room(key, roomId, name, map);
      }
    });
    final deleted = <String, int>{};
    final rawDeleted = raw['deleted'];
    if (rawDeleted is Map) {
      rawDeleted.forEach((k, v) {
        if (k is! String) return;
        final rev = v is int ? v : num.tryParse('${v ?? ''}')?.toInt();
        if (rev != null) deleted[k] = rev;
      });
    }
    final version = raw['version'] is int
        ? raw['version'] as int
        : num.tryParse('${raw['version'] ?? ''}')?.toInt() ?? 3;
    return GroupSyncSnapshot(version: version, rooms: rooms, deleted: deleted);
  }

  static GroupRoom _room(
    String key,
    String? roomId,
    String name,
    Map<String, Object?> map,
  ) {
    final members = (map['members'] is List)
        ? (map['members'] as List)
              .whereType<Map>()
              .map((m) => GroupMember.fromJson(m.cast<String, Object?>()))
              .toList()
        : const <GroupMember>[];
    final revision = map['revision'] is int
        ? map['revision'] as int
        : num.tryParse('${map['revision'] ?? 0}')?.toInt() ?? 0;
    return GroupRoom(
      key: key,
      roomId: roomId,
      name: name,
      revision: revision,
      members: members,
      embeddedLog: (map['log'] is List)
          ? (map['log'] as List)
                .whereType<Map>()
                .map((m) => m.cast<String, Object?>())
                .toList()
          : const <Map<String, Object?>>[],
    );
  }
  /// Salas vivas: caen las tombstoneadas. Réplica de la regla de
  /// `mergeGroupChatSyncSnapshots` (`group-chat.ts:607-617`): un tombstone
  /// `id:` es final; uno `name:` solo gana si su revisión >= la de la sala.
  List<GroupRoom> liveRooms() {
    final out = <GroupRoom>[];
    for (final entry in rooms.entries) {
      final tomb = deleted[entry.key];
      if (tomb == null) {
        out.add(entry.value);
        continue;
      }
      if (entry.key.startsWith('id:')) continue;
      if (tomb < entry.value.revision) out.add(entry.value);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}

String? _str(Object? v) => (v is String && v.isNotEmpty) ? v : null;

List<String> _strList(Object? v) => v is List
    ? v.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
    : const [];

/// Une dos espejos del MISMO gateway (o de gateways distintos) sala a sala.
///
/// Reglas copiaditas de Desktop (`group-chat.ts:457-620`):
/// - Rooms se indexan por clave durable; una clave `id:` nunca se duplica con
///   su antigua `name:` (`mergeRemote…` empareja por roomId, l.718-731).
/// - Log/identidad siguen la revisión más alta; EN EMPATE se unen miembros por
///   `rosterKey` y gana el lado local (`l.556-571`).
/// - `deleted` es la unión del max de revisiones (`l.495-501`).
/// - Ausente ≠ borrado: nada de lo que falte en [b] se elimina.
Map<String, GroupRoom> mergeGroupRooms({
  required Map<String, GroupRoom> base,
  required Map<String, GroupRoom> other,
  bool baseWinsTies = true,
}) {
  final out = Map<String, GroupRoom>.from(base);
  // Índice por roomId INMUTABLE: dos lados pueden proyectar la misma sala con
  // claves distintas (un rename llega como `id:<nuevo>`/`name:<viejo>` según
  // la antigüedad del espejo). La clave canónica del resultado es SIEMPRE la
  // del lado base, si existía: si no, la sala reaparecería bajo una clave
  // nueva en cada merge y `liveRooms` la contaría dos veces.
  final baseKeyByRoomId = <String, String>{
    for (final e in base.entries)
      if (e.value.roomId != null) e.value.roomId!: e.key,
  };
  for (final entry in other.entries) {
    final incoming = entry.value;
    final existingKey = incoming.roomId == null
        ? entry.key
        : (baseKeyByRoomId[incoming.roomId!] ?? entry.key);
    final current = out[existingKey];
    if (current == null) {
      out[existingKey] = incoming;
      continue;
    }
    out[existingKey] = _mergeRoom(
      current,
      incoming,
      baseWinsTies: baseWinsTies,
    );
  }
  return out;
}

GroupRoom _mergeRoom(GroupRoom a, GroupRoom b, {required bool baseWinsTies}) {
  final GroupRoom head;
  final List<GroupMember> members;
  if (a.revision != b.revision) {
    head = a.revision > b.revision ? a : b;
    members = head.members;
  } else {
    // Empate: identidad del que se considere local; miembros unidos por
    // rosterKey con el local ganando (group-chat.ts:556-569).
    final local = baseWinsTies ? a : b;
    final remote = baseWinsTies ? b : a;
    head = local;
    final byKey = <String, GroupMember>{
      for (final m in remote.members) m.rosterKey: m,
      for (final m in local.members) m.rosterKey: m,
    };
    members = byKey.values.toList();
  }
  return GroupRoom(
    // La clave del lado base gana: es la que ya indexan `out`,
    // `_localIdForDeleted` y las revisiones sincronizadas.
    key: a.key,
    roomId: a.roomId ?? b.roomId,
    name: head.name.isNotEmpty ? head.name : a.name,
    revision: a.revision > b.revision ? a.revision : b.revision,
    members: members,
  );
}

/// Clave de conversación Pocket para un grupo de un gateway.
///
/// `connectionId` es el UUID local de la conexión (estable para esta app);
/// `identity` es el `roomId` del grupo cuando lo hay. La forma coincide con la
/// de los bots (`<connectionId>/bot/<profile>`): `<connectionId>/group/<id>`.
String groupConversationId(String connectionId, String identity) =>
    '$connectionId/group/$identity';

/// Traduce un rótulo de miembro del espejo a un perfil real del gateway.
///
/// Un espejo escrito por OTRO Desktop lleva su `connectionId`
/// (`host.state.connectionId`), que aquí no significa nada; el perfil
/// (`name`) sí, igual que `previous_names` tras un `hermes profile rename`.
/// Devuelve null cuando el miembro no pertenece a este gateway.
String? memberProfileHere(GroupMember member, Set<String> localProfiles) {
  final direct = member.name;
  if (direct != null && localProfiles.contains(direct)) return direct;
  for (final prev in member.previousNames) {
    if (localProfiles.contains(prev)) return prev;
  }
  return null;
}

/// Nombre canónico de un grupo a partir de sus miembros y de los títulos ya
/// resueltos de los bots (`botRosterMeta.title > display_name > name` para
/// cada miembro; `labels.ts:34-62`). Devuelve null si ningún miembro aporta
/// título: el llamador mantiene el nombre del espejo.
String? canonicalGroupName(GroupRoom room, Map<String, String> titleByProfile) {
  final titled = <String>[];
  for (final m in room.members) {
    final t = m.title ?? (m.name == null ? null : titleByProfile[m.name]);
    if (t != null && t.trim().isNotEmpty && !titled.contains(t.trim())) {
      titled.add(t.trim());
    }
  }
  if (titled.isEmpty) return null;
  if (titled.length == 1) return titled.first;
  final shown = titled.take(3).join(', ');
  return titled.length > 3 ? '$shown…' : shown;
}
