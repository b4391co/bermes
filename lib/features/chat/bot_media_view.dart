/// Visor y reproducción de los medios que UN BOT entregó en el chat
/// (etiquetas `MEDIA:` → MessageAttachment).
///
/// El binario se resuelve contra el gateway del mensaje —nunca contra
/// cualquiera— con `GET /api/fs/read-data-url?path=…&profile=…` (la misma
/// ruta que usa Desktop, files.py:901-922) y se cachea en el caché local
/// [cache_media] reutilizado del camino de imágenes.
///
/// - imagen: visor a pantalla completa con zoom (InteractiveViewer).
/// - vídeo/audio: reproductor inline con controles.
/// - documento/archivo: se materializa a un fichero temporal y se abre con
///   la app del sistema (open_filex) o se comparte.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_services.dart';
import '../../design/tokens.dart';
import '../../domain/message/chat_models.dart';
import '../../domain/message/media_tags.dart';
import 'media_cache.dart';

/// Abre el visor correspondiente al adjunto [attachment] del gateway
/// [connectionId]. Sin acceso al gateway o archivo no recuperable: ficha de
/// error, nunca un roto silencioso.
Future<void> openBotMedia(
  BuildContext context, {
  required MessageAttachment attachment,
  required String connectionId,
  String? profile,
}) async {
  final kind = mediaKindOf(attachment.path);
  switch (kind) {
    case 'image':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ImageViewerPage(
            attachment: attachment,
            connectionId: connectionId,
          ),
        ),
      );
    case 'video':
    case 'audio':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PlayerPage(
            attachment: attachment,
            connectionId: connectionId,
            profile: profile,
            isVideo: kind == 'video',
          ),
        ),
      );
    case 'pdf':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PdfViewerPage(
            attachment: attachment,
            connectionId: connectionId,
            profile: profile,
          ),
        ),
      );
    default:
      await _openWithSystem(context, attachment, connectionId, profile);
  }
}

Future<void> _openWithSystem(
  BuildContext context,
  MessageAttachment a,
  String connectionId,
  String? profile,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await materializeBotMedia(a, connectionId, profile);
    if (file == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El gateway no pudo entregar este archivo'),
        ),
      );
      return;
    }
    final r = await OpenFilex.open(file.path);
    if (r.type != ResultType.done && r.type != ResultType.noAppToOpen) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo abrir: ${r.message}')),
      );
    } else if (r.type == ResultType.noAppToOpen) {
      // Sin app asociada: ofrecer compartir como respaldo.
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error al abrir: $e')));
  }
}

/// Materializa el archivo del bot en un path local (caché o temporal) y lo
/// devuelve. null si el gateway no lo sirve.
Future<File?> materializeBotMedia(
  MessageAttachment a,
  String connectionId,
  String? profile,
) async {
  // ¿Ya en caché local?
  final cached = MediaCache.load(a.path);
  if (cached?.localBytes != null) {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'bermes', a.name));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(cached!.localBytes!);
    return f;
  }
  final runtime = AppServices.connections.runtimeFor(connectionId);
  if (runtime == null) return null;
  final res = await runtime.http.fetchFsDataUrl(
    a.path,
    profile: profile,
  );
  if (res == null) return null;
  final dir = await getTemporaryDirectory();
  final f = File(p.join(dir.path, 'bermes', a.name));
  await f.parent.create(recursive: true);
  await f.writeAsBytes(res.bytes);
  // Alimentar también el caché (vale para cualquier kind).
  await MediaCache.put(a, res.bytes);
  return f;
}

