
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../design/tokens.dart';
import '../../domain/message/chat_models.dart';
import 'bot_media_view.dart';
import '../app_shell.dart' show BotAvatar;
import '../../design/live_avatar.dart';

/// Burbuja estilo Grok Bot: usuario derecha sobre tinta, bot izquierda sobre
/// superficie suave con avatar, markdown real y chips colapsables de tools.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isGroup;
  final bool showAuthor;

  /// Icono que le corresponde al autor (meta ui_meta.hermes-bots.avatar o
  /// data-url de profiles.get_asset): la burbuja muestra el dibujo real del
  /// bot, no iniciales genéricas.
  final String? avatarUrl;
  final String? avatarMetaJson;

  /// Conexión dueña del mensaje: necesaria para re-resolver las imágenes del
  /// historial contra su gateway (`GET /api/media`), no contra cualquiera.
  final String connectionId;

  const MessageBubble({
    super.key,
    required this.message,
    this.isGroup = false,
    this.showAuthor = false,
    this.connectionId = '',
    this.avatarUrl,
    this.avatarMetaJson,
  });

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system) return _systemNotice(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Hp.s2),
      child: Column(
        crossAxisAlignment: _isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (showAuthor && message.authorName != null)
            Padding(
              padding: const EdgeInsets.only(left: Hp.s6, bottom: Hp.s1),
              child: Text(
                message.authorName!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          _bubble(context),
        ],
      ),
    );
  }

  Widget _systemNotice(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = message.sendState == SendState.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Hp.s2),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 16,
            color: failed ? Hp.error : cs.onSurfaceVariant,
          ),
          const SizedBox(width: Hp.s2),
          Expanded(
            child: Text(
              message.text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: failed ? Hp.error : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Tema hermes-mobile: usuario = burbuja a la derecha; asistente =
    // tarjeta suave a la izquierda. El contraste entre ambas es de TONO
    // (no negro/blanco): en claro la burbuja del usuario pasa de tinta
    // casi negra a grafito suave legible.
    final userBubble = dark ? Hp.userBubbleDark : Hp.userBubbleLight;
    final fg = _isUser
        ? (dark ? Hp.userBubbleFgDark : Hp.userBubbleFgLight)
        : cs.onSurface;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.tools.isNotEmpty)
          ToolsChips(tools: message.tools, foreground: fg),
        if (message.attachments.isNotEmpty) ...[
          ImageStrip(
            attachments: message.attachments,
            connectionId: connectionId,
            onDark: _isUser && dark,
          ),
          const SizedBox(height: Hp.s2),
        ],
        if (message.text.isNotEmpty)
          GptMarkdown(
            message.text,
            style: TextStyle(color: fg, fontSize: 15, height: 1.5),
            // Streaming en vivo: nada de animación por carácter
            // (coste por token plano); el texto crece del stream.
            animation: GptMarkdownAnimation.none,
            isStreaming: message.streaming,
          ),
        _meta(context, fg),
      ],
    );

    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s4 + 2, vertical: Hp.s3 + 2),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        // Contraste por tono: usuario = grafito suave (Hp tokens), bot =
        // superficie baja. Ambos legibles sin el salto negro/blanco.
        color: _isUser ? userBubble : cs.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(Hp.rBubble),
          topRight: const Radius.circular(Hp.rBubble),
          bottomLeft: _isUser
              ? const Radius.circular(Hp.rBubble)
              : const Radius.circular(Hp.rSm),
          bottomRight: _isUser
              ? const Radius.circular(Hp.rSm)
              : const Radius.circular(Hp.rBubble),
        ),
      ),
      child: content,
    );

    // El avatar del bot queda centrado con la burbuja (Grok), no pegado
    return Row(
      mainAxisAlignment: _isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!_isUser) ...[
          LiveAvatar(
            size: 26,
            active: message.streaming,
            child: BotAvatar(
              seed: message.authorConnectionId ?? message.path.connectionId,
              label: message.authorName ?? message.path.gatewayId,
              size: 26,
              imageUrl: avatarUrl,
              avatarMetaJson: avatarMetaJson,
            ),
          ),
          const SizedBox(width: Hp.s3),
        ],
        Flexible(
          child: body,
        ),
        if (_isUser) const SizedBox(width: Hp.s2),
      ],
    );
  }

  Widget _meta(BuildContext context, Color fg) {
    if (message.streaming) {
      return Padding(
        padding: const EdgeInsets.only(top: Hp.s1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('escribiendo…', style: _metaStyle(context, fg))],
        ),
      );
    }
    final state = message.sendState;
    if (!_isUser || state == SendState.sent) return const SizedBox.shrink();
    final failed = state == SendState.failed;
    return Padding(
      padding: const EdgeInsets.only(top: Hp.s1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
            size: 13,
            color: failed ? Hp.error : fg.withValues(alpha: 0.6),
          ),
          const SizedBox(width: Hp.s1),
          Text(switch (state) {
            SendState.sending => 'enviando',
            SendState.failed => 'error — toca reintentar',
            SendState.cancelled => 'cancelado',
            _ => '',
          }, style: _metaStyle(context, failed ? Hp.error : fg)),
        ],
      ),
    );
  }

  TextStyle _metaStyle(BuildContext context, Color base) => Theme.of(
    context,
  ).textTheme.labelSmall!.copyWith(color: base.withValues(alpha: 0.7));
}

