import 'package:flutter/material.dart';

import '../../clients/herdr/herdr_client.dart';
import '../../core/logger.dart';
import '../../design/tokens.dart';

/// Panel Herdr: snapshot real de agentes sobre SSH (herdr api snapshot --json)
/// y acceso al terminal NDJSON de cada agente.
class HerdrPanel extends StatefulWidget {
  final HerdrClient client;
  final void Function(String paneId, String title) onOpenAgent;

  const HerdrPanel({super.key, required this.client, required this.onOpenAgent});

  static Future<void> show(
    BuildContext context, {
    required HerdrClient client,
    required void Function(String paneId, String title) onOpenAgent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
        child: HerdrPanel(client: client, onOpenAgent: onOpenAgent),
      ),
    );
  }

  @override
  State<HerdrPanel> createState() => _HerdrPanelState();
}

class _HerdrPanelState extends State<HerdrPanel> {
  final _log = Logger('HerdrPanel');
  bool _loading = true;
  bool _available = false;
  String? _version;
  List<HerdrAgent> _agents = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ok = await widget.client.isAvailable();
      if (!ok) {
        setState(() {
          _loading = false;
          _available = false;
        });
        return;
      }
      final agents = await widget.client.listAgents();
      final v = await widget.client.version();
      setState(() {
        _loading = false;
        _available = true;
        _agents = agents;
        _version = v.trim().isEmpty ? null : v.trim();
        _error = null;
      });
    } catch (e) {
      _log.error('snapshot herdr falló', e);
      setState(() {
        _loading = false;
        _available = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Herdr', style: Theme.of(context).textTheme.titleMedium),
                    if (_version != null)
                      Text(_version!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refrescar',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : !_available
              ? _buildMissing(context)
              : _agents.isEmpty
              ? Center(
                  child: Text(
                    'Sin agentes en este host',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: Hp.s6),
                  itemCount: _agents.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: Hp.s4),
                  itemBuilder: (context, i) => _agentTile(context, _agents[i]),
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(Hp.s3),
            child: Text(
              _error!,
              style: TextStyle(color: cs.error, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _buildMissing(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Hp.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: Hp.s3),
            Text(
              'Herdr no está instalado en este host',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Hp.s2),
            Text(
              'Instala herdr en la máquina remota para orquestar\n'
              'agentes y abrir su terminal desde aquí.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _agentTile(BuildContext context, HerdrAgent agent) {
    final cs = Theme.of(context).colorScheme;
    final (color, label) = switch (agent.status) {
      HerdrStatus.idle => (Hp.offline, 'idle'),
      HerdrStatus.working => (Hp.connecting, 'working'),
      HerdrStatus.blocked => (Hp.error, 'blocked'),
      HerdrStatus.done => (Hp.online, 'done'),
      HerdrStatus.unknown => (Hp.offline, '—'),
    };
    final hasPane = agent.paneId != null && agent.paneId!.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: Hp.avatarColor(agent.name).withValues(alpha: 0.14),
        child: Text(
          agent.name.isEmpty ? '?' : agent.name.characters.first,
          style: TextStyle(
            color: Hp.avatarColor(agent.name),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      title: Text(
        agent.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: Hp.s1),
          Text(
            agent.title?.isNotEmpty == true ? '${agent.title} · $label' : label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: hasPane
          ? FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenAgent(agent.paneId!, agent.name);
              },
              child: const Text('Terminal'),
            )
          : Text(
              'sin pane',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
    );
  }
}
