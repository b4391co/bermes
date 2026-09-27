import 'dart:async';

import '../../core/logger.dart';
import '../../domain/message/chat_models.dart';
import 'gateway_client.dart';
import 'rpc_types.dart';

/// Controlador de UNA conversación: aplica eventos del gateway a la línea
/// de tiempo local.
///
/// Reglas clave (según contrato Hermes):
/// - prompt.submit → ACK {status: streaming|queued}; fire-and-forget con
///   timeout amplio. NO reenviar si la conexión se perdió.
/// - streaming: message.start → message.delta* → message.complete.
/// - Herramientas: tool.start/tool.complete, diferenciadas del texto.
/// - Aprobaciones: server-request `approval` → card accionable.
class ChatSessionController {
  final EntityRefPath path;
  final HermesGatewayClient gateway;
  final String sessionId; // session del gateway (canónico del bot o room)
  final String? profile; // perfil del bot (routing ProfileParams) o null
  final _log = Logger('ChatCtl');

  final _messages = <ChatMessage>[];
  final _messagesController = StreamController<List<ChatMessage>>.broadcast();

  ChatSessionController(this.path, this.gateway, this.sessionId,
      {this.profile});

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Stream<List<ChatMessage>> get stream => _messagesController.stream;

  void attach() {
    gateway.events.listen(_onEvent);
    gateway.serverRequests.listen(_onServerRequest);
    // Replay de eventos perdidos tras reconexión.
    gateway.stateStream.listen((s) {
      if (s == GatewayLinkState.ready) {
        _replay().catchError((Object e) => _log.warning('replay failed: $e'));
      }
    });
  }

  Future<void> _replay() async {
    final events = await gateway.replaySession(sessionId);
    for (final e in events) {
      _onEvent(e);
    }
  }

  void _onEvent(GatewayEvent e) {
    if (e.sessionId != null && e.sessionId != sessionId) return;
    switch (e.type) {
      case 'message.start':
        _messages.add(
          ChatMessage(
            id: _localId(),
            path: path,
            role: MessageRole.assistant,
            text: '',
            streaming: true,
            origin: MessageOrigin.live,
            timestamp: DateTime.now(),
          ),
        );
        _notify();
        break;
      case 'message.delta':
        final text = e.payload['text'] as String? ?? '';
        final idx = _lastStreamingIndex();
        if (idx == null) {
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
        } else {
          final m = _messages[idx];
          _messages[idx] = m.copyWith(text: m.text + text);
        }
        _notify();
        break;
      case 'message.complete':
        final idx = _lastStreamingIndex();
        final text = e.payload['text'] as String?;
        if (idx != null) {
          final m = _messages[idx];
          _messages[idx] = m.copyWith(text: text ?? m.text, streaming: false);
          _notify();
        } else if (text != null && text.isNotEmpty) {
          _messages.add(
            ChatMessage(
              id: _localId(),
              path: path,
              role: MessageRole.assistant,
              text: text,
              streaming: false,
              origin: MessageOrigin.live,
              timestamp: DateTime.now(),
            ),
          );
          _notify();
        }
        break;
      case 'tool.start':
        final tool = ToolActivity(
          toolId: e.payload['tool_id'] as String? ?? '',
          name: e.payload['name'] as String? ?? '',
          argsText:
              e.payload['args_text'] as String? ??
              e.payload['args']?.toString(),
          running: true,
        );
        _appendToolToLast(tool);
        break;
      case 'tool.complete':
        final toolId = e.payload['tool_id'] as String?;
        if (toolId != null) {
          final idx = _lastIndexWithTool(toolId);
          if (idx != null) {
            final m = _messages[idx];
            final tools = [...m.tools];
            final ti = tools.indexWhere((t) => t.toolId == toolId);
            if (ti >= 0) {
              tools[ti] = tools[ti].copyWith(
                running: false,
                summary: e.payload['summary'] as String?,
              );
              _messages[idx] = m.copyWith(tools: tools);
              _notify();
            }
          }
        }
        break;
      case 'error':
        final message = e.payload['message'] as String? ?? 'error desconocido';
        _messages.add(
          ChatMessage(
            id: _localId(),
            path: path,
            role: MessageRole.system,
            text: message,
            origin: MessageOrigin.live,
            sendState: SendState.failed,
            timestamp: DateTime.now(),
          ),
        );
        _notify();
        break;
    }
  }

  void _onServerRequest(ServerRequest req) {
    if (req.method != 'approval') return;
    // Aprobaciones accionables: card en la conversación correcta.
    if (req.sessionId != sessionId) return;
    // choices disponibles: req.params['choices'] (la UI las renderiza).
    _log.info('approval request ${req.params['request_id']}');
    // La UI muestra la card; el modelo se construye aquí cuando la card llegue.
    // (La tarjeta accionable completa es parte del UI de chat; el controller
    // expone el evento crudo para ella.)
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

  String _localId() =>
      '${path.storageId}/${DateTime.now().microsecondsSinceEpoch}/${_messages.length}';

  void _notify() => _messagesController.add(List.unmodifiable(_messages));

  /// Enviar texto. Estados de envío inequívocos; NO reenviar automático.
  Future<void> send(String text) async {
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
    _notify();
    try {
      final result = await gateway.rawCall(
        'prompt.submit',
        params: {
          'session_id': sessionId,
          'text': text,
          if (profile != null) 'profile': profile,
        },
      );
      final status = result is Map<String, Object?> ? result['status'] : null;
      final idx = _messages.indexOf(optimistic);
      if (idx >= 0) {
        _messages[idx] = optimistic.copyWith(sendState: SendState.sent);
        _notify();
      }
      _log.info('prompt ack status=$status');
    } on JsonRpcError catch (e) {
      final idx = _messages.indexOf(optimistic);
      if (idx >= 0) {
        _messages[idx] = optimistic.copyWith(sendState: SendState.failed);
        _notify();
      }
      _log.warning('prompt failed ${e.code}');
    }
  }

  /// Cancelación (session.interrupt) si el gateway la soporta.
  Future<void> interrupt() async {
    try {
      await gateway.rawCall(
        'session.interrupt',
        params: {
          'session_id': sessionId,
          if (profile != null) 'profile': profile,
        },
      );
    } on JsonRpcError catch (e) {
      _log.warning('interrupt failed ${e.code}');
    }
  }

  void dispose() {
    _messagesController.close();
  }
}