/// Actividad de herramientas como chips colapsables: "🔧 nombre — summary".
/// El chip está abierto cuando la tool corre; se pliega al completar.
class ToolsChips extends StatefulWidget {
  final List<ToolActivity> tools;
  final Color foreground;

  const ToolsChips({super.key, required this.tools, required this.foreground});

  @override
  State<ToolsChips> createState() => _ToolsChipsState();
}

class _ToolsChipsState extends State<ToolsChips> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final runningCount = widget.tools.where((t) => t.running).length;
    final label = runningCount > 0
        ? 'usando ${widget.tools.length} herramienta${widget.tools.length == 1 ? '' : 's'}…'
        : 'usó ${widget.tools.length} herramienta${widget.tools.length == 1 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Hp.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Hp.rSm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 15,
                  color: widget.foreground.withValues(alpha: 0.7),
                ),
                const SizedBox(width: Hp.s1),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: widget.foreground.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            for (final t in widget.tools)
              Padding(
                padding: const EdgeInsets.only(left: Hp.s3, top: Hp.s1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.running)
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    else
                      Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: widget.foreground.withValues(alpha: 0.7),
                      ),
                    const SizedBox(width: Hp.s2),
                    Flexible(
                      child: Text(
                        _toolLabel(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.foreground.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// Nombre amable del DM bot→bot: la herramienta `message_agent` es el
  /// turno interno con otro agente — se traduce a «Esperando a `target`…»
  /// (target del args JSON; si no, «otro agente»).
  static String _toolLabel(ToolActivity t) {
    final base = t.summary == null || t.summary!.isEmpty
        ? t.name
        : '${t.name} — ${t.summary}';
    if (t.name != 'message_agent') return base;
    if (base != t.name) {
      // Ya hay summary del backend (ack/reply): respetarlo.
      return t.running ? 'Esperando a ${t.target ?? 'otro agente'}…' : base;
    }
    return t.running
        ? 'Esperando a ${t.target ?? 'otro agente'}…'
        : 'DM con ${t.target ?? 'otro agente'}';
  }
}

/// Miniaturas de las imágenes de un turno.
///
/// Render verificado en main (BackendContracts, files.py:301-339):
/// - el historial proyecta la imagen como texto `@image:<ruta>` SIN bytes
///   (`session_history.py::_user_image_display_text`), así que re-resolver
///   es obligatorio, no una optimización;
/// - `GET /api/media?path=…` responde JSON `{data_url: "data:<mime>;base64,…"}`
///   (no binario), sólo imágenes, y restringido a las raíces
///   `<HERMES_HOME>/{images,screenshots,cache}` del proceso dashboard: en
///   multiperfil la imagen de OTRO perfil puede dar 403;
/// - por eso `localBytes` (turno recién enviado) pinta inmediato y, si no
///   hay bytes ni ruta legible, queda la ficha con nombre: nunca un roto.
class ImageStrip extends StatelessWidget {
  final List<MessageAttachment> attachments;
  final String connectionId;
  final bool onDark;
  const ImageStrip({
    super.key,
    required this.attachments,
    required this.connectionId,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Hp.s2,
      runSpacing: Hp.s2,
      children: [
        for (final a in attachments)
          // Un solo camino: BotMediaTile resuelve CUALQUIER medio — imagen
          // (cascada /api/media → /api/fs/read-data-url, como Desktop: en
          // multiperfil /api/media puede dar 403 fuera de sus raíces),
          // vídeo, audio o archivo.
          BotMediaTile(
            attachment: a,
            connectionId: connectionId,
            onDark: onDark,
          ),
      ],
    );
  }
}
