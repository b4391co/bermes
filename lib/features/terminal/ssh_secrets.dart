import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secretos SSH por host (password, private key, passphrase) en secure
/// storage (Keystore Android / DPAPI). NUNCA en la DB.
///
/// Instancia propia del almacén de plataforma con claves aisladas bajo
/// el prefijo `ssh/` (sin colisión con `session/` ni `remember/`).
class SshSecrets {
  final FlutterSecureStorage _storage;

  SshSecrets([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'ssh/';

  Future<String?> readPassword(String hostId) =>
      _storage.read(key: '${_prefix}password/$hostId');

  Future<void> writePassword(String hostId, String password) =>
      _storage.write(key: '${_prefix}password/$hostId', value: password);

  Future<String?> readPrivateKey(String hostId) =>
      _storage.read(key: '${_prefix}key/$hostId');

  Future<void> writePrivateKey(String hostId, String pem) =>
      _storage.write(key: '${_prefix}key/$hostId', value: pem);

  Future<String?> readPassphrase(String hostId) =>
      _storage.read(key: '${_prefix}passphrase/$hostId');

  Future<void> writePassphrase(String hostId, String passphrase) =>
      _storage.write(key: '${_prefix}passphrase/$hostId', value: passphrase);

  /// Borra TODOS los secretos SSH de un host.
  Future<void> deleteAll(String hostId) async {
    await _storage.delete(key: '${_prefix}password/$hostId');
    await _storage.delete(key: '${_prefix}key/$hostId');
    await _storage.delete(key: '${_prefix}passphrase/$hostId');
  }
}

/// Acceso único para la feature terminal.
final SshSecrets sshSecrets = SshSecrets();
