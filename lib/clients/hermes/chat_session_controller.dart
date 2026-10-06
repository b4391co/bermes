import 'dart:async';
import 'dart:convert';

import '../../core/logger.dart';
import '../../core/notify.dart';
import '../../core/turn_activity.dart';
import '../../features/chat/media_cache.dart';
import '../../domain/message/chat_models.dart';
import '../../domain/message/media_tags.dart';
import 'gateway_client.dart';
import 'rpc_types.dart';

/// Controlador de UNA conversación: aplica eventos del gateway a la línea
/// de tiempo local.
///
/// Reglas del contrato real (todos los nombres verificados en
/// apps/shared/src/gateway-contract.generated.ts ::BackendGatewayEventMap /
/// GATEWAY_EVENT_TYPES):
/// - `prompt.submit` → ACK `{status: streaming|queued|steered|redirected}`
///   (PromptSubmitResult :2500-2508). `user_row_id` rebindea la fila optimista.
///   NO reenviar si la conexión se perdió.
/// - Turno: `message.start` (:5555, payload vacío) → `message.delta`*
///   (:5549 StreamDeltaPayload `{text, rendered?}`) → `message.complete`
///   (:5547 MessageCompletePayload). `message.interim` (:5551) sella un
///   comentario provisional como segmento propio; NO es un delta.
/// - Razón: `reasoning.delta` / `thinking.delta` / `reasoning.available`.
/// - Herramientas: `tool.start` (:5649 ToolStartPayload `{tool_id,name,args?,
///   args_text?,preview?}`) y `tool.complete` (:5651 ToolCompletePayload
///   `{tool_id,name,result?,summary?,duration_s?}`). No existen
///   `tool.update`/`tool.stop`.
/// - Fin de turno: `message.complete.status` ∈ complete|error|interrupted
///   (TurnStatus :4434); `error` (:5541 ErrorPayload `{message}`) es un fallo
///   de transporte/turno reportado como evento.
/// - Aprobaciones: server→client request `approval`
///   (ServerRequestMap :5465 ApprovalRequestParams) con respuesta
///   `{choice: once|session|always|deny, all?}` sobre el MISMO id de frame;
///   `request.cancel` (:5601 RequestCancelPayload) retira la tarjeta.
/// - El backend puede retirar la sesión viva bajo el cliente:
///   `session.reclaimed` (:5597) → nada más se puede enviar a ese runtime.
class ChatSessionController {
  final EntityRefPath path;
  final HermesGatewayClient gateway;
  final String sessionId; // session del gateway (canónico del bot o room)
  final String? profile; // perfil del bot (routing ProfileParams) o null

  /// Aviso cuando la sesión canónica se resuelve tras un intento de envío:
  /// la UI re-adjunta el controller con la sesión real.
  void Function(String sessionId)? onSessionResolved;

  /// Avisos al UI: historial a recargar (replay truncado) y sesión retirada.
  void Function()? onHistoryStale;
  void Function()? onSessionReclaimed;

  /// Título de la sesión cambiado por otro cliente (`session.title`): la UI lo
  /// muestra sin reiniciar el chat.
  void Function(String title)? onSessionTitle;

  /// Burbuja optimista cuyo ACK de `prompt.submit` está en vuelo. Se sella por
  /// eventos (`_completeTurn`) o por el ACK (`send`), lo que llegue primero.
  ChatMessage? _pendingOptimistic;
  final _log = Logger('ChatCtl');

  final _messages = <ChatMessage>[];
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();
  final _approvals = <String, ApprovalRequest>{};
  final _approvalController =
      StreamController<List<ApprovalRequest>>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _attached = false;
  bool _disposed = false;
  // Id VIVO del gateway: `session.resume` lo mintea y TODOS los RPC de sesión
  // (prompt.submit, session.interrupt, adjuntos) y los frames de eventos lo
  // usan (tui_gateway/server.py:1173-1187). null = aún sin resume OK.
  String? _runtimeId;
  Future<String>? _resuming;
  /// Timer de silencio del turno (ver `_liveEventTypes`): se reprograma con
  /// cada evento vivo; al expirar baja la vida del bot.
  Timer? _turnWatchdog;

  ChatSessionController(
    this.path,
    this.gateway,
    this.sessionId, {
    this.profile,
  });

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Stream<List<ChatMessage>> get stream => _messagesController.stream;

