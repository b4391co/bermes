import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/logger.dart';
import '../../clients/hermes/http_client.dart';

/// Almacén de secretos: tokens por conexión en secure storage
/// (Keystore Android / DPAPI Windows). NUNCA en la DB ni en logs.
///
/// Resiliencia: si el Keystore se corrompe (reinstalaciones, restore de
/// backup), las lecturas/escrituras resetean el almacén UNA vez; si
/// persiste, degradan a null/false con log (el usuario vuelve a loguearse).
class SecureStore {
  final Logger _log = Logger('SecureStore');
  final FlutterSecureStorage _storage;

  SecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  String _key(String connectionId) => 'session/$connectionId';

  Future<StoredSession?> readSession(String connectionId) async {
    final raw = await _readSafe(_key(connectionId));
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(Map<String, Object?>.from(_decode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSession(String connectionId, StoredSession session) =>
      _storage.write(key: _key(connectionId), value: _encode(session.toJson()));

  Future<void> deleteSession(String connectionId) =>
      _storage.delete(key: _key(connectionId));

  // password del login solo si el usuario activa "recordar" (opcional).
  static const _rememberPrefix = 'remember/';

  Future<String?> readRememberedPassword(String connectionId) =>
      _readSafe('$_rememberPrefix$connectionId');

  Future<void> writeRememberedPassword(String connectionId, String password) =>
      _writeSafe('$_rememberPrefix$connectionId', password);

  Future<void> deleteRememberedPassword(String connectionId) =>
      _storage.delete(key: '$_rememberPrefix$connectionId');

  /// El keystore de Android puede colgar indefinidamente en el PRIMER
  /// acceso tras un arranque en frío (race conocido en algunos emuladores
  /// y dispositivos). Cada acceso lleva timeout y UN reintento; el fallo
  /// degrada a null (no bloquea el bootstrap ni la UI).
  Future<String?> _readSafe(String key) async {
    Future<String?> attempt() => _storage
        .read(key: key)
        .timeout(const Duration(seconds: 6), onTimeout: () => null);
    try {
      final first = await attempt();
      if (first != null) return first;
      return await attempt(); // el keystore tardío suele responder al 2º.
    } catch (e) {
      _log.warning('lectura segura falló; reseteando keystore', e);
      await _tryReset();
      try {
        return await attempt();
      } catch (e2) {
        _log.error('keystore irrecuperable', e2);
        return null;
      }
    }
  }

  Future<void> _writeSafe(String key, String value) async {
    try {
      await _storage
          .write(key: key, value: value)
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      _log.warning('escritura segura falló; reseteando keystore', e);
      await _tryReset();
      await _storage
          .write(key: key, value: value)
          .timeout(const Duration(seconds: 6));
    }
  }

  Future<void> _tryReset() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  static String _encode(Map<String, Object?> json) {
    final parts = <String>[];
    json.forEach((k, v) => parts.add('$k=$v'));
    return parts.join('&');
  }

  static Map<String, String> _decode(String raw) {
    final out = <String, String>{};
    for (final part in raw.split('&')) {
      final eq = part.indexOf('=');
      if (eq > 0) out[part.substring(0, eq)] = part.substring(eq + 1);
    }
    return out;
  }
}
