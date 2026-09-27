import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'bot_meta.dart';

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

  /// Resincroniza TODAS las conexiones conectadas (bots + sesiones).
  /// Botón de Ajustes: para forzar roster/sesiones sin reiniciar la app.
  Future<void> resyncAll() async {
    final db = _db;
    if (db == null) return;
    for (final entry in _runtimes.entries) {
      final row = _rowsById[entry.key];
      if (row == null || _syncing.contains(entry.key)) continue;
      if (entry.value.gateway.state != GatewayLinkState.ready) continue;
      _syncing.add(entry.key);
      syncBots(row, entry.value, db)
          .whenComplete(() => _syncing.remove(entry.key));
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
      // Decisión del usuario (27/09): SOLO bots en la lista — las sesiones
      // de Desktop se vieron aquí por error y se purgan al primer sync.
      await (db.delete(db.conversations)
            ..where((x) => x.kind.equals('session')))
          .go();
      final profiles = await runtime.gateway.listProfiles();
      for (final p in profiles) {
        final name = p['name'] as String?;
        if (name == null || name.isEmpty) continue;
        // Contrato de nombres hermes-mobile (Profile.kt::effectiveTitle):
        // ui_meta.hermes-bots.title > display_name > name.
        final botMeta = BotRosterMeta.fromProfile(p);
        if (botMeta?.hidden == true) continue; // bot oculto por Desktop
        final displayName = (botMeta?.title?.isNotEmpty ?? false)
            ? botMeta!.title!
            : ((p['display_name'] as String?)?.isNotEmpty ?? false)
                ? p['display_name'] as String
                : name;
        // Avatar (hermes-mobile BotAvatar): ui_meta.hermes-bots.avatar
        // {shape,color,icon,image_url} render nativo; data-url de
        // profiles.get_asset como ÚLTIMO recurso (más barato: solo si no
        // hay meta). image_url del meta puede ser data: o http(s):.
        String? avatarUrl = botMeta?.avatar?.imageUrl;
        if (avatarUrl == null && p['has_avatar'] == true) {
          try {
            avatarUrl = await runtime.gateway.profileAvatar(name);
          } catch (_) {}
        }
        // Diagnóstico: claves crudas del primer perfil (gateways reales).
        if (profiles.indexOf(p) == 0) {
          _log.info('profiles[0] keys=${p.keys.toList()} '
              'title=${botMeta?.title} display_name=${p['display_name']} '
              'avatar_meta=${botMeta?.avatar != null}');
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
          // CanonicalSessionInfo real (hermes-mobile Profile.kt):
          // {id, resolved_id, title, preview, …}. resolved_id > id.
          canonical = (rawCanonical['resolved_id'] ??
                  rawCanonical['id'] ??
                  rawCanonical['session_id'])
              ?.toString();
        }
        // Fallback: session.resume/crea del Bot Chat scopiado por perfil.
        canonical ??= await runtime.gateway.resumeCanonicalSession(name);
        final id = '${row.id}/bot/$name';
        await db.into(db.conversations).insertOnConflictUpdate(
              ConversationsCompanion.insert(
                id: id,
                connectionId: row.id,
                kind: 'bot',
                gatewayId: name, // identidad estable: nombre del perfil
                title: displayName,
                subtitle: Value((botMeta?.description?.isNotEmpty ?? false)
                    ? botMeta!.description
                    : p['description'] as String?),
                avatarSeed: Value(name),
                avatarUrl: Value(avatarUrl),
                botAvatarMeta: Value(botMeta?.avatar == null
                    ? null
                    : const JsonEncoder().convert(botMeta!.avatar!.toJson())),
                isGroup: const Value(false),
                gatewayLabel: Value(row.name),
                canonicalSession: Value(canonical),
              ),
            );
        _log.info('bot sync ${row.name}/$name canonical=${canonical ?? '??'}');
      }
    } catch (e) {
      // Un gateway sin profiles.list (versión antigua) no bloquea nada.
      _log.warning('syncBots ${row.name} falló', e);
    }
  }
}
