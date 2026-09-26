import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../clients/herdr/herdr_client.dart';
import '../../clients/ssh/ssh_session.dart';
import '../../core/app_services.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';
import 'herdr_panel.dart';
import 'host_editor.dart';
import 'host_tile.dart';
import 'ssh_secrets.dart';
import 'term_session.dart';
import 'terminal_pane.dart';

/// Pestaña Terminal: fleet de hosts SSH con sesiones reales (PTY) y Herdr.
///
/// - Lista de hosts desde la tabla SshHosts (drift, stream reactivo).
/// - Estado vacío elegante con llamada a la acción.
/// - Tap en host → sesión SSH real con TOFU de huella → TerminalPane.
/// - Barra de sesiones activas (chips, máx 3): tap cambia, X separa.
/// - Herdr: panel con snapshot de agentes + bridge NDJSON por agente.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  static const _maxSessions = 3;

  final _log = Logger('Terminal');

  /// Sesiones activas: separar NO mata el proceso remoto (solo el canal).
  final List<TermSession> _sessions = [];
  int _activeIndex = 0;

  Stream<List<SshHost>>? _hosts$;

  @override
  void initState() {
    super.initState();
    _hosts$ = AppServices.db.sshHosts.select().watch();
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      unawaited(s.close());
    }
    super.dispose();
  }

  Future<void> _connectHost(SshHost host) async {
    // Ya activa: solo cambia de pestaña.
    final existing = _sessions.indexWhere(
      (s) => !s.isHerdrBridge && s.hostId == host.id,
    );
    if (existing >= 0) {
      setState(() => _activeIndex = existing);
      return;
    }
    if (_sessions.length >= _maxSessions) {
      _snack('Máximo $_maxSessions sesiones simultáneas. Separa una (X).');
      return;
    }

    // Pestaña provisional "conectando" mientras corre el handshake.
    final pending = ConnectingSession(hostId: host.id, title: host.name);
    setState(() {
      _sessions.add(pending);
      _activeIndex = _sessions.length - 1;
    });
    try {
      final session = SshTerminalSession();
      await session.connect(
        host: host.host,
        port: host.port,
        username: host.username,
        password: host.authKind == 'password'
            ? await sshSecrets.readPassword(host.id)
            : null,
        privateKeyPem: host.authKind == 'key'
            ? await sshSecrets.readPrivateKey(host.id)
            : null,
        passphrase: host.authKind == 'key'
            ? await sshSecrets.readPassphrase(host.id)
            : null,
        verifyFingerprint: (fp) => _verifyTofu(host, fp),
      );
      final i = _sessions.indexOf(pending);
      setState(() {
        _sessions[i] = SshTermSession(
          session: session,
          sshClient: session.client!,
          hostId: host.id,
          title: host.name,
        );
        _activeIndex = i;
      });
    } catch (e) {
      _sessions.remove(pending);
      if (mounted) {
        setState(() {
          if (_sessions.isEmpty) {
            _activeIndex = 0;
          } else {
            _activeIndex = _activeIndex.clamp(0, _sessions.length - 1);
          }
        });
      }
      _log.error('conexión SSH falló ${host.name}', e);
      _snack('No se pudo conectar a ${host.name}: ${_errText(e)}');
    }
  }

  /// TOFU: coincide → conecta; primera vez pregunta y guarda; difiere → avisa.
  Future<bool> _verifyTofu(SshHost host, HostFingerprint fp) async {
    final known = await (AppServices.db
            .select(AppServices.db.sshHosts)
          ..where((h) => h.id.equals(host.id)))
        .getSingleOrNull();
    final knownFp = known?.knownFingerprint;
    if (knownFp == fp.sha256) return true;
    if (!mounted) return false;
    final ok = await showFingerprintDialog(
      context,
      fp,
      knownFingerprint: knownFp,
    );
    if (!ok) return false;
    await (AppServices.db.sshHosts.update()
          ..where((h) => h.id.equals(host.id)))
        .write(SshHostsCompanion(knownFingerprint: Value(fp.sha256)));
    _log.info('huella aceptada ${host.name}');
    return true;
  }

  Future<void> _openHerdr(SshTermSession s) async {
    final client = HerdrClient(ssh: s.sshClient);
    if (!mounted) return;
    await HerdrPanel.show(
      context,
      client: client,
      onOpenAgent: (paneId, title) => _openHerdrAgent(s, client, paneId, title),
    );
  }

  /// Abre el terminal NDJSON de un agente como nueva pestaña.
  Future<void> _openHerdrAgent(
    SshTermSession s,
    HerdrClient client,
    String paneId,
    String title,
  ) async {
    if (_sessions.length >= _maxSessions) {
      _snack('Máximo $_maxSessions sesiones simultáneas.');
      return;
    }
    final pending = ConnectingSession(hostId: s.hostId, title: title);
    setState(() {
      _sessions.add(pending);
      _activeIndex = _sessions.length - 1;
    });
    try {
      final bridge = await client.attachTerminal(paneId: paneId, cols: 80, rows: 24);
      final i = _sessions.indexOf(pending);
      setState(() {
        _sessions[i] = HerdrTermSession(
          bridge: bridge,
          hostId: s.hostId,
          title: title,
        );
        _activeIndex = i;
      });
    } catch (e) {
      _sessions.remove(pending);
      setState(() {
        _activeIndex = _activeIndex.clamp(0, _sessions.length - 1);
      });
      _log.error('bridge herdr falló $paneId', e);
      _snack('No se pudo abrir el terminal de Herdr: ${_errText(e)}');
    }
  }

  /// Separar la sesión: cierra el canal SSH local, NO mata el proceso remoto.
  Future<void> _detach(int index) async {
    final s = _sessions[index];
    await s.close();
    setState(() {
      _sessions.removeAt(index);
      if (_sessions.isEmpty) {
        _activeIndex = 0;
      } else if (_activeIndex >= _sessions.length || _activeIndex < 0) {
        _activeIndex = _sessions.length - 1;
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _errText(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _sessions.isEmpty ? AppBar(title: const Text('Terminal')) : null,
      body: _sessions.isEmpty ? _buildHostList() : _buildSessionView(),
    );
  }

  // ── Lista de hosts (estado vacío incluido) ────────────────────────────

  Widget _buildHostList() {
    return StreamBuilder<List<SshHost>>(
      stream: _hosts$,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final hosts = (snap.data ?? const <SshHost>[])
            .where((h) => h.enabled)
            .toList(growable: false);
        if (hosts.isEmpty) {
          return _EmptyState(onAdd: () => _openEditor(null));
        }
        return ListView.separated(
          itemCount: hosts.length,
          separatorBuilder: (_, _) => const Divider(indent: Hp.s4),
          itemBuilder: (context, i) => HostTile(
            host: hosts[i],
            connected: _sessions.any(
              (s) => !s.isHerdrBridge && s.hostId == hosts[i].id,
            ),
            onConnect: () => _connectHost(hosts[i]),
            onEdit: () => _openEditor(hosts[i]),
            onDelete: () => _deleteHost(hosts[i]),
          ),
        );
      },
    );
  }

  Future<void> _openEditor(SshHost? host) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HostEditor(existing: host)),
    );
    if (saved == true) _log.info('host ${host == null ? 'creado' : 'editado'}');
  }

  Future<void> _deleteHost(SshHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${host.name}'),
        content: const Text(
          'Se elimina el host de la lista y sus secretos guardados. '
          'La máquina remota no se ve afectada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await sshSecrets.deleteAll(host.id);
    await (AppServices.db.delete(
      AppServices.db.sshHosts,
    )..where((h) => h.id.equals(host.id))).go();
    _log.info('host eliminado ${host.name}');
  }

  // ── Vista de sesión activa ────────────────────────────────────────────

  Widget _buildSessionView() {
    final cs = Theme.of(context).colorScheme;
    final picking = _activeIndex < 0;
    final active = _activeIndex.clamp(0, _sessions.length - 1);
    final session = _sessions[active];
    if (picking) {
      // Modo "añadir": lista de hosts sin cerrar las sesiones vivas.
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => setState(() => _activeIndex = 0),
          ),
          title: const Text('Nueva sesión'),
        ),
        body: _buildHostList(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
          if (session is SshTermSession)
            IconButton(
              tooltip: 'Herdr (agentes)',
              icon: const Icon(Icons.hub_outlined),
              onPressed: () => _openHerdr(session),
            ),
        ],
      ),
      body: Column(
        children: [
          // Barra de sesiones activas (chips, máx 3).
          Container(
            color: cs.surfaceContainerLowest,
            padding: const EdgeInsets.symmetric(horizontal: Hp.s2),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 5),
                children: [
                  for (var i = 0; i < _sessions.length; i++)
                    _SessionChip(
                      session: _sessions[i],
                      active: i == active,
                      onTap: () => setState(() => _activeIndex = i),
                      onDetach: () => _detach(i),
                    ),
                  // Nueva sesión sin cerrar las existentes.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Hp.s1),
                    child: IconButton(
                      tooltip: 'Nueva sesión',
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () => setState(() => _activeIndex = -1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: session.pane),
        ],
      ),
    );
  }
}

/// Chip de sesión activa: nombre + estado, X para separar (no mata remoto).
class _SessionChip extends StatelessWidget {
  final TermSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDetach;

  const _SessionChip({
    required this.session,
    required this.active,
    required this.onTap,
    required this.onDetach,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s1),
      child: Material(
        color: active ? cs.primary : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Hp.rSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Hp.rSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: Hp.s3, right: Hp.s1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  session.isHerdrBridge
                      ? Icons.hub_rounded
                      : Icons.terminal_rounded,
                  size: 15,
                  color: active ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: Hp.s1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: active ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    tooltip: 'Separar (el proceso remoto sigue vivo)',
                    padding: EdgeInsets.zero,
                    iconSize: 15,
                    icon: Icon(
                      Icons.close_rounded,
                      color: active ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    onPressed: onDetach,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Estado vacío: icono + mensaje + botón de alta de host.
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(Hp.s8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.terminal_rounded,
                  size: 44,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Hp.s5),
              Text(
                'Conecta tu primera máquina',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Hp.s2),
              Text(
                'Terminal SSH real con PTY, huella verificada (TOFU)\n'
                'y Herdr para orquestar agentes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Hp.s5),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Añadir host SSH'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
