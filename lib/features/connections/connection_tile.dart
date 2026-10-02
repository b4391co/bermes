import 'dart:async';

import 'package:drift/drift.dart' hide Column;

import '../../core/app_services.dart';

import 'package:flutter/material.dart';

import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';
import '../../domain/connection/connection_profile.dart';

/// Estado vivo de una conexión para la lista de Ajustes.
///
/// Se apoya en el stream real del ConnectionManager (runtimes) y en el
/// stateStream de cada gateway: nada simulado. Sin runtime = gris.
class ConnectionTile extends StatefulWidget {
  final Connection data;
  final ConnectionManager connections;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabledChanged;

  const ConnectionTile({
    super.key,
    required this.data,
    required this.connections,
    required this.onTap,
    required this.onEnabledChanged,
  });

  @override
  State<ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<ConnectionTile> {
  StreamSubscription<GatewayLinkState>? _sub;
  GatewayLinkState _link = GatewayLinkState.disconnected;
  bool _tracked = false;

  @override
  void initState() {
    super.initState();
    widget.connections.stream.listen(_onRuntimesChanged);
    _track();
    _refreshBotCount();
  }

  @override
  void didUpdateWidget(ConnectionTile old) {
    super.didUpdateWidget(old);
    if (old.data.id != widget.data.id) _track();
  }

  int _botCount = 0;

  void _onRuntimesChanged(Map<String, ConnectionRuntime> runtimes) {
    if (!mounted) return;
    // Un runtime puede haber aparecido o desaparecido para esta conexión.
    _track(runtimes);
    _refreshBotCount();
    setState(() {});
  }

  Future<void> _refreshBotCount() async {
    final db = AppServices.db;
    final n =
        await (db.select(db.conversations)..where(
              (c) =>
                  c.connectionId.equals(widget.data.id) & c.kind.equals('bot'),
            ))
            .get();
    if (mounted && n.length != _botCount) {
      setState(() => _botCount = n.length);
    }
  }

  void _track([Map<String, ConnectionRuntime>? runtimes]) {
    final runtime = (runtimes ?? widget.connections.runtimes)[widget.data.id];
    if (runtime == null) {
      _sub?.cancel();
      _sub = null;
      _tracked = false;
      _link = GatewayLinkState.disconnected;
      return;
    }
    if (_tracked) return;
    _tracked = true;
    _link = runtime.gateway.state;
    _sub = runtime.gateway.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _link = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  (Color, IconData, String) get _status {
    if (!widget.data.enabled) {
      return (Hp.offline, Icons.pause_circle_outline_rounded, 'Desactivada');
    }
    return switch (_link) {
      GatewayLinkState.ready => (
        Hp.online,
        Icons.check_circle_rounded,
        'Conectada',
      ),
      GatewayLinkState.connecting => (
        Hp.connecting,
        Icons.autorenew_rounded,
        'Conectando…',
      ),
      GatewayLinkState.reconnecting => (
        Hp.connecting,
        Icons.autorenew_rounded,
        'Reconectando…',
      ),
      GatewayLinkState.authExpired => (
        Hp.error,
        Icons.lock_clock_rounded,
        'Sesión expirada',
      ),
      GatewayLinkState.error => (
        Hp.error,
        Icons.error_outline_rounded,
        'Error',
      ),
      GatewayLinkState.disconnected => (
        Hp.offline,
        Icons.circle_outlined,
        'Sin conexión',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _status;
    final profile = _profileOf(widget.data);
    return ListTile(
      onTap: widget.onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Hp.avatarColor(profile.name).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Hp.rSm),
        ),
        alignment: Alignment.center,
        child: Text(
          profile.name.isEmpty ? '?' : profile.name.characters.first,
          style: TextStyle(
            color: Hp.avatarColor(profile.name),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      title: Text(
        profile.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        '${profile.host}:${profile.port}${profile.basePath}  ·  $label'
        '  ·  $_botCount bots',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Hp.s3),
          Switch(
            value: widget.data.enabled,
            onChanged: widget.onEnabledChanged,
          ),
        ],
      ),
    );
  }

  /// Profile vista (sin secretos) para mostrar datos.
  static ConnectionProfile _profileOf(Connection row) => ConnectionProfile(
    id: row.id,
    name: row.name,
    scheme: row.scheme,
    host: row.host,
    port: row.port,
    basePath: row.basePath,
    username: row.username,
    enabled: row.enabled,
  );
}