  /// Aprobaciones abiertas de ESTA sesión, en orden de llegada.
  List<ApprovalRequest> get approvals => List.unmodifiable(_approvals.values);
  Stream<List<ApprovalRequest>> get approvalStream =>
      _approvalController.stream;

  /// Suscribe el controller a eventos y server-requests del gateway.
  /// Idempotente: un re-adjunto no duplica la aplicación de eventos.
  void attach() {
    if (_attached || _disposed) return;
    _attached = true;
    _subs.add(gateway.events.listen(_onEvent));
    _subs.add(gateway.serverRequests.listen(_onServerRequest));
    // Replay de eventos perdidos tras reconexión.
    _subs.add(
      gateway.stateStream.listen((s) {
        if (s == GatewayLinkState.ready) {
          _replay().catchError((Object e) => _log.warning('replay failed: $e'));
        }
      }),
    );
  }

  Future<void> _replay() async {
    // El hueco ya se despacha dentro de replaySession (filtrado por seq);
    // aquí sólo se decide si la línea local es fiable: `truncated` significa
    // que el anillo del backend expulsó eventos por debajo del watermark y
    // hay que recargar el historial, no fiarse del replay
    // (tui_gateway/event_replay.py::is_truncated, json-rpc-gateway.ts:564-568).
    final replay = await gateway.replaySession(sessionId);
    if (replay.truncated) onHistoryStale?.call();
  }

  /// Monta la sesión viva (`session.resume`) una vez por generación. El
  /// runtime id caduca si el gateway la reapró/evictó; el retry ante 4001 lo
  /// re-mintea (server.py:1178-1186). Single-flight: abrir el chat dispara
  /// UN resume aunque send y replay lleguen a la vez.
  Future<String> _ensureResumed() {
    final existing = _runtimeId;
    if (existing != null) return Future.value(existing);
    return _resuming ??= gateway
        .resumeSession(sessionId, profile: profile)
        .then((sid) {
          _runtimeId = sid;
          return sid;
        })
        .whenComplete(() => _resuming = null);
  }

  /// Tipos que significan «el turno sigue vivo» (se reprograma el watchdog).
  static const _liveEventTypes = {
    'message.start',
    'message.delta',
    'message.interim',
    'reasoning.delta',
    'thinking.delta',
    'reasoning.available',
    'tool.start',
    'tool.complete',
    'status.update',
    'notification.show',
  };

