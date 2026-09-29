/// Sincronización del espejo de grupos de Hermes Desktop hacia la caché local.
///
/// Contract (todo citado del repo real, commit e408d36):
/// - El espejo vive en `ui_meta['hermes-bots-groups']` del perfil `default` y
///   Desktop lo publica con `profiles.configure` (`group-chat.ts:1174-1192`) y
///   lo lee con `profiles.list` (`group-chat.ts:1013-1026`). Los demás perfiles
///   solo aportan `ui_meta['hermes-bots'].groups` (`types.ts:75`), la
///   membresía bot→grupo.
/// - Este módulo es LECTOR. Pocket NUNCA escribe `hermes-bots-groups`: es el
///   único registro on-disk de las salas del Desktop (`group-chat.ts:180-183`)
///   y publicar una proyección más pobre las degradaría.
/// - El espejo se propaga por las CONEXIONES, no por perfiles: Desktop lo
///   publica en el perfil `default` de CADA gateway alcanzable
///   (`group-chat.ts:88-91,1180-1182`) con la proyección COMPLETA, así que una
///   conexión puede traer salas con miembros de otros gateways. Por eso la
///   resolución de miembros se hace contra el conjunto de perfiles de TODAS
///   las conexiones y las salas se fusionan entre conexiones.
/// - Borrar una fila local solo cuando el snapshot la tombstonea;
///   "sala ausente ≠ borrado" (`group-chat.ts:673-675`).
library;

import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';
import 'group_rooms.dart';

/// Una fila `profiles.list` ya reducida a lo que el sync de grupos necesita.
class GatewayProfileSnapshot {
  final String name;
  final GroupSyncSnapshot groups;

  /// Nombres de grupo de la membresía legacy (`ui_meta.hermes-bots.groups`).
  final Set<String> membershipNames;

  const GatewayProfileSnapshot({
    required this.name,
    required this.groups,
    this.membershipNames = const {},
  });
}

/// Estado de una conexión para el sync de grupos.
class ConnectionGroupState {
  final String id;

  /// Nombre local de la conexión (para el subtítulo).
  final String label;
  final List<GatewayProfileSnapshot> profiles;

  /// Título canónico ya resuelto por perfil en ESTA conexión
  /// (`ui_meta.hermes-bots.title` > `display_name` > `name`,
  /// `labels.ts:34-62`).
  final Map<String, String> titles;

  const ConnectionGroupState({
    required this.id,
    required this.label,
    required this.profiles,
    required this.titles,
  });
}


/// Fusiona los espejos de grupos de TODAS las conexiones en un único mapa
/// global `identidad → sala`, al estilo de `mergeGroupChatSyncSnapshots`
/// (`group-chat.ts:457-620`):
/// - rooms se indexan por clave durable (`id:<roomId>` / `name:<name>`);
/// - identidad/miembros siguen la revisión más alta, en empate gana el primero
///   (estable entre llamadas);
/// - la lista de miembros se une por `rosterKey`;
/// - los tombstones se unen tomando la revisión máxima por clave.
({Map<String, GroupRoom> rooms, Map<String, int> deleted})
    mergeGroupMirrors(List<ConnectionGroupState> connections) {
  var rooms = <String, GroupRoom>{};
  final deleted = <String, int>{};
  for (final conn in connections) {
    for (final p in conn.profiles) {
      rooms = mergeGroupRooms(base: rooms, other: p.groups.rooms);
      p.groups.deleted.forEach((k, v) {
        deleted[k] = v > (deleted[k] ?? 0) ? v : deleted[k] ?? 0;
      });
    }
  }
  return (rooms: rooms, deleted: deleted);
}

