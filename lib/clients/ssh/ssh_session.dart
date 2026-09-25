import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../core/logger.dart';

/// Huella del host recibida durante el handshake (para TOFU).
class HostFingerprint {
  final String host;
  final int port;
  final String keyType; // ssh-ed25519, ssh-rsa…
  final String sha256; // formato OpenSSH: "SHA256:<base64>"

  const HostFingerprint({
    required this.host,
    required this.port,
    required this.keyType,
    required this.sha256,
  });
}

/// Sesión de terminal SSH interactiva con PTY.
///
/// - Autenticación: contraseña o private key (con passphrase opcional).
/// - Verificación de huella del servidor: dartssh2 entrega el fingerprint
///   OpenSSH-style `SHA256:<b64>` en el callback `onVerifyHostKey`; la
///   comparación con la huella conocida (TOFU) la hace el llamador.
/// - PTY real: pty-req xterm-256color + shell. Aplicaciones interactivas
///   (vim, htop) corren sobre el emulador xterm2.
/// - Las credenciales SSH son INDEPENDIENTES de las del gateway Hermes.
class SshTerminalSession {
  final _log = Logger('SshSession');

  SSHClient? _client;
  SSHSession? _shell;
  final _output = StreamController<Uint8List>.broadcast();
  final _closed = StreamController<void>.broadcast();

  Stream<Uint8List> get output => _output.stream;
  Stream<void> get onClosed => _closed.stream;
  bool get isOpen => _client != null && _shell != null;

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    String? passphrase,
    required Future<bool> Function(HostFingerprint fp) verifyFingerprint,
    int cols = 80,
    int rows = 24,
  }) async {
    final socket = await SSHSocket.connect(host, port);
    try {
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: password == null ? null : () => password,
        identities: privateKeyPem != null
            ? [...SSHKeyPair.fromPem(privateKeyPem, passphrase)]
            : null,
        onVerifyHostKey: (type, Uint8List fingerprint) async {
          // fingerprint llega ya como UTF-8 "SHA256:<b64>" según dartssh2.
          final fp = HostFingerprint(
            host: host,
            port: port,
            keyType: type,
            sha256: utf8.decode(fingerprint),
          );
          return verifyFingerprint(fp);
        },
      );
    } catch (e) {
      await socket.close();
      rethrow;
    }

    _shell = await _client!.shell(
      pty: SSHPtyConfig(width: cols, height: rows, type: 'xterm-256color'),
      environment: {'TERM': 'xterm-256color'},
    );

    _shell!.stdout.cast<Uint8List>().listen(
      _output.add,
      onError: (Object e) => _log.warning('stdout error: $e'),
      onDone: _handleClosed,
    );
    _shell!.stderr.cast<Uint8List>().listen(_output.add);
    _shell!.done.then((_) => _handleClosed());
  }

  void write(String text) {
    _shell?.write(utf8.encode(text));
  }

  void writeBytes(Uint8List bytes) {
    _shell?.write(bytes);
  }

  void resize(int cols, int rows) {
    _shell?.resizeTerminal(cols, rows);
  }

  /// Cerrar la sesión SSH. NOTA DE PRODUCTO: en SSH clásico, cerrar el canal
  /// termina el shell remoto. Separar sin matar el proceso = usar tmux/herdr
  /// en el host. La UI debe dejar esto claro (diferencia desconectar/separar).
  Future<void> close() async {
    _handleClosed();
    _shell?.close();
    await _client?.close();
    _client = null;
    _shell = null;
  }

  void _handleClosed() {
    if (!_closed.isClosed) _closed.add(null);
  }

  Future<void> dispose() async {
    await close();
    await _output.close();
    await _closed.close();
  }
}

class SshException implements Exception {
  final String message;
  const SshException(this.message);

  @override
  String toString() => message;
}