  void _onEvent(GatewayEvent e) {
    // Watchdog de silencio: cualquier evento vivo reprograma un timer de 4
    // min. Si expira, el turno se consideró terminado sin `message.complete`
    // (thinking larguísimo o cierre perdido en reconexión) y se baja la vida
    // — más honesto que un «…» eterno. El tipo interno `turn.silence` lo
    // dispara el propio timer.
    if (e.type == 'turn.silence') {
      _turnWatchdog?.cancel();
      _turnWatchdog = null;
      TurnActivity.end(path.storageId);
      return;
    }
    if (_liveEventTypes.contains(e.type)) {
      _turnWatchdog?.cancel();
      _turnWatchdog = Timer(const Duration(minutes: 4), () {
        if (!_disposed) TurnActivity.end(path.storageId);
      });
    }
    if (_runtimeId == null && e.sessionId != null && e.sessionId!.isNotEmpty) {
      _runtimeId = e.sessionId;
    }
    switch (e.type) {
      // ── turno ───────────────────────────────────────────────────────────
      case 'message.start':
        // Reutiliza el segmento en streaming ya abierto si existe: un
        // `message.start` sin `message.complete` previo (turno reabierto tras
        // un reconnect) no debe partir la respuesta en dos burbujas.
        if (_lastStreamingIndex() == null) _openStreamingSegment();
        // Aura + bocadillo desde el PRIMER evento del turno: las fases de
        // contexto/skills pueden tardar en emitir el primer delta.
        TurnActivity.begin(path.storageId);
        break;

      case 'message.delta':
        // StreamDeltaPayload: {text, rendered?}. `rendered` es la versión ya
        // formateada del trozo; el texto crudo sigue en `text`.
        final text = e.payload['text'] as String? ?? '';
        if (text.isEmpty) break;
        // Aura en gateways que no emiten `message.start` (0.15.0): el delta
        // es la primera señal viva del turno.
        TurnActivity.begin(path.storageId);
        final idx = _lastStreamingIndex();
        if (idx == null) {
          _openStreamingSegment(text: text);
        } else {
          final m = _messages[idx];
          _messages[idx] = m.copyWith(text: m.text + text);
          _notify();
        }
        break;

      case 'message.interim':
        // MessageInterimPayload {text, already_streamed}: texto provisional
        // que NO forma parte del turno. Con `already_streamed` el trozo ya
        // está en el segmento abierto; sin él, se sella el segmento y se abre
        // un segmento propio (nunca se pega al turno en curso).
        final it = e.payload['text'] as String? ?? '';
        if (it.isEmpty) break;
        if (e.payload['already_streamed'] == true) break;
        _sealStreaming();
        _openStreamingSegment(text: it);
        _sealStreaming();
        break;

      case 'message.complete':
        _completeTurn(e.payload);
        break;

      // ── razonamiento ────────────────────────────────────────────────────
      case 'reasoning.delta':
      case 'thinking.delta':
        // Thinking largo SIN deltas de texto: sigue encendiendo la vida del
        // bot (aura + bocadillo) — el turno no ha terminado.
        TurnActivity.begin(path.storageId);
        _appendReasoning(e.payload['text'] as String? ?? '');
        break;

      case 'reasoning.available':
        // Razón final disponible: se guarda como sidecar del segmento, no
        // como texto del turno (MessageInterim/StreamDeltaPayload lo separan).
        _appendReasoning(e.payload['text'] as String? ?? '');
        break;

      case 'tool.start':
        // ToolStartPayload (:5710): {tool_id, name, args?, args_text?, preview?}
        final toolId = e.payload['tool_id'] as String?;
        if (toolId == null) break;
        // Herramienta corriendo = bot trabajando aunque el texto tarde:
        // context/skills ejecutan tools sin emitir deltas de momento.
        TurnActivity.begin(path.storageId);
        _appendToolToLast(
          ToolActivity(
            toolId: toolId,
            name: e.payload['name'] as String? ?? 'tool',
            argsText:
                _stringify(e.payload['args']) ??
                e.payload['args_text'] as String?,
            preview: e.payload['preview'] as String?,
            running: true,
          ),
        );
        break;

      case 'tool.complete':
        _completeTool(e.payload);
        break;

      // ── estado de sesión ────────────────────────────────────────────────
      case 'status.update':
        // StatusUpdatePayload {kind, text}: línea transitoria (lifecycle,
        // compacting, goal, heartbeat…). No es contenido del turno: se expone
        // como mensaje de sistema sólo si trae texto, sin tocar el segmento.
        // Un status durante el turno también enciende la vida del bot en la
        // lista (fases context/skills sin deltas).
        final text = e.payload['text'] as String? ?? '';
        TurnActivity.begin(path.storageId);
        if (text.isNotEmpty) _systemLine(text, failed: false);
        break;

      case 'session.reclaimed':
        // El backend retiró el runtime bajo el cliente: cualquier envío
        // posterior a este sessionId es inútil. Se cierra el segmento y la UI
        // re-resuelve la sesión (openBotCanonicalChat la reabre por título).
        _sealStreaming();
        _systemLine('El gateway retiró esta sesión viva; reabriendo.',
            failed: false);
        onSessionReclaimed?.call();
        break;

      case 'notification.show':
        // Mensajes de OTROS bots al runtime de este (bot→bot): el backend
        // los anuncia como notification.show; se muestran como línea de
        // sistema centrada con el texto y el origen. Sin `text` no hay nada
        // que pintar (no inventamos contenido).
        final text = (e.payload['text'] ?? e.payload['message']) as String?;
        if (text != null && text.isNotEmpty) {
          _systemLine(text, failed: false);
        }
        break;

      case 'request.cancel':
        // Dos formas en el backend: el evento `_emit('request.cancel')` manda
        // {id, method, reason} (server_requests.py:125-127) y el payload del
        // contrato RequestCancelPayload {request_id} (:5601). Aceptar ambas.
        final rid = (e.payload['request_id'] ?? e.payload['id']) as String?;
        if (rid != null && _approvals.remove(rid) != null) _notifyApprovals();
        break;

      case 'session.title':
        // El gateway emite {"session_id","title"} al renombrar la sesión
        // (_emit("session.title", sid, …)). La fila viaja por sync; aquí se
        // propaga a la UI para refrescar el título sin reiniciar el chat.
        final t = e.payload['title'] as String?;
        if (t != null && t.isNotEmpty) onSessionTitle?.call(t);
        break;
      case 'error':
        // ErrorPayload {message} (json-rpc-gateway.ts / contracts).
        _systemLine(
          e.payload['message'] as String? ?? 'Error del gateway',
          failed: true,
        );
        break;
    }
  }

