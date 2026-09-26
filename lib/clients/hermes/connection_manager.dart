import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart'
    show AppDatabase, Connection, ConversationsCompanion;
import '../../core/logger.dart';
import '../../data/secure/secure_store.dart';
import '../../domain/connection/connection_profile.dart';
import 'gateway_client.dart';
import 'http_client.dart';

/// Instancia viva de UNA conexión: su cliente HTTP, su cliente WS y su estado.
class ConnectionRuntime {
  final ConnectionProfile profile;
  final HermesHttpClient http;
  final HermesGatewayClient gateway;

  factory ConnectionRuntime(ConnectionProfile profile) {
    final http = HermesHttpClient(profile);
    return ConnectionRuntime._(profile, http, HermesGatewayClient(profile, http));
  }

  ConnectionRuntime._(this.profile, this.http, this.gateway);

  Future<void> dispose() async {
    await gateway.disconnect();
    gateway.dispose();
    http.dispose();
  }
}

/// Gestor de N conexiones simultáneas e independientes.
///
/// - Cada gateway tiene su runtime aislado: sesión, tokens, cookies, WS.
/// - Un gateway caído NO bloquea el resto.
/// - Eliminar una conexión local no toca nada del servidor.
class ConnectionManager {
  final _log = Logger('ConnManager');
  final _runtimes = <String, ConnectionRuntime>{};
  final _controller =
      StreamController<Map<String, ConnectionRuntime>>.broadcast();

  Map<String, ConnectionRuntime> get runtimes => Map.unmodifiable(_runtimes);
  Stream<Map<String, ConnectionRuntime>> get stream => _controller.stream;

  ConnectionRuntime? runtimeFor(String connectionId) => _runtimes[connectionId];

  ConnectionRuntime ensureRuntime(ConnectionProfile profile) {
    final existing = _runtimes[profile.id];
    if (existing != null) return existing;
    final runtime = ConnectionRuntime(profile);
    _runtimes[profile.id] = runtime;
    _notify();
    return runtime;
  }

  Future<void> removeRuntime(String connectionId) async {
    final runtime = _runtimes.remove(connectionId);
    if (runtime != null) {
      await runtime.dispose();
      _notify();
    }
    _log.info('runtime removed $connectionId');
  }

  void _notify() => _controller.add(Map.unmodifiable(_runtimes));

  Future<void> disposeAll() async {
    for (final r in _runtimes.values) {
      await r.dispose();
    }
    _runtimes.clear();
    await _controller.close();
  }

  /// Bootstrap al arrancar la app: crea el runtime de cada conexión
  /// persistida y autentica con la contraseña recordada (si la hay).
  /// Sin sesión válida el runtime queda vivo pero "sin conexión": el chat
  /// marca error reintentable en lugar de fingir conectividad.
  Future<void> bootstrap(
    List<Connection> rows, {
    required SecureStore secrets,
    required AppDatabase db,
  }) async {
    for (final row in rows) {
      if (!row.enabled) continue;
      if (_runtimes.containsKey(row.id)) continue;
      final profile = ConnectionProfile(
        id: row.id,
        name: row.name,
        scheme: row.scheme,
        host: row.host,
        port: row.port,
        basePath: row.basePath,
        authKind: HermesAuthKind.values.asNameMap()[row.authKind] ??
            HermesAuthKind.password,
        username: row.username,
        allowInsecureTls: row.allowInsecureTls,
        enabled: row.enabled,
      );
      final runtime = ensureRuntime(profile);
      final password = await secrets.readRememberedPassword(row.id);
      if (password == null || password.isEmpty) continue;
      try {
        final result = await runtime.http.login(profile.username, password);
        _log.info('bootstrap login ${row.name}: ok=${result.ok}');
        if (result.ok) {
          await syncBots(row, runtime, db);
        }
      } catch (e) {
        _log.warning('bootstrap login ${row.name} falló', e);
      }
    }
  }

  /// Descubre los bots del gateway (hermes-map §4: profiles.list) y los
  /// refleja como conversaciones kind='bot' en la caché local. NO borra
  /// filas locales: la eliminación local es explícita del usuario.
  Future<void> syncBots(
    Connection row,
    ConnectionRuntime runtime,
    AppDatabase db,
  ) async {
    try {
      final profiles = await runtime.gateway.listProfiles();
      for (final p in profiles) {
        final name = p['name'] as String?;
        if (name == null || name.isEmpty) continue;
        final displayName = (p['display_name'] as String?) ?? name;
        // Avatar REAL del perfil (igual que Hermes Desktop): data-url.
        String? avatarUrl;
        if (p['has_avatar'] == true) {
          try {
            avatarUrl = await runtime.gateway.profileAvatar(name);
          } catch (_) {}
        }
        final id = '${row.id}/bot/$name';
        // Chat canónico del bot (hermes-map §4): sesión con título exacto
        // "Bot Chat". session.resume trae el session_id runtime REAL que
        // exige prompt.submit; sin él el envío falla (sesión inexistente).
        String? canonicalSessionId;
        try {
          final resumed = await runtime.gateway.rawCall(
            'session.resume',
            params: {'title': 'Bot Chat'},
          );
          if (resumed is Map<String, Object?>) {
            canonicalSessionId = resumed['session_id'] as String?;
          }
        } catch (_) {}
        await db.into(db.conversations).insertOnConflictUpdate(
              ConversationsCompanion.insert(
                id: id,
                connectionId: row.id,
                kind: 'bot',
                gatewayId: canonicalSessionId ?? name,
                title: displayName,
                subtitle: Value(p['description'] as String?),
                avatarSeed: Value(name),
                avatarUrl: Value(avatarUrl),
                isGroup: const Value(false),
                gatewayLabel: Value(row.name),
              ),
            );
        _log.info(
          'bot sync ${row.name}/$name session=${canonicalSessionId ?? '??'}',
        );
      }
    } catch (e) {
      // Un gateway sin profiles.list (versión antigua) no bloquea nada.
      _log.warning('syncBots ${row.name} falló', e);
    }
  }
}
