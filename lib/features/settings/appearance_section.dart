import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../design/tokens.dart';

/// Estado global del tema: el MaterialApp escucha y cambia en vivo.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Selector persistente de modo de tema: Sistema / Claro / Oscuro.
///
/// Persistencia: JSON en path_provider (getApplicationSupportDirectory/
/// settings.json). SecureStore es para secretos, no para preferencias.
class ThemeModeSetting {
  static const _file = 'settings.json';
  static const _key = 'theme_mode';

  /// Lee el modo persistido; `system` si nunca se guardó o el archivo
  /// está corrupto.
  static Future<ThemeMode> load() async {
    try {
      final map = await _readFile();
      final raw = map[_key];
      return switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    final map = await _readFile();
    map[_key] = mode.name;
    final dir = await AppServices.supportDir();
    final f = File('${dir.path}/$_file');
    await f.writeAsString(map.entries
        .map((e) => '${e.key}=${e.value}')
        .join('\n'));
  }

  static Future<Map<String, String>> _readFile() async {
    try {
      final dir = await AppServices.supportDir();
      final f = File('${dir.path}/$_file');
      if (!await f.exists()) return {};
      final out = <String, String>{};
      for (final line in (await f.readAsString()).split('\n')) {
        final eq = line.indexOf('=');
        if (eq > 0) out[line.substring(0, eq)] = line.substring(eq + 1);
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}

/// Sección Apariencia de la pantalla Ajustes.
class AppearanceSection extends StatefulWidget {
  final ThemeMode initial;

  const AppearanceSection({super.key, required this.initial});

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  late ThemeMode _mode = widget.initial;

  Future<void> _pick(ThemeMode mode) async {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    themeNotifier.value = mode;
    await ThemeModeSetting.save(mode);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, 0),
          child: Text('Apariencia', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: Hp.s2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Hp.s3),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_rounded, size: 18),
                label: Text('Sistema'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 18),
                label: Text('Claro'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 18),
                label: Text('Oscuro'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _pick(s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              side: WidgetStatePropertyAll(
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(Hp.rMd)),
              ),
            ),
          ),
        ),
        const SizedBox(height: Hp.s2),
      ],
    );
  }
}

/// Tarjeta de sección redondeada estilo Grok/iOS compartida por Ajustes.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Hp.s4, vertical: Hp.s2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Hp.rLg),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
