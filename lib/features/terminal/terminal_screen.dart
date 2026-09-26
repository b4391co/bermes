import 'package:flutter/material.dart';

/// Terminal: hosts SSH + sesiones Herdr. Entrega E.
/// Diseño inspirado en Moshi/TermRover: fleet de agentes y terminal real PTY.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inkSoft = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF5A6072)
        : const Color(0xFF9BA1AF);
    return Scaffold(
      appBar: AppBar(title: Text('Terminal')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Terminal SSH y Herdr — Entrega E',
              style: TextStyle(fontSize: 12.5, color: inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