/// Aplica el espejo global de grupos a TODAS las conexiones.
///
/// Cada grupo del espejo se materializa en la conexión de cada uno de sus
/// miembros locales: un grupo multi-gateway produce una fila por gateway
/// (cada una con su propia identidad `<connectionId>/group/<roomId>`), que es
/// lo que permite mostrarlo dentro de su sección. Si la sala no tiene ningún
/// miembro local, se materializa en la primera conexión que la proyectó
/// (`[ponytail]` simplificación: se muestra igual, sin sección propia).
///
/// Reglas por fila:
/// - Identidad: `groupConversationId(connectionId, room.identity)`, con
///   `identity` = `roomId` inmutable cuando existe. Un rename remoto NO
///   duplica la sala (el bug anterior usaba el nombre visible como PK).
/// - Solo se escribe si la revisión entrante >= la sincronizada; así un espejo
///   rezagado no revierte uno más nuevo.
/// - Re-creación preserva pin/orden locales (`localConvPrefs`).
/// - Título: el que proyecta Desktop; si viene vacío, se compone de los
///   títulos canónicos de los miembros.
Future<void> syncGroupMirrors({
  required AppDatabase db,
  required List<ConnectionGroupState> connections,
}) async {
  if (connections.isEmpty) return;

  // Conjunto de perfiles de TODAS las conexiones: el espejo de una puede
  // nombrar miembros de otra.
  final profilesByConn = {
    for (final c in connections)
      c.id: {for (final p in c.profiles) p.name},
  };
  final allProfiles = <String>{for (final s in profilesByConn.values) ...s};
  // Primer título visto por perfil: estable entre llamadas (orden de
  // conexiones), así que un perfil gema-no idéntico en dos gateways no hace
  // oscilar el subtítulo de un grupo entre ciclos.
  final titleByProfile = <String, String>{};
  for (final c in connections) {
    c.titles.forEach((k, v) => titleByProfile.putIfAbsent(k, () => v));
  }

  final merged = mergeGroupMirrors(connections);
  final snapshot = GroupSyncSnapshot(rooms: merged.rooms, deleted: merged.deleted);
  final live = snapshot.liveRooms();

  // 1) Colocar cada sala por conexión: `<connectionId>|<identidad>` → miembros.
  final placements = <String, ({GroupRoom room, String connId, List<String> members})>{};
  for (final room in live) {
    final here = <String, List<String>>{};
    for (final c in connections) {
      final members = <String>[];
      for (final m in room.members) {
        final p = memberProfileHere(m, allProfiles);
        if (p != null &&
            profilesByConn[c.id]!.contains(p) &&
            !members.contains(p)) {
          members.add(p);
        }
      }
      if (members.isNotEmpty) here[c.id] = members;
    }
    // Cada gateway con miembros locales del grupo recibe SU fila: la sala es
    // la misma entidad (mismo roomId) y la lista de salas de Desktop es la
    // misma en todos sus backends (`group-chat.ts:88-91`), así que un grupo
    // multi-gateway no es una sala duplicada sino la misma sala vista desde
    // dos gateways. Si ninguno tiene miembros, la dueña es la primera conexión
    // que la proyectó.
    if (here.isEmpty) {
      for (final c in connections) {
        if (c.profiles.any((p) => p.groups.rooms.containsKey(room.key))) {
          here[c.id] = const [];
          break;
        }
      }
    }
    for (final e in here.entries) {
      placements['${e.key}|${room.identity}'] =
          (room: room, connId: e.key, members: e.value);
    }
  }

  // 2) Escribir cada sala en cada conexión donde tiene miembros.
  for (final place in placements.values) {
    final conn = connections.firstWhere((c) => c.id == place.connId);
    await _writeRoom(
      db: db,
      conn: conn,
      room: place.room,
      memberProfiles: place.members,
      titleByProfile: titleByProfile,
    );
  }

  // 3) Caídas por conexión: solo tombstones y solo si la fila local no va más
  //    alta (un gateway rezagado no puede matar una sala viva en otro).
  final revisionByIdentity = {
    for (final r in live) r.identity: r.revision,
  };
  for (final conn in connections) {
    final prior = await db.groupSyncState(conn.id);
    for (final entry in merged.deleted.entries) {
      final id = _localIdForDeleted(
        connectionId: conn.id,
        key: entry.key,
        prior: prior,
      );
      if (id == null) continue;
      final state = prior[id];
      if (state == null) continue;
      final roomId = state.roomId;
      if (roomId != null &&
          revisionByIdentity[roomId] != null &&
          revisionByIdentity[roomId]! > entry.value) {
        continue; // una proyección más nueva revivió la sala en otro lado
      }
      await (db.delete(db.conversations)
            ..where((c) => c.id.equals(id)))
          .go();
    }
  }
  // 4) Canal legacy: antes, la ÚNICA fuente de grupos era
  //    `ui_meta['hermes-bots'].groups` y cada nombre se insertaba como
  //    conversación indexada por NOMBRE visible. Esas filas ya no son la
  //    fuente: la sala la describe el espejo con su `roomId`
  //    (`group-chat.ts:216-223`), así que se purgan una vez el espejo cubre el
  //    nombre. Mientras el espejo NO lo cubre (backend antiguo sin
  //    `hermes-bots-groups`), la fila legacy sigue siendo lo único que hay y
  //    NO se toca: la pertenencia del bot siempre se ve además en su
  //    subtítulo, puesto que Desktop también la lista ahí
  //    (`bot-row.tsx:417`, `i18n.ts:188`).
  final legacyNames = <String>{
    for (final c in connections)
      for (final p in c.profiles) ...p.membershipNames,
  };
  final liveNames = {for (final r in live) r.name};
  final coveredByMirror = live.isNotEmpty;
  for (final conn in connections) {
    final stale = await (db.select(db.conversations)
          ..where((c) => c.connectionId.equals(conn.id))
          ..where((c) => c.kind.equals('group'))
          ..where((c) => c.groupRoomId.isNull()))
        .get();
    for (final row in stale) {
      // El espejo cubre este nombre con una sala real → la fila legacy
      // (indexada por nombre) es un duplicado de esa misma sala.
      final superseded = coveredByMirror && liveNames.contains(row.gatewayId);
      // El espejo existe y ya NO lista el nombre en ninguna parte (ni sala ni
      // membresía): la pertenencia desapareció del roster.
      final orphaned = coveredByMirror && !legacyNames.contains(row.gatewayId);
      if (!superseded && !orphaned) continue;
      await (db.delete(db.conversations)
            ..where((c) => c.id.equals(row.id)))
          .go();
    }
  }
}

