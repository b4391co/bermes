import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'features/app_shell.dart';

void main() {
  runApp(const HermesPocketApp());
}

class HermesPocketApp extends StatelessWidget {
  const HermesPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Pocket',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
