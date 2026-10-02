import 'package:flutter/material.dart';

import 'core/logger.dart';

import 'design/theme.dart';
import 'features/app_shell.dart';
import 'features/settings/appearance_section.dart';

void main() {
  Logger('Main').info('Hermes Pocket arrancando');
  // En debug, vuelca el error cruda en vez de la inspección de widgets
  // (evita el bucle del reporte estructurado y deja el log legible).
  assert(() {
    FlutterError.onError = (details) {
      Logger('FlutterError').error(
        'EXC: ${details.exception}\n${details.stack}',
        details.exception,
        details.stack,
      );
    };
    return true;
  }());
  runApp(const HermesPocketApp());
}

class HermesPocketApp extends StatefulWidget {
  const HermesPocketApp({super.key});

  @override
  State<HermesPocketApp> createState() => _HermesPocketAppState();
}

class _HermesPocketAppState extends State<HermesPocketApp> {
  @override
  void initState() {
    super.initState();
    ThemeModeSetting.load().then((m) => themeNotifier.value = m);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'Hermes Pocket',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: mode,
        home: const AppShell(),
      ),
    );
  }
}
