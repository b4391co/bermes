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

class ToolActivity {
  final String toolId;
  final String name;
  final String? argsText;
  final String? summary;
  final bool running;

  const ToolActivity({
    required this.toolId,
    required this.name,
    this.argsText,
    this.summary,
    required this.running,
  });

  ToolActivity copyWith({bool? running, String? summary}) => ToolActivity(
    toolId: toolId,
    name: name,
    argsText: argsText,
    running: running ?? this.running,
  );
}

/// Aprobación accionable (server-request `approval`).
class ApprovalRequest {
  final String requestId;
  final String sessionId;
  final String command;
  final String? description;
  final String? toolName;
  final List<ApprovalChoice> choices;
  final bool allowPermanent;
  final DateTime receivedAt;

  const ApprovalRequest({
    required this.requestId,
    required this.sessionId,
    required this.command,
    this.description,
    this.toolName,
    required this.choices,
    this.allowPermanent = false,
    required this.receivedAt,
  });
}

enum ApprovalChoice { once, session, always, deny }

/// Mensaje visible en la línea de tiempo.
class ChatMessage {
  final String id; // id local estable (row_id si viene del gateway)
  final EntityRefPath path; // a qué conversación pertenece
  final MessageRole role;
  final String? authorName; // autor en grupos (perfil/handle)
  final String? authorConnectionId; // gateway de origen del autor
  final String text;
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
  }) => ChatMessage(
    id: id,
    path: path,
    role: role,
    authorName: authorName ?? this.authorName,
    authorConnectionId: authorConnectionId ?? authorConnectionId,
    text: text ?? this.text,
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
