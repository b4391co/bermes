import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../clients/hermes/chat_session_controller.dart';
import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
import '../../clients/hermes/rooms_client.dart';
import '../../clients/hermes/rpc_types.dart';
import '../../core/app_services.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart' as db;
import '../../design/tokens.dart';
import '../../domain/entity/entity_ref.dart';
import '../../domain/message/chat_models.dart';
import '../app_shell.dart' show BotAvatar;
import 'message_bubble.dart';

/// Chat de UNA conversación (bot canónico o grupo de un gateway).
///
/// - Cablea [ChatSessionController] de verdad cuando hay runtime: replay en
///   vivo, envío optimista, streaming progresivo y cancelación.
/// - Historial local desde la tabla Messages (paginado hacia arriba).
/// - Borrador persistido en Drafts con guardado con debounce.
/// - Scroll anclado al fondo solo cuando el usuario está cerca del fondo.
class ChatScreen extends StatefulWidget {
  /// Clave de la conversación en la tabla Conversations (Conversation.id).
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _pageSize = 60;
  static const _draftDebounce = Duration(milliseconds: 600);
  static const _stickyBottomThreshold = 250.0;

  final _log = Logger('Chat');
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();

  Timer? _draftTimer;
  bool _loadingOlder = false;
  bool _hasMoreHistory = true;
  bool _nearBottom = true;
  bool _sending = false;
  bool _hasError = false;

  ChatSessionController? _controller;
  StreamSubscription<List<ChatMessage>>? _liveSub;
  List<ChatMessage> _live = const [];
  final _roomController = StreamController<List<ChatMessage>>.broadcast();

  db.Conversation? _conversation;
  List<db.Message> _history = const [];
  ConnectionRuntime? _runtime;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadConversation();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _liveSub?.cancel();
    // El controller se suscribe al gateway en attach(): sin dispose, cada
    // re-adjunto (sesión recién resuelta, reentrada al chat) dejaría un
    // listener vivo aplicando eventos sobre una página muerta.
    _controller?.dispose();
    unawaited(_roomController.close());
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Carga ─────────────────────────────────────────────────────────────

  Future<void> _loadConversation() async {
    final database = AppServices.db;
    final row =
        await (
              database.select(
                database.conversations,
              )..where((c) => c.id.equals(widget.conversationId))
            ).getSingleOrNull();
    if (!mounted) return;
    if (row == null) {
      _log.warning('conversation not found ${widget.conversationId}');
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _conversation = row);
    _connectRuntime();
    await _restoreDraft();
    await _loadHistory();
    // Vuelca el borrador pendiente si lo hubo antes de montar.
    if (_draftTimer?.isActive ?? false) _flushDraft();
  }

  /// Runtime del gateway de esta conversación, si está vivo. Sin simulación:
  /// sin runtime el chat funciona en modo solo-historial y el envío marca
  /// error reintentable.
  void _connectRuntime() {
    final conv = _conversation;
    if (conv == null) return;
    final runtime = AppServices.connections.runtimeFor(conv.connectionId);
    if (runtime == null) return;
    _runtime = runtime;
    _attachController();
  }

  void _attachController() {
    final conv = _conversation;
    final runtime = _runtime;
    if (conv == null || runtime == null || _controller != null) return;

    final kind = EntityKind.values.firstWhere(
      (k) => k.name == conv.kind,
      orElse: () => EntityKind.session,
    );
    final path = EntityRefPath(
      connectionId: conv.connectionId,
      kind: kind,
      gatewayId: conv.gatewayId,
    );
    // Bots: la sesión de envío es la canónica "Bot Chat" del perfil
    // (resuelta en syncBots); el envío va scopiado con profile=<perfil>.
    // Grupos/sesiones: gatewayId ES el room/session id.
    // Grupos de Desktop (agrupación por ui_meta.groups): la conversación
    // vive en Desktop; aquí se listan y se abren los bots miembros. No hay
    // sesión de room que inventar: el envío directo está bloqueado.
    var sendSession = conv.kind == 'group' ? null : conv.canonicalSession;
    if (sendSession == null && conv.kind == 'bot') {
      // En sync el gateway no dio id (o estaba caído). Reintento resolver
      // ahora, en abierto; si sigue sin id, NO creo una sesión inventada:
      // el envío mostrará la causa real.
      unawaited(
        runtime.gateway
            .resumeCanonicalSession(conv.gatewayId)
            .then((id) async {
              if (!mounted) return;
              if (id == null) return; // sin Bot Chat aún: el send dará causa.
              await (AppServices.db.update(AppServices.db.conversations)
                    ..where((c) => c.id.equals(conv.id)))
                  .write(
                db.ConversationsCompanion(
                  canonicalSession: Value(id),
                ),
              );
              _reattachWithSession(id);
              _loadHistory();
            }),
      );
      sendSession = null;
    }
    if (conv.kind == 'group') {
      // Salas hosted: el timeline es `groups.log` + eventos `room.event`.
      _startRoomLog();
      return;
    }
    _startController(path, sendSession, runtime);
  }