  /// MessageCompletePayload (:4422-4439): `text` puede venir como `unknown`
  /// (los caminos de espejo de subagentes sólo traen texto), `status` ∈
  /// complete|error|interrupted, `error`/`recoverable`/`partial` marcan el
  /// fallo, `persisted_turn.row_ids` son las direcciones duraderas de SQLite.
  void _completeTurn(Map<String, Object?> payload) {
    final status = payload['status'] as String?;
    final raw = payload['text'];
    final text = raw is String ? raw : null;
    final err = payload['error'] as String?;
    final idx = _lastStreamingIndex();

    if (idx != null) {
      final m = _messages[idx];
      // Un `text` ausente NO borra lo ya streammeado: el contrato admite
      // payloads parciales (`partial`) y espejos sin cuerpo.
      _messages[idx] = _extractMedia(
        m.copyWith(
          text: (text != null && text.isNotEmpty) ? text : m.text,
          streaming: false,
          sendState: status == 'error' ? SendState.failed : m.sendState,
        ),
      );
    } else if ((text != null && text.isNotEmpty) || err != null) {
      _messages.add(
        _extractMedia(
          ChatMessage(
            id: _localId(),
            path: path,
            role: MessageRole.assistant,
            text: text ?? '',
            origin: MessageOrigin.live,
            sendState: status == 'error' ? SendState.failed : SendState.sent,
            timestamp: DateTime.now(),
          ),
        ),
      );
    }
    // El turno cerró por `message.complete`: quitar el «trabajando» aunque
    // el segmento viniera ya sellado (idempotente).
    TurnActivity.end(path.storageId);
    if (status == 'interrupted') {
      _systemLine('Turno cancelado.', failed: false);
    }
    // Aviso local si el usuario no está mirando este chat: «el bot
    // terminó». Sin push externo: el gateway no ofrece push propio.
    unawaited(
      Notifier.turnDone(
        conversationId: path.storageId,
        botTitle: profile ?? 'Bot',
        preview: (text ?? '').isEmpty
            ? (err ?? '')
            : (text!.length > 120 ? '${text.substring(0, 120)}…' : text),
        ok: status != 'error',
      ),
    );
    // El turno cerró por eventos. Si el ACK de `prompt.submit` sigue en vuelo
    // (el fake lento no lo responde hasta el final), la burbuja optimista
    // quedaría pegada en 'enviando' para siempre — y con ella el botón
    // Detener. Se sella aquí; el ACK posterior sólo confirma.
    _sealPendingOptimistic();
    _notify();
  }

  void _completeTool(Map<String, Object?> payload) {
    final toolId = payload['tool_id'] as String?;
    if (toolId == null || toolId.isEmpty) return;
    final idx = _lastIndexWithTool(toolId);
    if (idx == null) return;
    final m = _messages[idx];
    final tools = [...m.tools];
    final ti = tools.indexWhere((t) => t.toolId == toolId);
    if (ti < 0) return;
    // ToolCompletePayload: {tool_id, name, args?, duration_s?, result?,
    // summary?, result_text?, inline_diff?}. `summary` es opcional: sin él se
    // usa `result_text` (o el resultado serializado), nunca se deja la
    // herramienta colgada sin desenlace.
    final detail =
        payload['summary'] as String? ??
        payload['result_text'] as String? ??
        _stringify(payload['result']);
    tools[ti] = tools[ti].copyWith(running: false, summary: detail);
    _messages[idx] = m.copyWith(tools: tools);
    _notify();
  }

