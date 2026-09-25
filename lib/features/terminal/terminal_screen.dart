import 'package:flutter/material.dart';

/// Terminal: hosts SSH + sesiones Herdr. Entrega E.
/// Diseño inspirado en Moshi/TermRover: fleet de agentes y terminal real PTY.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal_rounded, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('Terminal SSH y Herdr — Entrega E'),
          ],
        ),
      ),
    );
  }
}
