import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/connection/connection_profile.dart';
import '../../clients/hermes/http_client.dart';

/// Almacén de secretos: tokens por conexión en secure storage
/// (Keystore Android / DPAPI Windows). NUNCA en la DB ni en logs.
class SecureStore {
  final FlutterSecureStorage _storage;

  SecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  String _key(String connectionId) => 'session/$connectionId';

  Future<StoredSession?> readSession(String connectionId) async {
    final raw = await _storage.read(key: _key(connectionId));
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
      _storage.read(key: '$_rememberPrefix$connectionId');

  Future<void> writeRememberedPassword(String connectionId, String password) =>
      _storage.write(key: '$_rememberPrefix$connectionId', value: password);

  Future<void> deleteRememberedPassword(String connectionId) =>
      _storage.delete(key: '$_rememberPrefix$connectionId');

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

/// Wrapper tipado para la sesión de una conexión concreta.
extension ConnectionSessionX on SecureStore {
  Future<ConnectionSession?> readConnectionSession(ConnectionProfile p) async {
    final s = await readSession(p.id);
    if (s == null) return null;
    return ConnectionSession(
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      expiresAt: s.expiresAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.expiresAtMs!),
    );
  }
}
