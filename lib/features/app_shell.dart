import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/logger.dart';
import '../design/tokens.dart';
import 'conversations/conversations_screen.dart';
import 'settings/settings_screen.dart';
import 'terminal/terminal_screen.dart';

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
    // persistida + login automático con contraseña recordada.
    () async {
      try {
        final rows = await AppServices.db.select(AppServices.db.connections).get();
        await AppServices.connections.bootstrap(rows, secrets: AppServices.secrets);
      } catch (e) {
        // Un bootstrap fallido no bloquea la UI: cada chat reintenta.
        Logger('Bootstrap').warning('bootstrap conexiones falló', e);
      }
    }();
  }


  bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 640;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      const (icon: Icons.chat_bubble_outline_rounded, selected: Icons.chat_bubble_rounded, label: 'Chats'),
      const (icon: Icons.terminal_outlined, selected: Icons.terminal_rounded, label: 'Terminal'),
      const (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: 'Ajustes'),
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

/// Avatar con personalidad: color determinista por seed + iniciales,
/// o imagen real del bot cuando existe.
class BotAvatar extends StatelessWidget {
  final String seed;
  final String label;
  final String? imageUrl;
  final double size;
  final bool isGroup;

  const BotAvatar({
    super.key,
    required this.seed,
    required this.label,
    this.imageUrl,
    this.size = 46,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Hp.avatarColor(seed);
    final initials = _initials(label);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
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
