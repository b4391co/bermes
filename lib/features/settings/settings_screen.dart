import 'package:flutter/material.dart';

/// Ajustes: conexiones, tema, export/import (Entrega F).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: const [
          // Secciones: Conexiones · Apariencia · Datos (export/import) · Acerca de
        ],
      ),
    );
  }
}
