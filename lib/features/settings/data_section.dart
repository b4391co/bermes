import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart';
import '../../data/settings/settings_package.dart';
import '../../design/tokens.dart';
import 'appearance_section.dart';


/// Sección Datos: exportar/importar ajustes con SettingsPackage real.
///
/// Sin share_plus/file_picker en pubspec: export escribe un archivo en
/// Documents (muestra la ruta) e import pide la ruta en un diálogo.
class DataSection extends StatefulWidget {
  const DataSection({super.key});

  @override
  State<DataSection> createState() => _DataSectionState();
}

class _DataSectionState extends State<DataSection> {
  final _log = Logger('Data');
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, Hp.s2),
          child: Text('Datos', style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Exportar ajustes'),
          subtitle: const Text(
            'Conexiones (sin secretos) a un archivo JSON',
          ),
          onTap: _busy ? null : _export,
        ),
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Importar ajustes'),
          subtitle: const Text('Desde un archivo exportado'),
          onTap: _busy ? null : _import,
        ),
        const SizedBox(height: Hp.s1),
      ],
    );
  }

  void _setBusy(bool v) {
    if (mounted) setState(() => _busy = v);
  }

  Future<void> _export() async {
    _setBusy(true);
    try {
      final db = AppServices.db;
      final rows = await db.select(db.connections).get();
      final pkg = SettingsPackage(
        data: {
          'connections': rows.map((r) => _rowToJson(r)).toList(),
        },
        includesSecrets: false,
      );
      final dir = await AppServices.documentsDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      final file = File('${dir.path}/hermes-pocket-ajustes-$stamp.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(pkg.toJson()));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exportado a ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, st) {
      _log.error('export failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Map<String, Object?> _rowToJson(Connection r) => {
    'id': r.id,
    'name': r.name,
    'scheme': r.scheme,
    'host': r.host,
    'port': r.port,
    'basePath': r.basePath,
    'authKind': r.authKind,
    'username': r.username,
    'allowInsecureTls': r.allowInsecureTls,
    'enabled': r.enabled,
  };

  Future<void> _import() async {
    final path = await _askPath();
    if (path == null || path.trim().isEmpty) return;
    _setBusy(true);
    try {
      final raw = await File(path.trim()).readAsString();
      final pkg = SettingsPackage.parse(raw);
      final list = pkg.data['connections'];
      if (list is! List) {
        throw const SettingsFormatException(
          'El paquete no incluye conexiones',
        );
      }
      final db = AppServices.db;
      var added = 0;
      var skipped = 0;
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final id = item['id'] as String?;
        if (id == null) continue;
        final exists =
            await (db.select(db.connections)..where((c) => c.id.equals(id)))
                .getSingleOrNull();
        if (exists != null) {
          skipped++;
          continue;
        }
        await db.into(db.connections).insert(
              ConnectionsCompanion.insert(
                id: id,
                name: item['name'] as String? ?? 'Conexión',
                scheme: item['scheme'] as String? ?? 'http',
                host: item['host'] as String? ?? '',
                port: (item['port'] as num?)?.toInt() ?? 9119,
                basePath: Value(item['basePath'] as String? ?? ''),
                authKind: item['authKind'] as String? ?? 'password',
                username: Value(item['username'] as String? ?? ''),
                allowInsecureTls:
                    Value(item['allowInsecureTls'] as bool? ?? false),
                enabled: Value(item['enabled'] as bool? ?? true),
              ),
            );
        added++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importadas $added conexiones'
            '${skipped > 0 ? ' ($skipped ya existían)' : ''}',
          ),
        ),
      );
    } on SettingsFormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paquete inválido: ${e.message}')),
        );
      }
    } catch (e, st) {
      _log.error('import failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar: $e')),
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> _askPath() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar ajustes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ruta del archivo exportado (.json):'),
            const SizedBox(height: Hp.s2),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/storage/emulated/0/Download/…json',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }
}

/// Sección Acerca de: versión fija (sin package_info en pubspec).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  /// Sin package_info en pubspec: constante sincronizada con pubspec.yaml.
  static const version = '0.1.2';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, Hp.s2),
          child: Text(
            'Acerca de',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListTile(
          leading: Icon(Icons.developer_mode_rounded, color: cs.onSurfaceVariant),
          title: const Text('Hermes Pocket'),
          subtitle: const Text(
            'Cliente Android para Hermes Agent de Nous Research',
          ),
          trailing: const Text(
            'v$version',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: Hp.s1),
      ],
    );
  }
}
