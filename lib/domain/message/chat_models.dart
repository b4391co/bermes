import '../../domain/entity/entity_ref.dart';

/// Modelo de mensaje de chat.
///
/// Unifica: mensajes de usuario, respuestas en streaming, actividad de
/// herramientas (diferenciada del texto), aprobaciones y estados de envío.

enum MessageRole { user, assistant, system, tool }

/// Estados de envío inequívocos.
enum SendState { drafting, sending, sent, failed, cancelled }

/// Cómo se recibió/aplicó este mensaje localmente.
enum MessageOrigin { history, live, optimistic, local }

/// Actividad de herramienta (`ToolStartPayload` :4492-4500 /
/// `ToolCompletePayload` :4502-4514).
class ToolActivity {
  final String toolId;
  final String name;
  final String? argsText;
  final String? preview;
  final String? summary;
  final double? durationS;
  final bool running;

  const ToolActivity({
    required this.toolId,
    required this.name,
    this.argsText,
    this.preview,
    this.summary,
    this.durationS,
    required this.running,
  });

  ToolActivity copyWith({
    bool? running,
    String? summary,
    double? durationS,
  }) => ToolActivity(
    toolId: toolId,
    name: name,
    argsText: argsText,
    preview: preview,
    summary: summary ?? this.summary,
    durationS: durationS ?? this.durationS,
    running: running ?? this.running,
  );
}

/// Aprobación accionable (server-request `approval`).
///
/// `serverRequestId` es el id del FRAME JSON-RPC (`srq-<uuid12>`,
/// tui_gateway/server_requests.py:49): la respuesta va contra ÉL, no como RPC
/// nuevo. `requestId` es la clave de la cola de approvals del agente
/// (ApprovalRequestParams.request_id) y sólo la usa el RPC de fallback
/// `approval.respond`.
class ApprovalRequest {
  final String? serverRequestId;
  final String? requestId;
  final String sessionId;
  final String command;
  final String? description;
  final String? toolName;
  final List<ApprovalChoice> choices;
  final bool allowPermanent;
  final DateTime receivedAt;

  const ApprovalRequest({
    this.serverRequestId,
    this.requestId,
    required this.sessionId,
    required this.command,
    this.description,
    this.toolName,
    required this.choices,
    this.allowPermanent = false,
    required this.receivedAt,
  });
}

/// ApprovalChoice = 'once' | 'session' | 'always' | 'deny'
/// (apps/shared/src/gateway-contract.generated.ts:1486, :4233).
enum ApprovalChoice {
  once('once'),
  session('session'),
  always('always'),
  deny('deny');

  const ApprovalChoice(this.wire);
  final String wire;
}

/// Alambre → enum; null para valores que el contrato no define (nunca se
/// inventa una opción que el backend no ofreció).
ApprovalChoice? approvalChoiceFromWire(Object? raw) {
  for (final c in ApprovalChoice.values) {
    if (c.wire == raw) return c;
  }
  return null;
}

/// Mensaje visible en la línea de tiempo.
class ChatMessage {
  final String id; // id local estable (row_id si viene del gateway)
  final EntityRefPath path; // a qué conversación pertenece
  final MessageRole role;
  final String? authorName; // autor en grupos (perfil/handle)
  final String? authorConnectionId; // gateway de origen del autor
  final String text;

  /// Razón acumulada de `reasoning.delta` / `thinking.delta` /
  /// `reasoning.available` (StreamDeltaPayload, generated contract :4411-4416).
  final String? reasoning;

  /// `user_row_id` del ACK de `prompt.submit`
  /// (tui_gateway/contracts/prompt_voice.py:68-70): dirección duradera de la
  /// fila en el store del perfil. Con ella el optimista se descuenta contra el
  /// historial REST (`row_id` de TranscriptMessage) en vez de por texto.
  final int? gatewayRowId;
  final DateTime? timestamp;
  final SendState sendState;
  final MessageOrigin origin;
  final List<ToolActivity> tools;
  final bool streaming;

  const ChatMessage({
    required this.id,
    required this.path,
    required this.role,
    this.authorName,
    this.authorConnectionId,
    required this.text,
    this.reasoning,
    this.gatewayRowId,
    this.timestamp,
    this.sendState = SendState.sent,
    this.origin = MessageOrigin.history,
    this.tools = const [],
    this.streaming = false,
  });

  ChatMessage copyWith({
    String? text,
    SendState? sendState,
    List<ToolActivity>? tools,
    bool? streaming,
    String? authorName,
    DateTime? timestamp,
    String? reasoning,
    int? gatewayRowId,
  }) => ChatMessage(
    id: id,
    path: path,
    role: role,
    authorName: authorName ?? this.authorName,
    authorConnectionId: authorConnectionId ?? this.authorConnectionId,
    text: text ?? this.text,
    reasoning: reasoning ?? this.reasoning,
    gatewayRowId: gatewayRowId ?? this.gatewayRowId,
    timestamp: timestamp ?? this.timestamp,
    sendState: sendState ?? this.sendState,
    origin: origin,
    tools: tools ?? this.tools,
    streaming: streaming ?? this.streaming,
  );
}

/// Ruta a una conversación: conexión + tipo + id del gateway.
class EntityRefPath {
  final String connectionId;
  final EntityKind kind;
  final String gatewayId; // profile name | room_id | session_id

  const EntityRefPath({
    required this.connectionId,
    required this.kind,
    required this.gatewayId,
  });

  String get storageId => '$connectionId/${kind.name}/$gatewayId';
}

/// Conversación (bot canónico o grupo).
class Conversation {
  final EntityRefPath path;
  final String title;
  final String? subtitle; // descripción del bot, miembros del grupo
  final String? avatarSeed; // seed de color/avatar
  final String? avatarUrl; // data-url del avatar real si hay
  final bool isGroup;
  final String? gatewayLabel; // etiqueta discreta para desambiguar
  final DateTime? lastActivity;
  final String? preview;
  final int unreadCount;
  final String? connectionStatusChip; // estado visible cuando aplica

  const Conversation({
    required this.path,
    required this.title,
    this.subtitle,
    this.avatarSeed,
    this.avatarUrl,
    this.isGroup = false,
    this.gatewayLabel,
    this.lastActivity,
    this.preview,
    this.unreadCount = 0,
    this.connectionStatusChip,
  });

  Conversation copyWith({
    String? title,
    String? preview,
    DateTime? lastActivity,
    int? unreadCount,
    String? gatewayLabel,
    String? avatarUrl,
    String? connectionStatusChip,
  }) => Conversation(
    path: path,
    title: title ?? this.title,
    subtitle: subtitle,
    avatarSeed: avatarSeed ?? avatarSeed,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isGroup: isGroup,
    gatewayLabel: gatewayLabel ?? this.gatewayLabel,
    lastActivity: lastActivity ?? this.lastActivity,
    preview: preview ?? this.preview,
    unreadCount: unreadCount ?? this.unreadCount,
    connectionStatusChip: connectionStatusChip ?? this.connectionStatusChip,
  );
}
