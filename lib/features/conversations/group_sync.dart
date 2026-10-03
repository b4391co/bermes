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

  /// Orden del usuario (menor = primero). Decide la conexión dueña de cada
  /// sala del espejo y desempata títulos.
  final int displayOrder;

  /// Fecha de creación de la conexión: desempate estable cuando dos
  /// conexiones comparten `displayOrder`.
  final DateTime createdAt;

  /// `installId` del gateway (`GET /api/status`/authMe; `connections.installId`).
  /// El espejo real de Desktop identifica cada miembro con el `installId`
  /// del backend que lo aporta (`types.ts:130-147`): es la clave EXACTA para
  /// resolver a qué conexión pertenece un miembro aunque dos gateways tengan
  /// bots homónimos (dos `default`, el escenario del usuario).
  final String? installId;

  const ConnectionGroupState({
    required this.id,
    required this.label,
    required this.profiles,
    required this.titles,
    required this.createdAt,
    this.displayOrder = 0,
    this.installId,
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
({Map<String, GroupRoom> rooms, Map<String, int> deleted}) mergeGroupMirrors(
  List<ConnectionGroupState> connections,
) {
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

/// Aplica el espejo global de grupos: UNA fila local por sala, en la
/// conexión dueña — el primer gateway con miembros según el orden del
/// usuario. Las copias del mismo roomId proyectadas por otros gateways se
/// limpian; un grupo multi-gateway no repite fila.
///
/// - Identidad: `groupConversationId(connectionId, room.identity)`, con
///   `identity` = `roomId` inmutable cuando existe. Un rename remoto NO
///   duplica la sala (el bug anterior usaba el nombre visible como PK).
/// - Título: el que proyecta Desktop; si viene vacío, se compone de los
///   títulos canónicos de los miembros.
Future<void> syncGroupMirrors({
  required AppDatabase db,
  required List<ConnectionGroupState> connections,
}) async {
  if (connections.isEmpty) return;
  // El orden del USUARIO decide la dueña de cada sala (y el primer título
  // visto por perfil); empate → la conexión más antigua. Ordenar aquí para
  // no depender del orden de inserción del mapa interno del manager.
  final conns = [...connections]
    ..sort((a, b) {
      final byOrder = a.displayOrder.compareTo(b.displayOrder);
      if (byOrder != 0) return byOrder;
      return a.createdAt.compareTo(b.createdAt);
    });

  // Perfiles por conexión: el espejo de una puede nombrar miembros de otra.
  // (0.1.27: la resolución de miembros va conexión por conexión; el antiguo
  // conjunto global `allProfiles` hacía que un homónimo en otro gateway
  // secuestrara la resolución.)
  final profilesByConn = {
    for (final c in conns) c.id: {for (final p in c.profiles) p.name},
  };
  // Primer título visto por perfil: estable entre llamadas (orden de
  // conexiones), así que un perfil gema-no idéntico en dos gateways no hace
  // oscilar el subtítulo de un grupo entre ciclos.
  final titleByProfile = <String, String>{};
  for (final c in conns) {
    c.titles.forEach((k, v) => titleByProfile.putIfAbsent(k, () => v));
  }

  final merged = mergeGroupMirrors(conns);
  final snapshot = GroupSyncSnapshot(
    rooms: merged.rooms,
    deleted: merged.deleted,
  );
  final live = snapshot.liveRooms();

  // 1) Colocar cada sala por conexión: `<connectionId>|<identidad>` → miembros.
  final placements =
      <String, ({GroupRoom room, String connId, List<String> members})>{};
  // Resolución de miembros (0.1.27): un miembro del espejo pertenece a UNA
  // conexión. Orden:
  //  1. `member.installId` == `c.installId` (contrato real de Desktop,
  //     `types.ts:130-147`) — exacto aunque dos gateways tengan bots
  //     homónimos (dos `default`, el escenario del usuario).
  //  2. Nombre: primera conexión (orden del usuario) cuyo roster lo tenga —
  //     fallback para espejos sin installId (backends antiguos, fakes).
  // Cada perfil cuenta UNA vez por sala: antes el nombre resolvía en TODAS
  // las conexiones (contando miembros de más) o sólo en la dueña (ocultando
  // a los miembros del otro gateway).
  final installIdByConn = {
    for (final c in conns)
      if (c.installId != null) c.installId!: c.id,
  };
  for (final room in live) {
    final here = <String, List<String>>{};
    for (final m in room.members) {
      String? connId;
      if (m.installId != null) connId = installIdByConn[m.installId!];
      String? p;
      if (connId != null) {
        p = memberProfileHere(m, profilesByConn[connId] ?? const {});
      } else {
        for (final c in conns) {
          final q = memberProfileHere(m, profilesByConn[c.id] ?? const {});
          if (q != null) {
            p = q;
            connId = c.id;
            break;
          }
        }
      }
      if (p == null || connId == null) continue;
      final members = here.putIfAbsent(connId, () => []);
      if (!members.contains(p)) members.add(p);
    }
    // La lista de salas de Desktop es la misma en todos sus backends
    // (`group-chat.ts:88-91`): el mismo roomId llega proyectado por cada
    // gateway. Si ninguno tiene miembros, la sala no se materializa aquí.
    if (here.isEmpty) {
      for (final c in conns) {
        if (c.profiles.any((p) => p.groups.rooms.containsKey(room.key))) {
          here[c.id] = const [];
          break;
        }
      }
    }
    // UNA fila por sala. La dueña es la conexión que HOSTEA la sala: la
    // primera (orden del usuario) cuyo espejo del `default` lleva la clave.
    // El chat habla `groups.*` por el WS de la dueña; si la dueña se elige
    // sólo por tener miembros, una sala mixta acaba en un gateway que NO la
    // hospeda y su `groups.log` sale vacío (bug 0.1.24: «el grupo mezclado no
    // aparece»). Los demás gateways proyectan la MISMA sala (mismo roomId) y
    // no se repiten. Si ningún espejo la lleva (backend antiguo con sólo
    // membresías `ui_meta.hermes-bots.groups`), cae a la primera con miembros.
    final hostIdx = conns.indexWhere(
      (c) => c.profiles.any((p) => p.groups.rooms.containsKey(room.key)),
    );
    final owner = hostIdx >= 0 ? conns[hostIdx] : conns.firstWhere(
      (c) => here.containsKey(c.id),
      orElse: () => conns.first,
    );
    if (here.containsKey(owner.id) || hostIdx >= 0) {
      // Miembros PARA LA FILA: los de TODAS las conexiones que los
      // resolvieron, en orden del usuario (0.1.27). Antes sólo iban los de
      // la dueña: un grupo con bots de dos gateways se veía como
      // «1 miembro · <dueña>» aunque el otro gateway aportara miembros —
      // el usuario lo leía como «el grupo mixto no aparece».
      final allMembers = <String>[
        for (final c in conns) ...?here[c.id],
      ];
      placements['${owner.id}|${room.identity}'] = (
        room: room,
        connId: owner.id,
        // Si nadie resolvió miembros (roster aún no sincronizado), la sala
        // se coloca igualmente con lista vacía: su log es el real.
        members: allMembers,
      );
    }
  }

  // 2) Escribir cada sala en cada conexión donde tiene miembros.
  for (final place in placements.values) {
    final conn = conns.firstWhere((c) => c.id == place.connId);
    await _writeRoom(
      db: db,
      conn: conn,
      room: place.room,
      memberProfiles: place.members,
      titleByProfile: titleByProfile,
    );
  }
  // 2b) Filas huérfanas: salas vivas cuya fila local quedó en una conexión
  //     que ya no es la dueña (o cuya conexión está caída y no participa en
  //     este ciclo). Se limpian sobre TODAS las filas de grupos con roomId,
  //     no solo las conexiones sincronizadas: si la dueña pasó a otra
  //     conexión, la anterior no debe seguir visible ni siquiera caída.
  final placedIds = placements.keys.toSet();
  final liveIdentities = {for (final r in live) r.identity};
  final orphans =
      await (db.select(db.conversations)
            ..where((c) => c.kind.equals('group'))
            ..where((c) => c.groupRoomId.isNotNull()))
          .get();
  for (final row in orphans) {
    if (placedIds.contains('${row.connectionId}|${row.groupRoomId}')) continue;
    if (!liveIdentities.contains(row.groupRoomId)) continue;
    await (db.delete(db.conversations)..where((c) => c.id.equals(row.id))).go();
  }
  // 3) Caídas por conexión: solo tombstones y solo si la fila local no va más
  //    alta (un gateway rezagado no puede matar una sala viva en otro).
  final revisionByIdentity = {for (final r in live) r.identity: r.revision};
  for (final conn in conns) {
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
      await (db.delete(db.conversations)..where((c) => c.id.equals(id))).go();
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
    for (final c in conns)
      for (final p in c.profiles) ...p.membershipNames,
  };
  final liveNames = {for (final r in live) r.name};
  final coveredByMirror = live.isNotEmpty;
  for (final conn in conns) {
    final stale =
        await (db.select(db.conversations)
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
      await (db.delete(
        db.conversations,
      )..where((c) => c.id.equals(row.id))).go();
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
      : (canonicalGroupName(room, {
              for (final p in memberProfiles) p: titleByProfile[p] ?? p,
            }) ??
            room.identity);
  final prefs = await db.localConvPrefs(id);
  await db
      .into(db.conversations)
      .insertOnConflictUpdate(
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
