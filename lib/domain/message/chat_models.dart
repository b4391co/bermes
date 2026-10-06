import 'dart:convert';

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

  /// Target del DM bot→bot (`message_agent`): `target` del args JSON.
  String? get target {
    final a = argsText;
    if (a == null || a.isEmpty) return null;
    try {
      final m = jsonDecode(a);
      if (m is Map) return m['target']?.toString();
    } catch (_) {}
    return null;
  }

  ToolActivity copyWith({bool? running, String? summary, double? durationS}) =>
      ToolActivity(
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

/// Imagen adjunta a un turno vía `image.attach_bytes`
/// (tui_gateway/contracts/prompt_voice.py:120-131: el contenido va en
/// base64, los magic bytes deciden el tipo; AttachedImageResult :92-101
/// devuelve `path`). La imagen queda EN COLA para el siguiente turno: se
/// adjunta ANTES de `prompt.submit`. `localBytes` es el respaldo del
/// selector para pintar sin depender de la URL de lectura del gateway.
class MessageAttachment {
  final String path; // path gateway-visible devuelto por attach
  final String name;
  final int? bytes;

  /// Miniatura en RAM (bytes del selector local). No se persiste: tras
  /// reiniciar la app, la imagen se re-resuelve contra el gateway.
  final List<int>? localBytes;

  const MessageAttachment({
    required this.path,
    required this.name,
    this.bytes,
    this.localBytes,
  });

  MessageAttachment withLocalBytes(List<int>? b) => MessageAttachment(
    path: path,
    name: name,
    bytes: bytes,
    localBytes: b ?? localBytes,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    if (bytes != null) 'bytes': bytes,
  };

  static MessageAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return MessageAttachment(
      path: path,
      name: raw['name'] as String? ?? path.split('/').last,
      bytes: (raw['bytes'] as num?)?.toInt(),
    );
  }

  static List<MessageAttachment> decodeJson(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(fromJson)
          .whereType<MessageAttachment>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  static String? encodeJson(List<MessageAttachment> atts) =>
      atts.isEmpty ? null : jsonEncode(atts.map((a) => a.toJson()).toList());
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

  /// Imágenes adjuntas del turno (ver MessageAttachment). Vacío en mensajes
  /// sin adjuntos y en todo lo que no sea chat 1-a-1 con bots.
  final List<MessageAttachment> attachments;

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
    this.attachments = const [],
    this.streaming = false,
  });

  ChatMessage copyWith({
    String? text,
    SendState? sendState,
    List<ToolActivity>? tools,
    List<MessageAttachment>? attachments,
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
    attachments: attachments ?? this.attachments,
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
