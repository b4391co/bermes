import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:file_picker/file_picker.dart';
import '../../core/notify.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../clients/hermes/chat_session_controller.dart';
import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
import 'media_cache.dart';
import 'mention_menu.dart';
import 'voice_recorder.dart';
import '../screen/screen_controller.dart';
import '../screen/screen_view.dart';
import '../../clients/hermes/rooms_client.dart';
import '../../clients/hermes/rpc_types.dart';
import '../../core/app_services.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart' as db;
import '../../design/tokens.dart';
import '../../domain/entity/entity_ref.dart';
import '../../domain/message/chat_models.dart';
import '../../design/live_avatar.dart';
import '../../domain/message/media_tags.dart';
import '../app_shell.dart' show BotAvatar;
import 'chat_info_sheet.dart';
import 'message_bubble.dart';

/// Chat de UNA conversación (bot canónico o grupo de un gateway).
///
/// - Cablea [ChatSessionController] de verdad cuando hay runtime: replay en
///   vivo, envío optimista, streaming progresivo y cancelación.
/// - Historial local desde la tabla Messages (paginado hacia arriba).
/// - Borrador persistido en Drafts con guardado con debounce.
/// - Scroll anclado al fondo solo cuando el usuario está cerca del fondo.
class ChatScreen extends StatefulWidget {
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
  final _focus = FocusNode();
  final _input = TextEditingController();
  List<MentionCandidate> _mentionShown = const [];
  int _mentionStart = -1;
  int _mentionCaret = -1;

  Timer? _draftTimer;
  bool _loadingOlder = false;
  bool _hasMoreHistory = true;
  bool _nearBottom = true;

  bool _sending = false;
  final VoiceRecorder _voice = VoiceRecorder();

  /// Imágenes seleccionadas pendientes de adjuntar al próximo turno (bots).
  List<MessageAttachment> _pending = const [];

  bool _hasError = false;

  ChatSessionController? _controller;
  StreamSubscription<List<ChatMessage>>? _liveSub;
  List<ChatMessage> _live = const [];
  final _roomController = StreamController<List<ChatMessage>>.broadcast();

  db.Conversation? _conversation;
  List<db.Message> _history = const [];

  /// Título recibido por `session.title` (renombrado desde otro cliente).
  String? _titleOverride;

  /// display name del autor de grupo → (meta avatar, data-url). Lo llena
  /// [_loadConversation] con los bots sincronizados.
  Map<String, (String?, String?)> _botAvatars = const {};

