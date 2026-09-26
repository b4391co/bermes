import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../clients/hermes/chat_session_controller.dart';
import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
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
    _controller?.dispose();
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
    final controller = ChatSessionController(
      path,
      runtime.gateway,
      conv.gatewayId,
    );
    controller.attach();
    _liveSub = controller.stream.listen(_onLive);
    setState(() {
      _controller = controller;
      _live = controller.messages;
    });
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
        b.deleteWhere<db.$MessagesTable, db.Message>(
          database.messages,
          (m) =>
              m.conversationId.equals(conv.id) &
              m.origin.equals('live'),
        );
        b.insertAll(database.messages, live.map(_rowFrom).toList());
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
    final database = AppServices.db;
    final query = database.select(database.messages)
      ..where(
        (m) =>
            m.conversationId.equals(widget.conversationId) &
            m.origin.equals('history'),
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
                  stream: _controller?.stream,
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
                        return MessageBubble(
                          key: ValueKey(message.id),
                          message: message,
                          isGroup: isGroup,
                          showAuthor:
                              isGroup &&
                              message.role == MessageRole.assistant &&
                              previous?.authorName != message.authorName,
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
            if (canCancel)
              IconButton.filledTonal(
                tooltip: 'Detener',
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
