import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../clients/hermes/rfb_client.dart';
import '../../design/tokens.dart';

/// Visor del Screen de Hermes (RFB sobre WS).
///
/// Estados de control VISUALMENTE inequívocos:
/// - Watch (observando): badge azul "Observando", input de teclado/ratón off.
/// - Control (human al lease): badge verde "Controlando", input activo.
/// El backend gatea el input real por lease (RfbClientFilter); la app no
/// implementa exclusión por su cuenta: si otro cliente toma el control,
/// el servidor cierra con 4000 y volvemos a Watch.
class ScreenViewer extends StatefulWidget {
  final HermesRfbClient client;
  final VoidCallback onBackToWatch;

  const ScreenViewer({
    super.key,
    required this.client,
    required this.onBackToWatch,
  });

  @override
  State<ScreenViewer> createState() => _ScreenViewerState();
}

class _ScreenViewerState extends State<ScreenViewer> {
  final TransformationController _transform = TransformationController();
  final FramebufferCanvas _canvas = FramebufferCanvas();
  RfbState _state = RfbState.connecting;
  bool _controlling = false;
  int? _lastImageHash;

  @override
  void initState() {
    super.initState();
    widget.client.states.listen(_onState);
    widget.client.frames.listen((frame) {
      _applyFrame(frame);
      _onFrame();
    });
  }

  void _onState(RfbState s) {
    if (!mounted) return;
    setState(() {
      _state = s;
      if (s == RfbState.disconnected) _controlling = false;
    });
  }

  DateTime _lastRaster = DateTime.now();

  Future<void> _onFrame() async {
    // Presupuesto de recursos: rasterizar máx ~12 fps aunque lleguen más frames.
    final now = DateTime.now();
    if (now.difference(_lastRaster).inMilliseconds < 80) return;
    _lastRaster = now;
    _canvas.ensureSize(widget.client.width, widget.client.height);
    final hash = _canvas.width * 1000003 + _canvas.height;
    if (hash == _lastImageHash) return;
    _lastImageHash = hash;
    if (mounted) setState(() {});
  }

