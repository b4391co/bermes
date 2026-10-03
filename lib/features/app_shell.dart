import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_services.dart';

import '../clients/hermes/bot_meta.dart';
import '../core/logger.dart';
import '../design/tokens.dart';
import 'conversations/conversations_screen.dart';
import 'settings/settings_screen.dart';
import 'terminal/terminal_screen.dart';
import 'conversations/bot_face.dart';

/// Shell de navegación: Conversaciones · Terminal · Ajustes.
/// Navegación inicial acordada; bots y grupos comparten lista con filtros.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Bootstrap de conexiones al arrancar: runtime por cada conexión
    // persistida + login automático con contraseña recordada + roster bots.
    () async {
      try {
        final rows = await AppServices.db
            .select(AppServices.db.connections)
            .get();
        await AppServices.connections.bootstrap(
          rows,
          secrets: AppServices.secrets,
          db: AppServices.db,
        );
      } catch (e) {
        // Un bootstrap fallido no bloquea la UI: cada chat reintenta.
        Logger('Bootstrap').warning('bootstrap conexiones falló', e);
      }
    }();
  }

  bool _isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 640;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      const (
        icon: Icons.chat_bubble_outline_rounded,
        selected: Icons.chat_bubble_rounded,
        label: 'Chats',
      ),
      const (
        icon: Icons.terminal_outlined,
        selected: Icons.terminal_rounded,
        label: 'Terminal',
      ),
      const (
        icon: Icons.settings_outlined,
        selected: Icons.settings_rounded,
        label: 'Ajustes',
      ),
    ];
    final wide = _isWide(context);
    final body = IndexedStack(
      index: _index,
      children: const [
        ConversationsScreen(),
        TerminalScreen(),
        SettingsScreen(),
      ],
    );

    if (!wide) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 68,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor: Theme.of(context).colorScheme.surfaceContainerLow,
            labelTextStyle: WidgetStatePropertyAll(
              TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ),
            ],
          ),
        ),
      );
    }

    // Fold 6 desplegado / tablet / horizontal: rail lateral + contenido.
    return Scaffold(
      body: Row(
        children: [
          NavigationRailTheme(
            data: NavigationRailThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              indicatorColor: Theme.of(context).colorScheme.surfaceContainerLow,
              labelType: NavigationRailLabelType.all,
              groupAlignment: 0,
            ),
            child: NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Avatar de bot con contrato hermes-mobile: formas geométricas (circle,
/// square, rounded, hexagon), color hex, icono Material o imagen URL
/// (http(s)/data:); fallback iniciales. BotAvatarMeta en
/// lib/clients/hermes/bot_meta.dart (ui_meta.hermes-bots.avatar).
class BotAvatar extends StatelessWidget {
  final String seed;
  final String label;
  final String? imageUrl;
  final String?
  avatarMetaJson; // JSON BotAvatarMeta (ui_meta.hermes-bots.avatar)
  final double size;
  final bool isGroup;

  const BotAvatar({
    super.key,
    required this.seed,
    required this.label,
    this.imageUrl,
    this.avatarMetaJson,
    this.size = 46,
    this.isGroup = false,
  });

  static const _iconMap = <String, IconData>{
    'smart_toy': Icons.smart_toy_rounded,
    'science': Icons.science_rounded,
    'psychology': Icons.psychology_rounded,
    'code': Icons.code_rounded,
    'build': Icons.build_rounded,
    'bolt': Icons.bolt_rounded,
    'extension': Icons.extension_rounded,
    'sensors': Icons.sensors_rounded,
  };

  /// Iconos Material ofertados para editar el icono de un bot (los nombres
  /// son claves de `_iconMap`; el gateway los guarda en
  /// `ui_meta.hermes-bots.avatar.icon`, igual que hermes-mobile).
  static const List<String> iconChoices = [
    'smart_toy',
    'science',
    'psychology',
    'code',
    'build',
    'bolt',
    'extension',
    'sensors',
  ];

  /// IconData registrada para un nombre de icono del contrato hermes-mobile
  /// (null si este build no lo conoce → la UI cae al fallback `smart_toy`).
  static IconData? iconFor(String name) => _iconMap[name];

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    final color = _colorOf(meta) ?? Hp.avatarColor(seed);
    final initials = _initials(label);
    final bytes = _bytesOf();
    final remoteUrl = meta?.imageUrl;
    Widget? content;
    if (bytes != null) {
      content = Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            _iconOr(meta) ?? _initialsText(initials, color),
      );
    } else if (remoteUrl != null && remoteUrl.startsWith('http')) {
      content = Image.network(
        remoteUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            _iconOr(meta) ?? _initialsText(initials, color),
      );
    } else if (meta?.shape != null &&
        (isBlobShape(meta!.shape) ||
            kDesktopShapes.contains(meta.shape) ||
            meta.shape == 'hexagon')) {
      // Avatar de Hermes Desktop: cara procedural (blobatar) o forma clásica
      // (avatar.tsx:27,996). El color sigue el mismo contrato que el editor
      // (hex propio o hue determinista por nombre).
      content = BotFace(
        name: seed,
        shape: meta.shape,
        color: meta.color,
        size: size,
      );
    } else if (meta?.icon != null) {
      content = Icon(
        _iconMap[meta!.icon] ?? Icons.smart_toy_rounded,
        color: color,
        size: size * 0.62,
      );
    }
    // Sin fondo en ningún caso: el "dibujo" (imagen/icono) o, en su defecto,
    // las iniciales teñidas del color del bot. Nada de cajas de color.
    if (content == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: _initialsText(initials, color)),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: content),
    );
  }

  Color? _colorOf(BotAvatarMeta? meta) {
    final hex = meta?.color;
    if (hex == null || hex.length < 7) return null;
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  Widget? _iconOr(BotAvatarMeta? meta) =>
      meta?.icon == null ? null : _icon(meta!.icon!);

  Widget _icon(String name) => Icon(
    _iconMap[name] ?? Icons.smart_toy_rounded,
    color: _colorOf(_meta()) ?? Hp.avatarColor(seed),
    size: size * 0.52,
  );

  Widget _initialsText(String initials, Color color) => Text(
    initials,
    style: TextStyle(
      color: color,
      fontSize: size * 0.38,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
  );

  Uint8List? _bytesOf() {
    final url = imageUrl;
    if (url == null) return null;
    if (url.startsWith('data:')) {
      try {
        return base64Decode(url.split(',').last);
      } catch (_) {
        return null;
      }
    }
    return null; // http(s) se deja para una fase con cacheo de red
  }

  BotAvatarMeta? _meta() {
    final j = avatarMetaJson;
    if (j == null || j.isEmpty) return null;
    try {
      return BotAvatarMeta.fromJson(const JsonDecoder().convert(j) as Map);
    } catch (_) {
      return null;
    }
  }

  String _initials(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
