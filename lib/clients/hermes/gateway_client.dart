import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/logger.dart';
import 'bot_meta.dart';
import 'profile_canonical.dart';
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

/// El título canónico único: `(profile, "Bot Chat")` ES la identidad del
/// forever-chat del bot (canonical-chat.ts:49 CANONICAL_CHAT_TITLE).
const canonicalChatTitle = 'Bot Chat';

/// Techo de los escaneos `session.list` por perfil
/// (canonical-chat.ts:43 PROFILE_SESSION_LIST_LIMIT).
const profileSessionListLimit = 200;

/// Cliente JSON-RPC NDJSON sobre WS del gateway Hermes.
///
/// Contrato (docs/protocol/hermes-map.md §2):
/// - Primer frame: gateway.ready con replay_epoch.
/// - Ping: gateway.ping cada 15 s.
/// - Eventos: {method:"event", params:{type, session_id?, payload?, seq?}}.
/// - Replay: session.events.since {session_id, last_seen}.
/// - Auth: ticket single-use 30 s de POST /api/auth/ws-ticket en query ?ticket=.
/// - Reconnecting con espera progresiva (0.5s → 30s máx, factor 1.6).
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

  /// Pings `gateway.ping` sin respuesta: 3 seguidos (45 s) fuerzan
  /// reconexión — socket half-open sin onError/onDone.
  int _unansweredPings = 0;
  bool _manuallyClosed = false;

  final _stateController = StreamController<GatewayLinkState>.broadcast();
  final _eventsController = StreamController<GatewayEvent>.broadcast();
  final _serverRequestsController = StreamController<ServerRequest>.broadcast();
  final _pending = <Object, Completer<Object?>>{};
  final _watermarks = <String, int>{}; // session_id → last_seen seq
  String? _epoch;
  // Sesiones con un replay en curso: los frames en vivo que llegan mientras se
  // espera la respuesta se guardan y se sueltan DESPUÉS del hueco replayado,
  // filtrados por seq, para que un frame no se despache dos veces ni adelanten
  // al replay (apps/shared/src/json-rpc-gateway.ts:438-446, 646+).
  final _replayHold = <String, List<GatewayEvent>>{};

  HermesGatewayClient(this.profile, this.http);

  GatewayLinkState get state => _state;

  /// Espera a que el enlace quede `ready`, falle, o expire [timeout].
  Future<void> readyOrTimeout(Duration timeout) async {
    if (_state == GatewayLinkState.ready) return;
    final done = Completer<void>();
    late final StreamSubscription<GatewayLinkState> sub;
    late final Timer t;
    void finish([Object? err]) {
      if (done.isCompleted) return;
      sub.cancel();
      t.cancel();
      err == null ? done.complete() : done.completeError(err);
    }

    sub = _stateController.stream.listen((s) {
      if (s == GatewayLinkState.ready) finish();
      if (s == GatewayLinkState.error || s == GatewayLinkState.authExpired) {
        finish(StateError('enlace en estado $s'));
      }
    });
    t = Timer(
      timeout,
      () => finish(TimeoutException('gateway no ready', timeout)),
    );
    return done.future;
  }

  GatewayReady? get readyInfo => _ready;
  Stream<GatewayLinkState> get stateStream => _stateController.stream;
  Stream<GatewayEvent> get events => _eventsController.stream;
  Stream<ServerRequest> get serverRequests => _serverRequestsController.stream;

  /// `replay_epoch` del proceso backend (gateway.ready). Un cambio significa
  /// que los watermarks describen una numeración que ya no existe
  /// (apps/shared/src/json-rpc-gateway.ts:613-625).
  String? get replayEpoch => _epoch;

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
      // Dos credenciales de upgrade según el modo del gateway:
      // - Gated (panel tras proveedor OAuth): ticket single-use de
      //   POST /api/auth/ws-ticket (routes.py:458-466), `?ticket=`.
      // - Loopback (sin gate): el session token vale directamente como
      //   `?token=` (web_server_chat.py:291-297). El endpoint del ticket no
      //   existe en ese modo (es ruta del gate), así que el mint fallaría
      //   siempre; se consulta hasGatewayToken para bifurcar.
      // - Sin autenticación (`authKind: none`, gateway LAN que anuncia
      //   auth_required=false): ninguna credencial — ni ticket ni token.
      final uri = Uri.parse(profile.wsUrl).replace(
        queryParameters: profile.authKind == HermesAuthKind.none
            ? const {}
            : http.hasGatewayToken
            ? {'token': http.gatewayToken!}
            : {'ticket': await _mintTicketOrExpire()},
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
          // Códigos terminales del gate (hermes_cli/web_routers/chat_ws.py:139-151):
          // 4401 = credencial inválida (ticket muerto/usado), 4403 = guard
          // (chat deshabilitado, Host-Origin rechazado o peer no-loopback).
          // Reintentar contra ellos es un bucle de denegación: se para y el UI
          // muestra la causa real. Cualquier otro cierre -> backoff normal.
          final code = ws.closeCode;
          if (code == 4401) {
            _setState(GatewayLinkState.authExpired);
            return;
          }
          if (code == 4403) {
            _log.error(
              'gate rechazó el canal de chat (close 4403): '
              'chat deshabilitado, Host-Origin o peer no local',
            );
            _setState(GatewayLinkState.error);
            return;
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
      if (readyParams?['type'] != 'gateway.ready') {
        // El contrato fija el primer frame servidor→cliente como
        // `gateway.ready` (tui_gateway/ws.py:324-331; el cliente compartido lo
        // detecta por type en apps/shared/src/json-rpc-gateway.ts:51). Un frame
        // de otro tipo NO es un ready: se reenvía al pipeline de eventos y el
        // enlace se declara error para reconectar, en vez de marcar "ready" sin
        // replay_epoch y sin haber consumido el frame.
        _onFrame(first);
        throw StateError(
          'primer frame no es gateway.ready: ${readyParams?['type'] ?? '<sin type>'}',
        );
      }
      _ready = GatewayReady.fromPayload(payload);
      _adoptReplayEpoch(_ready?.replayEpoch);
      _reconnectAttempts = 0;
      // El anuncio de capacidades se envía CON el socket ya utilizable: el
      // backend lo procesa igual, y si se marcase ready después, cualquier
      // llamada concurrente (p.ej. el roster de bots) vería 'not connected'.
      _setState(GatewayLinkState.ready);
      await _sendRaw(
        RpcRequest(
          _nextRequestId++,
          'client.capabilities',
          // Anuncio obligatorio una vez por generación de socket: sin él el
          // backend no emite server-requests (approval/clarify) y el agente
          // espera su deadline completo
          // (apps/shared/src/json-rpc-channel.ts:484-491).
          params: {'server_requests': true},
        ),
      );

      // Heartbeat con deadline (convención Desktop json-rpc-channel.ts:143-144,
      // 490-536): un socket half-open (p. ej. adb reverse o NAT que traga
      // writes sin RST) acepta los pings en silencio y el canal queda mudo sin
      // onError/onDone. Si 3 pings seguidos no responden (45 s), se fuerza la
      // reconexión: el estado vuelve a `reconnecting` y las peticiones en
      // vuelo fallan con 'not connected' en vez de colgar 30 s por RPC.
      _unansweredPings = 0;
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _unansweredPings++;
        if (_unansweredPings >= 3) {
          _log.warning(
            'sin respuesta a 3 pings (45 s): socket half-open, '
            'forzando reconexión',
          );
          _unansweredPings = 0;
          _scheduleReconnect();
          return;
        }
        _request(
          'gateway.ping',
        ).whenComplete(() => _unansweredPings = 0).ignore();
      });
    } catch (e, st) {
      _log.warning('connect failed', e, st);
      _setState(GatewayLinkState.error);
      _scheduleReconnect();
    }
  }

  /// Mint del ticket WS (gated). null → el estado ya quedó en authExpired
  /// y el caller devuelve sin abrir socket.
  Future<String> _mintTicketOrExpire() async {
    final ticket = await http.mintWsTicket();
    if (ticket == null) {
      _setState(GatewayLinkState.authExpired);
      throw StateError('sin ticket WS (sesión caducada)');
    }
    return ticket;
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
      // El orden ES el del cliente compartido (json-rpc-gateway.ts:438-448):
      // aparcar ANTES de tocar el watermark. Si el frame adelanta el cursor y
      // luego se aparca, `_flushReplayHold` lo descarta por `seq <= watermark`
      // y la sesión queda muda: ni streaming ni botón de cancelación.
      if (sid != null && _replayHold.containsKey(sid)) {
        // Replay en vuelo para esta sesión: se aparca; flushReplayHold lo
        // despachará tras el hueco, filtrado por seq.
        _replayHold[sid]!.add(event);
        return;
      }
      // El seq es un contador MONOTÓNICO por sesión
      // (tui_gateway/event_replay.py:65-69); el watermark sólo avanza hacia
      // arriba, o un frame fuera de orden (replay duplicado, broadcast sin
      // seq) retrocedería el cursor y provocaría reentrega en el siguiente
      // replay (apps/shared/src/json-rpc-gateway.ts:451-467, same rule).
      if (sid != null && seq != null && seq > (_watermarks[sid] ?? 0)) {
        _watermarks[sid] = seq;
      }
      _dispatchEvent(event);
      return;
    }

    if (method != null && id is String) {
      // Server→client request (approval, clarify, sudo, secret…). El id real es
      // `srq-<uuid12>` (tui_gateway/server_requests.py:49); el contrato no fija
      // prefijo accionable, así que la detección es estructural como en el
      // cliente compartido: `id` string + `method` (json-rpc-channel.ts:53-54).
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

    // Respuesta a una llamada propia: id NO-nulo y sin `method`
    // (is_response_frame, tui_gateway/server_requests.py:299). Un `id: null`
    // es un notification-response y un frame con `method` ya se consumió
    // arriba: ninguno puede casarse con una llamada pendiente.
    if (id != null && method == null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (frame.containsKey('error')) {
        final err = (frame['error'] as Map<String, Object?>?) ?? const {};
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

  void _dispatchEvent(GatewayEvent event) => _eventsController.add(event);

  /// Desplacha un frame de replay sólo si su seq hace avanzar el watermark
  /// (json-rpc-gateway.ts::dispatchIfNewer 591-607). Sin seq se despacha
  /// siempre: no hay orden que violar.
  void _dispatchIfNewer(GatewayEvent event) {
    final sid = event.sessionId;
    final seq = event.seq;
    if (sid != null && seq != null) {
      if (seq <= (_watermarks[sid] ?? 0)) return;
      _watermarks[sid] = seq;
    }
    _dispatchEvent(event);
  }

  /// Registra el epoch del proceso; un cambio (reinicio del backend) invalida
  /// TODOS los watermarks, que describirían una numeración inexistente y
  /// harían creer al cliente que no perdió nada
  /// (json-rpc-gateway.ts::adoptReplayEpoch 613-625).
  void _adoptReplayEpoch(String? epoch) {
    if (epoch == null || epoch.isEmpty || epoch == _epoch) return;
    final changed = _epoch != null;
    _epoch = epoch;
    if (changed) {
      _watermarks.clear();
      _replayHold.clear();
    }
  }

  /// Suelta los frames aparcados durante el replay de [sessionId], filtrados
  /// por seq para no duplicar lo ya entregado por el replay.
  void _flushReplayHold(String sessionId) {
    final parked = _replayHold.remove(sessionId);
    if (parked == null) return;
    for (final e in parked) {
      _dispatchIfNewer(e);
    }
  }

  /// Llamada JSON-RPC con futuro.
  /// Timeout por petición. `prompt.submit` puede tardar hasta el cierre del
  /// turno en gateways que no ACKean antes (el cliente Desktop usa
  /// 1 800 000 ms = techo del turno del agente, apps/desktop client.ts:19-27);
  /// el resto de RPCs, 30 s.
  static const _longTimeoutMethods = {'prompt.submit'};

  Future<Object?> _request(String method, {Map<String, Object?>? params}) {
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _sendRaw(RpcRequest(id, method, params: params)).catchError((Object e) {
      _pending.remove(id);
      completer.completeError(e);
    });
    return completer.future.timeout(
      _longTimeoutMethods.contains(method)
          ? const Duration(minutes: 30)
          : const Duration(seconds: 30),
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

  /// Responder a un server-request (aprobación, clarify, secreto…).
  ///
  /// El contrato NO es una llamada nueva: es una respuesta JSON-RPC con el
  /// MISMO id del request y un miembro `result`
  /// (tui_gateway/server_requests.py:2 «response frame carrying the same
  /// `id`»; ::resolve_response 201-240 lee `frame["id"]` + `frame["result"]`;
  /// el emisor del cliente es `{jsonrpc,id,result}` en
  /// apps/shared/src/json-rpc-channel.ts:344). Un frame con `method` sería
  /// otro request del cliente, nunca una respuesta.
  Future<void> respondToServerRequest(
    Object requestId,
    Map<String, Object?> result,
  ) {
    final ws = _ws;
    if (ws == null) return Future.error(JsonRpcError(-32000, 'not connected'));
    ws.sink.add(
      jsonEncode({'jsonrpc': '2.0', 'id': requestId, 'result': result}),
    );
    return Future.value();
  }

  /// Responder a un server-request con error JSON-RPC: el backend lo trata
  /// como «sin respuesta» (server_requests.py:218-220) y retira la tarjeta
  /// cuando el cliente ya no puede accionarla. -32601 = sin handler
  /// (apps/shared/src/json-rpc-channel.ts:73).
  Future<void> failServerRequest(Object requestId, int code, String message) {
    final ws = _ws;
    if (ws == null) return Future.error(JsonRpcError(-32000, 'not connected'));
    ws.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': requestId,
        'error': {'code': code, 'message': message},
      }),
    );
    return Future.value();
  }

  /// Sincronizar eventos de una sesión tras reconexión. El resultado real es
  /// `{events, latest_seq, truncated, count, epoch,`
  /// `open_requests}` (tui_gateway/methods_session.py:2456-2470 +
  /// Monta la sesión viva en el gateway para poder hablar con ella. Sin
  /// `session.resume`, `prompt.submit` rechaza cualquier id con 4001
  /// "session not found": el gateway solo acepta turnos sobre sesiones VIVAS
  /// (tui_gateway/server.py:1173-1187, `_sess_nowait`). El resume devuelve un
  /// RUNTIME id nuevo (uuid, methods_session.py:65-67) que hay que usar en
  /// todos los RPC de sesión (prompt.submit, session.interrupt, adjuntos) y
  /// con el que llegan los eventos (server.py:1296-1325 estampa
  /// `ui_session_id` = runtime en los frames). Hermes Desktop hace exactamente
  /// esto al abrir cada chat (use-session-actions/index.ts:1912-1932) y
  /// reintenta con resume ante 4001 (use-prompt-actions/submit.ts:908-915).
  /// `omit_messages: true`: el transcript lo pinta la línea local; evita
  /// duplicar historial en la respuesta (igual que Desktop).
  Future<String> resumeSession(String storedId, {String? profile}) async {
    final result = await _request(
      'session.resume',
      params: {
        'session_id': storedId,
        'source': 'hermes-pocket',
        'omit_messages': true,
        if (profile != null && profile.isNotEmpty) 'profile': profile,
      },
    );
    final sid = result is Map<String, Object?> ? result['session_id'] : null;
    if (sid is! String || sid.isEmpty) {
      throw JsonRpcError(-32000, 'resume sin session_id');
    }
    return sid;
  }

  /// Sincronizar eventos de una sesión tras reconexión (contrato de
  /// `session.events.since`: methods_session.py:2456-2470 +
  /// contracts/sessions.py::SessionEventsSinceResult). `events` son los
  /// `params` de cada frame de evento, ya con `seq`
  /// (tui_gateway/event_replay.py:100-110); `truncated` dice que el anillo
  /// perdió eventos y el llamador debe recargar el historial en vez de
  /// fiarse del replay; `epoch` cambiante (reinicio del backend) invalida
  /// todos los watermarks (apps/shared/src/json-rpc-gateway.ts:613-625).
  Future<SessionReplay> replaySession(String sessionId) async {
    final last = _watermarks[sessionId];
    // Aparcar los frames en vivo de ESTA sesión mientras se pide el hueco: un
    // frame que llegue durante la ida no debe adelantar ni duplicar el replay
    // (json-rpc-gateway.ts::fetchSessionReplay 520-536).
    _replayHold[sessionId] = <GatewayEvent>[];
    try {
      final result = await _request(
        'session.events.since',
        params: {
          'session_id': sessionId,
          // `last_seen` es `int | None` en el contrato
          // (contracts/sessions.py::SessionEventsSinceParams); el handler hace
          // int(params.get("last_seen", 0)), así que un null EXPLÍCITO daría
          // -32602. Sin watermark conocido no se envía el campo.
          'last_seen': ?last,
        },
      );
      final replay = SessionReplay.fromResult(result);
      _adoptReplayEpoch(replay.epoch);
      // `open_requests`: server-requests sin responder que el anillo de
      // eventos NO puede traer. Se entregan antes de que el llamador vea el
      // resultado (json-rpc-channel.ts:396-409).
      for (final r in replay.openRequests) {
        _serverRequestsController.add(r);
      }
      for (final e in replay.events) {
        _dispatchIfNewer(e);
      }
      return replay;
    } finally {
      _flushReplayHold(sessionId);
    }
  }

  // ── Métodos de alto nivel (tipados por los consumidores) ──────────────

  Future<Object?> rawCall(String method, {Map<String, Object?>? params}) =>
      _request(method, params: params);

  /// Roster de bots del gateway. FUENTE PRIMARIA: `profiles.list` por WS
  /// (methods_profiles.py:267-284) — es lo que consume Desktop y trae las
  /// filas completas: `ui_meta` (+ espejo de grupos), `ui_meta_revisions`,
  /// `canonical_session`, `previous_names`. El REST GET /api/profiles
  /// (web_routers/profiles.py:83-99) NO trae esos campos: con él la app no
  /// ve grupos ni sesión canónica ni avatar meta. Queda como FALLBACK para
  /// un gateway sin `profiles.list` (versiones viejas). Un WS que responde
  /// vacío también cae al REST antes de devolver lista vacía.
  Future<List<Map<String, Object?>>> listProfiles() async {
    Object? decode(Object? data) => data is List
        ? {'profiles': data}
        : data is Map<String, Object?> && data['profiles'] is List
        ? data
        : null;

    Object? result;
    try {
      result = decode(await _request('profiles.list'));
    } on JsonRpcError {
      result = null;
    }
    if (result == null) {
      try {
        result = decode(await http.getJson('/api/profiles'));
      } catch (_) {
        result = null; // red/HTTP; el login ya validó credenciales.
      }
    }
    final List raw = switch (result) {
      {'profiles': final List p} => p,
      final List l => l,
      _ => const [],
    };
    return raw.whereType<Map<String, Object?>>().toList();
  }

  /// Diagnóstico del roster: fuente efectiva (WS/REST) y qué trae el perfil
  /// `default` respecto al espejo de grupos de Desktop y la sesión canónica.
  /// Motivación: el REST real no trae `ui_meta`/`canonical_session`
  /// (web_routers/profiles.py:83-99); si el roster acaba en REST, la app no
  /// puede ver grupos ni resolver envíos sin reanudar por título.
  Future<Map<String, Object?>> rosterDiagnostic() async {
    String source = 'none';
    List<Map<String, Object?>> profiles = const [];
    Object? result;
    try {
      result = await _request('profiles.list');
      source = 'ws:profiles.list';
    } on JsonRpcError catch (e) {
      source = 'ws-error:${e.code}';
    }
    final decoded = result is List
        ? {'profiles': result}
        : result is Map<String, Object?> && result['profiles'] is List
        ? result
        : null;
    if (decoded != null) {
      profiles = (decoded['profiles'] as List)
          .whereType<Map<String, Object?>>()
          .toList();
    }
    if (profiles.isEmpty) {
      try {
        final rest = await http.getJson('/api/profiles');
        if (rest is List) {
          profiles = rest.whereType<Map<String, Object?>>().toList();
        } else if (rest is Map && rest['profiles'] is List) {
          profiles = (rest['profiles'] as List)
              .whereType<Map<String, Object?>>()
              .toList();
        }
        if (profiles.isNotEmpty && !source.startsWith('ws-ok')) {
          source = '$source→rest:/api/profiles';
        }
      } catch (e) {
        source = '$source→rest-error';
      }
    }
    // Estado de la credencial: con token, ¿el gateway la acepta?
    final me = await http.authMe();
    Map<String, Object?>? def;
    for (final p in profiles) {
      if (p['name'] == 'default') def = p;
    }
    final uiMeta = def?['ui_meta'];
    final groupsMirror = uiMeta is Map ? uiMeta['hermes-bots-groups'] : null;
    final rooms = groupsMirror is Map ? groupsMirror['rooms'] : null;
    final deleted = groupsMirror is Map ? groupsMirror['deleted'] : null;
    return {
      'source': source,
      'profiles': profiles.length,
      'default_present': def != null,
      'default_ui_meta': uiMeta != null,
      'groups_mirror_present': groupsMirror != null,
      'rooms': rooms is Map ? rooms.length : 0,
      'tombstones': deleted is Map ? deleted.length : 0,
      'canonical_session': canonicalFromProfile(def ?? const {}) != null,
      'bot_meta': def != null ? BotRosterMeta.fromProfile(def) != null : false,
      // La credencial activa (token o sesión) es aceptada por el gateway.
      'auth_ok': me != null,
      'auth_kind': http.hasGatewayToken ? 'sessionToken' : 'password/bearer',
      // Diagnóstico de rechazo: ¿anuncia el gateway un proveedor de
      // contraseña? Si no, NADIE puede entrar por usuario/contraseña —
      // el problema es de configuración del servidor, no de credenciales.
      'auth_providers': me == null
          ? (await http.authProviders())
                ?.map((p) =>
                      '${p['name']}${p['supports_password'] == true ? ' (contraseña)' : ''}')
                .toList()
          : null,
    };
  }

  /// Resuelve la sesión canónica "Bot Chat" de UN perfil, tal cual lo hace
  /// Hermes Desktop en `apps/desktop/src/plugins/hermes-bots/canonical-chat.ts`.
  ///
  /// Identidad = NOMBRE: `(profile, "Bot Chat")` es un registro exacto gracias
  /// al índice UNIQUE(title) del core (`tui_gateway/methods_profiles.py:148-182`
  /// `_canonical_session_row`), y el lookup es una consulta indexada
  /// `WHERE title = ?`, sin ventana de recencia
  /// (canonical-chat.ts:230-270 → `session.list {profile, title, limit:200,
  /// include_hidden:true}`; `include_hidden` es OBLIGATORIO porque el chat
  /// canónico nace oculto — canonical-chat.ts:235, 434-437).
  ///
  /// FAIL CLOSED: un error del lookup NO significa «no hay Bot Chat» — es la
  /// forma exacta de bifurcar el forever-chat (canonical-chat.ts:241-251,
  /// 271-278). Igualmente, una lista VACÍA cuando el roster ya confirmó una
  /// sesión canónica es ausencia NO confirmada, no ausencia
  /// (canonical-chat.ts:287-297). En ambos casos se lanza y la UI ofrece
  /// reintentar; nunca se crea.
  ///
  /// Si no hay fila, se CREA por JSON-RPC `session.create` — el único método
  /// del contrato (apps/shared/src/gateway-contract.generated.ts:5378 RPC_METHODS;
  /// `tui_gateway/contracts/sessions.py:118-147`). NO existe
  /// `POST /api/sessions` en el dashboard real: sus rutas con POST son
  /// bulk-delete / import / owner-backfill / prune
  /// (`hermes_cli/web_routers/sessions.py:430,449,754,866`).
  Future<String?> resumeCanonicalSession(String profile) async {
    final r = await CanonicalChain.resolve(
      listByTitle: () => _canonicalListRows(profile),
      // Confirmación positiva del roster: `ProfileRow.canonical_session`
      // (methods_profiles.py:230). Si existe, un lookup vacío es dudoso.
      rosterConfirmsCanonical: () async {
        for (final p in await listProfiles()) {
          if (p['name'] != profile) continue;
          return canonicalFromProfile(p) != null;
        }
        return false;
      },
      create: () => _createCanonicalSession(profile),
    );
    if (r.created) {
      _log.info(
        "canonical 'Bot Chat' creada vía session.create para "
        "$profile: ${r.sessionId}",
      );
    }
    return r.sessionId;
  }

  /// `session.create` del chat canónico, con los params del contrato Desktop:
  /// `title` + `hidden: true` + `follow_profile_config: true`
  /// (canonical-chat.ts:427-447; campos declarados en
  /// contracts/sessions.py:118-135). `follow_profile_config` es el contrato
  /// explícito que impide que el runtime quede clavado a un modelo/proveedor
  /// viejo (canonical-chat.ts:438-444). El `Params` del gateway es
  /// `extra="forbid"` (registry.py::validate_params): ningún campo extra.
  ///
  /// La fila es LAZY: `session_id` es el runtime y `stored_session_id` la fila
  /// duradera, que no existe hasta el primer prompt
  /// (contracts/sessions.py:138-147, docstring :146-147). Se devuelve la
  /// duradera como identidad del registro, igual que Desktop
  /// (canonical-chat.ts:449-450).
  ///
  /// ADOPT-BEFORE-MINT: si `session.title` rechaza por título duplicado, otro
  /// escritor ganó el título canónico — se readopta SU fila en vez de crear una
  /// segunda (canonical-chat.ts:472-494).
  Future<Map<String, Object?>?> _createCanonicalSession(String profile) async {
    final created = await _request(
      'session.create',
      params: {
        'profile': profile,
        'title': canonicalChatTitle,
        'hidden': true,
        'follow_profile_config': true,
      },
    );
    if (created is! Map) return null;
    final map = Map<String, Object?>.from(created);
    final runtime = map['session_id'];
    if (runtime is String && runtime.isNotEmpty) {
      try {
        // Escribe el título de inmediato: materializa la fila y cierra la
        // ventana sin-título en la que un segundo clic mintearía un duplicado
        // (canonical-chat.ts:456-470).
        await _request(
          'session.title',
          params: {'session_id': runtime, 'title': canonicalChatTitle},
        );
      } on JsonRpcError catch (e) {
        if (RegExp(
          r'already in use',
          caseSensitive: false,
        ).hasMatch(e.message)) {
          final rows = await _canonicalListRows(profile);
          final winner = rows
              .map(CanonicalChain.registryId)
              .firstWhere((id) => id != null, orElse: () => null);
          if (winner != null) {
            _log.info("título canónico ya tomado; adoptada $winner");
            return {'session_id': winner};
          }
        }
        // Gateway antiguo sin escritura eager: prompt.submit materializa la
        // fila (canonical-chat.ts:495).
      }
    }
    return map;
  }

  Future<List<Map<String, Object?>>> _canonicalListRows(String profile) async {
    final listed = await _request(
      'session.list',
      params: {
        'profile': profile,
        'title': canonicalChatTitle,
        // Límite del escaneo por perfil, el mismo que Desktop
        // (canonical-chat.ts:43 PROFILE_SESSION_LIST_LIMIT).
        'limit': profileSessionListLimit,
        'include_hidden': true,
      },
    );
    final rows =
        (listed is Map<String, Object?> ? listed['sessions'] : listed) ??
        const <Object?>[];
    if (rows is List) {
      return rows.whereType<Map<String, Object?>>().toList();
    }
    return const [];
  }

  /// Avatar de un perfil como data-URL, o null si el perfil no tiene.
  ///
  /// Contrato real (`tui_gateway/contracts/profiles_vault_complete_foreign_
  /// subagents.py:334-349`): params `{name, asset:'avatar'}` y resultado
  /// `{found, mime?, size?, data}` — el data-url viaja en **`data`**, NO en
  /// `data_url` (se tolera el alias por compatibilidad), y la ausencia es
  /// `found:false`, no error. `size` son bytes reales publicados por el
  /// gateway (0 si no lo informa).
  Future<({String dataUrl, int size})?> profileAvatar(String name) async {
    final result = await _request(
      'profiles.get_asset',
      params: {'name': name, 'asset': 'avatar'},
    );
    if (result is! Map) return null;
    if (result['found'] == false) return null;
    final url = result['data'] ?? result['data_url'];
    if (url is! String || !url.startsWith('data:')) return null;
    return (dataUrl: url, size: result['size'] as int? ?? 0);
  }

  /// Publica (o borra) la imagen de avatar de un perfil.
  ///
  /// Contrato real (`tui_gateway/methods_profiles.py:408-442`):
  /// `{name, asset:'avatar', data}` con `data` = data-URL
  /// `image/png|jpeg|webp` ≤2 MB (el gateway sniffá la mágia), o
  /// `{name, asset, clear: true}` para borrarla. Respuesta `{ok, asset,
  /// size?, removed?}`; los rechazos salen como error JSON-RPC (4063 name,
  /// 4066 asset, 4067 data, 4069 tamaño, 4070 formato). Es el MISMO canal que
  /// usa Hermes Desktop (`apps/desktop/src/plugins/hermes-bots/data.ts:
  /// 380-408`): la imagen viaja aquí, NO en `ui_meta`, porque los data-URL se
  /// expulsan de `profiles.configure` (tope de 64 KB por clave, y viajarían en
  /// cada `profiles.list`). Gateways antiguos sin el método → false.
  Future<bool> setProfileAvatar(
    String name, {
    String? dataUrl,
    bool clear = false,
  }) async {
    try {
      final result = await _request(
        'profiles.set_asset',
        params: {
          'name': name,
          'asset': 'avatar',
          if (clear) 'clear': true else 'data': dataUrl,
        },
      );
      return result is Map && result['ok'] == true;
    } on JsonRpcError {
      return false;
    }
  }

  /// Sesiones de un perfil (hermes-map §2: session.list viaja con `profile`
  /// en los params). Es lo que Hermes Desktop muestra en su barra lateral
  /// por perfil; filas con title/preview/started_at/last_active/message_count
  /// y session_id cuando la versión del gateway lo incluye.
  Future<List<Map<String, Object?>>> listSessions(String profile) async {
    try {
      final result = await _request(
        'session.list',
        params: {'profile': profile, 'limit': 100},
      );
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

  /// Inventario de proveedores/modelos para el picker de un perfil.
  ///
  /// RPC `model.options`
  /// (tui_gateway/contracts/config_free_tier_control.py:213-281): params
  /// `{profile?, explicit_only?, include_unconfigured?, refresh?}`, result
  /// `{providers: [{slug, name, models[], is_current?, authenticated?, ...}],
  /// model, provider}`.
  Future<ModelOptions?> modelOptions(
    String profile, {
    bool refresh = false,
  }) async {
    final Object? result;
    try {
      result = await _request(
        'model.options',
        params: {'profile': profile, if (refresh) 'refresh': true},
      );
    } catch (_) {
      return null; // gateway antiguo sin model.options: picker degradado
    }
    if (result is! Map) return null;
    final providers = <ModelOptionProvider>[];
    final raw = result['providers'];
    if (raw is List) {
      for (final p in raw) {
        final option = ModelOptionProvider.tryParse(p);
        if (option != null) providers.add(option);
      }
    }
    return ModelOptions(
      providers: providers,
      model: result['model'] is String ? result['model'] as String : '',
      provider: result['provider'] is String
          ? result['provider'] as String
          : '',
    );
  }

  /// Cambia el modelo de un perfil: `PUT /api/profiles/{name}/model`
  /// (hermes_cli/web_routers/profiles.py:1040-1051) — escribe config.yaml del
  /// perfil por el mismo camino validado de `/api/model/set` (provider y
  /// model son required, strip; 400 si faltan). Lanza si el gateway lo
  /// rechaza.
  Future<void> setProfileModel(
    String profile, {
    required String provider,
    required String model,
  }) async {
    final result = await http.putJson(
      '/api/profiles/${Uri.encodeComponent(profile)}/model',
      body: {'provider': provider, 'model': model},
    );
    if (result is! Map || result['ok'] != true) {
      throw StateError('el gateway rechazó el cambio de modelo');
    }
  }

  /// `ui_meta['hermes-bots']` + revision CAS de un perfil (hermes-map §4).
  /// Devuelve también `revision` (`ui_meta_revisions['hermes-bots']`, siempre
  /// presente en gateways con CAS — methods_profiles.py:242-251) para que el
  /// guardado pueda ir con `ui_meta_expected_revisions`.
  ///
  /// Se lee ADEMÁS el asset de avatar (`profiles.get_asset`) sólo cuando el
  /// perfil lo anuncia (`has_avatar`): esa imagen vive fuera de `ui_meta` y
  /// hay que reenviar su proyección al guardar, si no un `configureBot` desde
  /// Pocket la desreferencia. Coste: un RPC por apertura del editor (el sync
  /// de roster NO pasa por aquí).
  Future<({BotRosterMeta? meta, int revision})> profileRosterMeta(
    String name, {
    bool withAvatar = false,
  }) async {
    try {
      final profiles = await listProfiles();
      for (final p in profiles) {
        if (p['name'] != name) continue;
        final revs = p['ui_meta_revisions'];
        final rev = revs is Map ? (revs['hermes-bots'] as int? ?? 0) : 0;
        var meta = BotRosterMeta.fromProfile(p);
        if (withAvatar && meta != null && p['has_avatar'] == true) {
          final asset = await profileAvatar(name);
          if (asset != null) meta = meta.withImage(asset.dataUrl);
        }
        return (meta: meta, revision: rev);
      }
    } catch (e) {
      _log.info('profileRosterMeta $name no disponible: $e');
    }
    return (meta: null, revision: 0);
  }

  /// Edita metadatos de roster de un bot (hermes-map §4: profiles.configure):
  /// ui_meta.hermes-bots {title, description, avatar{shape,color,icon}, groups}.
  /// `expectedRevision` activa el CAS por clave
  /// (`ui_meta_expected_revisions`, methods_profiles.py:575-600): si otro
  /// cliente (Desktop) tocó la sección desde que se leyó, el gateway rechaza
  /// la escritura y `applied.ui_meta` sale false → devolvemos false, así la
  /// UI avisa en vez de pisar el cambio ajeno.
  ///
  /// Contrato de escritura (verificado contra `methods_profiles.py:600-606` y
  /// contra lo que manda Desktop, `plugins/hermes-bots/data.ts:353-372`): el
  /// gateway FUSIONA `ui_meta` por clave y la sección `hermes-bots` viaja
  /// COMPLETA desde el cliente — no hay fusión profunda dentro de `avatar`.
  /// De ahí las dos reglas de esta función:
  ///  - `rawSection` se reenvía entera (claves de Desktop que Pocket no
  ///    modela: `pinned`, `sectionId`, `sectionName`, `screenAutoOpen`,
  ///    `created`). Sin eso un guardado desde Pocket las borra.
  ///  - `avatar` se REEMPLAZA entero: por eso `BotAvatarMeta.icon` null
  ///    significa "quitar el icono" (mandar `icon: null` no lo borra; hay que
  ///    no mandarlo, y para eso se reconstruye la clave aquí).
  ///  - title/description vacíos = "el usuario lo borró" → se omite la clave
  ///    (no se escribe `''`).
  ///
  /// La IMAGEN del avatar no viaja por aquí: es [setProfileAvatar], como en
  /// Desktop. Sólo se re-proyecta su `image_url` si [avatar] lo trae.
  Future<bool> configureBot(
    String name, {
    String? title,
    String? description,
    BotAvatarMeta? avatar,
    List<String> groups = const [],
    int? expectedRevision,

    /// Sección `hermes-bots` CRUDA leída del gateway (`BotRosterMeta.raw`).
    Map<String, Object?> rawSection = const {},
  }) async {
    final metaMap = BotRosterMeta(
      title: title,
      description: description,
      avatar: avatar,
      groups: groups,
      imageDataUrl: avatar?.imageUrl,
      raw: rawSection,
    ).toUiMetaSection();
    try {
      final result = await _request(
        'profiles.configure',
        params: {
          'name': name,
          'ui_meta': {'hermes-bots': metaMap},
          if (expectedRevision != null)
            'ui_meta_expected_revisions': {'hermes-bots': expectedRevision},
        },
      );
      // applied.ui_meta dice si la sección se escribió (false = conflicto CAS
      // o fallo best-effort, methods_profiles.py:579, :391).
      if (result is Map) {
        final applied = result['applied'];
        if (applied is Map && applied['ui_meta'] == false) return false;
      }
      return true;
    } on JsonRpcError {
      return false;
    }
  }

  /// Publica el espejo de grupos (`ui_meta['hermes-bots-groups']`) en el
  /// perfil `default` — el MISMO canal que Desktop
  /// (`profiles.configure` + CAS por clave, group-chat.ts:1174-1192 y
  /// methods_profiles.py:575-611). [snapshot] debe ser el espejo actual
  /// FUSIONADO con la sala nueva: el gateway reemplaza la clave entera, así
  /// que enviar sólo la sala nueva borraria las demás (la app lo garantiza
  /// con mergeGroupRooms). `expectedRevision` activa el CAS; false = conflicto
  /// (otro cliente tocó el espejo) o fallo — la UI lo reporta sin pisar.
  Future<bool> publishGroupMirror({
    required Map<String, Object?> snapshot,
    int? expectedRevision,
  }) async {
    try {
      final result = await _request(
        'profiles.configure',
        params: {
          'name': 'default',
          'ui_meta': {'hermes-bots-groups': snapshot},
          if (expectedRevision != null)
            'ui_meta_expected_revisions': {
              'hermes-bots-groups': expectedRevision,
            },
        },
      );
      if (result is Map) {
        final applied = result['applied'];
        if (applied is Map && applied['ui_meta'] == false) return false;
      }
      return true;
    } on JsonRpcError {
      return false;
    }
  }

  /// Lee el espejo de grupos CRUDO del perfil `default` + su revisión CAS.
  /// El editor de miembros necesita el mapa TAL CUAL (con claves de Desktop
  /// que Pocket no modela) para reenviarlo entero tras editar una sala.
  /// null = el gateway no publica espejo en este perfil.
  Future<({Map<String, Object?> raw, int revision})?> readGroupMirror() async {
    try {
      for (final p in await listProfiles()) {
        if (p['name'] != 'default') continue;
        final ui = p['ui_meta'];
        final raw = ui is Map ? ui['hermes-bots-groups'] : null;
        if (raw is! Map) return null;
        final revs = p['ui_meta_revisions'];
        final rev = revs is Map
            ? (revs['hermes-bots-groups'] as int? ??
                  num.tryParse('${revs['hermes-bots-groups']}')?.toInt() ??
                  0)
            : 0;
        return (raw: raw.cast<String, Object?>(), revision: rev);
      }
    } on JsonRpcError {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  void _scheduleReconnect() {
    if (_manuallyClosed) return;
    _setState(GatewayLinkState.reconnecting);
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _ws = null;
    // Las peticiones en vuelo no pueden esperar al reintento: el socket está
    // muerto (o half-open) y sus futures colgarían hasta el timeout. Fallan
    // AHORA con 'not connected'; el llamador reintenta si procede.
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(JsonRpcError(-32000, 'not connected'));
      }
    }
    _pending.clear();
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

  /// Historial: `GET /api/sessions/{id}/messages`
  /// (apps/desktop/src/api/sessions.ts:455-493).
  ///
  /// Params del cliente real: `limit`, `offset`, `order`
  /// ('latest'|'oldest'), `include_compacted` y **`profile`** — el owner de la
  /// fila viaja en la query; sin él un host que no es el dueño responde 404
  /// "Session not found" (client.ts:231-247 `sessionReadOwnerPin`).
  /// La página de hidratación del Desktop usa 120 filas
  /// (sessions.ts:499 `LATEST_SESSION_MESSAGES_LIMIT`).
  Future<List<Map<String, Object?>>?> fetchSessionMessages(
    String sessionId, {
    String? profile,
    int limit = 120,
    int offset = 0,
    String order = 'latest',
  }) async {
    try {
      final query = StringBuffer('?limit=$limit&offset=$offset&order=$order');
      if (profile != null && profile.isNotEmpty) {
        query.write('&profile=${Uri.encodeQueryComponent(profile)}');
      }
      final result = await http.getJson(
        '/api/sessions/${Uri.encodeComponent(sessionId)}/messages$query',
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

/// Cadón puro (testeable sin IO): la resolución del chat canónico del
/// Desktop, replicada línea por línea.
///
///  - lookup por título EXACTO falla ⇒ se LANZA, nunca se lee como
///    «no existe» (canonical-chat.ts:241-278).
///  - lookup devuelve cero filas PERO el roster confirmó una sesión canónica ⇒
///    ausencia no confirmada ⇒ se lanza igual
///    (canonical-chat.ts:287-297, hermes-agent#98383).
///  - cero filas y el roster no confirmó nada ⇒ ausencia confirmada ⇒ crear
///    (canonical-chat.ts:413-447).
class CanonicalResolutionFailed implements Exception {
  final String message;
  const CanonicalResolutionFailed(this.message);
  @override
  String toString() => 'CanonicalResolutionFailed: $message';
}

class CanonicalChain {
  final String? sessionId;
  final bool created;
  const CanonicalChain._(this.sessionId, this.created);

  static Future<CanonicalChain> resolve({
    required Future<List<Map<String, Object?>>> Function() listByTitle,
    required Future<bool> Function() rosterConfirmsCanonical,
    required Future<Map<String, Object?>?> Function() create,
  }) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await listByTitle();
    } catch (e) {
      throw CanonicalResolutionFailed(
        'No se pudo consultar el registro "Bot Chat" ($e) — no se abre un chat nuevo.',
      );
    }
    // Sólo filas con el título EXACTO: `root_title` es el título duradero del
    // linaje que reporta un gateway con lookup por índice; `title` cubre los
    // listados por ventana (canonical-chat.ts:155-163 isCanonicalBotChatHistory).
    final match = rows
        .where(isCanonicalBotChatRow)
        .map(registryId)
        .firstWhere((id) => id != null, orElse: () => null);
    if (match != null) return CanonicalChain._(match, false);

    bool confirmedAbsent;
    try {
      confirmedAbsent = !await rosterConfirmsCanonical();
    } catch (_) {
      confirmedAbsent = false;
    }
    if (!confirmedAbsent) {
      throw CanonicalResolutionFailed(
        'No se pudo confirmar el registro "Bot Chat" — no se abre un chat nuevo.',
      );
    }

    try {
      final created = await create();
      final id = created == null ? null : registryId(created);
      if (id != null) return CanonicalChain._(id, true);
    } catch (e) {
      throw CanonicalResolutionFailed(
        'No se pudo crear la sesión "Bot Chat" ($e).',
      );
    }
    return const CanonicalChain._(null, false);
  }

  /// Id del REGISTRO (identidad), no la punta viva. `id` es la fila del
  /// registro; `resolved_id` la punta del linaje de compresión, que es lo que
  /// Desktop ABRE mientras la fila sigue siendo la identidad
  /// (canonical-chat.ts:419, 580-590; methods_profiles.py:172-180).
  static String? registryId(Map<String, Object?> row) {
    final id = row['id'] ?? row['session_id'];
    return (id is String && id.isNotEmpty) ? id : null;
  }

  static bool isCanonicalBotChatRow(Map<String, Object?> row) {
    if (row['root_title'] == canonicalChatTitle) return true;
    return row['title'] == canonicalChatTitle;
  }
}

/// Resultado del RPC `model.options`
/// (tui_gateway/contracts/config_free_tier_control.py:270-277).
class ModelOptions {
  final List<ModelOptionProvider> providers;

  /// Modelo/proveedor VIGENTES del perfil consultado.
  final String model;
  final String provider;
  const ModelOptions({
    required this.providers,
    required this.model,
    required this.provider,
  });
}

/// Fila de proveedor del picker (`ModelOptionProvider`, :237-260). Sólo los
/// campos que la UI usa; el resto se descarta.
class ModelOptionProvider {
  final String slug;
  final String name;
  final List<String> models;
  final bool? isCurrent;
  final bool? authenticated;

  const ModelOptionProvider({
    required this.slug,
    required this.name,
    required this.models,
    this.isCurrent,
    this.authenticated,
  });

  static ModelOptionProvider? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'];
    final name = raw['name'];
    if (slug is! String || slug.isEmpty) return null;
    final models = <String>[
      if (raw['models'] is List)
        for (final m in raw['models'] as List)
          if (m is String) m,
    ];
    return ModelOptionProvider(
      slug: slug,
      name: name is String && name.isNotEmpty ? name : slug,
      models: models,
      isCurrent: raw['is_current'] is bool ? raw['is_current'] as bool : null,
      authenticated: raw['authenticated'] is bool
          ? raw['authenticated'] as bool
          : null,
    );
  }
}
