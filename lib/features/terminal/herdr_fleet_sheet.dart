import 'package:flutter/material.dart';

import '../../clients/herdr/herdr_client.dart';
import '../../clients/herdr/herdr_fleet.dart';
import '../../design/tokens.dart';

/// Hoja "Flota Herdr": sondea todos los hosts SSH guardados en paralelo
/// (probe efímero) y agrupa los agentes por host, con su estado semántico.
/// Tap en un agente → [onOpenAgent] con el host y el pane.
class HerdrFleetSheet extends StatefulWidget {
  final List<SshHostInfo> hosts;
  final Future<HerdrCredentials> Function(SshHostInfo host) credentialsFor;
  final Future<void> Function(SshHostInfo host, String sha256) onFingerprint;
  final void Function(SshHostInfo host, HerdrAgent agent) onOpenAgent;

  const HerdrFleetSheet({
    super.key,
    required this.hosts,
    required this.credentialsFor,
    required this.onFingerprint,
    required this.onOpenAgent,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SshHostInfo> hosts,
    required Future<HerdrCredentials> Function(SshHostInfo) credentialsFor,
    required Future<void> Function(SshHostInfo host, String sha256)
    onFingerprint,
    required void Function(SshHostInfo, HerdrAgent) onOpenAgent,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: HerdrFleetSheet(
            hosts: hosts,
            credentialsFor: credentialsFor,
            onFingerprint: onFingerprint,
            onOpenAgent: onOpenAgent,
          ),
        ),
      ),
    );
  }

  @override
  State<HerdrFleetSheet> createState() => _HerdrFleetSheetState();
}

class _HerdrFleetSheetState extends State<HerdrFleetSheet> {
  final List<FleetHostResult> _results = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    setState(() {
      _results.clear();
      _done = false;
    });
    final stream = HerdrFleet().probeAll(
      widget.hosts,
      widget.credentialsFor,
      onFingerprint: widget.onFingerprint,
    );
    await for (final r in stream) {
      if (!mounted) return;
      setState(() => _results.add(r));
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final probed = _results.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _done ? 'Flota Herdr' : 'Sondeando… ($probed/${widget.hosts.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Reintentar',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _probe,
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _results.isEmpty && !_done
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
              ? Center(
                  child: Text(
                    'Sin hosts SSH guardados',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: Hp.s6),
                  children: [
                    for (final r in _results) _hostSection(context, r),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _hostSection(BuildContext context, FleetHostResult r) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = r.error != null
        ? 'Error: ${_clip(r.error!)}'
        : r.notFound
        ? 'herdr no encontrado'
        : r.agents.isEmpty
        ? 'herdr sin agentes'
        : '${r.agents.length} agente(s)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, Hp.s1),
          child: Row(
            children: [
              Icon(
                r.error != null
                    ? Icons.error_outline_rounded
                    : r.agents.isEmpty
                    ? Icons.circle_outlined
                    : Icons.hub_rounded,
                size: 16,
                color: r.error != null
                    ? cs.error
                    : r.agents.isEmpty
                    ? cs.onSurfaceVariant
                    : cs.primary,
              ),
              const SizedBox(width: Hp.s2),
              Text(r.host.name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: Hp.s2),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        for (final a in r.agents)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
            leading: CircleAvatar(
              radius: 17,
              backgroundColor: Hp.avatarColor(a.name).withValues(alpha: 0.14),
              child: Text(
                a.name.isEmpty ? '?' : a.name[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Hp.avatarColor(a.name),
                ),
              ),
            ),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: a.paneId != null
                ? Text(a.paneId!, style: const TextStyle(fontSize: 11.5))
                : null,
            trailing: _statusDot(context, a.status),
            onTap: r.error == null && a.paneId != null && a.paneId!.isNotEmpty
                ? () {
                    Navigator.of(context).pop();
                    widget.onOpenAgent(r.host, a);
                  }
                : null,
          ),
        const Divider(indent: Hp.s4),
      ],
    );
  }

  Widget _statusDot(BuildContext context, HerdrStatus status) {
    final (color, label) = switch (status) {
      HerdrStatus.idle => (Hp.offline, 'idle'),
      HerdrStatus.working => (Hp.connecting, 'working'),
      HerdrStatus.blocked => (Hp.error, 'blocked'),
      HerdrStatus.done => (Hp.online, 'done'),
      HerdrStatus.unknown => (Hp.offline, '—'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Hp.s1),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _clip(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;
}
