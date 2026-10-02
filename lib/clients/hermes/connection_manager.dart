import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'bot_meta.dart';

import '../../data/database/app_database.dart'
    show AppDatabase, Connection, ConversationsCompanion, ConnectionsCompanion;
import '../../core/logger.dart';
import '../../data/secure/secure_store.dart';
import '../../domain/connection/connection_profile.dart';
import 'gateway_client.dart';
import 'profile_canonical.dart';
import '../../features/conversations/group_rooms.dart';
import '../../features/conversations/group_sync.dart';
import 'http_client.dart';

/// Instancia viva de UNA conexión: su cliente HTTP, su cliente WS y su estado.
class ConnectionRuntime {
  final ConnectionProfile profile;
  final HermesHttpClient http;
  final HermesGatewayClient gateway;

  factory ConnectionRuntime(ConnectionProfile profile) {
    final http = HermesHttpClient(profile);
    return ConnectionRuntime._(
      profile,
      http,
      HermesGatewayClient(profile, http),
    );
  }

  /// El gate rotó la sesión bearer en mitad de una ruta: hay que persistirla
  /// (nunca en la DB; el gestor la escribe en secure storage).
  Future<void> Function(String connectionId, StoredSession session)?
  onSessionRotated;

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
      // Un gateway recién listo refresca SU roster y luego aplica el espejo de
      // salas con el roster de las demás conexiones ya vistas.
      unawaited(_refreshOne(profile.id, db).then((_) => _syncGroupMirrors(db)));
    });
    _runtimes[profile.id] = runtime;
    _notify();
    return runtime;
  }

  final _rowsById = <String, Connection>{};
  final _syncing = <String>{};

  /// DB inyectada al bootstrap para el auto-sync de rosters.
  AppDatabase? _db;

  /// Almacén de secretos inyectado por el bootstrap (sesiones y contraseñas
  /// recordadas). El login posterior al guardado lo reutiliza para persistir.
  SecureStore? _secrets;

  /// Registra filas + DB (bootstrap) para el auto-sync en ready.
  void registerRows(
    List<Connection> rows,
    AppDatabase db, {
    SecureStore? secrets,
  }) {
    _db = db;
    if (secrets != null) _secrets = secrets;
    for (final r in rows) {
      _rowsById[r.id] = r;
    }
  }

  /// Colecciona los perfiles de cada gateway listo y luego los refresca.
  ///
  /// El espejo de grupos de Desktop viaja en el perfil `default` de CADA
  /// conexión y puede nombrar miembros de otra (`group-chat.ts:88-91`: la
  /// proyección COMPLETA se publica en todos los gateways). Por eso el sync de
  /// salas necesita ver el roster de TODAS las conexiones a la vez, no el de
  /// una sola.
  Future<void> resyncAll() async {
    final db = _db;
    if (db == null) return;
    for (final id in _collectReady()) {
      await _refreshOne(id, db);
    }
    await _syncGroupMirrors(db);
  }

  /// Refresca UNA conexión y su parte de las salas.
  Future<void> resyncOne(String connectionId) async {
    final db = _db;
    if (db == null) return;
    await _refreshOne(connectionId, db);
    await _syncGroupMirrors(db);
  }

  List<String> _collectReady() {
    final out = <String>[];
    for (final entry in _runtimes.entries) {
      if (_syncing.contains(entry.key)) continue;
      if (entry.value.gateway.state != GatewayLinkState.ready) continue;
      if (!_rowsById.containsKey(entry.key)) continue;
      out.add(entry.key);
    }
    return out;
  }

  Future<void> _refreshOne(String connectionId, AppDatabase db) async {
    final row = _rowsById[connectionId];
    final runtime = _runtimes[connectionId];
    if (row == null || runtime == null) return;
    if (!_snapshotByConn.containsKey(connectionId) &&
        runtime.gateway.state != GatewayLinkState.ready) {
      return;
    }
    _syncing.add(connectionId);
    try {
      await syncBots(row, runtime, db);
    } finally {
      _syncing.remove(connectionId);
    }
  }

  /// Aplica a todas las conexiones el espejo de salas acumulado en este ciclo.
  Future<void> _syncGroupMirrors(AppDatabase db) async {
    final states = <ConnectionGroupState>[];
    for (final entry in _snapshotByConn.entries) {
      final row = _rowsById[entry.key];
      if (row == null) continue;
      states.add(
        ConnectionGroupState(
          id: entry.key,
          label: row.name,
          profiles: entry.value.profiles,
          titles: entry.value.titles,
          displayOrder: row.displayOrder,
          createdAt: row.createdAt,
        ),
      );
    }
    if (states.isEmpty) return;
    try {
      await syncGroupMirrors(db: db, connections: states);
    } catch (e) {
      _log.warning('syncGroupMirrors falló', e);
    }
  }

  /// Espejo de salas + roster visto por conexión en el último sync.
  final _snapshotByConn = <String, _ConnRoster>{};

  Future<void> removeRuntime(String connectionId) async {
    _snapshotByConn.remove(connectionId);
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
  /// persistida y restaura su sesión.
  ///
  /// Orden fiel al contrato (las sesiones del Pocket son de cookie o bearer,
  /// nunca del flujo RFC 8252 con navegador del Desktop):
  ///  1. sesión bearer guardada → `GET /api/auth/me` la valida baratísimo
  ///     (routes.py:449-455). Si responde, ésa es la identidad vigente y NO se
  ///     toca la contraseña.
  ///  2. si caducó, se rota con el refresh token (`POST /auth/native/refresh`,
  ///     routes.py:496-519). Un 401 `session_expired` es terminal; un 503 es
  ///     el proveedor inalcanzable y NO borra la sesión (routes.py:499-500).
  ///  3. sin bearer útil: contraseña recordada → `POST /auth/password-login`
  ///     con el nombre de proveedor anunciado por el gate (routes.py:183-192,
  ///     372-418). El proveedor NO se hardcodea: es 404 si no existe.
  ///
  /// Tras una sesión usable se abre el WS (un ticket por conexión,
  /// routes.py:458-466). Sin sesión válida el runtime queda vivo pero "sin
  /// conexión": el chat marca error reintentable en lugar de fingir
  /// conectividad.
  Future<void> bootstrap(
    List<Connection> rows, {
    required SecureStore secrets,
    required AppDatabase db,
  }) async {
    _secrets = secrets;
    registerRows(rows, db, secrets: secrets);
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
        authKind:
            HermesAuthKind.values.asNameMap()[row.authKind] ??
            HermesAuthKind.password,
        username: row.username,
        allowInsecureTls: row.allowInsecureTls,
        enabled: row.enabled,
      );
      final runtime = ensureRuntime(profile);
      runtime.onSessionRotated = (id, session) =>
          secrets.writeSession(id, session);
      final signedIn = await _restoreSession(runtime, row, secrets);
      _log.info('bootstrap ${row.name}: sesion=$signedIn');
      if (!signedIn) continue;
      try {
        // connect() NO lanza: los estados de fallo se propagan por
        // stateStream. Si aquí no se espera a ready, el listener de
        // ensureRuntime (que hace el sync en la transición) corre a la vez
        // que este syncBots y la segunda pasada falla con 'not connected'
        // contra un socket que aún está negociando. Se espera el ready con
        // un tope; si no llega, syncBots de abajo falla con causa clara.
        await runtime.gateway.connect();
        await runtime.gateway.readyOrTimeout(const Duration(seconds: 20));
        await syncBots(row, runtime, db);
      } catch (e) {
        _log.warning('bootstrap ${row.name} no conectó', e);
      }
    }
  }

  /// Devuelve true si el runtime quedó con una sesión utilizable.
  Future<bool> _restoreSession(
    ConnectionRuntime runtime,
    Connection row,
    SecureStore store,
  ) async {
    // 1) sesión bearer guardada: `/api/auth/me` es la comprobación barata y es
    //    LA ÚNICA que demuestra una sesión bearer viva (routes.py:449-455).
    final stored = await store.readSession(row.id);
    if (stored != null) {
      runtime.http.restoreSession(
        stored,
        onRotated: (session) => store.writeSession(row.id, session),
      );
      if (await runtime.http.authMe() != null) return true;
      final rt = stored.refreshToken;
      if (rt != null && rt.isNotEmpty) {
        final refreshed = await runtime.http.refreshSession(rt);
        final session = refreshed.session;
        switch (refreshed.outcome) {
          case RefreshOutcome.rotated:
            await store.writeSession(row.id, session!.toStored());
            return true;
          case RefreshOutcome.expired:
          case RefreshOutcome.rejected:
            // Terminal (routes.py:516-519): fuera el bearer para que la
            // contraseña recordada pueda volver a autenticar.
            await store.deleteSession(row.id);
            runtime.http.forgetSession();
          case RefreshOutcome.providerUnavailable:
          case RefreshOutcome.transport:
            // Transitorio: el contrato prohíbe forzar re-login aquí
            // (routes.py:499-500, request_utils.py:48-50) → se conserva la
            // sesión y NO se gasta el anti-fuerza-bruta con un login.
            _log.info(
              'bootstrap ${row.name}: proveedor de auth no alcanzable; se '
              'conserva la sesión guardada',
            );
            return false;
        }
      } else {
        await store.deleteSession(row.id);
        runtime.http.forgetSession();
      }
    }
    // 2) session token de gateway loopback: estático, no rotable; la
    //    comprobación de vida es la MISMA que el bearer (/api/auth/me).
    if (row.authKind == 'sessionToken') {
      final token = await store.readGatewayToken(row.id);
      _log.info('restore ${row.name}: sessionToken presente=${token != null}');
      if (token == null || token.isEmpty) return false;
      runtime.http.adoptGatewayToken(token);
      final me = await runtime.http.authMe();
      _log.info('restore ${row.name}: authMe=${me != null}');
      if (me != null) return true;
      runtime.http.forgetGatewayToken();
      _log.warning(
        'restore ${row.name}: el session token fue rechazado por '
        'el gateway. Si el gateway está tras un portal OAuth (gate), el '
        'token NO vale: vuelve al método Usuario. Se intenta la contraseña '
        'recordada como respaldo.',
      );
      // FALLBACK: si hay contraseña recordada, recuperar el acceso en vez de
      // quedarse sin conexión (el usuario puede haber migrado a token por
      // error contra un gateway gated).
      final fallbackPw = await store.readRememberedPassword(row.id);
      if (fallbackPw != null && fallbackPw.isNotEmpty) {
        final result = await login(
          runtime,
          username: row.username,
          password: fallbackPw,
        );
        _log.info('restore ${row.name}: fallback password ok=${result.ok}');
        return result.ok;
      }
      return false;
    }
    // 3) contraseña recordada → sesión de cookie.
    final password = await store.readRememberedPassword(row.id);
    if (password == null || password.isEmpty) return false;
    final result = await login(
      runtime,
      username: row.username,
      password: password,
    );
    _log.info('bootstrap login ${row.name}: ok=${result.ok}');
    return result.ok;
  }

  /// Autenticación con contraseña: `POST /auth/password-login` con el nombre de
  /// proveedor que anuncia el gate (routes.py:372-418) y, como hace el
  /// Desktop, UN mint de `POST /api/auth/ws-ticket` para CONFIRMAR que la
  /// sesión es realmente utilizable (oauth-rest-request.ts:130-186,
  /// connection-config.ts:1119: la comprobación de vida es el propio mint).
  ///
  /// El gate NUNCA devuelve tokens en el body del login (routes.py:413-417 +
  /// cookies.py:90-106: sólo HttpOnly Set-Cookie, ilegibles para la app), así
  /// que persistir `access_token: ''` sería una sesión fantasma: el mint
  /// devuelve lo que hace viva la sesión entre arranques — el bearer rotado
  /// de `/auth/native/refresh` (routes.py:491-519) si este gateway lo soporta,
  /// y si no, la cookie que el propio cliente HTTP conserva en su tarro.
  Future<AuthResult> login(
    ConnectionRuntime runtime, {
    required String username,
    required String password,
    String provider = '',
  }) async {
    final result = await runtime.http.login(
      username,
      password,
      provider: provider,
    );
    if (!result.ok) return result;
    if (await runtime.http.mintWsTicket() == null) {
      runtime.http.forgetSession();
      return const AuthResult.fail(
        AuthFailureCause.badCredentials,
        'El gateway aceptó las credenciales pero no concede un ticket WS: '
        'la sesión no es utilizable',
      );
    }
    final bearer = runtime.http.accessToken;
    if (bearer != null && bearer.isNotEmpty) {
      await _secrets?.writeSession(
        runtime.profile.id,
        StoredSession(
          accessToken: bearer,
          refreshToken: runtime.http.refreshToken,
        ),
      );
    }
    return result;
  }

  /// Abre el WS y sincroniza el roster de una conexión ya autenticada.
  ///
  /// Lo usa el editor tras guardar: mantiene el único camino de conexión
  /// (ticket por conexión, routes.py:458-466) en el gestor y no en la UI.
  Future<void> connectAndSync(ConnectionRuntime runtime, Connection row) async {
    final db = _db;
    await runtime.gateway.connect();
    if (db == null) return;
    registerRows([row], db);
    await syncBots(row, runtime, db);
  }

  /// Descubre los bots del gateway (hermes-map §4: profiles.list) y los
  /// refleja como conversaciones kind='bot' en la caché local. NO borra
  /// filas locales: la eliminación local es explícita del usuario.
  ///
  /// Los GRUPOS ya no se descubren aquí: la sala vive en el espejo
  /// `ui_meta['hermes-bots-groups']` del perfil `default` y la aplica
  /// `syncGroupMirrors` (ver `group_sync.dart`), que necesita ver el roster de
  /// todas las conexiones. Aquí solo se acumula ese espejo y se anotan los
  /// nombres de grupo del bot en su subtítulo
  /// (`ui_meta['hermes-bots'].groups`, `types.ts:75`).
  Future<void> syncBots(
    Connection row,
    ConnectionRuntime runtime,
    AppDatabase db,
  ) async {
    try {
      // El PIN es preferencia LOCAL: se preserva a través del upsert de sync
      // (insertOnConflictUpdate escribiría el default false si no lo llevamos).
      // La fila previa COMPLETA sirve también para saltar escrituras sin
      // cambios: reescribir el row reemite el watch de la lista y los
      // avatares parpadean (re-decodificación) en cada sync.
      final priorRows = {
        for (final r in await db.select(db.conversations).get()) r.id: r,
      };
      final priorPins = {
        for (final e in priorRows.entries)
          e.key: (e.value.pinned, e.value.pinnedGateway),
      };
      // Decisión del usuario (27/09): SOLO bots en la lista — las sesiones
      // de Desktop se vieron aquí por error y se purgan al primer sync.
      await (db.delete(
        db.conversations,
      )..where((x) => x.kind.equals('session'))).go();
      // Limpieza de huérfanas: conversaciones de conexiones ya eliminadas
      // (el alta de una conexión nueva no debe dejar filas fantasma duplicadas).
      final live = (await db.select(db.connections).get())
          .map((c) => c.id)
          .toSet();
      await (db.delete(db.conversations)..where(
            (x) => x.connectionId.isNotIn(live.isEmpty ? ['@'] : live.toList()),
          ))
          .go();
      final profiles = await runtime.gateway.listProfiles();
      // Identidad portable del backend para los descriptores de miembro de
      // grupo (/api/status.install_id, types.ts:103-106). Best-effort: un
      // gateway viejo sin install_id deja la columna null y el descriptor
      // sale sin installId (Desktop hace lo mismo con roster rows fantasma).
      try {
        final iid = await runtime.http.installId();
        if (iid != null && iid != row.installId) {
          await (db.update(db.connections)..where((c) => c.id.equals(row.id)))
              .write(ConnectionsCompanion(installId: Value(iid)));
        }
      } catch (_) {}
      final roster = _ConnRoster();
      for (final p in profiles) {
        final name = p['name'] as String?;
        if (name == null || name.isEmpty) continue;
        // Contrato de nombres canónico (labels.ts::displayName y
        // hermes-mobile Profile.kt::effectiveTitle):
        // ui_meta.hermes-bots.title > display_name > name.
        final botMeta = BotRosterMeta.fromProfile(p);
        if (botMeta?.hidden == true) continue; // bot oculto por Desktop
        final displayName = (botMeta?.title?.isNotEmpty ?? false)
            ? botMeta!.title!
            : ((p['display_name'] as String?)?.isNotEmpty ?? false)
            ? p['display_name'] as String
            : name;
        roster.titles[name] = displayName;
        // Espejo de salas: SOLO el perfil `default` de cada gateway lo lleva
        // (Desktop lo publica ahí, `group-chat.ts:1180-1182`).
        if (name == 'default') {
          final snap = GroupSyncSnapshot.tryParse(
            (p['ui_meta'] is Map)
                ? (p['ui_meta'] as Map)['hermes-bots-groups']
                : null,
          );
          if (snap != null) {
            // Membresía bot→grupo de TODOS los perfiles de este gateway
            // (`ui_meta.hermes-bots.groups`, `types.ts:75`): se acumula en una
            // pasada aparte porque `profiles` incluye el propio `p`.
            final membership = <String>{
              for (final q in profiles)
                ...?BotRosterMeta.fromProfile(q)?.groups,
            };
            roster.profiles.add(
              GatewayProfileSnapshot(
                name: name,
                groups: snap,
                membershipNames: membership,
              ),
            );
          }
        }
        // Avatar: tres fuentes, en este orden de prioridad.
        //  1. `ui_meta.hermes-bots.avatar.icon` (Material) — el icono que el
        //     usuario ELIGIÓ en Pocket; manda sobre lo que publique el host
        //     para que "quitar el icono" sea posible en un bot con asset.
        //  2. `avatar.image_url` del meta (data: o http(s)) — filing de
        //     otros clientes.
        //  3. asset `profiles.get_asset` (data-url) — sólo si `has_avatar` y
        //     no hay nada anterior (es la más cara: viaja entera en cada
        //     sync). Si el gateway ya tenía asset y el usuario puso icono,
        //     se limpia la caché para no seguir mostrándolo.
        String? avatarUrl;
        final pickedIcon = botMeta?.avatar?.icon;
        if (pickedIcon == null) {
          avatarUrl = botMeta?.avatar?.imageUrl;
          if (avatarUrl == null && p['has_avatar'] == true) {
            try {
              avatarUrl = (await runtime.gateway.profileAvatar(name))?.dataUrl;
            } catch (_) {}
          }
        }
        // Diagnóstico: claves crudas del primer perfil (gateways reales).
        if (profiles.indexOf(p) == 0) {
          _log.info(
            'profiles[0] keys=${p.keys.toList()} '
            'title=${botMeta?.title} display_name=${p['display_name']} '
            'avatar_meta=${botMeta?.avatar != null}',
          );
        }
        // Chat canónico: la sesión la posee DESKTOP. La app NUNCA crea
        // sesiones nuevas (session.create inventaría una sesión que Desktop
        // no ve y partiría el historial en dos). Se usa la que el gateway
        // publica en ProfileRow.canonical_session ({id, resolved_id}); si no
        // hay, session.resume {title:'Bot Chat', profile} — que si el Bot
        // Chat no existe aún, fallará y el chat lo reportará con causa.
        String? canonical = canonicalFromProfile(p);
        canonical ??= await runtime.gateway.resumeCanonicalSession(name);
        // Membresía del bot: `ui_meta.hermes-bots.groups` es una lista de
        // NOMBRES (`types.ts:75`), la única representación de pertenencia que
        // publica Desktop. No es una sala: nunca se materializa como
        // conversación propia (haría PK de un nombre visible y duplicaría la
        // sala en cuanto el espejo la cubra). Se anota en el subtítulo.
        final groupNames = botMeta?.groups ?? const <String>[];
        final desc = (botMeta?.description?.isNotEmpty ?? false)
            ? botMeta!.description
            : null;
        final subtitle = groupNames.isEmpty
            ? desc
            : (desc == null || desc.isEmpty
                  ? 'Grupos: ${groupNames.join(', ')}'
                  : '$desc · Grupos: ${groupNames.join(', ')}');
        final id = '${row.id}/bot/$name';
        final prior = priorRows[id];
        final newMeta = botMeta?.avatar == null
            ? null
            : const JsonEncoder().convert(botMeta!.avatar!.toJson());
        final unchanged =
            prior != null &&
            prior.title == displayName &&
            prior.subtitle == subtitle &&
            prior.avatarUrl == avatarUrl &&
            prior.botAvatarMeta == newMeta &&
            prior.canonicalSession == canonical;
        if (unchanged) {
          continue; // nada cambió: no reemitir el watch (parpadeo de iconos)
        }
        await db
            .into(db.conversations)
            .insertOnConflictUpdate(
              ConversationsCompanion.insert(
                id: id,
                connectionId: row.id,
                kind: 'bot',
                gatewayId: name, // identidad estable: nombre del perfil
                title: displayName,
                subtitle: Value(subtitle),
                avatarSeed: Value(name),
                avatarUrl: Value(avatarUrl),
                botAvatarMeta: Value(newMeta),
                isGroup: const Value(false),
                gatewayLabel: Value(row.name),
                canonicalSession: Value(canonical),
                pinned: Value(priorPins[id]?.$1 ?? false),
                pinnedGateway: Value(priorPins[id]?.$2 ?? false),
              ),
            );
        _log.info('bot sync ${row.name}/$name canonical=${canonical ?? '??'}');
      }
      _snapshotByConn[row.id] = roster;
    } catch (e) {
      // Un gateway sin profiles.list (versión antigua) no bloquea nada.
      _log.warning('syncBots ${row.name} falló', e);
    }
  }
}

/// Roster + espejo de salas visto por una conexión en el último sync.
class _ConnRoster {
  final List<GatewayProfileSnapshot> profiles = [];
  final Map<String, String> titles = {};
}
