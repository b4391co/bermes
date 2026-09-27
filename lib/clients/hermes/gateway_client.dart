import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/logger.dart';
import 'bot_meta.dart';
import '../../domain/connection/connection_profile.dart';
import 'http_client.dart';
import 'rpc_types.dart';

/// Estado de la conexión WS (para UI diferenciada).
enum GatewayLinkState {
  disconnected,
  connecting,
  ready,
  reconnecting,
  authExpired,
  error,
}

/// Cliente JSON-RPC NDJSON sobre WS del gateway Hermes.
///
/// Contrato (docs/protocol/hermes-map.md §2):
/// - Primer frame: gateway.ready con replay_epoch.
/// - Ping: gateway.ping cada 15 s.
/// - Eventos: {method:"event", params:{type, session_id?, payload?, seq?}}.
/// - Replay: session.events.since {session_id, last_seen}.
/// - Auth: ticket single-use 30 s de POST /api/auth/ws-ticket en query ?ticket=.
///
/// Reconnecting con espera progresiva (0.5s → 30s máx, factor 1.6).
class HermesGatewayClient {
  final ConnectionProfile profile;
  final HermesHttpClient http;
  final _log = Logger('GatewayClient');

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  GatewayLinkState _state = GatewayLinkState.disconnected;
  GatewayReady? _ready;
  int _reconnectAttempts = 0;
  int _nextRequestId = 1;
  bool _manuallyClosed = false;

  final _stateController = StreamController<GatewayLinkState>.broadcast();
  final _eventsController = StreamController<GatewayEvent>.broadcast();
  final _serverRequestsController = StreamController<ServerRequest>.broadcast();
  final _pending = <Object, Completer<Object?>>{};
  final _watermarks = <String, int>{}; // session_id → last_seen seq

  HermesGatewayClient(this.profile, this.http);

  GatewayLinkState get state => _state;
  GatewayReady? get readyInfo => _ready;
  Stream<GatewayLinkState> get stateStream => _stateController.stream;
  Stream<GatewayEvent> get events => _eventsController.stream;
  Stream<ServerRequest> get serverRequests => _serverRequestsController.stream;

  Future<void> connect() async {
    if (_state == GatewayLinkState.connecting ||
        _state == GatewayLinkState.ready) {
      return;
    }
    _manuallyClosed = false;
    _setState(GatewayLinkState.connecting);
    await _openSocket();
  }

