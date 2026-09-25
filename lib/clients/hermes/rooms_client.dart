import 'dart:async';

import 'gateway_client.dart';

/// Modelos de hosted rooms (grupos) — contratos de tui_gateway/contracts/groups_bot_relay.py
/// y gateway/hosted_rooms.py (commit 3be17b1d, protocol_version 2).
class RoomMember {
  final String? memberId;
  final String? profile;
  final String? handle;
  final String? displayName;
  final String? target;

  const RoomMember({
    this.memberId,
    this.profile,
    this.handle,
    this.displayName,
    this.target,
  });

  factory RoomMember.fromJson(Map<String, Object?> j) => RoomMember(
    memberId: j['member_id'] as String?,
    profile: j['profile'] as String?,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String?,
    target: j['target'] as String?,
  );

  /// Nombre visible; fallback al handle; nunca clave de identidad.
  String get label => displayName ?? handle ?? profile ?? memberId ?? '?';
}

class Room {
  final String roomId;
  final String name;
  final List<RoomMember> members;
  final String authorityGatewayId;
  final int authorityEpoch;
  final int revision;

  const Room({
    required this.roomId,
    required this.name,
    required this.members,
    required this.authorityGatewayId,
    required this.authorityEpoch,
    required this.revision,
  });

  factory Room.fromJson(Map<String, Object?> j) => Room(
    roomId: j['room_id'] as String,
    name: j['name'] as String? ?? '',
    members: ((j['members'] as List?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(RoomMember.fromJson)
        .toList(),
    authorityGatewayId: j['authority_gateway_id'] as String? ?? '',
    authorityEpoch: j['authority_epoch'] as int? ?? 0,
    revision: j['revision'] as int? ?? 0,
  );
}

/// Evento del log de un room (taxonomía cerrada del backend).
class RoomEvent {
  final String roomId;
  final int seq;
  final String eventId;
  final String
  kind; // message.user | message.member | turn.* | authority.* | room.*
  final Map<String, Object?> actor;
  final Map<String, Object?> payload;
  final String? createdAt;
  final bool idempotent;

  const RoomEvent({
    required this.roomId,
    required this.seq,
    required this.eventId,
    required this.kind,
    required this.actor,
    required this.payload,
    this.createdAt,
    this.idempotent = false,
  });

  String get actorKind => actor['kind'] as String? ?? '';

  String get authorLabel => switch (actorKind) {
    'user' => 'Tú',
    'member' =>
      actor['display_name'] as String? ??
          actor['handle'] as String? ??
          actor['profile'] as String? ??
          'miembro',
    _ => actorKind,
  };
}

class RoomLogPage {
  final List<RoomEvent> events;
  final int latestSeq;
  final bool hasMore;
  final String? cursor;

  const RoomLogPage({
    required this.events,
    required this.latestSeq,
    required this.hasMore,
    this.cursor,
  });
}

/// Cliente de groups.* para una conexión.
///
/// REGLAS DE COMPATIBILIDAD CON DESKTOP:
/// - Los grupos viven en el gateway (shared-state.db). Esta app NO replica
///   estructuras: consume `groups.log` delta y `groups.state`.
/// - Los mensajes de usuario se envían con `groups.send` (actor user server-owned);
///   la app nunca simula turnos de miembros.
/// - Las aprobaciones de room van por `groups.approve` con task/execution_generation
///   del contexto — nunca por approval.respond de otra sesión.
/// - Eliminar/disband usa `groups.disband` (tumba server-side; no resucita).
class RoomsClient {
  final HermesGatewayClient gateway;

  RoomsClient(this.gateway);

  /// Capacidades del driver del gateway.
  Future<Map<String, Object?>?> capabilities() async {
    final r = await gateway.rawCall('groups.capabilities');
    return r is Map<String, Object?> ? r : null;
  }

  /// Lista de rooms visibles. El gateway no expone groups.list en el contrato:
  /// las rooms se descubren vía groups.state de cada room conocida y eventos
  /// room.created; el Desktop las recibe del snapshot del bot plugin.
  /// Aquí: state de rooms cacheadas localmente + eventos en vivo.
  Future<Room?> roomState(String roomId) async {
    final r = await gateway.rawCall(
      'groups.state',
      params: {'room_id': roomId},
    );
    if (r is! Map<String, Object?>) return null;
    final room = r['room'];
    if (room is Map<String, Object?>) return Room.fromJson(room);
    return null;
  }

  /// Página delta del log desde since_seq (idempotente por event_id).
  Future<RoomLogPage> log(
    String roomId, {
    int? sinceSeq,
    int limit = 200,
  }) async {
    final r = await gateway.rawCall(
      'groups.log',
      params: {'room_id': roomId, 'since_seq': sinceSeq, 'limit': limit},
    );
    if (r is! Map<String, Object?>) {
      return const RoomLogPage(events: [], latestSeq: 0, hasMore: false);
    }
    final events = ((r['events'] as List?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(_eventFrom)
        .toList();
    return RoomLogPage(
      events: events,
      latestSeq: r['latest_seq'] as int? ?? 0,
      hasMore: r['has_more'] as bool? ?? false,
      cursor: r['cursor'] as String?,
    );
  }

  RoomEvent _eventFrom(Map<String, Object?> j) => RoomEvent(
    roomId: j['room_id'] as String? ?? '',
    seq: j['seq'] as int? ?? 0,
    eventId: j['event_id'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    actor: (j['actor'] as Map?)?.cast<String, Object?>() ?? const {},
    payload: (j['payload'] as Map?)?.cast<String, Object?>() ?? const {},
    createdAt: j['created_at'] as String?,
    idempotent: j['idempotent'] as bool? ?? false,
  );

  /// Enviar mensaje de usuario al room (idempotente con client_event_id).
  Future<Map<String, Object?>?> send(
    String roomId,
    String text, {
    String? clientEventId,
  }) async {
    final r = await gateway.rawCall(
      'groups.send',
      params: {
        'room_id': roomId,
        'text': text,
        'client_event_id': clientEventId,
      },
    );
    return r is Map<String, Object?> ? r : null;
  }

  /// Crear grupo. Idempotente en el backend.
  Future<Room?> create(String name, List<Map<String, Object?>> members) async {
    final r = await gateway.rawCall(
      'groups.create',
      params: {'name': name, 'members': members},
    );
    final room = r is Map<String, Object?> ? r['room'] : null;
    return room is Map<String, Object?> ? Room.fromJson(room) : null;
  }

  Future<void> rename(String roomId, String name) => gateway
      .rawCall('groups.rename', params: {'room_id': roomId, 'name': name})
      .then((_) {});

  /// Disband: tumba permanente en el gateway (no resucita al reconectar).
  Future<void> disband(String roomId) => gateway
      .rawCall('groups.disband', params: {'room_id': roomId})
      .then((_) {});

  /// Aprobación en contexto room (camino remoto incluido: el backend la
  /// enruta vía Runs API del peer con HermesRoom grant).
  Future<void> approve({
    required String roomId,
    required String memberId,
    required String taskId,
    required String executionGeneration,
    required String choice, // once | session | always | deny
    required String requestId,
  }) async {
    await gateway.rawCall(
      'groups.approve',
      params: {
        'room_id': roomId,
        'member_id': memberId,
        'task_id': taskId,
        'execution_generation': executionGeneration,
        'choice': choice,
        'request_id': requestId,
      },
    );
  }

  /// Sincronización continua: aplica páginas delta hasta quedar al día.
  /// Devuelve todos los eventos nuevos (dedup por event_id lo hace el llamador).
  Future<List<RoomEvent>> syncAll(String roomId, {int? lastSeq}) async {
    final out = <RoomEvent>[];
    var since = lastSeq;
    for (var page = 0; page < 20; page++) {
      final p = await log(roomId, sinceSeq: since);
      out.addAll(p.events);
      if (!p.hasMore || p.events.isEmpty) break;
      since = p.events.last.seq;
    }
    return out;
  }
}
