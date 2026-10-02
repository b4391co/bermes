library;

/// Tipos del protocolo JSON-RPC del gateway Hermes (ver docs/protocol/hermes-map.md).
///
/// Frame NDJSON JSON-RPC 2.0. Eventos: {"method":"event","params":{type, session_id?, payload?}}.

class JsonRpcError implements Exception {
  final int code;
  final String message;
  final Object? data;

  JsonRpcError(this.code, this.message, [this.data]);

  @override
  String toString() => 'JsonRpcError($code): $message';
}

class RpcRequest {
  final Object id;
  final String method;
  final Map<String, Object?> params;

  RpcRequest(this.id, this.method, {Map<String, Object?>? params})
    : params = params ?? const {};

  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  };
}

class RpcResponse {
  final Object id;
  final Object? result;
  final JsonRpcError? error;

  RpcResponse({required this.id, this.result, this.error});
}

/// Evento del gateway: {type, session_id?, payload?}.
class GatewayEvent {
  final String type;
  final String? sessionId;
  final Map<String, Object?> payload;
  final int? seq;

  GatewayEvent({
    required this.type,
    this.sessionId,
    required this.payload,
    this.seq,
  });

  factory GatewayEvent.fromParams(Map<String, Object?> params) {
    final payload = params['payload'];
    return GatewayEvent(
      type: params['type'] as String? ?? '',
      sessionId: params['session_id'] as String?,
      payload: payload is Map<String, Object?> ? payload : <String, Object?>{},
      seq: params['seq'] as int?,
    );
  }
}

/// Server-request: el backend pregunta (aprobaciones, secretos…).
class ServerRequest {
  /// `srq-<hex12>` (server_requests.py:49); el contrato lo define string.
  final String id;
  final String method;
  final String sessionId;
  final Map<String, Object?> params;

  ServerRequest({
    required this.id,
    required this.method,
    required this.sessionId,
    required this.params,
  });

  /// Una fila de `open_requests`: `{id, method, params}`
  /// (server_requests.py::Request.snapshot 68-76; el consumidor la reentrega
  /// con `replayed: true`, json-rpc-channel.ts:400-409). null si la fila no
  /// trae id+method string, que es lo único accionable.
  static ServerRequest? fromSnapshot(Map<Object?, Object?> entry) {
    final id = entry['id'];
    final method = entry['method'];
    if (id is! String || method is! String) return null;
    final params = entry['params'];
    return ServerRequest(
      id: id,
      method: method,
      sessionId: params is Map ? (params['session_id'] as String? ?? '') : '',
      params: params is Map ? Map<String, Object?>.from(params) : const {},
    );
  }
}

/// Primer frame tras conectar: gateway.ready con replay_epoch.
class GatewayReady {
  final String replayEpoch;
  final bool changeEvents;
  final bool heartbeat;

  GatewayReady({
    required this.replayEpoch,
    required this.changeEvents,
    required this.heartbeat,
  });

  factory GatewayReady.fromPayload(Map<String, Object?> payload) =>
      GatewayReady(
        replayEpoch: payload['replay_epoch'] as String? ?? '',
        changeEvents: payload['change_events'] as bool? ?? false,
        heartbeat: payload['heartbeat'] as bool? ?? false,
      );
}

/// Resultado de `session.events.since` — el contrato real devuelve
/// `{events, latest_seq, truncated, count, epoch, open_requests}`
/// (tui_gateway/contracts/sessions.py::SessionEventsSinceResult, servido en
/// tui_gateway/methods_session.py:2456-2470).
///
/// `events` son los `params` de cada frame de evento —NUEVAMENTE envueltos no:
/// devolver el sobre JSON-RPC haría que cada evento replayado pasara por la
/// puerta `event.type` del cliente y se descartara en silencio
/// (tui_gateway/event_replay.py:100-110).
class SessionReplay {
  final List<GatewayEvent> events;
  final int latestSeq;

  /// true ⇒ el anillo del backend ya expulsó eventos por debajo de
  /// `last_seen`: el replay está incompleto y el llamador debe recargar el
  /// historial, no fiarse de él (event_replay.py::is_truncated 112-117).
  final bool truncated;
  final String? epoch;

  /// Server-requests sin responder en esta sesión (`{id, method, params}`,
  /// server_requests.py::Request.snapshot 68-76). El anillo de eventos no
  /// puede transportar «una pregunta sigue abierta», así que viajan aquí.
  final List<ServerRequest> openRequests;

  const SessionReplay({
    this.events = const [],
    this.latestSeq = 0,
    this.truncated = false,
    this.epoch,
    this.openRequests = const [],
  });

  /// Decodificación tolerante: un gateway que no conozca algún campo simplemente
  /// no lo manda. Un resultado que no sea un objeto (o falte) es «nada que
  /// replayar», no un error.
  factory SessionReplay.fromResult(Object? result) {
    if (result is! Map) {
      return const SessionReplay();
    }
    final map = Map<String, Object?>.from(result);
    final rawEvents = map['events'];
    final rawRequests = map['open_requests'];
    return SessionReplay(
      events: rawEvents is List
          ? rawEvents
                .whereType<Map<Object?, Object?>>()
                .map(
                  (e) => GatewayEvent.fromParams(Map<String, Object?>.from(e)),
                )
                .toList(growable: false)
          : const [],
      latestSeq: (map['latest_seq'] as num?)?.toInt() ?? 0,
      truncated: map['truncated'] == true,
      epoch: map['epoch'] is String ? map['epoch'] as String : null,
      openRequests: rawRequests is List
          ? rawRequests
                .whereType<Map<Object?, Object?>>()
                .map(ServerRequest.fromSnapshot)
                .nonNulls
                .toList(growable: false)
          : const [],
    );
  }
}