Future<void> _writeRoom({
  required AppDatabase db,
  required ConnectionGroupState conn,
  required GroupRoom room,
  required List<String> memberProfiles,
  required Map<String, String> titleByProfile,
}) async {
  final id = groupConversationId(conn.id, room.identity);
  // Una sola lectura de la fila: identidad, revisión y bandera de oculta.
  final prior = await db.groupConversationRow(id);
  if (prior != null && room.revision < prior.groupSyncRevision) return;
  // El usuario ocultó ESTA sala (mismo roomId): no se re-materializa. Un
  // `roomId` nuevo sí es una sala nueva — Desktop mintea un id fresco en cada
  // recreate y sus tombstones `id:` son finales (`group-chat.ts:607-613`), así
  // que un homónimo no hereda el ocultamiento.
  if (prior != null && prior.kind == 'group-hidden') return;

  final title = room.name.isNotEmpty
      ? room.name
      : (canonicalGroupName(
            room,
            {for (final p in memberProfiles) p: titleByProfile[p] ?? p},
          ) ??
          room.identity);
  final prefs = await db.localConvPrefs(id);
  await db.into(db.conversations).insertOnConflictUpdate(
    ConversationsCompanion.insert(
      id: id,
      connectionId: conn.id,
      kind: 'group',
      gatewayId: room.identity,
      title: title,
      subtitle: Value(_subtitle(memberProfiles, conn.label)),
      avatarSeed: Value(room.identity),
      isGroup: const Value(true),
      gatewayLabel: Value(conn.label),
      pinned: Value(prefs.pinned),
      pinnedGateway: Value(prefs.pinnedGateway),
      sortOrder: Value(prefs.sortOrder),
      groupRoomId: Value(room.roomId),
      groupSyncRevision: Value(room.revision),
      groupSyncName: Value(room.name),
    ),
  );
}

/// Localiza la fila local que un tombstone del espejo debe retirar.
///
/// Clave `id:<roomId>` → `<conn>/group/<roomId>`. Clave `name:<name>` (salas
/// legacy sin roomId) → la fila cuyo nombre sincronizado (o cuyo `gatewayId`
/// legacy) era ese nombre.
String? _localIdForDeleted({
  required String connectionId,
  required String key,
  required Map<String, ({String? roomId, int revision, String? syncName})>
      prior,
}) {
  if (key.startsWith('id:')) {
    return groupConversationId(connectionId, key.substring(3));
  }
  final name = key.startsWith('name:') ? key.substring(5) : key;
  for (final e in prior.entries) {
    if (e.value.syncName == name) return e.key;
  }
  for (final e in prior.entries) {
    if (e.key == '$connectionId/group/$name') return e.key;
  }
  return null;
}

String _subtitle(List<String> memberProfiles, String gatewayLabel) {
  if (memberProfiles.isEmpty) return gatewayLabel;
  return memberProfiles.length == 1
      ? '1 miembro · $gatewayLabel'
      : '${memberProfiles.length} miembros · $gatewayLabel';
}