  /// Server→client request `approval` (ServerRequestMap:5465).
  /// ApprovalRequestParams (:4219-4231): `{session_id, request_id, command?,
  /// description?, choices?: ('once'|'session'|'always'|'deny')[],
  /// allow_permanent?, allow_session?, smart_denied?, tool_name?}`.
  void _onServerRequest(ServerRequest req) {
    if (_disposed) return;
    if (req.method == 'request.cancel') {
      // Retirada por id de petición abierta: el id del FRAME es la clave que
      // el cliente usa para responder (server_requests.py::ServerRequest.id).
      if (_approvals.remove(req.id) != null) _notifyApprovals();
      return;
    }
    if (req.method != 'approval') return;
    // Aprobaciones accionables: sólo las de ESTA sesión.
    if (req.sessionId.isNotEmpty && req.sessionId != sessionId) return;
    final raw = req.params['choices'];
    _approvals[req.id] = ApprovalRequest(
      serverRequestId: req.id,
      requestId: req.params['request_id'] as String?,
      sessionId: req.sessionId.isEmpty ? sessionId : req.sessionId,
      command: req.params['command'] as String? ?? '',
      description: req.params['description'] as String?,
      toolName: req.params['tool_name'] as String?,
      choices: raw is List
          ? raw.map(approvalChoiceFromWire).nonNulls.toList(growable: false)
          : const [],
      allowPermanent: req.params['allow_permanent'] != false,
      receivedAt: DateTime.now(),
    );
    _notifyApprovals();
    _log.info('approval ${req.id} request_id=${req.params['request_id']}');
  }

  /// Responder a una aprobación. El frame de respuesta lleva el MISMO id del
  /// server-request y `{choice, all?}` (ApprovalResult :4232-4235); NO es
  /// `approval.respond` — ese RPC es el fallback cuando la tarjeta ya no tiene
  /// el request abierto en memoria (apps/desktop/src/store/prompts.ts:363-391).
  Future<void> answerApproval(
    ApprovalRequest approval,
    ApprovalChoice choice, {
    bool all = false,
  }) async {
    if (approval.serverRequestId == null) {
      // Sin request abierto: único camino posible es el RPC de sesión.
      await gateway.rawCall(
        'approval.respond',
        params: {
          'session_id': sessionId,
          if (profile != null) 'profile': profile,
          'choice': choice.wire,
          if (all) 'all': true,
          if (approval.requestId != null) 'request_id': approval.requestId,
        },
      );
      _approvals.remove(approval.serverRequestId);
      _notifyApprovals();
      return;
    }
    await gateway.respondToServerRequest(approval.serverRequestId!, {
      'choice': choice.wire,
      if (all) 'all': true,
    });
    _approvals.remove(approval.serverRequestId);
    _notifyApprovals();
  }

  /// `approval.pending` re-consulta la cola del servidor tras un reconnect
  /// (RpcMethods:4743 ApprovalPendingResult `{approvals: PendingApproval[]}`).
  Future<void> refreshApprovals() async {
    try {
      final result = await gateway.rawCall(
        'approval.pending',
        params: {
          'session_id': sessionId,
          if (profile != null) 'profile': profile,
        },
      );
      final list = result is Map ? result['approvals'] : null;
      if (list is! List) return;
      for (final entry in list.whereType<Map<Object?, Object?>>()) {
        final rid = entry['request_id'];
        if (rid is! String || _approvals.containsKey(rid)) continue;
        final raw = entry['choices'];
        _approvals[rid] = ApprovalRequest(
          requestId: rid,
          sessionId: sessionId,
          command: entry['command'] as String? ?? '',
          description: entry['description'] as String?,
          toolName: entry['tool_name'] as String?,
          choices: raw is List
              ? raw.map(approvalChoiceFromWire).nonNulls.toList(growable: false)
              : const [],
          allowPermanent: entry['allow_permanent'] != false,
          receivedAt: DateTime.now(),
        );
      }
      _notifyApprovals();
    } on JsonRpcError catch (e) {
      _log.info('approval.pending no disponible: ${e.code}');
    }
  }

