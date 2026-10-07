import 'dart:async';
import 'dart:math';

import 'gateway_client.dart';

/// Modelos de hosted rooms (grupos) — contratos de tui_gateway/contracts/groups_bot_relay.py
/// y gateway/hosted_rooms.py (protocol_version 2).
///
/// Verificado contra las fuentes reales del backend (`groups.send` toma
/// `{room_id, event_id?, payload}` — NO `text`/`client_event_id`—; `created_at`
/// es float de segundos; `cursor` de `groups.log` es int; `groups.create` exige
/// `room_id` del cliente; `groups.rename` exige `event_id`), commit
/// `e408d363393ccb72267e67bcccf4f8954b438cd9`.
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

  /// `created_at` del backend: epoch en SEGUNDOS (REAL en
  /// `gateway/hosted_rooms.py::_event_from_row`).
  final double? createdAtSeconds;
  final bool idempotent;

  /// Frame original del log (la UI de chat lo reutiliza para pintar sin
  /// duplicar parsers).
  final Map<String, Object?> raw;

  const RoomEvent({
    required this.roomId,
    required this.seq,
    required this.eventId,
    required this.kind,
    required this.actor,
    required this.payload,
    this.createdAtSeconds,
    this.idempotent = false,
    this.raw = const {},
  });

  /// ms de época para la UI; null si el backend no trajo marca.
  int? get tsMs =>
      createdAtSeconds == null ? null : (createdAtSeconds! * 1000).round();

  /// Texto del evento según su `kind` (`hosted_room_discussion.py:60-63`:
  /// `message.user`/`message.member` llevan `text`; el resto no). Siempre
  /// string: nunca lanza.
  String get text => payload['text'] as String? ?? '';

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

  /// `cursor` de `groups.log`: seq del último evento devuelto (o `since_seq`
  /// pedido si la página viene vacía). Nunca un string.
  final int cursor;
  final int latestSeq;
  final bool hasMore;
  final String? authorityGatewayId;
  final int? authorityEpoch;

  const RoomLogPage({
    required this.events,
    required this.cursor,
    required this.latestSeq,
    required this.hasMore,
    this.authorityGatewayId,
    this.authorityEpoch,
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

  /// Estado de una sala (replay cursor + autoridad + `driver_status`).
  ///
  /// `GroupsStateParams` = `{room_id, include_disbanded?}`; el resultado envuelve
  /// la sala bajo `room` (`GroupsStateResult`), igual que `groups.create`.
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

  /// Página delta del log desde [sinceSeq] (exclusive; `since_seq` real).
  Future<RoomLogPage> log(
    String roomId, {
    int? sinceSeq,
    int? limit,
    bool includeDisbanded = false,
  }) async {
    final r = await gateway.rawCall(
      'groups.log',
      params: {
        'room_id': roomId,
        // `since_seq`/`limit` son `int | None` y el handler pasa el valor por
        // defecto (`methods_groups.py` `_passthrough` para `groups.log`:
        // `p.get("since_seq", 0)`, `p.get("limit", 100)`); un `null` explícito
        // rompería la validación, así que simplemente no se envían.
        'since_seq': ?sinceSeq,
        'limit': ?limit,
        if (includeDisbanded) 'include_disbanded': true,
      },
    );
    if (r is! Map<String, Object?>) {
      return const RoomLogPage(
        events: [],
        cursor: 0,
        latestSeq: 0,
        hasMore: false,
      );
    }
    final events = ((r['events'] as List?) ?? const [])
        .whereType<Map<String, Object?>>()
        .map(_eventFrom)
        .toList();
    final auth = (r['authority'] as Map?)?.cast<String, Object?>();
    return RoomLogPage(
      events: events,
      cursor: _int(r['cursor']) ?? (sinceSeq ?? 0),
      latestSeq: _int(r['latest_seq']) ?? 0,
      hasMore: r['has_more'] as bool? ?? false,
      authorityGatewayId: auth?['gateway_id'] as String?,
      authorityEpoch: _int(auth?['epoch']),
    );
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  /// Hex de [Random.secure], `bytes` octetos.
  static String _hex(int bytes) {
    final rnd = Random.secure();
    return List.generate(
      bytes,
      (_) => rnd.nextInt(256),
    ).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  RoomEvent _eventFrom(Map<String, Object?> j) => RoomEvent(
    roomId: j['room_id'] as String? ?? '',
    seq: _int(j['seq']) ?? 0,
    eventId: j['event_id'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    actor: (j['actor'] as Map?)?.cast<String, Object?>() ?? const {},
    payload: (j['payload'] as Map?)?.cast<String, Object?>() ?? const {},
    // `created_at` es FLOAT (epoch segundos) en `_event_from_row`; NUNCA un
    // string (el `as String?` del archivo original lo perdía/reventaba).
    createdAtSeconds: (j['created_at'] as num?)?.toDouble(),
    idempotent: j['idempotent'] as bool? ?? false,
    raw: j,
  );

  /// Enviar mensaje de usuario al room.
  ///
  /// Contrato REAL (`tui_gateway/contracts/groups_bot_relay.py:231-244` +
  /// `tui_gateway/methods_groups.py:381-393`, params `extra="forbid"`):
  /// `{room_id, event_id?, payload}` → `{event, client_event_id, accepted,
  /// driver_started}`. NO existen `text` ni `client_event_id` como params:
  /// - `event_id` es la clave de reintentos; el backend la valida como
  ///   identificador (`^[A-Za-z0-9][A-Za-z0-9._:-]*$`, ≤128 chars,
  ///   `gateway/hosted_rooms.py:208,244`) y la mapea a `user:<sha256(event_id)>`,
  ///   que es el `event_id` del log. Reenviar la MISMA clave con el MISMO
  ///   payload es idempotente; misma clave con contenido distinto → code 4111
  ///   (`EventConflictError`). El `client_event_id` del resultado es un eco.
  /// - `payload` pasa `validate_user_payload`
  ///   (`gateway/hosted_room_discussion.py:60,198-203`): `_exact_fields` exige
  ///   EXACTAMENTE `{text, thread_id}` (ambos string; texto no vacío ≤64 KB
  ///   UTF-8). Un campo de más FALLA la validación.
  /// - `threadId` es el hilo de discusión de la sala: los mensajes del mismo
  ///   hilo comparten `thread_id` y el driver contesta por hilo
  ///   (`hosted_room_discussion.py:572-602`). Los clientes mintan hilos nuevos
  ///   (Desktop `mintGroupThreadId`); este default `'t<p36>-<rand>'` es una
  ///   CONVENCIÓN LOCAL documentada, no un valor del protocolo.
  /// El actor es server-owned (`{"kind":"user","id":"desktop"}`); la app nunca
  /// lo manda.
  Future<Map<String, Object?>?> send(
    String roomId,
    String text, {
    required String clientEventId,
    String? threadId,
  }) async {
    final r = await gateway.rawCall(
      'groups.send',
      params: {
        'room_id': roomId,
        'event_id': clientEventId,
        'payload': {'text': text, 'thread_id': threadId ?? newThreadId()},
      },
    );
    return r is Map<String, Object?> ? r : null;
  }

  /// Envío con clave de idempotencia autogenerada.
  ///
  /// Devuelve el par (resultado, clave + hilo usados): si el llamador necesita
  /// reintentar ESTE envío (timeout, desconexión) DEBE reenviar por [send] la
  /// MISMA `clientEventId` y el MISMO `threadId` del recibo; un retry con
  /// clave nueva (o hilo nuevo) duplica el mensaje.
  Future<
    ({Map<String, Object?>? result, String clientEventId, String threadId})
  >
  sendText(
    String roomId,
    String text, {
    String? clientEventId,
    String? threadId,
  }) async {
    final id = clientEventId ?? newClientEventId();
    final thread = threadId ?? newThreadId();
    final result = await send(
      roomId,
      text,
      clientEventId: id,
      threadId: thread,
    );
    return (result: result, clientEventId: id, threadId: thread);
  }

  /// Clave de reintentos válida para el validador del backend (`IDENTIFIER_RE`):
  /// `u` + 32 hex ([Random.secure]), ≤128 chars, sin separadores prohibidos.
  static String newClientEventId() => 'u${_hex(16)}';

  /// Hilo de discusión (convención local; ver [send]).
  static String newThreadId() =>
      't${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_hex(3)}';

  /// Crear grupo.
  ///
  /// `GroupsCreateParams` (`groups_bot_relay.py:180-186`): `room_id` es
  /// REQUERIDO y lo elige el CLIENTE (idempotencia por contenido: mismo
  /// `room_id` + mismo nombre/miembros → la MISMA sala, `idempotent: true`;
  /// mismo id con otro contenido → `RoomConflictError`). Por eso [roomId] es
  /// opcional y se genera con [newRoomId] cuando falta: reenviar el id
  /// guardado es el reintento seguro.
  /// `authority_gateway_id` se acepta pero se ignora (la autoridad es siempre
  /// la identidad de instalación del gateway).
  Future<Room?> create(
    String name,
    List<Map<String, Object?>> members, {
    String? roomId,
  }) async {
    final r = await gateway.rawCall(
      'groups.create',
      params: {
        'room_id': roomId ?? newRoomId(),
        'name': name,
        // `_exact_fields` del backend: SOLO profile/handle/display_name/
        // target. Los descriptores del espejo (name/installId/connectionId/
        // connectionLabel) se Filtran aquí — en 0.1.49 se mandaban crudos y
        // `groups.create` fallaba siempre (4112 → «no deja enviar»).
        'members': [
          for (final m in members)
            {
              'profile': m['profile'] ?? m['name'],
              'handle': m['handle'] ?? m['name'],
              if (m['display_name'] != null) 'display_name': m['display_name'],
              if (m['target'] != null) 'target': m['target'],
            },
        ],
      },
    );
    final room = r is Map<String, Object?> ? r['room'] : null;
    return room is Map<String, Object?> ? Room.fromJson(room) : null;
  }

  /// `room_id` generado (convención local: los ids los elige quien crea;
  /// válido para `IDENTIFIER_RE`, ≤128 chars).
  static String newRoomId() => 'room-${_hex(16)}';

  /// Renombrar. `GroupsRenameParams` (`groups_bot_relay.py:247-250`):
  /// `event_id` es REQUERIDO (el rename es un evento `room.renamed` en el log
  /// y la clave es idempotente por contenido). Reenviar la MISMA
  /// [clientEventId] para reintentar.
  Future<void> rename(
    String roomId,
    String name, {
    required String clientEventId,
  }) => gateway
      .rawCall(
        'groups.rename',
        params: {'room_id': roomId, 'event_id': clientEventId, 'name': name},
      )
      .then((_) {});

  /// Aprobación en contexto room (camino remoto incluido: el backend la
  /// enruta vía Runs API del peer con HermesRoom grant).
  ///
  /// `GroupsApproveParams` (`groups_bot_relay.py:1477-1485`):
  /// `execution_generation` es INT (el handler hace `int(params.get(...) or 0)`
  /// — un string daría error), `choice` ∈ once|session|always|deny.
  Future<void> approve({
    required String roomId,
    required String memberId,
    required String taskId,
    required int executionGeneration,
    required String choice,
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
  /// Avanza por el `cursor` (int) de cada página — el valor real del
  /// resultado de `groups.log`, no el seq observado —; dedup por `event_id`
  /// lo hace el llamador.
  Future<List<RoomEvent>> syncAll(String roomId, {int? lastSeq}) async {
    final out = <RoomEvent>[];
    var since = lastSeq ?? 0;
    for (var page = 0; page < 20; page++) {
      final p = await log(roomId, sinceSeq: since);
      out.addAll(p.events);
      if (!p.hasMore || p.cursor <= since) break;
      since = p.cursor;
    }
    return out;
  }
}

/// Validador local del shape que MANDA [RoomsClient.create] — espejo exacto
/// de `hosted_room_discussion.validate_roster` + `_validate_target` del
/// backend real: dos miembros, `profile` NO duplicado, `target` con
/// `connection_id` O `gateway_id`, y al menos un miembro LOCAL (perfil
/// conocido por el gateway). 4000 = params inválidos (`ValidationError`),
/// 4115 = sin miembro local (`RoomLocalMemberRequired`).
({String? code, String? message})? validateRosterWire(
  List<Map<String, Object?>> members,
  Set<String> localProfiles,
) {
  if (members.length < 2) {
    return (code: '4000', message: 'at least two members are required');
  }
  final ids = <String>{};
  final profiles = <String>{};
  var hasLocal = false;
  for (final m in members) {
    // `_exact_fields` del backend (extra="forbid"): cualquier clave NO
    // admitida hace fallar `groups.create` ENTERO — en 0.1.49 se mandaba
    // `name` (y campos de espejo) y la sala nunca quedaba hosted →
    // `groups.send` 4112 → «no deja enviar». `RoomMemberInput` real:
    // profile/handle/display_name/target (`groups_bot_relay.py:76-84`).
    const allowed = {'profile', 'handle', 'display_name', 'target'};
    final unknown = m.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      return (
        code: '4000',
        message: 'unknown member field(s): ${unknown.join(', ')}',
      );
    }
    if (m.containsKey('member_id')) {
      return (code: '4000', message: 'member_id is server-owned');
    }
    for (final k in const ['profile', 'handle', 'display_name']) {
      final v = m[k];
      if (v != null && (v is! String || v.trim().isEmpty)) {
        return (code: '4000', message: '$k must be a non-empty string');
      }
    }
    final profile = m['profile'] as String?;
    final isLocal = profile != null && localProfiles.contains(profile);
    final target = m['target'];
    if (target == null) {
      if (!isLocal) {
        return (code: '4000', message: 'local members omit target');
      }
      ids.add('local:$profile');
      hasLocal = true;
    } else if (target is! Map) {
      return (code: '4000', message: 'target must be an object');
    } else {
      for (final k in const ['connection_id', 'gateway_id']) {
        final v = target[k];
        if (v != null && (v is! String || v.trim().isEmpty)) {
          return (code: '4000', message: 'target.$k must be non-empty');
        }
      }
      final cid = target['connection_id'] as String?;
      final gid = target['gateway_id'] as String?;
      if (cid == null && gid == null) {
        return (
          code: '4000',
          message: 'target must set connection_id or gateway_id',
        );
      }
      ids.add('remote:${profile ?? ''}:${cid ?? ''}:${gid ?? ''}');
    }
    if (profile != null) {
      if (!profiles.add(profile)) {
        return (code: '4000', message: 'duplicate profile $profile');
      }
      if (isLocal) hasLocal = true;
    }
  }
  if (ids.length != members.length) {
    return (code: '4000', message: 'duplicate member identity');
  }
  if (!hasLocal) {
    return (code: '4115', message: 'no member profile is local');
  }
  return null;
}
