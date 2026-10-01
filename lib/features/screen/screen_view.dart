import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../design/tokens.dart';
import 'screen_controller.dart';

/// Convierte la base HTTP del gateway en la URL del WS de pantalla.
/// Mismo patrón que `sibling-ws-url.ts` de Hermes Desktop; el ticket viaja en
/// QUERY a propósito (web_routers/display.py: noVNC no negocia subprotocolos).
String buildDisplayWsUrl(String httpBaseUrl, String path, String ticket) {
  final base = httpBaseUrl
      .replaceFirst(RegExp(r'^https'), 'wss')
      .replaceFirst(RegExp(r'^http'), 'ws');
  return '$base$path?display_ticket=${Uri.encodeQueryComponent(ticket)}';
}

/// Visor Screen del bot: RFB (VNC) sobre el WebSocket del gateway, con los
/// controles de lease de Hermes Desktop (Observar / Tomar control / Devolver).
class ScreenView extends StatefulWidget {
  final ScreenController controller;
  final String botTitle;

  const ScreenView({
    super.key,
    required this.controller,
    required this.botTitle,
  });

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

class _ScreenViewState extends State<ScreenView> {
  late final WebViewController _web;
  final _statusKey = GlobalKey<_ScreenStateBadgeState>();

  StreamSubscription<ScreenStatus>? _statusSub;
  StreamSubscription<Map<String, Object?>>? _eventSub;
  String _message = 'Preparando escritorio…';
  bool _viewerReady = false;

