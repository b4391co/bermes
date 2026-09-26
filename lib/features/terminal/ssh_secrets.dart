import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/logger.dart';

/// Secretos SSH por host (password, private key, passphrase) en secure
/// storage (Keystore Android / DPAPI). NUNCA en la DB.
///
/// Instancia propia del almacén de plataforma con claves aisladas bajo
/// el prefijo `ssh/` (sin colisión con `session/` ni `remember/`).
///
/// Resiliencia: si el Keystore del dispositivo se corrompe (reinstalaciones,
/// backup restore, cambio de pantalla de bloqueo), la lectura lanza. En vez
/// de romper la conexión SSH, se intenta resetear el almacén UNA vez; si
/// persiste, se degrada a null con log claro (el usuario reintroduce el
/// secreto desde el editor).
class SshSecrets {
  final Logger _log = Logger('SshSecrets');
  final FlutterSecureStorage _storage;

  SshSecrets([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'ssh/';

  Future<String?> readPassword(String hostId) =>
      _readSafe('${_prefix}password/$hostId');

  Future<void> writePassword(String hostId, String password) =>
      _writeSafe('${_prefix}password/$hostId', password);

  Future<String?> readPrivateKey(String hostId) =>
      _readSafe('${_prefix}key/$hostId');

  Future<void> writePrivateKey(String hostId, String pem) =>
      _writeSafe('${_prefix}key/$hostId', pem);

  Future<String?> readPassphrase(String hostId) =>
      _readSafe('${_prefix}passphrase/$hostId');

  Future<void> writePassphrase(String hostId, String passphrase) =>
      _writeSafe('${_prefix}passphrase/$hostId', passphrase);

  /// Borra TODOS los secretos SSH de un host.
  Future<void> deleteAll(String hostId) async {
    await _storage.delete(key: '${_prefix}password/$hostId');
    await _storage.delete(key: '${_prefix}key/$hostId');
    await _storage.delete(key: '${_prefix}passphrase/$hostId');
  }

  Future<String?> _readSafe(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _log.warning('lectura segura falló; reseteando keystore', e);
      await _tryReset();
      try {
        return await _storage.read(key: key);
      } catch (e2) {
        _log.error('keystore irrecuperable; secreto no disponible', e2);
        return null;
      }
    }
  }

  Future<void> _writeSafe(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _log.warning('escritura segura falló; reseteando keystore', e);
      await _tryReset();
      await _storage.write(key: key, value: value);
    }
  }

  Future<void> _tryReset() async {
    try {
      await _storage.deleteAll();
    } catch (_) {
      // Nada más que hacer: el siguiente acceso volverá a fallar y se
      // degradará a null.
    }
  }
}

/// Acceso único para la feature terminal.
final SshSecrets sshSecrets = SshSecrets();