  Future<void> _openSocket() async {
    try {
      final ticket = await http.mintWsTicket();
      if (ticket == null) {
        _setState(GatewayLinkState.authExpired);
        return;
      }
      final uri = Uri.parse(
        '${profile.wsUrl}?ticket=${Uri.encodeQueryComponent(ticket)}',
      );
      final ws = WebSocketChannel.connect(uri);
      _ws = ws;

      // Un solo listener: el primer frame ES el ready; el resto pasa a _onFrame.
      final completer = Completer<dynamic>();
      late final StreamSubscription<dynamic> sub;
      sub = ws.stream.listen(
        (frame) {
          if (!completer.isCompleted) {
            completer.complete(frame);
          } else {
            _onFrame(frame);
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
          _scheduleReconnect();
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(const SocketException('ws closed'));
          }
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
      _wsSub = sub;

      final first = await completer.future.timeout(const Duration(seconds: 15));
      final firstFrame = jsonDecode(first as String) as Map<String, Object?>;
      final readyParams = firstFrame['params'] as Map<String, Object?>?;
      final payload = readyParams?['payload'] as Map<String, Object?>? ?? {};
      _ready = GatewayReady.fromPayload(payload);
      _reconnectAttempts = 0;
      _setState(GatewayLinkState.ready);

      await _sendRaw(
        RpcRequest(
          _nextRequestId++,
          'client.capabilities',
          params: {'server_requests': true},
        ),
      );

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _request('gateway.ping').ignore();
      });
    } catch (e, st) {
      _log.warning('connect failed', e, st);
      _setState(GatewayLinkState.error);
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    Map<String, Object?>? frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, Object?>;
    } on FormatException {
      return; // frame no-JSON ignorado
    }
    final method = frame['method'] as String?;
    final id = frame['id'];

    if (method == 'event') {
      final params = frame['params'] as Map<String, Object?>? ?? {};
      final event = GatewayEvent.fromParams(params);
      final sid = event.sessionId;
      final seq = event.seq;
      if (sid != null && seq != null) _watermarks[sid] = seq;
      _eventsController.add(event);
      return;
    }

    if (method != null && id is String && id.startsWith('srv_')) {
      // Server→client request (aprobaciones, secretos…)
      final params = frame['params'] as Map<String, Object?>? ?? {};
      _serverRequestsController.add(
        ServerRequest(
          id: id,
          method: method,
          sessionId: params['session_id'] as String? ?? '',
          params: params,
        ),
      );
      return;
    }

    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (frame.containsKey('error')) {
        final err = frame['error'] as Map<String, Object?>;
        completer.completeError(
          JsonRpcError(
            err['code'] as int? ?? -1,
            err['message'] as String? ?? 'error',
            err['data'],
          ),
        );
      } else {
        completer.complete(frame['result']);
      }
    }
  }

  /// Llamada JSON-RPC con futuro.
  Future<Object?> _request(String method, {Map<String, Object?>? params}) {
    final ws = _ws;
    if (ws == null || _state != GatewayLinkState.ready) {
      return Future.error(JsonRpcError(-32000, 'not connected'));
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendRaw(RpcRequest(id, method, params: params)).catchError((Object e) {
      _pending.remove(id);
      completer.completeError(e);
    });
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw JsonRpcError(-32001, 'timeout');
      },
    );
  }

  Future<void> _sendRaw(RpcRequest req) async {
    final ws = _ws;
    if (ws == null) throw JsonRpcError(-32000, 'socket closed');
    ws.sink.add(jsonEncode(req.toJson()));
  }

  /// Responder a un server-request (aprobación).
  Future<void> respondToServerRequest(Object requestId, Object? result) {
    final ws = _ws;
    if (ws == null) return Future.error(JsonRpcError(-32000, 'not connected'));
    return _sendRaw(
      RpcRequest(requestId, '__result__', params: {'result': result}),
    );
  }

  /// Sincronizar eventos de una sesión tras reconexión.
  Future<List<GatewayEvent>> replaySession(String sessionId) async {
    final last = _watermarks[sessionId];
    final result = await _request(
      'session.events.since',
      params: {'session_id': sessionId, 'last_seen': ?last},
    );
    final events = (result as Map<String, Object?>?)?['events'];
    if (events is! List) return const [];
    return events
        .whereType<Map<String, Object?>>()
        .map((e) => GatewayEvent.fromParams(e))
        .toList();
  }

  // ── Métodos de alto nivel (tipados por los consumidores) ──────────────

  Future<Object?> rawCall(String method, {Map<String, Object?>? params}) =>
      _request(method, params: params);

  /// Roster de bots del gateway. Hermes Desktop lista los perfiles con
  /// REST GET /api/profiles (hermes-protocol §1), que es el camino que
  /// SIEMPRE existe; profiles.list por JSON-RPC es el fallback (contrato
  /// hermes-map §4, gateway moderno). Un WS que responde vacío también
  /// cae al REST antes de devolver lista vacía.
  Future<List<Map<String, Object?>>> listProfiles() async {
    Object? decode(Object? data) => data is List
        ? {'profiles': data}
        : data is Map<String, Object?> && data['profiles'] is List
            ? data
            : null;

    Object? result;
    try {
      result = decode(await http.getJson('/api/profiles'));
    } catch (_) {
      result = null; // red/HTTP cae al WS; el login ya validó credenciales.
    }
    if (result == null) {
      try {
        result = decode(await _request('profiles.list'));
      } on JsonRpcError {
        result = null;
      }
    }
    final List raw = switch (result) {
      {'profiles': final List p} => p,
      final List l => l,
      _ => const [],
    };
    return raw.whereType<Map<String, Object?>>().toList();
  }

  /// Resuelve la sesión canónica "Bot Chat" de UN perfil (hermes-map §3).
  ///
  /// IMPORTANTE (sincronía con Desktop): la sesión canónica la CREA el
  /// gateway/Desktop al abrir el bot (identidad UNIQUE(title) por perfil —
  /// canonical-chat.ts:49). Esta app NUNCA crea sesiones: `session.resume`
  /// es la única vía. Si el Bot Chat no existe todavía, devuelve null y el
  /// chat lo dice (el usuario lo abre una vez en Desktop). Así móvil y
  /// Desktop comparten SIEMPRE la misma sesión e historial.
  Future<String?> resumeCanonicalSession(String profile) async {
    try {
      final result = await _request('session.resume', params: {
        'title': 'Bot Chat',
        'profile': profile,
      });
      if (result is! Map<String, Object?>) return null;
      final id = result['session_id'] as String?;
      if (id != null && id.isNotEmpty) return id;
    } on JsonRpcError {
      return null; // no existe todavía (bot sin Bot Chat).
    } catch (e) {
      _log.warning('canonical session resume falló', e);
    }
    return null;
  }

  /// Avatar de un perfil como data-URL (hermes-map §4: profiles.get_asset).
  Future<String?> profileAvatar(String name) async {
    final result = await _request(
      'profiles.get_asset',
      params: {'name': name, 'asset': 'avatar'},
    );
    final url = (result as Map<String, Object?>?)?['data_url'] ?? result;
    return url is String && url.startsWith('data:') ? url : null;
  }

  /// Sesiones de un perfil (hermes-map §2: session.list viaja con `profile`
  /// en los params). Es lo que Hermes Desktop muestra en su barra lateral
  /// por perfil; filas con title/preview/started_at/last_active/message_count
  /// y session_id cuando la versión del gateway lo incluye.
  Future<List<Map<String, Object?>>> listSessions(String profile) async {
    try {
      final result = await _request('session.list', params: {
        'profile': profile,
        'limit': 100,
      });
      final List raw = switch (result) {
        {'sessions': final List s} => s,
        {'rows': final List r} => r,
        final List l => l,
        _ => const [],
      };
      return raw.whereType<Map<String, Object?>>().toList();
    } on JsonRpcError {
      return const [];
    }
  }

  /// Lee la sección `ui_meta['hermes-bots']` de un perfil (grupos, título…).
  /// null si el perfil no existe o no trae meta de roster.
  Future<BotRosterMeta?> profileRosterMeta(String name) async {
    try {
      final profiles = await listProfiles();
      for (final p in profiles) {
        if (p['name'] == name) return BotRosterMeta.fromProfile(p);
      }
    } catch (e) {
      _log.info('profileRosterMeta $name no disponible: $e');
    }
    return null;
  }

  /// Edita metadatos de roster de un bot (hermes-map §4: profiles.configure;
  /// mismo contrato que Hy4ri/hermes-mobile BotsViewModel::wsClientConfigureBot):
  /// ui_meta.hermes-bots {title, description, avatar{shape,color,icon}}.
  /// CAS por ui_meta_expected_revisions omitido (igual que la referencia).
  Future<bool> configureBot(
    String name, {
    String? title,
    String? description,
    BotAvatarMeta? avatar,
    List<String> groups = const [],
  }) async {
    final metaMap = <String, Object?>{};
    if (title != null && title.isNotEmpty) metaMap['title'] = title;
    if (description != null && description.isNotEmpty) {
      metaMap['description'] = description;
    }
    if (avatar != null &&
        (avatar.shape != null ||
            avatar.color != null ||
            avatar.icon != null)) {
      metaMap['avatar'] = avatar.toJson();
    }
    if (groups.isNotEmpty) metaMap['groups'] = groups;
    try {
      await _request('profiles.configure', params: {
        'name': name,
        'ui_meta': {
          'hermes-bots': metaMap,
        },
      });
      return true;
    } on JsonRpcError {
      return false;
    }
  }


  void _scheduleReconnect() {
    if (_manuallyClosed) return;
    _setState(GatewayLinkState.reconnecting);
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _ws = null;
    // Espera progresiva: 0.5s, 0.8s, 1.28s … 30s máx.
    final delay = Duration(
      milliseconds: min(30000, (500 * pow(1.6, _reconnectAttempts++)).toInt()),
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_state == GatewayLinkState.reconnecting && !_manuallyClosed) {
        await _openSocket();
      }
    });
  }

  void _setState(GatewayLinkState s) {
    if (_state == s) return;
    _state = s;
    _stateController.add(s);
  }

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _wsSub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _setState(GatewayLinkState.disconnected);
  }

  void dispose() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _ws?.sink.close();
    _stateController.close();
    _eventsController.close();
    _serverRequestsController.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(JsonRpcError(-32002, 'client disposed'));
      }
    }
    _pending.clear();
  }

  /// Historial HTTP (hermes-map §4):
  /// GET /api/sessions/{id}/messages?limit&offset&order.
  Future<List<Map<String, Object?>>?> fetchSessionMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final result = await http.getJson(
        '/api/sessions/$sessionId/messages'
        '?limit=$limit&offset=$offset&order=latest',
      );
      if (result is! Map<String, Object?>) return null;
      final msgs = result['messages'];
      if (msgs is! List) return null;
      return msgs.whereType<Map<String, Object?>>().toList(growable: false);
    } catch (e) {
      _log.info('historial HTTP no disponible: $e');
      return null;
    }
  }
}