  int _roomLastSeq = 0;
  StreamSubscription<GatewayEvent>? _roomSub;
  bool _roomLoading = false;

  void _startRoomLog() {
    final conv = _conversation;
    final runtime = _runtime;
    final roomId = conv?.groupRoomId ?? conv?.gatewayId;
    if (conv == null || runtime == null || roomId == null || roomId.isEmpty) {
      return;
    }
    final client = RoomsClient(runtime.gateway);
    // El enlace puede seguir conectando (el bootstrap del shell arranca en
    // paralelo con esta pantalla). _request NO encola: 'not connected' es un
    // fallo real. Se espera el ready (o su timeout) antes de pedir el log.
    unawaited(() async {
      try {
        await runtime.gateway.readyOrTimeout(const Duration(seconds: 20));
        await _loadRoomLog(client, roomId);
      } catch (e, st) {
        _log.warning('room log load falló', e, st);
      }
    }());
    // 2) Suscribir eventos en vivo: el backend emite `room.event`
    //    (hosted_room_service::publish) con el evento dentro de payload.event.
    _roomSub = runtime.gateway.events.listen((e) async {
      if (e.type != 'room.event') return;
      final ev = e.payload['event'];
      final payloadRoom = e.payload['room_id'];
      if (ev is! Map || payloadRoom != roomId) return;
      final seq = (ev['seq'] as num?)?.toInt() ?? 0;
      if (seq <= _roomLastSeq) return;
      _roomLastSeq = seq;
      setState(() => _live = [..._live, _roomMessage(conv, roomId, ev)]);
      _roomController.add(_live);
    });
  }

