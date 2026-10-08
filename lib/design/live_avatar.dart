import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Avatar «vivo» al estilo Hermes Desktop (referencia Parker de hermes):
///
/// - **Aura orbital**: elipses de colores girando alrededor del avatar
///   (anillos de electrón). Giran cuando [active] (fijados, bot
///   trabajando/streaming); sin aura cuando [active] es falso.
/// - **Bocadillo «…»**: burbuja oscura abajo a la derecha con 3 puntos que
///   laten (el bot «piensa»). Visible solo con [active].
/// - **Flotación**: balanceo vertical suave del conjunto ([float]).
///
/// El hijo es el avatar real (`BotAvatar`/`BotFace`): la decoración vive
/// alrededor, no lo sustituye.
class LiveAvatar extends StatefulWidget {
  final Widget child;
  final double size;

  /// Aura girando + bocadillo «…» (bot fijo o con vida).
  final bool active;

  /// Balanceo vertical tipo «float».
  final bool float;

  /// Modo fila (lista de chats): aura ceñida al avatar — la orbital ancha
  /// (34% de margen) dentro del ListTile aplastaba el icono y desbordaba
  /// sobre el título. La orbital GRANDE queda para Fijados/cabecera.
  final bool compact;

  const LiveAvatar({
    super.key,
    required this.child,
    required this.size,
    this.active = true,
    this.float = false,
    this.compact = false,
  });

  @override
  State<LiveAvatar> createState() => _LiveAvatarState();
}

class _LiveAvatarState extends State<LiveAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _spin; // rotación de las órbitas
  late final AnimationController _dots; // latido de los puntos
  late final AnimationController _bob; // flotación

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.active) {
      _spin.repeat();
      _dots.repeat();
    }
    if (widget.float) _bob.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LiveAvatar old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      if (widget.active) {
        _spin.repeat();
        _dots.repeat();
      } else {
        _spin.stop();
        _dots.stop();
      }
    }
    if (widget.float != old.float) {
      if (widget.float) {
        _bob.repeat(reverse: true);
      } else {
        _bob.stop();
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _dots.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact
        ? widget.size * 0.08 // fila: aura ceñida, caja ≈ size*1.16 ≤ 56
        : widget.size * 0.34; // margen para que el aura respire
    Widget stack = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (widget.active)
          AnimatedBuilder(
            animation: _spin,
            builder: (context, _) => CustomPaint(
              size: Size(widget.size + pad * 2, widget.size + pad * 2),
              painter: _OrbitsPainter(progress: _spin.value),
            ),
          ),
        Padding(
          padding: EdgeInsets.all(pad),
          child: widget.child,
        ),
        if (widget.active)
          Positioned(
            right: -pad * 0.15,
            bottom: -pad * 0.1,
            child: _DotBubble(pulse: _dots),
          ),
      ],
    );
    if (widget.float) {
      stack = AnimatedBuilder(
        animation: _bob,
        builder: (context, child) {
          // Curva seno: -3..+3 px de «respiración» vertical.
          final t = math.sin(_bob.value * math.pi) * 3;
          return Transform.translate(offset: Offset(0, t), child: child);
        },
        child: stack,
      );
    }
    return SizedBox(
      width: widget.size + pad * 2,
      height: widget.size + pad * 2,
      child: Center(child: stack),
    );
  }
}

/// Anillos elípticos giratorios: la firma visual de Desktop. Cada anillo es
/// una elipse rotada con su propio ángulo, radio y color; el giro completo
/// tarda ~9 s.
class _OrbitsPainter extends CustomPainter {
  final double progress;

  _OrbitsPainter({required this.progress});

  static const _colors = <Color>[
    Color(0xFF3ECF8E), // verde Hermes
    Color(0xFF5B6CFF), // índigo
    Color(0xFFE8618C), // rosa
    Color(0xFFF59E0B), // ámbar
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rx = size.width * 0.46;
    final ry = size.height * 0.28;
    for (var i = 0; i < 4; i++) {
      // Cada anillo: inclinación distinta + desfase de fase → trenza orgánica.
      final tilt = (-0.5 + i * 0.42) * math.pi / 2.2;
      final phase = progress * 2 * math.pi + i * math.pi / 4;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      canvas.scale(1.0, 0.62 + 0.10 * math.sin(phase));
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = _colors[i].withValues(alpha: 0.85);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        paint,
      );
      // «Electrón»: punto brillante que recorre el anillo.
      final ex = math.cos(phase) * rx;
      final ey = math.sin(phase) * ry;
      canvas.drawCircle(Offset(ex, ey), 2.4, Paint()..color = _colors[i]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OrbitsPainter old) => old.progress != progress;
}

/// Burbuja oscura con tres puntos que laten en secuencia (Desktop: el bot
/// «está trabajando»). La cola apunta hacia el avatar.
class _DotBubble extends StatelessWidget {
  final Animation<double> pulse;

  const _DotBubble({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => CustomPaint(
        size: const Size(30, 20),
        painter: _DotBubblePainter(phase: pulse.value),
      ),
    );
  }
}

class _DotBubblePainter extends CustomPainter {
  final double phase;

  _DotBubblePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    const bg = Color(0xCC141414);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(9),
    );
    // Fondo oscuro neutro (idéntico en ambos temas: sobre avatar claro u
    // oscuro se lee igual).
    canvas.drawRRect(r, Paint()..color = bg);
    // Cola hacia abajo-izquierda (apunta al avatar).
    final tail = Path()
      ..moveTo(4, size.height - 1)
      ..lineTo(0, size.height + 5)
      ..lineTo(10, size.height - 1)
      ..close();
    canvas.drawPath(tail, Paint()..color = bg);
    // Tres puntos con latido escalonado (0, +⅓, +⅔ de fase).
    final cy = size.height / 2;
    for (var i = 0; i < 3; i++) {
      final p = (phase + i / 3) % 1.0;
      final a = 0.35 + 0.65 * math.sin(p * math.pi);
      canvas.drawCircle(
        Offset(8.0 + i * 7.0, cy),
        2.2,
        Paint()..color = Colors.white.withValues(alpha: a.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_DotBubblePainter old) => old.phase != phase;
}
