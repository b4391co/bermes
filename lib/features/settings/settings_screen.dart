import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';
import '../connections/connection_editor.dart';
import '../connections/connection_tile.dart';
import 'appearance_section.dart';
import 'data_section.dart';

/// Ajustes: conexiones, apariencia, datos, acerca de (Entrega F).
///
/// Todo con datos reales: conexiones desde drift (watch) + estado vivo del
/// ConnectionManager; export/import vía SettingsPackage; tema persistido.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription<List<Connection>>? _sub;
  List<Connection> _connections = const [];
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _sub = (AppServices.db.select(AppServices.db.connections)
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .watch()
        .listen((rows) {
      if (!mounted) return;
      setState(() => _connections = rows);
    });
    ThemeModeSetting.load().then((mode) {
      if (!mounted) return;
      setState(() => _themeMode = mode);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _openEditor([Connection? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectionEditor(existing: existing),
      ),
    );
  }

  Future<void> _toggleEnabled(Connection row, bool enabled) async {
    await (AppServices.db.update(AppServices.db.connections)
          ..where((c) => c.id.equals(row.id)))
        .write(ConnectionsCompanion(enabled: Value(enabled)));
    if (!enabled) await AppServices.connections.removeRuntime(row.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.only(top: Hp.s2, bottom: Hp.s8),
        children: [
          _connectionsSection(cs),
          AppearanceSection(initial: _themeMode),
          const DataSection(),
          const AboutSection(),
        ],
      ),
    );
  }

  Widget _connectionsSection(ColorScheme cs) {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conexiones',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Nueva conexión',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _openEditor(),
              ),
            ],
          ),
        ),
        if (_connections.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s2, Hp.s4, Hp.s4),
            child: Row(
              children: [
                Icon(Icons.dns_outlined,
                    size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: Hp.s2),
                Expanded(
                  child: Text(
                    'Aún no hay gateways. Añade uno para ver tus bots.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )
        else
          ..._connections.map(
            (row) => ConnectionTile(
              key: ValueKey(row.id),
              data: row,
              connections: AppServices.connections,
              onTap: () => _openEditor(row),
              onEnabledChanged: (v) => _toggleEnabled(row, v),
            ),
          ),
        const SizedBox(height: Hp.s1),
      ],
    );
  }
}