  /// Runtime del gateway de esta conversación (null = sólo historial).
  ConnectionRuntime? _runtime;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // La caché resuelve rutas síncronas en _fromRow: hay que tener el
    // directorio antes de la primera página de historial.
    unawaited(MediaCache.warm());
    Notifier.visibleConversationId = widget.conversationId;
    _loadConversation();
  }

  @override
  void dispose() {
    if (Notifier.visibleConversationId == widget.conversationId) {
      Notifier.visibleConversationId = null;
    }
    _removeMentionOverlay();
    _draftTimer?.cancel();
    _liveSub?.cancel();
    _roomSub?.cancel();
    // El controller se suscribe al gateway en attach(): sin dispose, cada
    // re-adjunto (sesión recién resuelta, reentrada al chat) dejaría un
    // listener vivo aplicando eventos sobre una página muerta.
    _controller?.dispose();
    unawaited(_roomController.close());
    // El panel Screen embebido vive con el chat: su lease y sus streams se
    // liberan aquí (al cerrar el chat), no al pop de una ruta.
    final screen = _screen;
    _screen = null;
    if (screen != null) {
      unawaited(screen.releaseLease().whenComplete(screen.dispose));
    }
    unawaited(_voice.dispose());
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Carga ─────────────────────────────────────────────────────────────

  Future<void> _loadConversation() async {
    final database = AppServices.db;
    final row = await (database.select(
      database.conversations,
    )..where((c) => c.id.equals(widget.conversationId))).getSingleOrNull();
    if (!mounted) return;
    if (row == null) {
      _log.warning('conversation not found ${widget.conversationId}');
      Navigator.of(context).maybePop();
      return;
    }
    // Icono que le corresponde a cada autor: para el chat 1:1 basta la meta
    // de la propia conversación; en grupos se resuelve por display name del
    // miembro contra los bots sincronizados (identity real = perfil backend,
    // pero el log de la sala sólo expone display_name/handle).
    final botRows = await (database.select(
      database.conversations,
    )..where((c) => c.kind.equals('bot'))).get();
    if (!mounted) return;
    setState(() {
      _botAvatars = {
        for (final r in botRows)
          if (r.title.isNotEmpty && r.botAvatarMeta != null)
            r.title: (r.botAvatarMeta, r.avatarUrl),
      };
    });
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
        runtime.gateway.resumeCanonicalSession(conv.gatewayId).then((id) async {
          if (!mounted) return;
          if (id == null) return; // sin Bot Chat aún: el send dará causa.
          await (AppServices.db.update(AppServices.db.conversations)
                ..where((c) => c.id.equals(conv.id)))
              .write(db.ConversationsCompanion(canonicalSession: Value(id)));
          _reattachWithSession(id);
          _loadHistory();
        }),
      );
      sendSession = null;
    }
    if (conv.kind == 'group') {
      // Salas hosted: el timeline es `groups.log` + eventos `room.event`.
      // Sala sin roomId (clave `name:` del espejo): el gateway NO la hospeda
      // (groups.state/log → 4112/4114, verificado contra 0.21.5 real). Su
      // historia vive incrustada en el espejo y la persiste syncGroupMirrors
      // en la tabla messages; no hay canal en vivo ni log que pedir.
      if (conv.groupRoomId != null) {
        _startRoomLog();
      } else {
        // Menciones desde los miembros persistidos (no hay roomState).
        unawaited(
          _loadMentionCandidates(
            RoomsClient(runtime.gateway),
            conv.gatewayId,
            persistedOnly: true,
          ),
        );
      }
      return;
    }
    _startController(path, sendSession, runtime);
  }

  int _roomLastSeq = 0;
  StreamSubscription<GatewayEvent>? _roomSub;
  bool _roomLoading = false;
  bool _roomLogLoaded = false;

  /// Miembros de la sala para el autocompletado `@` (sólo grupos).
  List<MentionCandidate> _mentionCandidates = const [];

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
    // fallo real. Se espera el ready, y si la primera pasada falla (enlace
    // caído/tarde) se REINTENTA en cada transición a ready hasta cargar el
    // log — abrir un grupo con el gateway aún conectando ya no queda vacío.
    unawaited(_roomLogWithRetry(client, roomId));
    unawaited(_loadMentionCandidates(client, roomId));
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

  /// Carga los miembros de la sala (handle + display name + avatar) para el
  /// autocompletado `@`. El nombre que se inserta es el que el backend del
  /// grupo escucha para dirigir el turno (handle de `RelayAgentRow` /
  /// display name); los perfiles propios del usuario no se listan.
  Future<void> _loadMentionCandidates(
    RoomsClient client,
    String roomId, {
    bool persistedOnly = false,
  }) async {
    List<MentionCandidate> out = const [];
    if (persistedOnly) {
      // Sala sin roomId (clave `name:` del espejo): el gateway NO la hospeda
      // (groups.state → 4112) — los miembros vienen del espejo, persistidos
      // por syncGroupMirrors en groupMembersJson.
      final raw = _conversation?.groupMembersJson;
      if (raw == null || raw.isEmpty) return;
      final bots = [
        for (final m in (jsonDecode(raw) as List).whereType<Map>())
          // El mencionable es lo que el gateway escucha: el handle
          // (`RelayAgentRow.handle`); con homónimos entre gateways el handle
          // lleva el sufijo del origen (default-boneca / default-claudio).
          (m.cast<String, Object?>())['handle'] ??
              (m.cast<String, Object?>())['display_name'] ??
              (m.cast<String, Object?>())['title'] ??
              (m.cast<String, Object?>())['name'],
      ].whereType<String>().toList();
      if (mounted) {
        setState(() {
          _mentionCandidates = [
            for (final name in bots)
              MentionCandidate(
                name: name,
                avatarMeta: _botAvatars[name]?.$1,
                avatarUrl: _botAvatars[name]?.$2,
              ),
          ];
        });
      }
      return;
    }
    for (var attempt = 0; attempt < 6; attempt++) {
      final gw = _runtime?.gateway;
      if (gw == null || !mounted) return;
      try {
        await gw.readyOrTimeout(const Duration(seconds: 30));
        final room = await client.roomState(roomId);
        if (room == null) return;
        final bots = room.members.toList(growable: false);
        // Avatar desde el roster sincronizado (misma clave que las burbujas).
        out = [
          for (final m in bots)
            MentionCandidate(
              name: m.displayName ?? m.handle ?? m.profile!,
              avatarMeta: _botAvatars[m.displayName ?? '']?.$1,
              avatarUrl: _botAvatars[m.displayName ?? '']?.$2,
            ),
        ];
        if (out.isNotEmpty) break;
      } catch (_) {
        // enlace no ready / gateway sin groups.*: reintentar en la próxima
        // transición a ready; si nunca llega, sin autocompletado (el texto
        // libre con @ sigue funcionando).
      }
      try {
        await gw.stateStream.firstWhere((s) => s == GatewayLinkState.ready);
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    setState(() => _mentionCandidates = out);
  }

  /// Carga `groups.log` con reintentos anclados a las transiciones del
  /// enlace a `ready`. La primera pasada puede pillarse el arranque del
  /// shell (bootstrap en paralelo); sin esto el grupo quedaba vacío hasta
  /// re-abrirlo.
  Future<void> _roomLogWithRetry(RoomsClient client, String roomId) async {
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!mounted) return;
      final gw = _runtime?.gateway;
      if (gw == null) return;
      try {
        await gw.readyOrTimeout(const Duration(seconds: 30));
        if (_roomLogLoaded) return; // otro reintento ya lo cargó
        await _loadRoomLog(client, roomId);
        if (_roomLogLoaded) return;
      } catch (e) {
        lastError = e;
      }
      // Esperar la siguiente transición a ready antes de reintentar.
      try {
        await gw.stateStream.firstWhere((s) => s == GatewayLinkState.ready);
      } catch (_) {
        return;
      }
    }
    if (lastError != null) {
      _log.warning('room log load falló (definitivo)', lastError);
    }
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
          .where((e) => e.kind == 'message.user' || e.kind == 'message.member')
          .map((e) => _roomMessage(conv, roomId, e.raw))
          .toList();
      _roomLogLoaded = true;
      if (mounted) setState(() => _live = msgs);
      _roomController.add(_live);
    } catch (e) {
      // Gateway sin groups.* (versión antigua): el chat queda vacío y el
      // envío reportará la causa real.
      _log.warning('groups.log no disponible', e);
      rethrow;
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
    // Rename desde otro cliente (Desktop): `session.title` -> título vivo.
    controller.onSessionTitle = (t) {
      if (!mounted) return;
      setState(() => _titleOverride = t);
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
        b.insertAllOnConflictUpdate(
          database.messages,
          live.map(_rowFrom).toList(),
        );
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
        m.tools.isEmpty ? null : jsonEncode(m.tools.map(_toolToJson).toList()),
      ),
      // Sólo rutas/nombres: los bytes se re-resuelven contra el gateway
      // (GET /api/media → data_url); no se duplica el binario en la BD.
      attachmentsJson: Value(MessageAttachment.encodeJson(m.attachments)),
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
        await (AppServices.db.select(AppServices.db.drafts)
              ..where((d) => d.conversationId.equals(widget.conversationId)))
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
          (m) => m.conversationId.equals(conv.id) & m.origin.equals('history'),
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
                (r) =>
                    r.gatewayRowId.value == null ||
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
    var text = (m['text'] as String?) ?? m['content']?.toString();
    final rowId = (m['row_id'] as num?)?.toInt();
    final ts = (m['timestamp'] as num?)?.toDouble();
    // El asistente DELIVERA archivos con etiquetas `MEDIA: <ruta>` en su
    // texto (contrato de Desktop, parts.ts). Aquí se separan: la fila
    // guarda el texto limpio + adjuntos; la burbuja los pinta como medios.
    String? attachmentsJson;
    if (role == 'assistant') {
      final split = splitAssistantMedia(text ?? '');
      text = split.text;
      if (split.media.isNotEmpty) {
        attachmentsJson = MessageAttachment.encodeJson(split.media);
      }
    }
    if (text == null || (text.isEmpty && attachmentsJson == null)) return null;
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
      attachmentsJson: Value(attachmentsJson),
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
        await (database.select(database.messages)
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
    _updateMention();
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
    final attachments = _pending;
    if ((text.isEmpty && attachments.isEmpty) || _sending) return;
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
    setState(() => _pending = const []);
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
      await controller.send(text, attachments: attachments);
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
          // Las imágenes vuelven a la bandeja: un reintento las readjunta.
          // Las que ya llegaron al gateway (path no vacío) se re-hidratan
          // desde la caché local; las no enviadas conservan sus bytes.
          _pending = [
            for (final a in attachments)
              if (a.localBytes != null) a else (MediaCache.load(a.path) ?? a),
          ];
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
    final isRetry =
        _groupPendingEventId != null &&
        _groupPendingRoomId == roomId &&
        text == _groupPendingText;
    try {
      if (isRetry) {
        // Reintento EXPLÍCITO del mismo texto: se reúsa la pareja guardada.
        final r0 = await client.send(
          roomId,
          text,
          clientEventId: _groupPendingEventId!,
          threadId: _groupPendingThreadId,
        );
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
      final r = await client.send(
        roomId,
        text,
        clientEventId: eventId,
        threadId: threadId,
      );
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
    Map<String, Object?>? r,
    String text,
    db.Conversation conv,
    String roomId,
  ) async {
    final ev = (r as Map?)?['event'];
    final evId = (ev as Map?)?['event_id'];
    if (mounted) {
      setState(() {
        _live = [
          ..._live,
          ChatMessage(
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
          ),
        ];
        _sending = false;
      });
      _roomController.add(_live);
    }
  }

  // (2026-10-01) _showGroupNotice eliminado: los grupos hosted (room-1) son
  // ESCRIBIBLES por diseño (grupos multi-gateway: este requisito y Desktop
  // operan la misma sala vía groups.*). Mantener un aviso de «sólo Desktop»
  // contradice el requisito §5; la protección CAS ya vive en el guardado.

  Future<void> _interrupt() => _controller?.interrupt() ?? Future.value();

  bool get _isStreaming => _live.any((m) => m.streaming);

  // ── UI ────────────────────────────────────────────────────────────────

  /// Cabecera → sheet de info (identidad + ajustes: modelo del bot,
  /// miembros del grupo).
  /// Screen embebida en el chat: mitad escritorio / mitad conversación.
  /// El botón del AppBar alterna el panel; la barra del panel maximiza el
  /// escritorio (oculta el chat) o lo restaura. El controlador vive aquí
  /// para que el lease sobreviva a maximizar/restaurar, y se libera al
  /// salir del chat.
  ScreenController? _screen;
  bool _screenMaximized = false;

  void _toggleScreen() {
    final conv = _conversation;
    if (conv == null) return;
    if (_screen != null) {
      setState(() {
        _screen?.dispose();
        _screen = null;
        _screenMaximized = false;
      });
      return;
    }
    final target = screenTarget(conv);
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Necesito la conexión de este bot abierta para ver su pantalla.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _screen = ScreenController(
        runtime: target.runtime,
        profile: target.profile,
        viewerId: 'hp-${DateTime.now().millisecondsSinceEpoch}',
      );
      _screenMaximized = false;
    });
  }

  void _openInfo() {
    final conv = _conversation;
    if (conv == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ChatInfoSheet(conversation: conv, runtime: _runtime),
    );
  }

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
        title: InkWell(
          onTap: _openInfo,
          child: Row(
            children: [
              LiveAvatar(
                size: 32,
                active: _isStreaming,
                child: BotAvatar(
                  seed: conv.avatarSeed ?? conv.id,
                  label: conv.title,
                  size: 32,
                  isGroup: isGroup,
                  imageUrl: conv.avatarUrl,
                  avatarMetaJson: conv.botAvatarMeta,
                ),
              ),
              const SizedBox(width: Hp.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _titleOverride ?? conv.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Hp.s1),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (_runtime != null)
                      StreamBuilder<GatewayLinkState>(
                        stream: _runtime!.gateway.stateStream,
                        initialData: _runtime!.gateway.state,
                        builder: (context, snapshot) {
                          final s =
                              snapshot.data ?? GatewayLinkState.disconnected;
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
        actions: [
          if (!isGroup)
            IconButton(
              tooltip: _screen == null
                  ? 'Ver pantalla del bot'
                  : 'Ocultar pantalla del bot',
              onPressed: _toggleScreen,
              icon: Icon(
                _screen == null
                    ? Icons.desktop_windows_outlined
                    : Icons.desktop_windows_rounded,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_screen != null && _screenMaximized)
            Expanded(
              child: ScreenView(
                controller: _screen!,
                botTitle: _titleOverride ?? conv.title,
                mode: ScreenViewMode.pane,
                maximized: true,
                onToggleMaximize: () =>
                    setState(() => _screenMaximized = false),
              ),
            )
          else ...[
            if (_screen != null) ...[
              // Mitad y mitad: escritorio arriba, conversación abajo.
              Expanded(
                child: ScreenView(
                  controller: _screen!,
                  botTitle: _titleOverride ?? conv.title,
                  mode: ScreenViewMode.pane,
                  onToggleMaximize: () =>
                      setState(() => _screenMaximized = true),
                ),
              ),
              const Divider(height: 1),
            ],
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
                            all.length +
                            (_hasMoreHistory || _loadingOlder ? 1 : 0),
                        itemBuilder: (context, index) {
                          final header = _hasMoreHistory || _loadingOlder
                              ? 1
                              : 0;
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
                          final titled =
                              message.authorName == null &&
                                  !isGroup &&
                                  message.role == MessageRole.assistant
                              ? message.copyWith(
                                  authorName: _conversation?.title,
                                )
                              : message;
                          // Icono del autor: en 1:1 la meta del bot de la
                          // conversación; en grupos, la del bot sincronizado
                          // con ese display name (fallback: iniciales).
                          final (authorMeta, authorUrl) = isGroup
                              ? (_botAvatars[titled.authorName] ?? (null, null))
                              : (
                                  _conversation?.botAvatarMeta,
                                  _conversation?.avatarUrl,
                                );
                          return MessageBubble(
                            key: ValueKey(titled.id),
                            message: titled,
                            isGroup: isGroup,
                            connectionId: conv.connectionId,
                            showAuthor:
                                isGroup &&
                                titled.role == MessageRole.assistant &&
                                previous?.authorName != titled.authorName,
                            avatarUrl: authorUrl,
                            avatarMetaJson: authorMeta,
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
          ],
          StreamBuilder<List<ApprovalRequest>>(
            stream: _controller?.approvalStream,
            initialData: _controller?.approvals,
            builder: (context, snap) {
              final approvals = snap.data ?? const <ApprovalRequest>[];
              if (approvals.isEmpty) return const SizedBox.shrink();
              return _approvalBand(cs, approvals);
            },
          ),
          _composer(cs),
          _mentionHost(),
        ],
      ),
    );
  }

  /// Anfitrión del menú de menciones: se pinta DESPUÉS del composer y
  /// gestiona el `OverlayEntry` que muestra el follower (la aserción de
  /// FollowerLayer exige leader antes que follower en orden de pintado;
  /// el overlay de la Scaffold se pinta después del body).
  Widget _mentionHost() {
    return Builder(
      builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_mentionOpen) {
            _ensureMentionOverlay(context);
          } else {
            _removeMentionOverlay();
          }
        });
        return const SizedBox.shrink();
      },
    );
  }

  OverlayEntry? _mentionOverlay;

  void _ensureMentionOverlay(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    if (_mentionOverlay != null) return;
    _mentionOverlay = OverlayEntry(
      builder: (_) => PositionedDirectional(
        start: 0,
        bottom: 0,
        width: MediaQuery.sizeOf(context).width,
        child: CompositedTransformFollower(
          link: _composerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(8, -8),
          child: _mentionMenuWidget(),
        ),
      ),
    );
    overlay.insert(_mentionOverlay!);
  }

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
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

  /// Banda de aprobaciones pendientes (server-request `approval`).
  /// Los botones cubren EXACTAMENTE las `choices` que el gateway envió
  /// (server.py:733-743: once/session/always según allow_session/
  /// allow_permanent, + deny siempre). La respuesta viaja por el frame de
  /// resultado del server-request; `approval.respond` sólo como fallback.
  Widget _approvalBand(ColorScheme cs, List<ApprovalRequest> approvals) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in approvals)
            Padding(
              padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, Hp.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.gpp_maybe_outlined,
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: Hp.s2),
                      Expanded(
                        child: Text(
                          a.toolName == null
                              ? 'El bot pide aprobación'
                              : 'Aprobación: ${a.toolName}',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (a.command.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Hp.s1),
                      child: Text(
                        a.command,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (a.description != null && a.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Hp.s1),
                      child: Text(
                        a.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: Hp.s2),
                  Wrap(
                    spacing: Hp.s2,
                    children: [
                      for (final choice in a.choices)
                        FilledButton.tonal(
                          onPressed: () => _answerApproval(a, choice),
                          style: choice == ApprovalChoice.deny
                              ? FilledButton.styleFrom(
                                  foregroundColor: cs.error,
                                )
                              : null,
                          child: Text(switch (choice) {
                            ApprovalChoice.once => 'Permitir una vez',
                            ApprovalChoice.session => 'Permitir sesión',
                            ApprovalChoice.always => 'Permitir siempre',
                            ApprovalChoice.deny => 'Denegar',
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _answerApproval(ApprovalRequest a, ApprovalChoice c) async {
    try {
      await _controller?.answerApproval(a, c);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo responder: $e')));
    }
  }

  Widget _composer(ColorScheme cs) {
    // El botón Enviar se habilita según el contenido del campo. _input NO
    // dispara setState (onChanged sólo guarda el borrador con debounce y abre
    // el menú de menciones): sin escuchar al controlador, tras restaurar un
    // borrador o teclear sin ningún otro evento de estado, el botón quedaba
    // deshabilitado para siempre con texto visible.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final hasInput = value.text.trim().isNotEmpty || _pending.isNotEmpty;
        final canCancel = _isStreaming && _controller != null;
        final isBot = _conversation?.kind == 'bot';
        return SafeArea(
          top: false,
          child: CompositedTransformTarget(
            link: _composerLink,
            child: Container(
              padding: const EdgeInsets.fromLTRB(Hp.s3, Hp.s2, Hp.s3, Hp.s3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pending.isNotEmpty) _pendingStrip(cs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isBot) ...[
                        IconButton(
                          tooltip: 'Adjuntar imagen',
                          onPressed: _sending ? null : _pickImage,
                          icon: const Icon(Icons.image_outlined),
                        ),
                        IconButton(
                          tooltip:
                              'Nota de voz (se transcribe con el STT del '
                              'gateway; el audio NO se guarda en el chat)',
                          onPressed: _sending ? null : _recordVoiceNote,
                          icon: const Icon(Icons.mic_rounded),
                        ),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          onChanged: _onDraftChanged,
                          decoration: const InputDecoration(
                            hintText: 'Mensaje',
                          ),
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
                      else
                        IconButton.filled(
                          tooltip: _hasError ? 'Reintentar' : 'Enviar',
                          // Sin texto pero con imágenes pendientes también se
                          // puede enviar: la imagen EN COLA constituye el turno.
                          onPressed: _sending || (!hasInput && !_hasError)
                              ? null
                              : _send,
                          icon: Icon(
                            _hasError
                                ? Icons.refresh_rounded
                                : Icons.arrow_upward_rounded,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Miniaturas pendientes de adjuntar, con botón de quite.
  Widget _pendingStrip(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Hp.s2),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (_, _) => const SizedBox(width: Hp.s2),
          itemBuilder: (context, i) {
            final a = _pending[i];
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    Uint8List.fromList(a.localBytes!),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip: 'Quitar ${a.name}',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: cs.scrim.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => setState(
                      () => _pending = List.of(_pending)..removeAt(i),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Nota de voz (bots) ────────────────────────────────────────────────
  //
  // Flujo verificado (docs/research/adjuntos-y-notas-de-voz.md §B): no hay
  // tipo «nota de voz» en el contrato. Se graba local (m4a/AAC), se manda a
  // `POST /api/audio/transcribe` (web_models.py:84-86: `{data_url, mime_type}`;
  // respuesta `{ok, transcript, provider}`) y AL CHAT SÓLO VIAJA EL TEXTO.
  // La UI lo dice: nada de «audio enviado», nada de reproductor.

  Future<void> _recordVoiceNote() async {
    final started = DateTime.now();
    try {
      await _voice.start();
    } on VoiceRecordingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    } on Object catch (e) {
      _log.warning('grabación no arrancó', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el micrófono.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final action = await showDialog<VoiceNoteAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VoiceSheet(recorder: _voice),
    );
    if (action != VoiceNoteAction.keep) {
      await _voice.cancel();
      return;
    }
    VoiceRecording rec;
    try {
      rec = await _voice.stop();
    } on VoiceRecordingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    final runtime = _runtime;
    if (runtime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin gateway: no hay con quién transcribir.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final res = await runtime.http.transcribeAudio(
      rec.bytes,
      mimeType: rec.mimeType,
    );
    if (!mounted) return;
    if (!res.ok) {
      // Diagnóstico por causa (STT sin configurar ≠ red ≠ sesión muerta).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.detail ??
                'La transcripción falló (${res.cause?.name ?? 'desconocido'})',
          ),
        ),
      );
      return;
    }
    final draft = _input.text.trim();
    final text = draft.isEmpty ? res.text : '$draft\n${res.text}';
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _flushDraft();
    _log.info(
      'transcrito ${rec.bytes.length}B en '
      '${DateTime.now().difference(started).inSeconds}s '
      '(proveedor ${res.provider ?? '?'})',
    );
    if (mounted) _focus.requestFocus();
  }

  /// Selector de imagen (bots). `file_picker` en Android usa el
  /// document-provider (no hace falta permiso de almacenamiento); en
  /// Windows abre el diálogo nativo. Límite propio de 8 MB: el techo real
  /// del gateway es 25 MB por attach (prompt_attachments.py:18-20), así que
  /// el Pocket impone el suyo, más conservador, y lo anuncia.
  Future<void> _pickImage() async {
    // file_picker 13: `pickFiles` devuelve List<PlatformFile> (vacío = el
    // usuario canceló) y NO tiene allowMultiple en esta versión: un pick por
    // imagen (la bandeja admite varias acumuladas). `readAsBytes()` resuelve
    // el content:// de SAF en Android y el file:// de Windows.
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.image);
    } catch (e) {
      _log.warning('file picker falló', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El selector de archivos no está disponible'),
        ),
      );
      return;
    }
    if (picked.isEmpty || !mounted) return;
    const maxBytes = 8 * 1024 * 1024;
    final added = <MessageAttachment>[];
    var rejected = 0;
    for (final f in picked) {
      final declared = f.lengthSync();
      if (declared != null && declared > maxBytes) {
        rejected++;
        continue;
      }
      final Uint8List bytes;
      try {
        bytes = await f.readAsBytes();
      } on Object catch (e) {
        // SAF revocado / fichero movido (patrón de avatar_image.dart).
        _log.warning('lectura del picker falló', e);
        rejected++;
        continue;
      }
      if (bytes.isEmpty || bytes.length > maxBytes) {
        rejected++;
        continue;
      }
      added.add(
        MessageAttachment(
          // path se llena al adjuntar de verdad (respuesta del gateway).
          path: '',
          name: f.name,
          bytes: bytes.length,
          localBytes: bytes,
        ),
      );
    }
    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ninguna imagen cabía en el límite (8 MB).'),
        ),
      );
      return;
    }
    setState(() => _pending = [..._pending, ...added]);
    if (rejected > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rejected == 1
                ? '1 imagen superaba el límite de 8 MB.'
                : '$rejected imágenes superaban el límite de 8 MB.',
          ),
        ),
      );
    }
  }

  // ── Autocompletado de menciones (grupos) ────────────────────────────────

  final _composerLink = LayerLink();

  // ── Autocompletado de menciones (grupos) ────────────────────────────────

  bool _mentionOpen = false;

  /// El caret está dentro de un token `@…`: muestra el menú filtrado.
  /// El menú se pinta INLINE sobre el composer (Stack del propio _composer):
  /// depende de enlaces de overlay que con rootOverlay no se pintaban.
  void _updateMention() {
    final caret = _input.selection.isValid
        ? _input.selection.baseOffset
        : _input.text.length;
    final start = MentionToken.mentionStart(_input.text, caret);
    if (start == null || _mentionCandidates.isEmpty || !_focus.hasFocus) {
      _setMention(open: false);
      return;
    }
    final query = _input.text.substring(start + 1, caret).toLowerCase();
    final shown = _mentionCandidates
        .where((m) => m.name.toLowerCase().contains(query))
        .toList(growable: false);
    if (shown.isEmpty) {
      _setMention(open: false);
      return;
    }
    _setMention(open: true, start: start, caret: caret, shown: shown);
  }

  void _setMention({
    required bool open,
    int start = -1,
    int caret = -1,
    List<MentionCandidate> shown = const [],
  }) {
    final same =
        _mentionOpen == open &&
        _mentionStart == start &&
        _mentionCaret == caret &&
        _mentionShown.length == shown.length;
    if (same) return;
    setState(() {
      _mentionOpen = open;
      _mentionStart = start;
      _mentionCaret = caret;
      if (shown.isNotEmpty) _mentionShown = shown;
    });
  }

  Widget _mentionMenuWidget() {
    if (!_mentionOpen) return const SizedBox.shrink();
    return ConstrainedBox(
      // El ancho real lo dan las constraints del LayoutBuilder al hacer
      // layout (ver el Builder anidado): maxHeight acota el scroll.
      constraints: const BoxConstraints(maxHeight: 220),
      child: Builder(
        builder: (context) {
          return SizedBox(
            width: MediaQuery.sizeOf(context).width - 32.0,
            child: MentionMenu(candidates: _mentionShown, onPick: _pickMention),
          );
        },
      ),
    );
  }

  void _pickMention(MentionCandidate m) {
    final (text, caret) = MentionToken.replace(
      _input.text,
      _mentionStart,
      _mentionCaret,
      m.name,
    );
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: caret);
    _setMention(open: false);
    _draftTimer?.cancel();
    _flushDraft();
    _focus.requestFocus();
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
      // Caché multimedia local (cache_media): si este dispositivo ya bajó
      // la imagen, la miniatura sale sin tocar la red (ver ImageStrip).
      attachments: MessageAttachment.decodeJson(row.attachmentsJson)
          .map((a) => a.localBytes == null ? (MediaCache.load(a.path) ?? a) : a)
          .toList(),
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
  GatewayLinkState.connecting || GatewayLinkState.reconnecting => Hp.connecting,
  GatewayLinkState.authExpired || GatewayLinkState.error => Hp.error,
  GatewayLinkState.disconnected => Hp.offline,
};

/// Resultado de la hoja de grabación.
enum VoiceNoteAction { keep, discard }

class _VoiceSheet extends StatefulWidget {
  final VoiceRecorder recorder;
  const _VoiceSheet({required this.recorder});

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // La hoja se abre DESPUÉS de start(): el timer del recorder ya corre.
    _elapsed = widget.recorder.lastElapsed;
    _sub = widget.recorder.elapsed.listen((d) {
      if (mounted) setState(() => _elapsed = d);
    });
  }

  late final StreamSubscription<Duration> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  String get _label {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Grabando nota de voz'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 44, color: Hp.error),
          const SizedBox(height: Hp.s2),
          Text(
            _label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Hp.s2),
          Text(
            'Al soltar, el audio se transcribe con el STT del gateway y '
            'puedes editar el texto antes de enviarlo. El audio no se guarda.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, VoiceNoteAction.discard),
          child: const Text('Descartar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, VoiceNoteAction.keep),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