/// Miniatura para la burbuja: imagen precargada; vídeo con overlay de play;
/// audio con fila reproductible; resto con ficha de archivo.
class BotMediaTile extends StatelessWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  final bool onDark;
  const BotMediaTile({
    super.key,
    required this.attachment,
    required this.connectionId,
    this.profile,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = mediaKindOf(attachment.path);
    final fg = onDark ? cs.onPrimary : cs.onSurfaceVariant;
    switch (kind) {
      case 'image':
        return _ImageTile(
          attachment: attachment,
          connectionId: connectionId,
          onDark: onDark,
        );
      case 'video':
        return _VideoTile(
          attachment: attachment,
          connectionId: connectionId,
          profile: profile,
          onDark: onDark,
        );
      case 'pdf':
        return _PdfTile(
          attachment: attachment,
          connectionId: connectionId,
          profile: profile,
          onDark: onDark,
        );
      case 'audio':
        return _AudioTile(
          attachment: attachment,
          connectionId: connectionId,
          profile: profile,
          onDark: onDark,
        );
      default:
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openBotMedia(
            context,
            attachment: attachment,
            connectionId: connectionId,
            profile: profile,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Hp.s3,
              vertical: Hp.s2 + 2,
            ),
            decoration: BoxDecoration(
              color:
                  (onDark ? cs.onPrimary : cs.surfaceContainerHighest)
                      .withValues(alpha: onDark ? 0.12 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _fileIcon(attachment.name),
                  size: 20,
                  color: onDark ? cs.onPrimary : Colors.indigo,
                ),
                const SizedBox(width: Hp.s2),
                Flexible(
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onDark ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                ),
                if (attachment.bytes != null) ...[
                  const SizedBox(width: Hp.s2),
                  Text(
                    _human(attachment.bytes!),
                    style: TextStyle(fontSize: 11.5, color: fg),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  static IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (const {'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar'}.contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    if (const {'doc', 'docx', 'odt', 'rtf', 'txt', 'md'}.contains(ext)) {
      return Icons.description_rounded;
    }
    if (const {'xls', 'xlsx', 'csv', 'ods'}.contains(ext)) {
      return Icons.table_chart_rounded;
    }
    if (const {'apk', 'ipa'}.contains(ext)) return Icons.android_rounded;
    return Icons.insert_drive_file_rounded;
  }

  static String _human(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── imagen ──────────────────────────────────────────────────────────────

class _ImageTile extends StatefulWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final bool onDark;
  const _ImageTile({
    required this.attachment,
    required this.connectionId,
    this.onDark = false,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Uint8List?> _load() async {
    final a = widget.attachment;
    if (a.localBytes != null) return Uint8List.fromList(a.localBytes!);
    if (a.path.isEmpty || widget.connectionId.isEmpty) return null;
    // Primero el caché local (turnos previos ya resueltos):
    final cached = MediaCache.load(a.path);
    if (cached?.localBytes != null) return Uint8List.fromList(cached!.localBytes!);
    final runtime = AppServices.connections.runtimeFor(widget.connectionId);
    if (runtime == null) return null;
    // /api/media (imágenes bajo raíces del dashboard) y, si falla,
    // /api/fs/read-data-url (cualquier ruta del perfil) — misma cascada
    // que Desktop.
    final bytes =
        await runtime.http.fetchMedia(a.path) ??
        (await runtime.http.fetchFsDataUrl(a.path))?.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    await MediaCache.put(a, bytes);
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 190,
            height: 92,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final bytes = snap.data;
        if (bytes == null) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openBotMedia(
              context,
              attachment: widget.attachment,
              connectionId: widget.connectionId,
            ),
            child: Container(
              width: 190,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openBotMedia(
            context,
            attachment: widget.attachment,
            connectionId: widget.connectionId,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              bytes,
              width: 230,
              height: 230,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

class _ImageViewerPage extends StatelessWidget {
  final MessageAttachment attachment;
  final String connectionId;
  const _ImageViewerPage({
    required this.attachment,
    required this.connectionId,
  });

  @override
  Widget build(BuildContext context) {
    return _MediaScaffold(
      title: attachment.name,
      body: FutureBuilder<File?>(
        future: materializeBotMedia(attachment, connectionId, null),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final f = snap.data;
          if (f == null) {
            return const Center(child: Text('No se pudo cargar la imagen'));
          }
          return InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.file(f)),
          );
        },
      ),
    );
  }
}

// ── pdf ─────────────────────────────────────────────────────────────────

/// Ficha de PDF en la burbuja: icono + nombre; al tocar, visor integrado.
class _PdfTile extends StatelessWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  final bool onDark;
  const _PdfTile({
    required this.attachment,
    required this.connectionId,
    this.profile,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openBotMedia(
        context,
        attachment: attachment,
        connectionId: connectionId,
        profile: profile,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Hp.s3,
          vertical: Hp.s2 + 2,
        ),
        decoration: BoxDecoration(
          color: (onDark ? cs.onPrimary : cs.surfaceContainerHighest)
              .withValues(alpha: onDark ? 0.12 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 22,
              color: onDark ? cs.onPrimary : Colors.red.shade700,
            ),
            const SizedBox(width: Hp.s2),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onDark ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── vídeo / audio ───────────────────────────────────────────────────────

class _VideoTile extends StatefulWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  final bool onDark;
  const _VideoTile({
    required this.attachment,
    required this.connectionId,
    this.profile,
    this.onDark = false,
  });


  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Miniatura barata: sin frame grab, ficha oscura con icono grande. El
    // reproductor real se abre al tocar (no arrastrar un decoder en la
    // lista del chat).
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openBotMedia(
        context,
        attachment: widget.attachment,
        connectionId: widget.connectionId,
        profile: widget.profile,
      ),
      child: Container(
        width: 230,
        height: 130,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 44,
              color: cs.surface.withValues(alpha: 0.92),
            ),
            const SizedBox(height: Hp.s1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Hp.s2),
              child: Text(
                widget.attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.surface.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPage extends StatefulWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  final bool isVideo;
  const _PlayerPage({
    required this.attachment,
    required this.connectionId,
    this.profile,
    required this.isVideo,
  });

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  File? _file;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Salir de la app NO corta el audio del bot: pausa el vídeo y deja el
    // audio seguir (reproductor en segundo plano ya configurado por el
    // plugin). Al volver, el usuario retoma con los controles.
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
    }
  }

  Future<void> _init() async {
    try {
      final file = await materializeBotMedia(
        widget.attachment,
        widget.connectionId,
        widget.profile,
      );
      if (file == null) throw Exception('el gateway no entregó el archivo');
      if (!mounted) return;
      setState(() => _file = file);
      if (widget.isVideo) {
        final c = VideoPlayerController.file(file);
        await c.initialize();
        if (!mounted) {
          await c.dispose();
          return;
        }
        c.addListener(_onTick);
        setState(() => _video = c);
        c.play();
      } else {
        final a = AudioPlayer();
        await a.play(DeviceFileSource(file.path));
        if (!mounted) {
          await a.dispose();
          return;
        }
        setState(() => _audio = a);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            f.path,
            mimeType: widget.isVideo ? 'video/mp4' : 'audio/mpeg',
          ),
        ],
        subject: widget.attachment.name,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.removeListener(_onTick);
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MediaScaffold(
      title: widget.attachment.name,
      actions: _file == null
          ? const []
          : [
              IconButton(
                onPressed: _share,
                tooltip: 'Compartir / guardar',
                icon: const Icon(Icons.ios_share_rounded),
                color: Colors.white70,
              ),
            ],
      body: _error != null
          ? Center(
              child: Text(
                'No se pudo reproducir:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          : widget.isVideo
          ? _video == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _video!.value.aspectRatio,
                        child: VideoPlayer(_video!),
                      ),
                      VideoProgressIndicator(
                        _video!,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF3ECF8E),
                        ),
                      ),
                      _VideoControls(controller: _video!),
                    ],
                  )
          : const _AudioControls(),
    );
  }
}

/// Barra de controles del vídeo: play/pausa + tiempo. El scrubbing vive en
/// la barra de progreso (draggable).
class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  const _VideoControls({required this.controller});

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s3, vertical: Hp.s1),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                v.isPlaying ? controller.pause() : controller.play(),
            icon: Icon(
              v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          Text(
            _fmt(v.position),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: Slider(
              value: v.duration.inMilliseconds == 0
                  ? 0
                  : (v.position.inMilliseconds / v.duration.inMilliseconds)
                        .clamp(0.0, 1.0),
              onChanged: (f) => controller.seekTo(
                Duration(
                  milliseconds: (f * v.duration.inMilliseconds).round(),
                ),
              ),
            ),
          ),
          Text(
            _fmt(v.duration),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── andamiaje ───────────────────────────────────────────────────────────
class _MediaScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  const _MediaScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        backgroundColor: Colors.black,
        actions: actions,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _AudioTile extends StatelessWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  final bool onDark;
  const _AudioTile({
    required this.attachment,
    required this.connectionId,
    this.profile,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openBotMedia(
        context,
        attachment: attachment,
        connectionId: connectionId,
        profile: profile,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Hp.s3,
          vertical: Hp.s2 + 2,
        ),
        decoration: BoxDecoration(
          color: (onDark ? cs.onPrimary : cs.surfaceContainerHighest)
              .withValues(alpha: onDark ? 0.12 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 22,
              color: onDark ? cs.onPrimary : Colors.indigo,
            ),
            const SizedBox(width: Hp.s2),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onDark ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioControls extends StatelessWidget {
  const _AudioControls();

  @override
  Widget build(BuildContext context) {
    // Los controles del propio AudioPlayer no son widgets; para audio el
    // visor muestra una ficha con el nombre + barra indeterminada durante
    // la carga (reproducción inmediata en background al abrir).
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 48, color: Colors.white70),
          SizedBox(height: Hp.s2),
          Text('Reproduciendo…', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

// ── PDF ─────────────────────────────────────────────────────────────────

/// Visor de PDF integrado (flutter_pdfview). El binario se materializa
/// igual que el resto de medios (`/api/fs/read-data-url` del gateway del
/// mensaje) y se muestra aquí; compartir/guardar en la barra.
class _PdfViewerPage extends StatefulWidget {
  final MessageAttachment attachment;
  final String connectionId;
  final String? profile;
  const _PdfViewerPage({
    required this.attachment,
    required this.connectionId,
    this.profile,
  });

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  File? _file;
  String? _error;
  int _pages = 0;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _materialize();
  }

  Future<void> _materialize() async {
    try {
      final f = await materializeBotMedia(
        widget.attachment,
        widget.connectionId,
        widget.profile,
      );
      if (f == null) throw Exception('el gateway no entregó el archivo');
      if (mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _share() async {
    final f = _file;
    if (f == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'application/pdf')],
        subject: widget.attachment.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs(context),
      appBar: AppBar(
        title: Text(widget.attachment.name),
        actions: [
          IconButton(
            onPressed: _file == null ? null : _share,
            tooltip: 'Compartir / guardar',
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('No se pudo abrir:\n$_error'))
          : _file == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                PDFView(
                  filePath: _file!.path,
                  enableSwipe: true,
                  swipeHorizontal: true,
                  autoSpacing: true,
                  pageFling: true,
                  onPageChanged: (page, total) {
                    if (mounted) {
                      setState(() {
                        _page = (page ?? 0) + 1;
                        _pages = total ?? 0;
                      });
                    }
                  },
                ),
                if (_pages > 0)
                  Positioned(
                    bottom: Hp.s3,
                    right: Hp.s3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Hp.s2 + 2,
                        vertical: Hp.s1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_page / $_pages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static Color cs(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
}
