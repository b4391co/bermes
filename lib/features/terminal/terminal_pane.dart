import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

import '../../clients/ssh/ssh_session.dart';

/// Pestaña de terminal: una sesión SSH con PTY conectada a xterm2.
///
/// Requisitos cubiertos aquí:
/// - Terminal interactiva real (vim/htop funcionan sobre xterm2).
/// - Redimensionado PTY al cambiar tamaño de la vista.
/// - Barra táctil: Ctrl/Alt/Esc/Tab/flechas + pegar (pegar ≠ ejecutar).
/// - El teclado del sistema (IME, acentos, ñ) via xterm2 TextInput.
class TerminalPane extends StatefulWidget {
  final SshTerminalSession session;
  final String title;

  const TerminalPane({super.key, required this.session, required this.title});

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  late final TerminalController _terminalController;
  bool _ctrl = false;
  bool _alt = false;

  @override
  void initState() {
    super.initState();
    _terminalController = TerminalController();
    // El output del emulador (teclas del IME/teclado físico) → SSH.
    _terminal.onOutput = widget.session.write;
    widget.session.output.listen((data) {
      _terminal.write(String.fromCharCodes(data));
    });
    widget.session.onClosed.listen((_) {
      if (mounted) {
        _terminal.write('\r\n\x1b[90m— sesión cerrada —\x1b[0m\r\n');
      }
    });
  }

  @override
  void dispose() {
    _terminalController.dispose();
    super.dispose();
  }

  void _sendKey(LogicalKeyboardKey key, {String? sequence}) {
    if (sequence != null) {
      widget.session.write(sequence);
      return;
    }
    // Secuencias ANSI estándar para teclas de control.
    final seqs = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.escape: '\x1b',
      LogicalKeyboardKey.tab: '\t',
      LogicalKeyboardKey.arrowUp: '\x1b[A',
      LogicalKeyboardKey.arrowDown: '\x1b[B',
      LogicalKeyboardKey.arrowRight: '\x1b[C',
      LogicalKeyboardKey.arrowLeft: '\x1b[D',
      LogicalKeyboardKey.home: '\x1b[H',
      LogicalKeyboardKey.end: '\x1b[F',
    };
    final seq = seqs[key];
    if (seq != null) {
      widget.session.write(seq);
    }
  }

  void _toggleModifier(bool Function() get, void Function(bool) set) {
    set(!get());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          child: TerminalView(
            _terminal,
            controller: _terminalController,
            theme: isDark ? TerminalThemes.whiteOnBlack : _lightTerminalTheme,
            textStyle: const TerminalStyle(
              fontFamily: 'JetBrainsMonoNerd',
              // Roboto detrás: el paquete NerdFontMono no cubre todo el
              // BMP (p. ej. U+280F braille); sin fallback, Flutter pinta
              // cajas/tofu. Los glifos privados de icons SÍ están delante.
              fontFamilyFallback: ['Roboto', 'monospace'],
              fontSize: 13.5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            hardwareKeyboardOnly: false,
            autofocus: true,
          ),
        ),
        _buildKeyBar(context),
      ],
    );
  }

  Widget _buildKeyBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String label, VoidCallback onTap, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: active ? cs.primary : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            children: [
              chip(
                'Ctrl',
                () => _toggleModifier(() => _ctrl, (v) => _ctrl = v),
                active: _ctrl,
              ),
              chip(
                'Alt',
                () => _toggleModifier(() => _alt, (v) => _alt = v),
                active: _alt,
              ),
              chip(
                'Esc',
                () =>
                    _sendKey(LogicalKeyboardKey.escape, sequence: _mod('\x1b')),
              ),
              chip(
                'Tab',
                () => _sendKey(LogicalKeyboardKey.tab, sequence: _mod('\t')),
              ),
              chip(
                '↑',
                () => _sendKey(
                  LogicalKeyboardKey.arrowUp,
                  sequence: _mod('\x1b[A'),
                ),
              ),
              chip(
                '↓',
                () => _sendKey(
                  LogicalKeyboardKey.arrowDown,
                  sequence: _mod('\x1b[B'),
                ),
              ),
              chip(
                '←',
                () => _sendKey(
                  LogicalKeyboardKey.arrowLeft,
                  sequence: _mod('\x1b[D'),
                ),
              ),
              chip(
                '→',
                () => _sendKey(
                  LogicalKeyboardKey.arrowRight,
                  sequence: _mod('\x1b[C'),
                ),
              ),
              chip(
                'Home',
                () =>
                    _sendKey(LogicalKeyboardKey.home, sequence: _mod('\x1b[H')),
              ),
              chip(
                'End',
                () =>
                    _sendKey(LogicalKeyboardKey.end, sequence: _mod('\x1b[F')),
              ),
              chip('−', () => widget.session.write('-')),
              chip('|', () => widget.session.write('|')),
              chip('~', () => widget.session.write('~')),
              chip('/', () => widget.session.write('/')),
            ],
          ),
        ),
      ),
    );
  }

  String _mod(String base) {
    // Ctrl+tecla: & 0x1F para letras (Ctrl+C → \x03).
    if (_ctrl && base.length == 1) {
      final cu = base.codeUnitAt(0);
      if (cu >= 0x61 && cu <= 0x7A) return String.fromCharCode(cu - 0x60);
      if (cu >= 0x41 && cu <= 0x5A) return String.fromCharCode(cu - 0x40);
    }
    if (_alt) return '\x1b$base';
    return base;
  }
}

