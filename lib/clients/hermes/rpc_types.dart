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
  final Object id;
  final String method;
  final String sessionId;
  final Map<String, Object?> params;

  ServerRequest({
    required this.id,
    required this.method,
    required this.sessionId,
    required this.params,
  });
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
