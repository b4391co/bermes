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
    // Roster de bots SIEMPRE al día: cuando el gateway pasa a ready
    // (arranque, reconexión), se redescubre una vez por transición.
    runtime.gateway.stateStream.listen((s) {
      if (s != GatewayLinkState.ready) return;
      final row = _rowsById[profile.id];
      final db = _db;
      if (row == null || db == null || _syncing.contains(profile.id)) {
        return;
      }
      _syncing.add(profile.id);
      syncBots(row, runtime, db)
          .whenComplete(() => _syncing.remove(profile.id));
    });
    _runtimes[profile.id] = runtime;
    _notify();
    return runtime;
  }

  final _rowsById = <String, Connection>{};
  final _syncing = <String>{};

  /// DB inyectada al bootstrap para el auto-sync de rosters.
  AppDatabase? _db;

  /// Registra filas + DB (bootstrap) para el auto-sync en ready.
  void registerRows(List<Connection> rows, AppDatabase db) {
    _db = db;
    for (final r in rows) {
      _rowsById[r.id] = r;
    }
  }

  Future<void> removeRuntime(String connectionId) async {
    final runtime = _runtimes.remove(connectionId);
    if (runtime != null) {
      await runtime.dispose();
      _rowsById.remove(connectionId);
      _notify();
    }
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
    registerRows(rows, db);
    _log.info('bootstrap: ${rows.length} conexiones');
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
          await runtime.gateway.connect(); // WS ready antes de profiles.list
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
        // has_avatar puede faltar en versiones antiguas del REST: si no dice
        // false explícito, se intenta get_asset (barato; falla → iniciales).
        String? avatarUrl;
        if (p['has_avatar'] != false) {
          try {
            avatarUrl = await runtime.gateway.profileAvatar(name);
          } catch (_) {}
        }
        // Diagnóstico (2): si un gateway manda otra forma, el log muestra
        // las claves crudas del primer perfil para depurarlo sin ciegas.
        if (profiles.indexOf(p) == 0) {
          _log.info('profiles[0] keys=${p.keys.toList()} '
              'display_name=${p['display_name']} has_avatar=${p['has_avatar']}');
        }
        // Chat canónico: ProfileRow.canonical_session trae el session_id
        // de la sesión "Bot Chat" del perfil (hermes-protocol §3, línea
        // tui_gateway/methods_profiles.py::_canonical_session_row). Si el
        // gateway no lo da, fallback session.resume SCOPISADO por perfil.
        // canonical_session puede venir como id (string) o como SessionRow
        // {session_id, title, …} según la versión del gateway.
        String? canonical;
        final rawCanonical = p['canonical_session'];
        if (rawCanonical is String) {
          canonical = rawCanonical;
        } else if (rawCanonical is Map) {
          canonical = rawCanonical['session_id']?.toString();
        }
        canonical ??= await runtime.gateway
            .resumeCanonicalSession(name);
        final id = '${row.id}/bot/$name';
        await db.into(db.conversations).insertOnConflictUpdate(
              ConversationsCompanion.insert(
                id: id,
                connectionId: row.id,
                kind: 'bot',
                gatewayId: name, // identidad estable: nombre del perfil
                title: displayName,
                subtitle: Value(p['description'] as String?),
                avatarSeed: Value(name),
                avatarUrl: Value(avatarUrl),
                canonicalSession: Value(canonical),
                isGroup: const Value(false),
                gatewayLabel: Value(row.name),
              ),
            );
        _log.info('bot sync ${row.name}/$name canonical=${canonical ?? '??'}');
        // Sesiones de Hermes Desktop para este perfil (hermes-map §2/§3):
        // la barra lateral del Desktop es session.list por perfil. Cada fila
        // se refleja como conversación kind='session' reutilizable: identidad
        // estable = session_id si llega; si no, title (session.resume por
        // título funciona igual al abrir). NO borra filas locales.
        try {
          final sessions = await runtime.gateway.listSessions(name);
          for (final s in sessions) {
            final sid = (s['session_id'] ?? s['id'])?.toString();
            final stitle = (s['title'] as String?) ?? 'Sesión';
            if (stitle == 'Bot Chat') continue; // ya es la fila del bot
            final key = sid ?? stitle;
            await db.into(db.conversations).insertOnConflictUpdate(
                  ConversationsCompanion.insert(
                    id: '${row.id}/session/$key',
                    connectionId: row.id,
                    kind: 'session',
                    gatewayId: name,
                    title: stitle,
                    // Las sesiones viven DENTRO de un perfil: en la lista
                    // se desambiguan con el perfil delante del preview.
                    subtitle: Value('$name · ${s['preview'] ?? ''}'),
                    avatarUrl: Value(avatarUrl),
                    canonicalSession: Value(sid),
                    isGroup: const Value(false),
                    gatewayLabel: Value(row.name),
                  ),
                );
          }
          _log.info('sessions sync ${row.name}/$name: ${sessions.length} filas');
        } catch (e) {
          _log.warning('session.list ${row.name}/$name falló', e);
        }
      }
    } catch (e) {
      // Un gateway sin profiles.list (versión antigua) no bloquea nada.
      _log.warning('syncBots ${row.name} falló', e);
    }
  }
}
