import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

import '../../clients/herdr/herdr_client.dart';
import '../../clients/ssh/ssh_session.dart';
import 'terminal_pane.dart';

/// Contrato de sesión activa en la barra de pestañas: título + panel.
abstract class TermSession {
  String get hostId;
  String get title;
  bool get isHerdrBridge => false;

  /// Widget renderizable de la sesión.
  Widget get pane;

  /// Separar: cierra transporte local, NO mata procesos remotos.
  Future<void> close();
}

/// Sesión en progreso (conectando / verificando huella).
class ConnectingSession implements TermSession {
  @override
  final String hostId;
  @override
  final String title;

  ConnectingSession({required this.hostId, required this.title});

  @override
  bool get isHerdrBridge => false;

  @override
  Widget get pane => const Center(child: 
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Conectando…'),
      ],
    ),
  );

  @override
  Future<void> close() async {}
}

/// Sesión SSH interactiva real (PTY) sobre [SshTerminalSession].
class SshTermSession implements TermSession {
  final SshTerminalSession session;

  /// Cliente SSH subyacente, necesario para HerdrClient (probes/run/shell).
  final SSHClient sshClient;

  @override
  final String hostId;
  @override
  final String title;

  SshTermSession({
    required this.session,
    required this.sshClient,
    required this.hostId,
    required this.title,
  });

  @override
  bool get isHerdrBridge => false;

  @override
  Widget get pane => TerminalPane(session: session, title: title);

  @override
  Future<void> close() => session.dispose();
}

/// Sesión de terminal Herdr: bridge NDJSON (frames base64 ANSI) → xterm2.
class HerdrTermSession implements TermSession {
  final HerdrTerminalBridge bridge;
  @override
  final String hostId;
  @override
  final String title;

  HerdrTermSession({
    required this.bridge,
    required this.hostId,
    required this.title,
  });

  @override
  bool get isHerdrBridge => true;

  @override
  Widget get pane => HerdrPane(bridge: bridge);

  @override
  Future<void> close() => bridge.close();
}

/// Terminal de Herdr: mismo motor xterm2, E/S por el bridge NDJSON.
class HerdrPane extends StatefulWidget {
  final HerdrTerminalBridge bridge;

  const HerdrPane({super.key, required this.bridge});

  @override
  State<HerdrPane> createState() => _HerdrPaneState();
}

class _HerdrPaneState extends State<HerdrPane> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    // La E/S del bridge: lo que la terminal emite → terminal.input NDJSON;
    // frames base64 que llegan → write al emulador.
    _terminal = Terminal(
      maxLines: 10000,
      onOutput: widget.bridge.sendInput,
      onResize: (w, h, _, _) => widget.bridge.resize(w, h),
    );
    _sub = widget.bridge.output.listen((data) {
      final bytes = data is Uint8List
          ? data
          : Uint8List.fromList((data as List<int>));
      _terminal.write(String.fromCharCodes(bytes));
    });
    widget.bridge.onClosed.listen((_) {
      if (mounted) {
        _terminal.write('\r\n\x1b[90m— bridge herdr cerrado —\x1b[0m\r\n');
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TerminalView(
      _terminal,
      controller: _controller,
      theme: isDark ? TerminalThemes.whiteOnBlack : TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontFamily: 'monospace', fontSize: 13.5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      autofocus: true,
    );
  }
}
