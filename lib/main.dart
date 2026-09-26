import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'features/app_shell.dart';
import 'features/settings/appearance_section.dart';

void main() {
  runApp(const HermesPocketApp());
}

class HermesPocketApp extends StatefulWidget {
  const HermesPocketApp({super.key});

  @override
  State<HermesPocketApp> createState() => _HermesPocketAppState();
}

class _HermesPocketAppState extends State<HermesPocketApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    ThemeModeSetting.load().then((m) {
      if (mounted) setState(() => _themeMode = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Pocket',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: const AppShell(),
    );
  }
}