  ChatMessage _roomMessage(db.Conversation conv, String roomId, Map ev) {
    final actor = (ev['actor'] as Map?) ?? const {};
    final kind = ev['kind'] as String? ?? '';
    final text = ((ev['payload'] as Map?)?['text'] as String?) ?? '';
    final isUser = kind == 'message.user';
    final author = isUser
        ? 'Tú'
        : (actor['display_name'] as String? ??
            actor['handle'] as String? ??
            actor['profile'] as String? ??
            'miembro');
    return ChatMessage(
      id: 'room-${ev['event_id']}',
      path: EntityRefPath(
        connectionId: conv.connectionId,
        kind: EntityKind.group,
        gatewayId: roomId,
      ),
      role: isUser ? MessageRole.user : MessageRole.assistant,
      text: text,
      sendState: SendState.sent,
      origin: MessageOrigin.live,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (((ev['created_at'] as num?)?.toDouble() ?? 0) * 1000).round(),
      ),
      authorName: author,
    );
  }

  Future<void> _loadRoomLog(RoomsClient client, String roomId) async {
    if (_roomLoading) return;
    _roomLoading = true;
    final conv = _conversation!;
    try {
      final page = await client.log(roomId, sinceSeq: 0);
      _roomLastSeq = page.cursor;
      // Reconstrucción del timeline desde el log: se reemplaza _live (la
      // fuente de verdad es el servidor). Un re-abierto no duplica nada; los
      // optimistas de la sesión anterior viven en el log si fueron aceptados.
      final msgs = page.events
          .where((e) =>
              e.kind == 'message.user' || e.kind == 'message.member')
          .map((e) => _roomMessage(conv, roomId, e.raw))
          .toList();
      if (mounted) setState(() => _live = msgs);
      _roomController.add(_live);
    } catch (e) {
      // Gateway sin groups.* (versión antigua): el chat queda vacío y el
      // envío reportará la causa real.
      _log.warning('groups.log no disponible', e);
    } finally {
      _roomLoading = false;
    }
  }

  void _startController(
    EntityRefPath path,
    String? sendSession,
    ConnectionRuntime runtime,
  ) {
    final conv = _conversation!;
    final controller = ChatSessionController(
      path,
      runtime.gateway,
      // Sin id real NO se envía a una sesión inventada: el controller lo
      // sabe (sessionId vacío → causa clara + reintento de resolución).
      sendSession ?? '',
      profile: conv.kind == 'bot' ? conv.gatewayId : null,
    );
    controller.onSessionResolved = (id) {
      if (!mounted) return;
      // Sesión recién publicada por el gateway/Desktop: persisto, re-adjunto
      // y cargo historial; el usuario solo vuelve a pulsar Enviar.
      AppServices.db
          .into(AppServices.db.conversations)
          .insertOnConflictUpdate(
        db.ConversationsCompanion(
          id: Value(conv.id),
          canonicalSession: Value(id),
        ),
      );
      _reattachWithSession(id);
      _loadHistory();
    };

    _controller?.dispose();
    _liveSub?.cancel();
    _liveSub = controller.stream.listen(_onLive);
    // attach() SUSCRIBE el controller a los eventos del gateway. Omitirlo
    // dejaba la línea viva muda: sin streaming, sin botón Detener y sin
    // aprobaciones. Se hace tras el listen para no perder el primer frame.
    controller.attach();
    setState(() {
      _controller = controller;
      _live = controller.messages;
    });
  }

  void _reattachWithSession(String sessionId) {
    final conv = _conversation;
    final runtime = _runtime;
    if (conv == null || runtime == null) return;
    final kind = EntityKind.values.firstWhere(
      (k) => k.name == conv.kind,
      orElse: () => EntityKind.session,
    );
    _startController(
      EntityRefPath(
        connectionId: conv.connectionId,
        kind: kind,
        gatewayId: conv.gatewayId,
      ),
      sessionId,
      runtime,
    );
  }

  void _onLive(List<ChatMessage> live) {
    if (!mounted) return;
    setState(() => _live = live);
    _persistLive(live);
  }

  /// Persistencia de la línea viva. Se reemplaza el bloque con origen 'live'
  /// en cada cambio; el historial ('history') nunca se duplica con él.
  Future<void> _persistLive(List<ChatMessage> live) async {
    final database = AppServices.db;
    final conv = _conversation;
    if (conv == null) return;
    try {
      await database.batch((b) {
        // Los optimistic persistidos de envíos previos colisionarían con
        // los live que reutilizan el mismo id local: se limpian ambos y
        // el batch reescribe el estado en vivo completo. 'history' intacto.
        b.deleteWhere<db.$MessagesTable, db.Message>(
          database.messages,
          (m) =>
              m.conversationId.equals(conv.id) &
              (m.origin.equals('live') | m.origin.equals('optimistic')),
        );
        b.insertAllOnConflictUpdate(database.messages, live.map(_rowFrom).toList());
      });
    } catch (e) {
      _log.warning('persist live failed', e);
    }
  }

  db.MessagesCompanion _rowFrom(ChatMessage m) {
    final conv = _conversation!;
    return db.MessagesCompanion.insert(
      id: m.id,
      conversationId: conv.id,
      connectionId: conv.connectionId,
      role: m.role.name,
      authorName: Value(m.authorName),
      text_: Value(m.text),
      timestamp: Value(m.timestamp),
      sendState: Value(m.sendState.name),
      origin: Value(m.origin.name),
      toolsJson: Value(
        m.tools.isEmpty
            ? null
            : jsonEncode(m.tools.map(_toolToJson).toList()),
      ),
    );
  }

  Map<String, Object?> _toolToJson(ToolActivity t) => {
    'tool_id': t.toolId,
    'name': t.name,
    if (t.argsText != null) 'args_text': t.argsText,
    if (t.summary != null) 'summary': t.summary,
    'running': t.running,
  };

  Future<void> _restoreDraft() async {
    final row =
        await (AppServices.db.select(
          AppServices.db.drafts,
        )..where((d) => d.conversationId.equals(widget.conversationId)))
            .getSingleOrNull();
    if (row == null || row.text_.isEmpty || !mounted) return;
    _input.text = row.text_;
    _input.selection = TextSelection.collapsed(offset: row.text_.length);
  }

  Future<void> _loadHistory() async {
    await _pullRemoteHistory();
    final database = AppServices.db;
    final query = database.select(database.messages)
      ..where(
        (m) =>
            m.conversationId.equals(widget.conversationId) &
            (m.origin.equals('history') | m.origin.equals('live')),
      )
      ..orderBy([
        (m) => OrderingTerm.desc(m.timestamp),
        (m) => OrderingTerm.desc(m.rowId),
      ])
      ..limit(_pageSize + 1);
    final rows = await query.get();
    final hasMore = rows.length > _pageSize;
    final page = hasMore ? rows.sublist(0, _pageSize) : rows;
    page.sort(_byTimestamp);
    if (!mounted) return;
    setState(() {
      _history = page;
      _hasMoreHistory = hasMore;
    });
    _jumpToBottom();
  }

  /// Trae el historial real del gateway
  /// (`GET /api/sessions/{id}/messages`, apps/desktop/src/api/sessions.ts:455-493)
  /// y lo persiste con origen 'history'. Sin endpoint (versión antigua o
  /// sesión no resuelta): silencio — la línea viva sigue cubriendo la
  /// conversación de esta sesión.
  Future<void> _pullRemoteHistory() async {
    final runtime = _runtime;
    final conv = _conversation;
    if (runtime == null || conv == null) return;
    final sessionId = conv.canonicalSession ?? _controller?.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    // `profile` escota la lectura: la fila sólo la responde su backend dueño
    // (api/client.ts:231-247 sessionReadOwnerPin; sessions.ts:466-468).
    final msgs = await runtime.gateway.fetchSessionMessages(
      sessionId,
      profile: conv.kind == 'bot' ? conv.gatewayId : null,
    );
    if (msgs == null || msgs.isEmpty || !mounted) return;
    final database = AppServices.db;
    try {
      await database.batch((b) {
        b.deleteWhere<db.$MessagesTable, db.Message>(
          database.messages,
          (m) =>
              m.conversationId.equals(conv.id) & m.origin.equals('history'),
        );
        // Doble por DIRECCIÓN duradera, no por texto: `row_id` es la clave del
        // store (tui_gateway/contracts/common.py:169) y el ACK de
        // `prompt.submit` deja `user_row_id` en la línea viva, que se guarda
        // con el mismo id `gw:<row_id>` que usa el historial remoto. Comparar
        // textos duplicaba mensajes iguales y descartaba distintos.
        final seenRows = {
          for (final m in _live) m.gatewayRowId,
          for (final m in _history) m.gatewayRowId,
        }..remove(null);
        // `insertAllOnConflictUpdate`: dos páginas de historial pueden traer
        // la misma fila (paginación solapada) y el UNIQUE(id) reventaba el
        // lote entero — se perdían TODOS los mensajes, no el duplicado.
        b.insertAllOnConflictUpdate(
          database.messages,
          msgs.reversed
              .map((m) => _rowFromRemote(m, conv))
              .nonNulls
              .where(
                (r) => r.gatewayRowId.value == null ||
                    !seenRows.contains(r.gatewayRowId.value),
              )
              .toList(),
        );
      });
    } catch (e) {
      _log.warning('persist remote history failed', e);
    }
  }

  /// Fila de historial → registro local.
  ///
  /// Campos reales de `TranscriptMessage`
  /// (tui_gateway/contracts/common.py:158-176): `role`, `text`, `content`,
  /// `row_id`, `timestamp` (segundos float), `reasoning`, `tool_call_id`.
  /// No existen `created_at`/`ts`/`message_id`; el id duradero es `row_id`.
  db.MessagesCompanion? _rowFromRemote(
    Map<String, Object?> m,
    db.Conversation conv,
  ) {
    final role = m['role'] as String?;
    if (role != 'user' && role != 'assistant' && role != 'system') return null;
    final text = (m['text'] as String?) ?? m['content']?.toString();
    if (text == null || text.isEmpty) return null;
    final rowId = (m['row_id'] as num?)?.toInt();
    final ts = (m['timestamp'] as num?)?.toDouble();
    return db.MessagesCompanion.insert(
      id: rowId == null ? 'gw:${text.hashCode}' : 'gw:$rowId',
      conversationId: conv.id,
      connectionId: conv.connectionId,
      role: role!,
      text_: Value(text),
      gatewayRowId: Value(rowId),
      timestamp: Value(
        ts == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()),
      ),
      origin: const Value('history'),
    );
  }

  int _byTimestamp(db.Message a, db.Message b) {
    final at = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
    return at.compareTo(bt);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreHistory || _history.isEmpty) return;
    setState(() => _loadingOlder = true);
    final database = AppServices.db;
    final oldest = _history.first.timestamp ?? DateTime.now();
    final rows =
        await (
              database.select(database.messages)
                ..where(
                  (m) =>
                      m.conversationId.equals(widget.conversationId) &
                      m.origin.equals('history') &
                      m.timestamp.isSmallerThanValue(oldest),
                )
                ..orderBy([
                  (m) => OrderingTerm.desc(m.timestamp),
                  (m) => OrderingTerm.desc(m.rowId),
                ])
                ..limit(_pageSize + 1))
            .get();
    final hasMore = rows.length > _pageSize;
    final page = hasMore ? rows.sublist(0, _pageSize) : rows;
    page.sort(_byTimestamp);
    if (!mounted) return;
    setState(() {
      _history = [...page.reversed, ..._history];
      _hasMoreHistory = hasMore;
      _loadingOlder = false;
    });
    // Mantener la posición de lectura: el primer mensaje nuevo es el ancla.
    _preserveScrollAnchor(page.length);
  }

  void _preserveScrollAnchor(int addedCount) {
    if (!_scroll.hasClients || addedCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // Estábamos arriba (por eso se disparó la carga): mantener el primer
      // mensaje recién cargado visible.
      // Aproximación robusta: subir el delta máximo anterior si era ~0.
      if (_scroll.position.pixels < 2) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ── Scroll ────────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final nearBottom =
        pos.maxScrollExtent - pos.pixels <= _stickyBottomThreshold;
    if (nearBottom != _nearBottom && mounted) {
      setState(() => _nearBottom = nearBottom);
    }
    if (pos.pixels <= 120) _loadOlder();
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _nearBottom) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ── Borrador ──────────────────────────────────────────────────────────

  void _onDraftChanged(String text) {
    _draftTimer?.cancel();
    _draftTimer = Timer(_draftDebounce, _flushDraft);
  }

  Future<void> _flushDraft() async {
    _draftTimer?.cancel();
    try {
      await AppServices.db
          .into(AppServices.db.drafts)
          .insertOnConflictUpdate(
            db.DraftsCompanion.insert(
              conversationId: widget.conversationId,
              text_: Value(_input.text),
            ),
          );
    } catch (e) {
      _log.warning('draft save failed', e);
    }
  }

  // ── Envío ─────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final conv = _conversation;
    if (conv != null && conv.kind == 'group') {
      // Grupo hosted: el transporte es `groups.send` ( RoomsClient ), no una
      // sesión de bot. La sala vive en el gateway con room_id = conv.groupRoomId
      // (o conv.gatewayId para filas espejo sin id); el autor es server-owned.
      await _sendGroup(text);
      return;
    }
    // El 'Reintentar' de un SnackBar puede llegar DESPUÉS de dispose (la
    // acción del snackbar no cancela al morir la página): setState sobre un
    // State muerto lanza y el reintento jamás se envía.
    if (!mounted) return;
    setState(() {
      _sending = true;
      _hasError = false;
    });
    _input.clear();
    _flushDraft();
    _focus.requestFocus();
    final controller = _controller;
    if (controller == null) {
      // Sin gateway no hay transporte real: el texto vuelve al campo para
      // no perderlo y el estado queda en error reintentable.
      if (mounted) {
        setState(() {
          _sending = false;
          _hasError = true;
        });
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      }
      return;
    }
    try {
      await controller.send(text);
      if (mounted) setState(() => _sending = false);
    } on TimeoutException {
      // El turno SIGUE VIVO: el timeout es del ACK (prompt.submit contesta al
      // cierre del turno, no en la aceptación). No es un envío perdido: no se
      // devuelve el texto al composer ni se marca error. El stream y el cierre
      // (message.complete / session.interrupt) sellan la burbuja optimista.
      if (mounted) setState(() => _sending = false);
      _log.info('prompt ack timeout — turno en curso');
    } catch (e) {
      _log.warning('send failed', e);
      if (mounted) {
        setState(() {
          _sending = false;
          _hasError = true;
        });
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo enviar: ${e.toString().substring(0, e.toString().length.clamp(0, 140))}',
            ),
            action: SnackBarAction(
              label: 'Reintentar',
              onPressed: () => _send(),
            ),
          ),
        );
      }
    }
  }

  /// Envío a una hosted room. El `client_event_id` se guarda por turno: si el
  /// socket cae antes del ACK, el reintento REÚSA la misma pareja
  /// (event_id/thread_id) — idempotente server-side. Un retry con clave nueva
  /// duplicaría el mensaje.
  /// Envío de sala en vuelo: si el socket cae ANTES del ACK no sabemos si el
  /// servidor lo aceptó. NO se reintenta a ciegas ni se inventía un estado:
  /// la burbuja queda marcada como fallida y el reintento EXPLÍCITO del
  /// usuario reúsa la MISMA pareja (event_id, thread_id) — idempotente
  /// server-side (hosted_rooms: mismo event_id + mismo contenido = mismo
  /// evento). Si el usuario reescribe el texto, la clave cambia y es un
  /// mensaje nuevo.
  String? _groupPendingEventId;
  String? _groupPendingThreadId;
  String? _groupPendingRoomId;
  String? _groupPendingText;
  Future<void> _sendGroup(String text) async {
    final conv = _conversation;
    final runtime = _runtime;
    final roomId = conv?.groupRoomId ?? conv?.gatewayId;
    if (conv == null || runtime == null || roomId == null || roomId.isEmpty) {
      if (mounted) {
        setState(() => _hasError = true);
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      }
      return;
    }
    setState(() {
      _sending = true;
      _hasError = false;
    });
    _input.clear();
    _flushDraft();
    final client = RoomsClient(runtime.gateway);
    final isRetry = _groupPendingEventId != null &&
        _groupPendingRoomId == roomId &&
        text == _groupPendingText;
    try {
      if (isRetry) {
        // Reintento EXPLÍCITO del mismo texto: se reúsa la pareja guardada.
        final r0 = await client.send(roomId, text,
            clientEventId: _groupPendingEventId!,
            threadId: _groupPendingThreadId);
        _groupPendingEventId = _groupPendingThreadId = _groupPendingRoomId =
            _groupPendingText = null;
        await _roomAck(r0, text, conv, roomId);
        return;
      }
      final eventId = RoomsClient.newClientEventId();
      final threadId = RoomsClient.newThreadId();
      _groupPendingEventId = eventId;
      _groupPendingThreadId = threadId;
      _groupPendingRoomId = roomId;
      _groupPendingText = text;
      final r = await client.send(roomId, text,
          clientEventId: eventId, threadId: threadId);
      _groupPendingEventId = _groupPendingThreadId = _groupPendingRoomId =
          _groupPendingText = null;
      // La fila del autor es server-owned; la UI la pinta localmente ya y el
      // log de la sala (grupos.log / eventos room.event) la confirma al
      // reconectar. No se inventa `message.author` local.
      await _roomAck(r, text, conv, roomId);
    } catch (e) {
      // La pareja (event_id, thread_id) SEGURO pendiente: el reintento
      // explícito del mismo texto la reenvía (idempotente).
      _log.warning('group send failed', e);
      if (mounted) {
        setState(() {
          _sending = false;
          _hasError = true;
        });
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      }
    }
  }

  Future<void> _roomAck(
      Map<String, Object?>? r, String text, db.Conversation conv, String roomId) async {
    final ev = (r as Map?)?['event'];
    final evId = (ev as Map?)?['event_id'];
    if (mounted) {
      setState(() {
        _live = [..._live, ChatMessage(
          id: 'room-${evId ?? DateTime.now().microsecondsSinceEpoch}',
          path: EntityRefPath(
            connectionId: conv.connectionId,
            kind: EntityKind.group,
            gatewayId: roomId,
          ),
          role: MessageRole.user,
          text: text,
          sendState: SendState.sent,
          origin: MessageOrigin.live,
          timestamp: DateTime.now(),
          authorName: 'Tú',
        )];
        _sending = false;
      });
      _roomController.add(_live);
    }
  }

  void _showGroupNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Este grupo lo dirige Hermes Desktop. Escribe directamente a sus '
          'bots en la lista de chats.',
        ),
      ),
    );
  }

  Future<void> _interrupt() => _controller?.interrupt() ?? Future.value();

  bool get _isStreaming => _live.any((m) => m.streaming);

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final conv = _conversation;
    if (conv == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;
    final isGroup = conv.isGroup;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            BotAvatar(
              seed: conv.avatarSeed ?? conv.id,
              label: conv.title,
              size: 32,
              isGroup: isGroup,
            ),
            const SizedBox(width: Hp.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (_runtime != null)
                    StreamBuilder<GatewayLinkState>(
                      stream: _runtime!.gateway.stateStream,
                      initialData: _runtime!.gateway.state,
                      builder: (context, snapshot) {
                        final s = snapshot.data ?? GatewayLinkState.disconnected;
                        return Text(
                          _linkLabel(s),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: _linkColor(s)),
                          maxLines: 1,
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<List<ChatMessage>>(
                  // Salas hosted: no hay ChatSessionController; el timeline
                  // emite por su propio stream broadcast.
                  stream: _conversation?.kind == 'group'
                      ? _roomController.stream
                      : _controller?.stream,
                  initialData: _live,
                  builder: (context, snapshot) {
                    final live = snapshot.data ?? _live;
                    final all = [..._history.map(_fromRow), ...live];
                    if (all.isEmpty) return _emptyTimeline(cs);
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(
                        top: Hp.s4,
                        bottom: Hp.s6,
                      ),
                      itemCount:
                          all.length + (_hasMoreHistory || _loadingOlder ? 1 : 0),
                      itemBuilder: (context, index) {
                        final header =
                            _hasMoreHistory || _loadingOlder ? 1 : 0;
                        if (index == 0 && header == 1) {
                          return _olderIndicator();
                        }
                        final i = index - header;
                        final message = all[i];
                        final previous = i > 0 ? all[i - 1] : null;
                        // Burbujas de sesión sin autor (línea viva del bot):
                        // el avatar toma `path.gatewayId` ('default' → 'DE').
                        // El nombre visible del bot es `conv.title`; sin eso,
                        // la burbuja live se apellida distinto que su
                        // historial (que sí trae authorName).
                        final titled = message.authorName == null &&
                                !isGroup &&
                                message.role == MessageRole.assistant
                            ? message.copyWith(authorName: _conversation?.title)
                            : message;
                        return MessageBubble(
                          key: ValueKey(titled.id),
                          message: titled,
                          isGroup: isGroup,
                          showAuthor:
                              isGroup &&
                              titled.role == MessageRole.assistant &&
                              previous?.authorName != titled.authorName,
                        );
                      },
                    );
                  },
                ),
                if (!_nearBottom)
                  Positioned(
                    right: Hp.s4,
                    bottom: Hp.s4,
                    child: FloatingActionButton.small(
                      heroTag: 'chatScrollEnd',
                      onPressed: () {
                        setState(() => _nearBottom = true);
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      },
                      child: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ),
              ],
            ),
          ),
          _composer(cs),
        ],
      ),
    );
  }

  Widget _emptyTimeline(ColorScheme cs) {
    return Center(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(Hp.s8),
        child: Column(
          children: [
            Icon(Icons.forum_outlined, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: Hp.s4),
            Text(
              _conversation?.title ?? '',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Hp.s2),
            Text(
              _runtime == null
                  ? 'El gateway de esta conversación no está conectado. '
                      'Conéctalo en Ajustes para chatear.'
                  : 'Envía el primer mensaje.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _olderIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Hp.s4),
      child: Center(
        child: _loadingOlder
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _loadOlder,
                child: const Text('Cargar anteriores'),
              ),
      ),
    );
  }

  Widget _composer(ColorScheme cs) {
    final canCancel = _isStreaming && _controller != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Hp.s3, Hp.s2, Hp.s3, Hp.s3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: _onDraftChanged,
                decoration: const InputDecoration(hintText: 'Mensaje'),
              ),
            ),
            const SizedBox(width: Hp.s2),
            if (canCancel || _sending)
              IconButton.filledTonal(
                tooltip: 'Detener',
                // `_sending` cubre la espera del ACK: el turno YA corre en el
                // gateway aunque `message.start` no haya abierto segmento.
                // session.interrupt es idempotente; si el turno ya cerró, el
                // gateway responde not_interrupted y no pasa nada.
                onPressed: _interrupt,
                icon: const Icon(Icons.stop_rounded),
              )
            else if (_sending)
              const Padding(
                padding: EdgeInsets.all(Hp.s3),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else
              IconButton.filled(
                tooltip: _hasError ? 'Reintentar' : 'Enviar',
                onPressed: _send,
                icon: Icon(
                  _hasError
                      ? Icons.refresh_rounded
                      : Icons.arrow_upward_rounded,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  db.Conversation? get conv => _conversation;

  ChatMessage _fromRow(db.Message row) {
    var tools = const <ToolActivity>[];
    final raw = row.toolsJson;
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .whereType<Map>()
            .cast<Map<String, Object?>>();
        tools = list
            .map(
              (t) => ToolActivity(
                toolId: t['tool_id'] as String? ?? '',
                name: t['name'] as String? ?? '',
                argsText: t['args_text'] as String?,
                summary: t['summary'] as String?,
                running: t['running'] as bool? ?? false,
              ),
            )
            .toList(growable: false);
      } catch (e) {
        _log.warning('tools parse failed', e);
      }
    }
    return ChatMessage(
      id: row.id,
      path: EntityRefPath(
        connectionId: row.connectionId,
        kind: EntityKind.session,
        gatewayId: row.conversationId,
      ),
      role: MessageRole.values.firstWhere(
        (r) => r.name == row.role,
        orElse: () => MessageRole.system,
      ),
      authorName: row.authorName,
      authorConnectionId: row.authorConnectionId,
      text: row.text_,
      timestamp: row.timestamp,
      sendState: SendState.values.firstWhere(
        (s) => s.name == row.sendState,
        orElse: () => SendState.sent,
      ),
      origin: MessageOrigin.history,
      tools: tools,
    );
  }
}

String _linkLabel(GatewayLinkState s) => switch (s) {
  GatewayLinkState.ready => 'en línea',
  GatewayLinkState.connecting => 'conectando…',
  GatewayLinkState.reconnecting => 'reconectando…',
  GatewayLinkState.authExpired => 'sesión expirada',
  GatewayLinkState.error => 'error',
  GatewayLinkState.disconnected => 'sin conexión',
};

Color _linkColor(GatewayLinkState s) => switch (s) {
  GatewayLinkState.ready => Hp.online,
  GatewayLinkState.connecting || GatewayLinkState.reconnecting =>
    Hp.connecting,
  GatewayLinkState.authExpired || GatewayLinkState.error => Hp.error,
  GatewayLinkState.disconnected => Hp.offline,
};