/// Tema claro del terminal: fondo igual al surface de la app, texto tinta.
final _lightTerminalTheme = TerminalTheme(
  cursor: const Color(0xFF16181D),
  selection: const Color(0xFFB9BECE),
  foreground: const Color(0xFF16181D),
  background: const Color(0xFFF7F7F8),
  black: const Color(0xFF16181D),
  red: const Color(0xFFD64545),
  green: const Color(0xFF1F8F4D),
  yellow: const Color(0xFFB7791F),
  blue: const Color(0xFF2563EB),
  magenta: const Color(0xFF9333EA),
  cyan: const Color(0xFF0891B2),
  white: const Color(0xFF9AA0AE),
  brightBlack: const Color(0xFF5A6072),
  brightRed: const Color(0xFFEF4444),
  brightGreen: const Color(0xFF22C55E),
  brightYellow: const Color(0xFFF59E0B),
  brightBlue: const Color(0xFF3B82F6),
  brightMagenta: const Color(0xFFA855F7),
  brightCyan: const Color(0xFF06B6D4),
  brightWhite: const Color(0xFFEDEEF2),
  searchHitBackground: const Color(0xFFF59E0B),
  searchHitBackgroundCurrent: const Color(0xFFE8618C),
  searchHitForeground: Colors.white,
);

/// Diálogo de confirmación de huella (TOFU): MUESTRA la huella, nunca la oculta.
Future<bool> showFingerprintDialog(
  BuildContext context,
  HostFingerprint fp, {
  String? knownFingerprint,
}) async {
  final matches = knownFingerprint != null && knownFingerprint == fp.sha256;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(matches ? 'Host conocido' : 'Verificar huella del servidor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${fp.host}:${fp.port}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('Tipo: ${fp.keyType}'),
          const SizedBox(height: 8),
          SelectableText(
            fp.sha256,
            style: const TextStyle(fontFamily: 'JetBrainsMonoNerd', fontSize: 12),
          ),
          if (knownFingerprint != null && !matches) ...[
            const SizedBox(height: 12),
            const Text(
              '¡ATENCIÓN! La huella difiere de la conocida. '
              'Puede ser un ataque MITM o una reinstalación del host.',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Rechazar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(matches ? 'Conectar' : 'Confiar y conectar'),
        ),
      ],
    ),
  );
  return result ?? false;
}