  void _applyFrame(RfbFrame frame) {
    _canvas.ensureSize(frame.width, frame.height);
    for (final r in frame.rects) {
      if (r.encoding == 0 && r.pixels != null) {
        _canvas.applyRaw(r.x, r.y, r.w, r.h, r.pixels!);
      } else if (r.encoding == 1 && r.srcX != null && r.srcY != null) {
        _canvas.applyCopy(r.x, r.y, r.w, r.h, r.srcX!, r.srcY!);
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // ── Input helpers (solo con control) ──────────────────────────────────

  Offset _toFramebuffer(Offset local, Size viewSize, Size fbSize) {
    final sx = fbSize.width / viewSize.width;
    final sy = fbSize.height / viewSize.height;
    return Offset(
      (local.dx * sx).round().toDouble(),
      (local.dy * sy).round().toDouble(),
    );
  }

  void _pointer(KeyEvent event) {
    if (!_controlling) return;
    // Mapeo básico de teclas físicas → keysyms X11.
    final map = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.enter: 0xFF0D,
      LogicalKeyboardKey.escape: 0xFF1B,
      LogicalKeyboardKey.backspace: 0xFF08,
      LogicalKeyboardKey.tab: 0xFF09,
      LogicalKeyboardKey.arrowUp: 0xFF52,
      LogicalKeyboardKey.arrowDown: 0xFF54,
      LogicalKeyboardKey.arrowLeft: 0xFF51,
      LogicalKeyboardKey.arrowRight: 0xFF53,
      LogicalKeyboardKey.home: 0xFF50,
      LogicalKeyboardKey.end: 0xFF57,
      LogicalKeyboardKey.delete: 0xFFFF,
    };
    final key = event.logicalKey;
    final keysym = map[key];
    if (keysym != null) {
      widget.client.sendKey(keysym, down: event is KeyDownEvent);
    } else if (event.character != null && event.character!.isNotEmpty) {
      final cu = event.character!.runes.first;
      widget.client.sendKey(cu, down: event is KeyDownEvent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = _canvas.image;

    return Focus(
      autofocus: _controlling,
      onKeyEvent: (node, event) {
        _pointer(event);
        return KeyEventResult.handled;
      },
      child: Column(
        children: [
          _statusBar(context, cs),
          Expanded(
            child: Stack(
              children: [
                if (img != null)
                  InteractiveViewer(
                    transformationController: _transform,
                    maxScale: 6,
                    panEnabled: true,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final viewSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: _controlling
                              ? (event) {
                                  if (event is PointerScrollEvent) {
                                    final fb = _toFramebuffer(
                                      event.localPosition,
                                      viewSize,
                                      Size(
                                        _canvas.width.toDouble(),
                                        _canvas.height.toDouble(),
                                      ),
                                    );
                                    final mask = event.scrollDelta.dy < 0
                                        ? 8
                                        : 16;
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                      buttonMask: mask,
                                    );
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                    );
                                  }
                                }
                              : null,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: _controlling
                                ? (d) {
                                    final fb = _toFramebuffer(
                                      d.localPosition,
                                      viewSize,
                                      Size(
                                        _canvas.width.toDouble(),
                                        _canvas.height.toDouble(),
                                      ),
                                    );
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                      buttonMask: 1,
                                    );
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                    );
                                  }
                                : null,
                            onSecondaryTapUp: _controlling
                                ? (d) {
                                    final fb = _toFramebuffer(
                                      d.localPosition,
                                      viewSize,
                                      Size(
                                        _canvas.width.toDouble(),
                                        _canvas.height.toDouble(),
                                      ),
                                    );
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                      buttonMask: 4,
                                    );
                                    widget.client.sendPointer(
                                      fb.dx.toInt(),
                                      fb.dy.toInt(),
                                    );
                                  }
                                : null,
                            child: RawImage(
                              image: img,
                              fit: BoxFit.contain,
                              width: math.min(
                                viewSize.width,
                                _canvas.width.toDouble(),
                              ),
                              height:
                                  _canvas.height *
                                  math.min(
                                    viewSize.width,
                                    _canvas.width.toDouble(),
                                  ) /
                                  math.max(1, _canvas.width),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: Hp.s4),
                        Text(
                          _stateLabel(_state),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (_state == RfbState.disconnected ||
                    _state == RfbState.unauthorized ||
                    _state == RfbState.unsupported)
                  _errorOverlay(context, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(BuildContext context, ColorScheme cs) {
    final (label, color, icon) = _controlling
        ? ('Controlando', Hp.online, Icons.mouse_rounded)
        : ('Observando', const Color(0xFF0EA5E9), Icons.visibility_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s4, vertical: Hp.s2),
      color: cs.surfaceContainerLowest,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Hp.s2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          // Devolver control / tomar control.
          TextButton(
            onPressed: () {
              setState(() => _controlling = !_controlling);
              // El lease real se gestiona vía display.lease.acquire/release
              // desde el chat (el widget solo cambia su modo local de input).
            },
            child: Text(_controlling ? 'Devolver control' : 'Tomar control'),
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: widget.client.requestRefresh,
          ),
        ],
      ),
    );
  }

  Widget _errorOverlay(BuildContext context, ColorScheme cs) {
    return Container(
      color: cs.surface.withValues(alpha: 0.92),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(Hp.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.desktop_access_disabled_rounded,
              size: 40,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: Hp.s4),
            Text(
              _errorLabel(_state),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Hp.s4),
            Text(
              _errorHelp(_state),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _stateLabel(RfbState s) => switch (s) {
  RfbState.connecting => 'Conectando…',
  RfbState.handshaking => 'Negociando RFB…',
  RfbState.ready => 'Recibiendo pantalla…',
  RfbState.disconnected => 'Desconectado',
  RfbState.unauthorized => 'Ticket inválido o caducado',
  RfbState.unsupported => 'Codificación no soportada',
  RfbState.error => 'Error de conexión',
};

String _errorLabel(RfbState s) => switch (s) {
  RfbState.unauthorized => 'Sesión de Screen caducada',
  RfbState.unsupported => 'Servidor no compatible',
  _ => 'Desconectado',
};

String _errorHelp(RfbState s) => switch (s) {
  RfbState.unauthorized =>
    'El ticket de observación caduca en 30 s. Vuelve a abrir el Screen desde el chat para generar uno nuevo.',
  RfbState.unsupported =>
    'El servidor no ofrece la codificación Raw/CopyRect. Comprueba la versión del bot-desktop del host.',
  _ => 'Comprueba la conexión con el gateway y vuelve a abrir el Screen.',
};