  /// El visor controla (lease humano) → teclado/ratón vivos; si no, view-only.
  bool _controlling = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ScreenBridge',
        onMessageReceived: (m) => widget.controller.handleViewerEvent(m.message),
      )
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (p >= 100) setState(() => _viewerReady = true);
          },
          onWebResourceError: (e) {
            if (!mounted) return;
            setState(() => _message = 'Error del visor: ${e.description}');
          },
        ),
      );
    // Android: sin gestos nativos (el canvas de noVNC se los come) y zoom
    // desactivado; el resto de plataformas usa los defaults.
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    unawaited(_loadViewer());

    _statusSub = widget.controller.changes.listen((s) {
      if (!mounted) return;
      setState(() {});
      if (!s.running) {
        setState(() => _message = _messageFor(s));
      }
    });
    _eventSub = widget.controller.viewerEvents.listen(_onViewerEvent);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final st = await widget.controller.refresh();
      if (!mounted) return;
      setState(() => _message = _messageFor(st));
      if (st.state == 'stopped' || st.state == 'error') {
        // No se arranca el escritorio por sorpresa: el usuario decide
        // (recursos del host). El botón Iniciar está en la barra.
        return;
      }
      await _startViewer();
    } catch (e) {
      if (mounted) setState(() => _message = 'El gateway no responde: $e');
    }
  }

  /// Servir el visor por http local: `index.html` importa
  /// `novnc.bundle.js` como módulo ES y Chromium bloquea los módulos
  /// cargados por `file://` (CORS: origin 'null'). Se levanta un servidor
  /// shelf en un puerto libre de loopback, se sirve la carpeta de assets y
  /// se carga desde ahí. El WS del gateway se abre igual (origen http ≠
  /// origen file: los gateways reales ya lo manejan — noVNC nunca negoció
  /// subprotocolos, ver hermes-map §6).
  HttpServer? _viewerServer;
  final Map<String, Uint8List> _viewerCache = {};

  Future<Uint8List?> _viewerAsset(String key) async {
    return _viewerCache[key] ??= (await rootBundle.load(key)).buffer.asUint8List();
  }

  Future<void> _loadViewer() async {
    try {
      _viewerServer ??= await shelf_io.serve((shelf.Request req) async {
        final seg = req.url.pathSegments.last;
        final body = await _viewerAsset('assets/screen/$seg') ??
            await _viewerAsset('assets/screen/index.html');
        if (body == null) return shelf.Response.notFound('no viewer');
        return shelf.Response.ok(
          body,
          headers: {
            'Content-Type':
                seg.endsWith('.js') ? 'text/javascript' : 'text/html',
          },
        );
      }, InternetAddress.loopbackIPv4, 0);
      final port = _viewerServer!.port;
      await _web.loadRequest(Uri.parse('http://127.0.0.1:$port/index.html'));
    } catch (e) {
      if (mounted) setState(() => _message = 'No se pudo preparar el visor: $e');
    }
  }

  /// Pedir ticket fresco y abrir la RFB. El ticket es single-use 30 s: se
  /// observa → se conecta de inmediato.
  Future<void> _startViewer() async {
    try {
      setState(() => _message = 'Conectando con el escritorio…');
      final obs = await widget.controller.observe();
      final url = buildDisplayWsUrl(
        // base HTTP del perfil: el mismo que usa el cliente (sin credenciales).
        widget.controller.runtime.profile.baseUrl,
        obs.path,
        obs.ticket,
      );
      await _web.runJavaScript(
        "window.connectScreen && window.connectScreen(${_json({
              'wsUrl': url,
              'viewOnly': !(widget.controller.status?.humanControls ?? false) &&
                  !_controlling,
            })});",
      );
    } catch (e) {
      if (mounted) setState(() => _message = 'No se pudo abrir la pantalla: $e');
    }
  }

  static String _jsonEscape(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  static String _json(Map<String, Object?> m) {
    final parts = m.entries.map((x) {
      final v = x.value;
      final encoded = v is String
          ? _jsonEscape(v)
          : (v is bool ? v.toString() : 'null');
      return '"${x.key}": $encoded';
    });
    return '{${parts.join(',')}}';
  }

  void _onViewerEvent(Map<String, Object?> m) {
    if (!mounted) return;
    switch (m['event']) {
      case 'connected':
        setState(() => _message = '');
      case 'disconnected':
        final code = m['code'];
        final reason = m['reason'];
        if (code == 4000 || reason == 'control-taken') {
          // El último takeover gana (web_routers/display.py:74-105): volver a
          // observar con ticket fresco y sin control.
          setState(() {
            _controlling = false;
            _message = 'Otro cliente tomó el control. Volviendo a observar…';
          });
          unawaited(
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) _startViewer();
            }),
          );
        } else if (code == 4001) {
          setState(() {
            _controlling = false;
            _message = 'El escritorio del bot se detuvo.';
          });
        } else {
          setState(() {
            _controlling = false;
            _message = 'Desconectado ($code).';
          });
        }
      case 'credentialsrequired':
        // El RFB del bot-desktop no pide password (el ticket es la auth).
        setState(() => _message = 'El visor pidió credenciales inesperadas.');
    }
  }

  String _messageFor(ScreenStatus s) => switch (s.state) {
    'stopped' => 'El escritorio del bot está parado.',
    'starting' => 'Iniciando el escritorio…',
    'installing' => 'Instalando el entorno de escritorio en el host…',
    'error' => 'Error en el escritorio: ${s.error ?? 'desconocido'}',
    _ => s.humanControls
        ? 'Tienes el control del escritorio.'
        : 'El bot está usando su escritorio.',
  };

  @override
  void dispose() {
    _statusSub?.cancel();
    _eventSub?.cancel();
    unawaited(_viewerServer?.close(force: true) ?? Future.value());
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label falló: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.controller.status;
    final running = st?.running ?? false;
    final humanControls = _controlling || (st?.humanControls ?? false);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Screen · ${widget.botTitle}',
                overflow: TextOverflow.ellipsis),
            const SizedBox(width: Hp.s2),
            _ScreenStateBadge(key: _statusKey, controller: widget.controller),
          ],
        ),
        actions: [
          if (running && !humanControls)
            IconButton(
              tooltip: _controlling ? 'Devolver control' : 'Tomar control',
              onPressed: _busy
                  ? null
                  : () => _run(
                      'Tomar control',
                      () async {
                        if (_controlling) {
                          await widget.controller.releaseLease();
                          if (!mounted) return;
                          setState(() => _controlling = false);
                          await _startViewer();
                        } else {
                          await widget.controller.acquireLease();
                          if (!mounted) return;
                          setState(() => _controlling = true);
                          await _startViewer();
                        }
                      },
                    ),
              icon: Icon(
                _controlling ? Icons.mouse_rounded : Icons.touch_app_rounded,
              ),
            ),
          IconButton(
            tooltip: 'Recargar visor',
            onPressed: () => _startViewer(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (running)
            IconButton(
              tooltip: 'Parar escritorio',
              onPressed: _busy
                  ? null
                  : () => _run('Parar', () async {
                        await widget.controller.stop();
                        if (!mounted) return;
                        await _startViewer();
                      }),
              icon: const Icon(Icons.stop_circle_outlined),
            )
          else
            IconButton(
              tooltip: 'Iniciar escritorio',
              onPressed: _busy
                  ? null
                  : () => _run('Iniciar', () async {
                        await widget.controller.start();
                        if (!mounted) return;
                        // El arranque tarda (Xvnc + Xfce): esperar y observar.
                        for (var i = 0; i < 20; i++) {
                          await Future.delayed(const Duration(seconds: 2));
                          final s = await widget.controller.refresh();
                          if (s.state == 'running') break;
                        }
                        await _startViewer();
                      }),
              icon: const Icon(Icons.desktop_windows_outlined),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _web),
          if (_message.isNotEmpty && running && humanControls)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(Hp.s3),
                padding: const EdgeInsets.symmetric(
                  horizontal: Hp.s3,
                  vertical: Hp.s2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(Hp.rSm),
                ),
                child: Text(
                  _message,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          if (_message.isNotEmpty && (!running || !_viewerReady))
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy || running)
                    const Padding(
                      padding: EdgeInsets.only(bottom: Hp.s3),
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Hp.s5),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (!running && st?.state != 'installing')
                    Padding(
                      padding: const EdgeInsets.only(top: Hp.s4),
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run('Iniciar', () async {
                                  await widget.controller.start();
                                  await _startViewer();
                                }),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Iniciar escritorio'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip de estado (running/lease) que se refresca con los cambios del
/// controlador.
class _ScreenStateBadge extends StatefulWidget {
  final ScreenController controller;
  const _ScreenStateBadge({super.key, required this.controller});

  @override
  State<_ScreenStateBadge> createState() => _ScreenStateBadgeState();
}

class _ScreenStateBadgeState extends State<_ScreenStateBadge> {
  StreamSubscription<ScreenStatus>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.status;
    final cs = Theme.of(context).colorScheme;
    if (s == null) return const SizedBox.shrink();
    final (label, color) = switch (s.state) {
      'running' => (
        s.humanControls ? 'control humano' : 'en vivo',
        s.humanControls ? Colors.orange : Colors.green,
      ),
      'stopped' => ('parado', cs.onSurfaceVariant),
      'starting' || 'installing' => ('arrancando', Colors.blueGrey),
      _ => ('error', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
