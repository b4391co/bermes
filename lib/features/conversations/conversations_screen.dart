import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// Lista unificada: bots de todos los gateways + grupos, buscables.
/// En esta fase el catálogo se puebla al conectar gateways (Entrega C).
class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Añadir conexión',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PlaceholderAdd()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Hp.s8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: cs.onSurfaceVariant),
              const SizedBox(height: Hp.s5),
              Text(
                'Sin conversaciones todavía',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Hp.s2),
              Text(
                'Conecta un gateway Hermes para descubrir\n tus bots y grupos.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderAdd extends StatelessWidget {
  const _PlaceholderAdd();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conexiones')),
    body: const Center(child: Text('Gestión de conexiones — próxima entrega')),
  );
}