  int? _lastStreamingIndex() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].streaming) return i;
    }
    return null;
  }

  int? _lastIndexWithTool(String toolId) {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].tools.any((t) => t.toolId == toolId)) return i;
    }
    return null;
  }

  void _appendToolToLast(ToolActivity tool) {
    if (_messages.isEmpty) return;
    final idx = _messages.length - 1;
    final m = _messages[idx];
    _messages[idx] = m.copyWith(tools: [...m.tools, tool]);
    _notify();
  }

  void _openStreamingSegment({String text = ''}) {
    _messages.add(
      ChatMessage(
        id: _localId(),
        path: path,
        role: MessageRole.assistant,
        text: text,
        streaming: true,
        origin: MessageOrigin.live,
        timestamp: DateTime.now(),
      ),
    );
    // Registro global «este bot está trabajando»: aura + bocadillo en la
    // banda de fijados aunque no estés dentro del chat.
    TurnActivity.begin(path.storageId);
    _notify();
  }

  void _sealStreaming() {
    final idx = _lastStreamingIndex();
    if (idx == null) return;
    _messages[idx] = _extractMedia(_messages[idx].copyWith(streaming: false));
    TurnActivity.end(path.storageId);
    _notify();
  }

  /// Sella las etiquetas `MEDIA:` de un turno de asistente: el texto queda
  /// limpio y los archivos se vuelven adjuntos renderizables (contrato de
  /// entrega de Desktop, parts.ts). Se aplica al SELLAR (turno e interim),
  /// no durante el stream: el tag puede llegar partido en deltas y una
  /// burbuja en vivo no debe parpadear con el prefijo «MEDIA:».
  ChatMessage _extractMedia(ChatMessage m) {
    if (m.role != MessageRole.assistant || !m.text.contains('MEDIA:')) {
      return m;
    }
    final split = splitAssistantMedia(m.text);
    if (split.media.isEmpty) return m.copyWith(text: split.text);
    return m.copyWith(
      text: split.text,
      attachments: [...m.attachments, ...split.media],
    );
  }

  /// Sella la burbuja optimista cuando el turno cierra por eventos y el ACK
  /// de `prompt.submit` aún está en vuelo (gateway lento). Sin esto queda
  /// pegada en 'enviando' y el botón Detener no se va nunca.
  void _sealPendingOptimistic() {
    if (_pendingOptimistic == null) return;
    final idx = _messages.indexOf(_pendingOptimistic!);
    _pendingOptimistic = null;
    if (idx < 0) return;
    _messages[idx] = _messages[idx].copyWith(sendState: SendState.sent);
  }

  void _appendReasoning(String text) {
    if (text.isEmpty) return;
    final idx = _lastStreamingIndex();
    if (idx == null) {
      _openStreamingSegment();
      _messages[_messages.length - 1] = _messages.last.copyWith(
        reasoning: (_messages.last.reasoning ?? '') + text,
      );
    } else {
      final m = _messages[idx];
      _messages[idx] = m.copyWith(reasoning: (m.reasoning ?? '') + text);
    }
    _notify();
  }

  void _systemLine(String text, {required bool failed}) {
    _messages.add(
      ChatMessage(
        id: _localId(),
        path: path,
        role: MessageRole.system,
        text: text,
        origin: MessageOrigin.live,
        sendState: failed ? SendState.failed : SendState.sent,
        timestamp: DateTime.now(),
      ),
    );
    _notify();
  }

  /// `args` de ToolStartPayload es `Record<string, unknown> | null`: se
  /// serializa JSON legible, no `Object.toString()` de un Map dart.
  static String? _stringify(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } on Object {
      return value.toString();
    }
  }

  String _localId() =>
      '${path.storageId}/${DateTime.now().microsecondsSinceEpoch}/${_messages.length}';

  void _notify() => _messagesController.add(List.unmodifiable(_messages));

  void _notifyApprovals() =>
      _approvalController.add(List.unmodifiable(_approvals.values));

  /// Enviar texto. Estados de envío inequívocos; NO reenviar automático.
  ///
  /// [attachments] (bots sólo): imágenes ya seleccionadas, en bruto. El
  /// contrato las pone EN COLA antes del turno (`image.attach_bytes` →
  /// `prompt.submit`, prompt_voice.py:120-131); si la cola no se monta, no se
  /// envía — nunca se manda un turno sin la imagen que el usuario pidió.
  Future<void> send(
    String text, {
    List<MessageAttachment> attachments = const [],
  }) async {
    if (sessionId.isEmpty) {
      // Sin sesión canónica: no se inventa destino. Reintento resolver AHORA
      // por el registro de título (session.list → session.create si el roster
      // confirma ausencia); si aparece, la UI re-adjunta y reintenta.
      // CanonicalResolutionFailed se propaga como causa: la cadena FALLA
      // CERRADA y no mintea un duplicado (canonical-chat.ts:241-251).
      final resolved = profile == null || profile!.isEmpty
          ? null
          : await gateway.resumeCanonicalSession(profile!);
      if (resolved != null && resolved.isNotEmpty) {
        onSessionResolved?.call(resolved);
        throw const ChatSendException(
          'Sesión "Bot Chat" recién disponible; vuelve a enviar.',
        );
      }
      throw const ChatSendException(
        'El gateway no tiene la sesión "Bot Chat" de este bot todavía. '
        'Ábrela una vez en Hermes Desktop (o dale a Reintentar).',
      );
    }
    final optimistic = ChatMessage(
      id: _localId(),
      path: path,
      role: MessageRole.user,
      text: text,
      sendState: SendState.sending,
      origin: MessageOrigin.optimistic,
      timestamp: DateTime.now(),
    );
    _messages.add(optimistic);
    _pendingOptimistic = optimistic;
    _notify();
    try {
      // El session_id del submit es el RUNTIME vivo del gateway
      // (PromptSubmitParams: contracts/common.py:224-228; `_sess_nowait`,
      // server.py:1173-1187): sin `session.resume` previo el gateway
      // rechaza con 4001 "session not found" — por eso fallaba el envío en
      // cualquier bot. `profile` es el enrutado de perfil (ProfileParams).
      final runtimeId = await _ensureResumed();
      final attached = attachments.isEmpty
          ? const <MessageAttachment>[]
          : await _attachAndCache(attachments, runtimeId);
      final idxAdd = _messages.indexOf(optimistic);
      if (idxAdd >= 0 && attached.isNotEmpty) {
        _messages[idxAdd] = optimistic.copyWith(attachments: attached);
        _notify();
      }
      final result = await _submitWithRetry(text, runtimeId);
      final map = result is Map
          ? Map<String, Object?>.from(result)
          : const <String, Object?>{};
      final status = map['status'] as String?;
      // El ACK dice que el turno ESTÁ vivo (streaming|queued|steered|
      // redirected). Encender la vida del bot aquí mismo: entre el ACK y el
      // primer evento (message.start/tool.start/delta) puede pasar un rato
      // (fases de contexto/skills), y si el gateway no emite `message.start`
      // el aura dependería de los deltas — el hueco se vería como «parada».
      // El turno lo apaga `message.complete`/`interrupt`/cierre de runtime.
      if (status == null || _knownSubmitStatuses.contains(status)) {
        TurnActivity.begin(path.storageId);
      }
      // PromptSubmitResult: status ∈ streaming|queued|steered|redirected y
      // `user_row_id` es la fila duradera escrita para ESTE input
      // (contracts/prompt_voice.py:61-73). Con la fila conocida el optimista ya
      // no se duplica contra el historial REST (que pagina por row_id).
      final rowId = (map['user_row_id'] as num?)?.toInt();
      _pendingOptimistic = null;
      final idx = _messages.indexOf(optimistic);
      if (idx >= 0) {
        _messages[idx] = optimistic.copyWith(
          sendState: SendState.sent,
          gatewayRowId: rowId,
        );
        _notify();
      }
      if (status != null && !_knownSubmitStatuses.contains(status)) {
        _log.warning('prompt ack con status no contrato: $status');
      }
      _log.info('prompt ack status=${status ?? '<sin status>'} row=$rowId');
      // El turno ya cerró por eventos ANTES del ACK (o el ACK llegó y el
      // turno no estaba en streaming): la burbuja optimista no puede quedar
      // pegada en 'enviando'.
      if (idx >= 0 && _lastStreamingIndex() == null) {
        _messages[idx] = optimistic.copyWith(sendState: SendState.sent);
        _notify();
      }
    } on JsonRpcError catch (e) {
      _pendingOptimistic = null;
      final idx = _messages.indexOf(optimistic);
      if (idx >= 0) {
        _messages[idx] = optimistic.copyWith(sendState: SendState.failed);
        _notify();
      }
      _log.warning('prompt failed ${e.code} ${e.message}');
      throw ChatSendException(e.message);
    } on TimeoutException {
      // EL ACK no es el cierre del turno: `prompt.submit` puede tardar (o no
      // contestar hasta `message.complete`, según gateway). El turno está VIVO;
      // los eventos (message.* / session.interrupt) sellan la burbuja. NO se
      // marca failed — eso haría reintentar un mensaje ya aceptado.
      _log.info('ack timeout — turno en curso');
      rethrow;
    } catch (e) {
      _pendingOptimistic = null;
      // Transporte caído u otro fallo: el estado queda failed y el texto
      // vuelve al campo (UI). NO se reintente a ciegas.
      final idx = _messages.indexOf(optimistic);
      if (idx >= 0) {
        _messages[idx] = optimistic.copyWith(sendState: SendState.failed);
        _notify();
      }
      _log.warning('prompt falló (transporte)', e);
      throw ChatSendException(
        e is ChatSendException ? e.message : 'Sin conexión con el gateway',
      );
    }
  }

  /// prompt.submit con el runtime id. Ante 4001 "session not found" el
  /// runtime caducó (reap/evict/TTL, server.py:1178-1186): re-mintea con
  /// resume y reintenta UNA vez, como Desktop (submit.ts:908-915,
  /// withSessionNotFoundResume). Nunca reintenta en otros errores.
  Future<Object?> _submitWithRetry(String text, String runtimeId) async {
    Future<Object?> submit(String sid) => gateway.rawCall(
      'prompt.submit',
      params: {
        'session_id': sid,
        'text': text,
        if (profile != null) 'profile': profile,
      },
    );
    try {
      return await submit(runtimeId);
    } on JsonRpcError catch (e) {
      if (e.code != 4001) rethrow;
      _runtimeId = null;
      final fresh = await _ensureResumed();
      return submit(fresh);
    }
  }

  /// Encola imágenes en la sesión viva: `image.attach_bytes`
  /// (prompt_voice.py:120-131; métodos en methods_prompt.py ~794/~822; límite
  /// real 25 MB por attach, prompt_attachments.py:18-20). Los magic bytes
  /// deciden el tipo. params = SessionParams → `session_id` (runtime) + `profile?`.
  /// AttachedImageResult (:92-101): `{attached, path?, name?, bytes?, text?,
  /// message?}` — si `attached != true` el envío se ABORTA con el mensaje del
  /// gateway: nunca se manda un turno sin la imagen que el usuario pidió.
  Future<List<MessageAttachment>> _attachAndCache(
    List<MessageAttachment> items,
    String runtimeId,
  ) async {
    final out = <MessageAttachment>[];
    for (final a in items) {
      final raw = a.localBytes;
      if (raw == null || raw.isEmpty) {
        throw const ChatSendException('La imagen ya no está disponible.');
      }
      final result = await gateway.rawCall(
        'image.attach_bytes',
        params: {
          'session_id': runtimeId,
          if (profile != null) 'profile': profile,
          'content_base64': base64Encode(raw),
          'filename': a.name,
        },
      );
      final map = result is Map
          ? Map<String, Object?>.from(result)
          : const <String, Object?>{};
      if (map['attached'] != true) {
        final why = map['message'] as String? ?? 'el gateway rechazó la imagen';
        throw ChatSendException('No se pudo adjuntar $why');
      }
      final attached = MessageAttachment(
        path: map['path'] as String? ?? '',
        name: map['name'] as String? ?? a.name,
        bytes: (map['bytes'] as num?)?.toInt() ?? raw.length,
        localBytes: raw,
      );
      out.add(await MediaCache.put(attached, raw));
    }
    return out;
  }

  /// El UI NO asume éxito: el resultado dice si de verdad se cortó, y el
  /// `message.complete` con `status:'interrupted'` es el cierre definitivo de
  /// la línea. Los params del contrato son extra="forbid" — nada de campos de
  /// más (registry.py::validate_params).
  Future<bool> interrupt() async {
    try {
      final result = await gateway.rawCall(
        'session.interrupt',
        params: {
          'session_id': _runtimeId ?? sessionId,
          if (profile != null) 'profile': profile,
        },
      );
      final map = result is Map
          ? Map<String, Object?>.from(result)
          : const <String, Object?>{};
      final interrupted =
          map['interrupted'] == true || map['status'] == 'interrupted';
      if (!interrupted) {
        _log.info('interrupt: ${map['status'] ?? 'sin status'}');
      }
      return interrupted;
    } on JsonRpcError catch (e) {
      _log.warning('interrupt failed ${e.code} ${e.message}');
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _turnWatchdog?.cancel();
    _turnWatchdog = null;
    // El chat se cierra: si había un turno en vivo, la banda de fijados
    // deja de mostrarlo como trabajando (el turno sigue en el servidor,
    // pero aquí ya no hay nadie observándolo).
    TurnActivity.end(path.storageId);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _messagesController.close();
    _approvalController.close();
  }
}

/// `PromptSubmitStatus` (apps/shared/src/gateway-contract.generated.ts:2509).
const _knownSubmitStatuses = {'streaming', 'queued', 'steered', 'redirected'};

/// Fallo de envío con causa apta para mostrar al usuario.
class ChatSendException implements Exception {
  final String message;
  const ChatSendException(this.message);
  @override
  String toString() => message;
}
