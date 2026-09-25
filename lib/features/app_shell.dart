import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ConversationsScreen(),
          TerminalScreen(),
          SettingsScreen(),
        ],
      ),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal_rounded),
              label: 'Terminal',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Ajustes',
            ),
          ],
        ),
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
