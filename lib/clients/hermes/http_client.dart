import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:dio/io.dart';

import '../../core/logger.dart';
import '../../domain/connection/connection_profile.dart';

/// Resultado de autenticación con causas diferenciadas para diagnóstico.
enum AuthFailureCause {
  network,
  badCredentials,
  rateLimited,
  version,
  serverError,
  unknown,
}

class AuthResult {
  final bool ok;
  final AuthFailureCause? cause;
  final String? detail;

  const AuthResult.ok() : ok = true, cause = null, detail = null;
  const AuthResult.fail(this.cause, [this.detail]) : ok = false;
}

/// Resultado de `POST /api/audio/transcribe` (web_models.py:84-86;
/// audio.py:87-141).
class TranscribeResult {
  final bool ok;

  /// Texto transcrito (el backend NO persiste el audio: no hay tipo
  /// «voice note»; esto es lo único que viaja al chat).
  final String text;

  /// Causa diferenciada para diagnóstico:
  /// [AuthFailureCause.version] = 400 sin proveedor STT (el gateway no
  /// distingue por código: se saca del detail);
  /// [AuthFailureCause.badCredentials] = 401 sesión muerta;
  /// [AuthFailureCause.rateLimited] = 413 payload >25 MB;
  /// [AuthFailureCause.serverError] = resto (incl. 200 sin habla).
  final AuthFailureCause? cause;
  final String? detail;

  /// Proveedor STT que respondió (`provider` en la respuesta real,
  /// audio.py:138-141); se muestra en el diagnóstico, no en el chat.
  final String? provider;

  const TranscribeResult.ok(this.text, this.provider)
    : ok = true,
      cause = null,
      detail = null;
  const TranscribeResult.fail(this.cause, [this.detail])
    : ok = false,
      text = '',
      provider = null;
}

/// Sesión guardada en secure storage (tokens), una por conexión.
class StoredSession {
  final String accessToken;
  final String? refreshToken;
  final int? expiresAtMs;

  const StoredSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAtMs,
  });

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (expiresAtMs != null) 'expires_at': expiresAtMs,
  };

  factory StoredSession.fromJson(Map<String, Object?> json) => StoredSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String?,
    expiresAtMs: json['expires_at'] as int?,
  );
}

/// Tokens bearer de una sesión nativa (`_bearer_payload`, routes.py:110-115).
class NativeSession {
  final String accessToken;
  final String refreshToken;

  /// `exp` del access token, en segundos desde el epoch (routes.py:113).
  final int? expiresAt;
  final String provider;
  final String userId;

  const NativeSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt,
    this.provider = '',
    this.userId = '',
  });

  StoredSession toStored() => StoredSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAtMs: expiresAt == null ? null : expiresAt! * 1000,
  );
}

/// Clasificación de un POST /auth/native/refresh (routes.py:496-519).
enum RefreshOutcome {
  /// 200: tokens rotados en el body.
  rotated,

  /// 401 `session_expired`: el RT ya no lo acepta NINGÚN proveedor → hay que
  /// volver a iniciar sesión (routes.py:499, 516-519).
  expired,

  /// 503: proveedor de autenticación inalcanzable. El contrato lo distingue
  /// justamente para NO forzar re-login (routes.py:499-500,
  /// request_utils.py:48-50).
  providerUnavailable,

  /// 400 (`refresh_token` vacío) u otro código inesperado.
  rejected,

  /// Fallo de red/timeout: transitorio, igual que 503.
  transport,
}

class RefreshResult {
  final RefreshOutcome outcome;
  final NativeSession? session;
  final String? detail;

  const RefreshResult(this.outcome, {this.session, this.detail});

  bool get ok => outcome == RefreshOutcome.rotated;

  /// Nada que reintentar YA: hay que volver a autenticarse.
  bool get terminal => outcome == RefreshOutcome.expired;
}

/// Cliente HTTP del dashboard Hermes (`hermes serve`).
///
/// Contrato REAL verificado contra el SPA autorizado (hermes-agent e408d36);
/// las citas son de ese repo:
/// - GET  /api/health · /api/status → públicos (dashboard_auth/public_paths.py:12,15),
///   responden sin sesión y delatan la identidad/version del gateway
///   (web_routers/status.py:116-121, 458-502). Son la sonda de transporte.
/// - POST /auth/password-login {provider,username,password,next} → JSON
///   `{ok:true,next}` + cookies de sesión, u 8 estados 3xx si el proveedor es
///   un portal OAuth con manija nativa (routes.py:372-418). El proveedor NO es
///   "basic": hay que leer su nombre de `GET /api/auth/providers`
///   (routes.py:183-192) — un nombre equivocado es 404 (routes.py:385-388).
/// - POST /auth/native/refresh {refresh_token,provider} → body bearer
///   `{access_token,refresh_token,token_type,expires_at,provider,user_id}`
///   (routes.py:491-519 + `_bearer_payload` routes.py:110-115). 401
///   `session_expired` = re-login; 503 = proveedor inalcanzable, transitorio.
/// - POST /api/auth/ws-ticket → `{ticket,ttl_seconds:30}` single-use
///   (routes.py:458-466, ws_tickets.py:21,36-46).
/// - GET  /api/auth/me → identidad de la sesión vigente (routes.py:449-455).
/// - Autenticación de las rutas privadas: cookie HttpOnly **o**
///   `Authorization: Bearer` (middleware.py:166-174, request_utils.py:25-30).
/// - El gate renueva la sesión cookie con el RT de forma transparente y
///   re-emite Set-Cookie en CUALQUIER ruta autenticada (middleware.py:184-202,
///   128-142): por eso toda respuesta autenticada alimenta el tarro de cookies.
class HermesHttpClient {
  final ConnectionProfile profile;
  final dio.Dio _dio;
  CookieJarForConnection? _cookies;

  /// Bearer de la sesión nativa de ESTA conexión (`_bearer_payload`,
  /// routes.py:110-115). Alternativa a la cookie en las rutas autenticadas
  /// (middleware.py:166-174).
  String? _bearer;

  /// Refresh token en memoria (se persiste sólo en secure storage).
  String? _refreshToken;

  /// Pista de proveedor para el giro (`hermes_session_provider`,
  /// cookies.py:29, 82-87).
  String _providerHint = '';

  /// Renovación en vuelo: un solo giro de RT para todas las rutas que
  /// recibieron 401 concurrentemente (espejo local de refresh_singleflight.py;
  /// el RT es de un solo uso, middleware.py:213-231).
  Future<RefreshResult>? _refreshInFlight;

  /// Aviso del gestor: el gate rotó la sesión → persistirla.
  void Function(StoredSession session)? _onSessionRotated;

  /// Los secretos quedan enmascarados por Logger.
  static final _log = Logger('HttpClient');

  HermesHttpClient(this.profile, {dio.HttpClientAdapter? adapterOverride})
    : _dio = dio.Dio() {
    _dio.options
      ..baseUrl = profile.baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers = {'user-agent': 'HermesPocket/0.1'};
    _dio.httpClientAdapter = adapterOverride ?? _makeAdapter();
  }

  dio.HttpClientAdapter _makeAdapter() {
    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final client = HttpClient();
      if (profile.allowInsecureTls && profile.scheme == 'https') {
        // Opción EXPLÍCITA y advertida del usuario (solo para HTTPS con CA propia en LAN).
        // No se desactiva globalmente: se aplica solo a esta conexión.
        client.badCertificateCallback = ((cert, host, port) =>
            host == profile.host);
      }
      return client;
    };
    return adapter;
  }

  /// Prueba de transporte: **sin credenciales**, solo comprueba que hay un
  /// gateway Hermes respondiendo.
  ///
  /// El contrato real NO expone un login que un cliente nativo pueda sondear:
  /// `POST /auth/password-login` (routes.py:372-418) necesita el nombre del
  /// proveedor, exige body JSON válido, puede reenviar (302) al portal y
  /// confunde credenciales malas (401) con proveedor desconocido (404).
  /// Dispararlo desde «Probar conexión» además consumiría el presupuesto
  /// anti-fuerza-bruta de 10 intentos / 60 s por IP
  /// (routes.py:338-339, 382-384) y bloquearía el login real del usuario.
  ///
  /// Se sonda `GET /api/status`, que es pública aunque el panel esté tras el
  /// gate (public_paths.py:15) y es el mismo probe de latencia que lee el
  /// Desktop (connection-config.ts:18, main.ts:10615): sus campos `version` /
  /// `auth_required` (web_routers/status.py:458-502) identifican el servidor.
  ///
  /// [username]/[password] se aceptan por compatibilidad con el editor y NO se
  /// envían a ninguna parte.
  Future<AuthResult> probeTransport({
    String? username,
    String? password,
  }) async {
    try {
      final r = await _dio.get<Object?>(
        '/api/status',
        options: dio.Options(
          validateStatus: (c) => c != null && c < 600,
          responseType: dio.ResponseType.json,
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final code = r.statusCode ?? 0;
      if (code == 200) {
        final data = r.data;
        final isHermes =
            data is Map &&
            (data.containsKey('auth_required') || data.containsKey('version'));
        if (isHermes) return const AuthResult.ok();
        return const AuthResult.fail(
          AuthFailureCause.version,
          'Hay un servidor en esa dirección pero no responde como un gateway '
          'Hermes (revisa la ruta base, p. ej. /hermes)',
        );
      }
      if (code == 404 || code == 405) {
        return const AuthResult.fail(
          AuthFailureCause.version,
          'Hay un servidor web pero no expone /api/status: no es un gateway '
          'Hermes de esta versión (o falta la ruta base)',
        );
      }
      if (code == 429) {
        return const AuthResult.fail(
          AuthFailureCause.rateLimited,
          'Demasiados intentos; espera un minuto',
        );
      }
      return AuthResult.fail(
        AuthFailureCause.serverError,
        'El gateway respondió $code en /api/status',
      );
    } on dio.DioException catch (e) {
      return AuthResult.fail(_causeFrom(e), e.message);
    } catch (e) {
      return AuthResult.fail(AuthFailureCause.unknown, e.toString());
    }
  }

  List<Map<String, Object?>>? _providersCache;

  /// Proveedores interactivos anunciados por el gate (routes.py:183-192 —
  /// ruta pública por _GATE_PUBLIC_PREFIXES, middleware.py:41). El nombre del
  /// proveedor de contraseña NO es fijo: el SPA lo lee aquí
  /// (native-auth-decisions.ts:183-195). null = el gateway no lo expone.
  Future<List<Map<String, Object?>>?> authProviders() async {
    if (_providersCache != null) return _providersCache;
    try {
      final r = await _dio.get<Object?>(
        '/api/auth/providers',
        options: dio.Options(
          responseType: dio.ResponseType.json,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final data = r.data;
      final rows = data is Map ? data['providers'] : const <Object?>[];
      if (rows is! List) return null;
      return _providersCache = rows.whereType<Map<String, Object?>>().toList(
        growable: false,
      );
    } on dio.DioException catch (e) {
      _log.info('/api/auth/providers no disponible: ${e.message}');
    } catch (_) {}
    return null;
  }

  /// Nombre del proveedor que acepta contraseña (routes.py:385-388 devuelve
  /// 404 «Unknown provider» para cualquiera que no la soporte).
  Future<String?> passwordProviderName() async {
    final providers = await authProviders();
    if (providers == null || providers.isEmpty) return null;
    for (final p in providers) {
      if (p['supports_password'] == true) return p['name'] as String?;
    }
    return null;
  }

  /// Login usuario/contraseña → cookies de sesión (`hermes_session_at/rt/
  /// provider`, cookies.py:27-29).
  ///
  /// [provider] es el nombre anunciado por el gate; vacío = se resuelve con
  /// [passwordProviderName]. El body son EXACTAMENTE las claves del modelo
  /// `{provider,username,password,next}` (routes.py:365-369): Pydantic responde
  /// 422 si falta alguna, y `next` sólo se revalida como path de mismo
  /// origen (routes.py:92-96, request_utils.py:33-40).
  Future<AuthResult> login(
    String username,
    String password, {
    String provider = '',
  }) async {
    var name = provider;
    if (name.isEmpty) {
      // Sin lista de proveedores no adivinamos: el contrato no fija ningún
      // nombre (un "basic" inventado sería 404 en un gateway real).
      final discovered = await passwordProviderName();
      if (discovered == null) {
        return const AuthResult.fail(
          AuthFailureCause.version,
          'El gateway no anuncia ningún proveedor de contraseña '
          '(GET /api/auth/providers)',
        );
      }
      name = discovered;
    }
    try {
      final r = await _dio.post<Object?>(
        '/auth/password-login',
        data: {
          'provider': name,
          'username': username,
          'password': password,
          'next': '/',
        },
        // El login NUNCA se reintentar: un replay duplicado gasta el
        // anti-fuerza-bruta (routes.py:338-339). [replayOn401] es para
        // lecturas idempotentes como el mint de ticket.
        options: dio.Options(
          followRedirects: false,
          validateStatus: (c) => c != null && c < 600,
        ),
      );
      final code = r.statusCode ?? 0;
      if (code >= 300 && code < 400) {
        // El gate redirige a /login (o al portal) cuando la sesión no se
        // estableció por cookie: no hay sesión que guardar.
        _cookies?.clear();
        return const AuthResult.fail(
          AuthFailureCause.version,
          'El gateway reenvió el inicio de sesión a un portal OAuth; esta '
          'versión del Pocket solo completa sesiones por contraseña o bearer',
        );
      }
      if (code == 429) {
        return const AuthResult.fail(
          AuthFailureCause.rateLimited,
          'Demasiados intentos; espera un minuto',
        );
      }
      // La señal de éxito es la cookie AT: routes.py:413-417 sólo emite
      // Set-Cookie cuando la sesión se completó; el body `{ok,next}` no trae
      // tokens (routes.py:110-115 es del flujo nativo).
      if (observeCookies(r)) {
        _bearer = null; // la cookie manda; un bearer viejo no debe reaparecer
        _log.info('login ok por cookie (proveedor $name)');
        return const AuthResult.ok();
      }
      return AuthResult.fail(
        code == 401 ? AuthFailureCause.badCredentials : _causeOf(code),
        'password-login sin cookie de sesión (HTTP $code)',
      );
    } on dio.DioException catch (e) {
      return AuthResult.fail(_causeFrom(e), e.message);
    }
  }

  /// Instala una sesión bearer (p. ej. leída del secure storage) en este
  /// cliente. Desde ese momento la identificación preferente es
  /// `Authorization: Bearer` (middleware.py:166-174); el gate NO rota el
  /// bearer por nosotros: esta app debe llamar [refreshSession].
  void adoptBearerSession(StoredSession session) {
    _bearer = session.accessToken;
  }

  /// AccessToken en uso (null = solo cookies).
  String? get accessToken => _bearer;

  /// POST /auth/native/refresh {refresh_token,provider} (routes.py:491-519).
  ///
  /// [provider] es la pista de enrutamiento (`hermes_session_provider`,
  /// cookies.py:29, 82-87): vacío = el gate recorre todos los proveedores.
  /// Coalescido: si ya hay un giro en vuelo, se comparte su resultado en vez
  /// de rotar el RT dos veces (el RT es de un solo uso por proveedor;
  /// middleware.py:213-231, refresh_singleflight.py).
  Future<RefreshResult> refreshSession(
    String refreshToken, {
    String provider = '',
  }) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final fut = _doRefresh(refreshToken, provider);
    _refreshInFlight = fut;
    try {
      return await fut;
    } finally {
      if (identical(_refreshInFlight, fut)) _refreshInFlight = null;
    }
  }

  Future<RefreshResult> _doRefresh(String refreshToken, String provider) async {
    if (refreshToken.isEmpty) {
      return const RefreshResult(
        RefreshOutcome.rejected,
        detail: 'refresh_token requerido',
      );
    }
    try {
      final r = await _dio.post<Object?>(
        '/auth/native/refresh',
        data: {'refresh_token': refreshToken, 'provider': provider},
        options: dio.Options(
          responseType: dio.ResponseType.json,
          validateStatus: (c) => c != null && c < 600,
        ),
      );
      final code = r.statusCode ?? 0;
      final body = r.data;
      final map = body is Map<String, Object?>
          ? body
          : const <String, Object?>{};
      if (code == 200) {
        final at = map['access_token'];
        final rt = map['refresh_token'];
        if (at is! String || at.isEmpty || rt is! String || rt.isEmpty) {
          return const RefreshResult(
            RefreshOutcome.rejected,
            detail: 'respuesta sin access_token/refresh_token',
          );
        }
        final exp = switch (map['expires_at']) {
          final int v => v,
          final double v => v.toInt(),
          final String v => int.tryParse(v),
          _ => null,
        };
        return RefreshResult(
          RefreshOutcome.rotated,
          session: NativeSession(
            accessToken: at,
            refreshToken: rt,
            expiresAt: exp,
            provider: map['provider'] as String? ?? provider,
            userId: map['user_id'] as String? ?? '',
          ),
        );
      }
      if (code == 401) {
        // routes.py:516-519: todos los proveedores rechazaron el RT.
        _bearer = null;
        _cookies?.clear();
        return const RefreshResult(
          RefreshOutcome.expired,
          detail: 'session_expired; hay que volver a iniciar sesión',
        );
      }
      if (code == 503) {
        return const RefreshResult(
          RefreshOutcome.providerUnavailable,
          detail: 'proveedor de autenticación inalcanzable',
        );
      }
      return RefreshResult(
        RefreshOutcome.rejected,
        detail: 'native/refresh respondió $code',
      );
    } on dio.DioException catch (e) {
      if (e.type == dio.DioExceptionType.connectionTimeout ||
          e.type == dio.DioExceptionType.receiveTimeout ||
          e.type == dio.DioExceptionType.connectionError ||
          e.response == null) {
        return const RefreshResult(RefreshOutcome.transport);
      }
      return RefreshResult(
        RefreshOutcome.rejected,
        detail: e.response?.statusCode.toString(),
      );
    }
  }

  /// Mintea el ticket WS single-use de 30 s (routes.py:458-466).
  ///
  /// Idempotente-replay-seguro: si la sesión cookie caducó, el gate la renueva
  /// solo (middleware.py:184-202) o este mint reintenta UNA vez tras un
  /// /auth/native/refresh propio — igual que Desktop
  /// (oauth-rest-request.ts:130-186: timeout 8 s, `replayOn401: true`, y
  /// `[shouldRotateNativeTokenAfterRejection]` sólo para 401 estructurado,
  /// native-auth-decisions.ts:254-256). Un 403 NO rota: es una negativa de
  /// política sobre una identidad ya reconocida.
  Future<String?> mintWsTicket() async {
    Future<String?> attempt() async {
      final r = await _authorized<Object?>(
        send: (headers) => _dio.post<Object?>(
          '/api/auth/ws-ticket',
          // Sin body: el endpoint no lo declara (routes.py:458-466).
          options: dio.Options(
            headers: headers,
            responseType: dio.ResponseType.json,
            validateStatus: (c) => c != null && c < 600,
            // Desktop: 8 s (oauth-rest-request.ts:137).
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        ),
        read: (r) => r?.data,
      );
      final data = r;
      return data is Map ? data['ticket']?.toString() : null;
    }

    final first = await attempt();
    if (first != null) return first;
    final rotated = await _rotateBearer();
    if (!rotated) return null;
    return attempt();
  }

  /// GET JSON autenticado (rutas REST que el WS no refleja, p. ej.
  /// /api/profiles — web_routers/profiles.py). Reidentifica una vez ante 401.
  Future<dynamic> getJson(String path) async {
    final data = await _authorized<Object?>(
      send: (headers) => _dio.get<Object?>(
        path,
        options: dio.Options(
          headers: headers,
          responseType: dio.ResponseType.json,
          validateStatus: (c) => c != null && c < 600,
        ),
      ),
      read: (r) => _unwrap(r),
    );
    return data;
  }

  /// POST JSON autenticado. Lanza en error HTTP: el llamador decide. NO se
  /// reintenta ante 401 salvo que [replayOn401] lo pida — una mutación
  /// duplicada sí tiene efecto.
  Future<dynamic> postJson(
    String path, {
    Map<String, Object?>? body,
    bool replayOn401 = false,
  }) async {
    final data = await _authorized<Object?>(
      send: (headers) => _dio.post<Object?>(
        path,
        data: body,
        options: dio.Options(
          headers: headers,
          responseType: dio.ResponseType.json,
          validateStatus: (c) => c != null && c < 600,
        ),
      ),
      read: (r) => _unwrap(r),
    );
    return data;
  }

  /// PUT JSON autenticado. `PUT /api/profiles/{name}/model`
  /// (hermes_cli/web_routers/profiles.py:1040-1051, body {provider, model}).
  Future<dynamic> putJson(String path, {Map<String, Object?>? body}) async {
    final data = await _authorized<Object?>(
      send: (headers) => _dio.put<Object?>(
        path,
        data: body,
        options: dio.Options(
          headers: headers,
          responseType: dio.ResponseType.json,
          validateStatus: (c) => c != null && c < 600,
        ),
      ),
      read: (r) => _unwrap(r),
    );
    return data;
  }

  /// Transcripción de una nota de voz: `POST /api/audio/transcribe`.
  ///
  /// Contrato VERIFICADO en main (no commit objetivo):
  /// - request: web_models.py:84-86 `AudioTranscriptionRequest` exige
  ///   `data_url` (data-url con prefijo `data:`, `;base64` y coma — sin eso
  ///   400 "Audio payload must be base64 encoded", audio.py:87-95) y
  ///   `mime_type?` opcional (default `audio/webm`; el gate exige `audio/*`
  ///   o exactamente `video/webm`, audio.py:97-101).
  /// - respuesta: audio.py:138-141 `{ok, transcript, provider}` — la clave es
  ///   `transcript`, NO `text`. Silencio → 200 con `transcript: ""`
  ///   (audio.py:133-136): el Pocket lo distingue de un fallo.
  /// - sin proveedor STT configurado → 400 (NO 503); payload >25 MB → 413
  ///   (_MAX_TRANSCRIPTION_UPLOAD_BYTES, audio.py:52). Causas que el Pocket
  ///   diferencia de un fallo de red y NO reintenta a ciegas.
  /// El resultado es TEXTO: el backend no persiste el audio (no existe tipo
  /// 'voice note' en el contrato).
  Future<TranscribeResult> transcribeAudio(
    List<int> bytes, {
    required String mimeType,
  }) async {
    final outcome = await _authorized<Object?>(
      send: (headers) => _dio.post<Object?>(
        '/api/audio/transcribe',
        data: {
          'data_url': 'data:${mimeType};base64,${base64Encode(bytes)}',
          'mime_type': mimeType,
        },
        options: dio.Options(
          headers: headers,
          responseType: dio.ResponseType.json,
          validateStatus: (c) => c != null && c < 600,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      ),
      // El código importa para el diagnóstico: 400 sin STT ≠ 400 de payload,
      // 413 demasiado grande, 401 sesión muerta. read ve la respuesta entera.
      read: (r) => {'status': r?.statusCode ?? 0, 'body': r?.data},
    );
    final status = (outcome is Map ? outcome['status'] : null) as int? ?? 0;
    final data = outcome is Map ? outcome['body'] : null;
    final detail = data is Map
        ? (data['detail'] as String? ??
              (data['error'] is Map
                  ? (data['error'] as Map)['message'] as String?
                  : data['message'] as String?))
        : null;
    if (status == 200) {
      final text = data is Map ? data['transcript'] : null;
      if (text is String && text.isNotEmpty) {
        return TranscribeResult.ok(text, data['provider'] as String?);
      }
      // 200 con transcript vacío = grabación sin habla (audio.py:133-136).
      return const TranscribeResult.fail(
        AuthFailureCause.serverError,
        'No se reconoció ninguna palabra en la grabación',
      );
    }
    if (status == 401) {
      return const TranscribeResult.fail(
        AuthFailureCause.badCredentials,
        'La sesión caducó; vuelve a iniciar sesión en esta conexión',
      );
    }
    if (status == 413) {
      return const TranscribeResult.fail(
        AuthFailureCause.rateLimited,
        'La grabación supera el límite del gateway (25 MB)',
      );
    }
    if (status == 400) {
      // El gateway no distingue por código: sin STT y payload inválido son
      // ambos 400. La causa se saca del detail cuando lo hay.
      return TranscribeResult.fail(
        AuthFailureCause.version,
        detail == null || detail.isEmpty
            ? 'Este gateway no pudo transcribir (proveedor STT sin configurar)'
            : 'Transcripción rechazada: $detail',
      );
    }
    return TranscribeResult.fail(
      AuthFailureCause.serverError,
      'transcribe respondió HTTP $status',
    );
  }

  /// Bytes de un adjunto subido (imagen) vía `GET /api/media?path=…`.
  /// Contrato VERIFICADO en main (hermes_cli/web_routers/files.py:301-339):
  /// responde JSON `{data_url: "data:image/png;base64,…"}` — NO binario —,
  /// sólo extensiones de imagen (png/jpg/jpeg/gif/webp/svg/bmp/ico) con tope
  /// 25 MB, y restringido a las raíces `<HERMES_HOME>/{images,screenshots,
  /// cache}`; fuera de ellas → 403 «Path outside media roots». En multiperfil
  /// la imagen de OTRO perfil puede caer fuera de la raíz del dashboard →
  /// el Pocket pinta entonces su respaldo local (MessageAttachment.localBytes)
  /// o la ficha con nombre. null si el gateway no lo expone (versión antigua).
  Future<List<int>?> fetchMedia(String path) async {
    try {
      final data = await _authorized<Object?>(
        send: (headers) => _dio.get<Object?>(
          '/api/media',
          queryParameters: {'path': path},
          options: dio.Options(
            headers: headers,
            responseType: dio.ResponseType.json,
            validateStatus: (c) => c != null && c < 600,
            receiveTimeout: const Duration(seconds: 20),
          ),
        ),
        // Sólo 200 tiene {data_url}; 403 fuera de raíces, 404 inexistente,
        // 415 no-imagen y versiones antiguas sin ruta → null (fallback UI).
        read: (r) => (r?.statusCode ?? 0) == 200 ? _unwrap(r) : null,
      );
      final url = data is Map ? data['data_url'] : null;
      if (url is! String || url.isEmpty) return null;
      final comma = url.indexOf(',');
      if (!url.startsWith('data:') || comma < 0) return null;
      try {
        final bytes = base64Decode(url.substring(comma + 1));
        return bytes.isEmpty ? null : bytes;
      } on FormatException {
        return null;
      }
    } on dio.DioException {
      return null;
    }
  }

  /// Bytes de CUALQUIER archivo entregable vía
  /// `GET /api/fs/read-data-url?path=…&profile=…` (files.py:901-922, la MISMA
  /// ruta que usa Desktop para resolver `MEDIA:` sobre un gateway remoto).
  /// Responde `{dataUrl: "data:<mime>;base64,…"}` con el mime sniffado del
  /// archivo (mime_type.py) y tope `_FS_DATA_URL_MAX_BYTES` (413 si excede).
  /// A diferencia de /api/media no está restringido a imágenes ni a las
  /// raíces del dashboard: la ruta se valida contra el HOME del perfil
  /// (`_fs_path`, files.py:885-899 → session_id/profile pinnan owner).
  /// [profile] pinna el perfil dueño (sessionReadOwnerPin: sin él un host
  /// que no es dueño puede 404). null si el gateway no lo expone (versión
  /// antigua) o el archivo es demasiado grande / está fuera de raíz.
  Future<({List<int> bytes, String mime})?> fetchFsDataUrl(
    String path, {
    String? profile,
  }) async {
    try {
      final data = await _authorized<Object?>(
        send: (headers) => _dio.get<Object?>(
          '/api/fs/read-data-url',
          queryParameters: {
            'path': path,
            if (profile != null && profile.isNotEmpty)
              'profile': profile,
          },
          options: dio.Options(
            headers: headers,
            responseType: dio.ResponseType.json,
            validateStatus: (c) => c != null && c < 600,
            receiveTimeout: const Duration(seconds: 30),
          ),
        ),
        read: (r) => (r?.statusCode ?? 0) == 200 ? _unwrap(r) : null,
      );
      final url = data is Map ? data['dataUrl'] : null;
      if (url is! String || url.isEmpty) return null;
      final comma = url.indexOf(',');
      if (!url.startsWith('data:') || comma < 0) return null;
      final mime = url.substring(5, comma).split(';').first;
      try {
        final bytes = base64Decode(url.substring(comma + 1));
        if (bytes.isEmpty) return null;
        return (bytes: bytes, mime: mime.isEmpty ? 'application/octet-stream' : mime);
      } on FormatException {
        return null;
      }
    } on dio.DioException {
      return null;
    }
  }

  /// Lee la identidad de la sesión vigente (routes.py:449-455):
  /// `{user_id,email,display_name,org_id,provider,expires_at}`. null si no
  /// hay sesión utilizable — es la comprobación de sesión barata del bootstrap.
  /// Identidad estable del backend (`/api/status.install_id`, status.py:521-526):
  /// portable entre clientes — la usa el descriptor de miembro de grupo
  /// (types.ts:103-106). null si el gateway no la expone.
  Future<String?> installId() async {
    try {
      final data = await _authorized<Object?>(
        send: (headers) => _dio.get<Object?>(
          '/api/status',
          options: dio.Options(
            headers: headers,
            responseType: dio.ResponseType.json,
            validateStatus: (c) => c != null && c < 600,
          ),
        ),
        read: (r) => _unwrap(r),
      );
      final id = data is Map ? data['install_id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } on dio.DioException {
      return null;
    }
  }

  Future<Map<String, Object?>?> authMe() async {
    try {
      final data = await _authorized<Map<String, Object?>?>(
        send: (headers) => _dio.get<Object?>(
          '/api/auth/me',
          options: dio.Options(
            headers: headers,
            responseType: dio.ResponseType.json,
            validateStatus: (c) => c != null && c < 600,
          ),
        ),
        read: (r) {
          // 401 = sesión inexistente: null, no el body del error
          // (un Map del 401 haría creer a la UI que hay sesión viva).
          if ((r?.statusCode ?? 0) != 200) return null;
          final data = r?.data;
          return data is Map<String, Object?> ? data : null;
        },
      );
      return data;
    } on dio.DioException {
      return null;
    }
  }

  // ── mecanismo de identificación ───────────────────────────────────────

  /// Cabeceras de identificación para una ruta privada: cookie de sesión
  /// (si la hay) y bearer (si la sesión es nativa). El gate acepta cualquiera
  /// de las dos y la cookie tiene prioridad de rotación transparente
  /// (middleware.py:166-202).
  Map<String, String> _authHeaders() {
    final headers = <String, String>{};
    final cookie = _cookies?.header();
    if (cookie != null) headers['cookie'] = cookie;
    final bearer = _bearer;
    if (bearer != null) headers['authorization'] = 'Bearer $bearer';
    final gw = _gatewayToken;
    if (gw != null) {
      // Header dedicado (web_server.py:441-445 evita colisiones con proxies
      // que ya usan Authorization) + Bearer legacy (446-449).
      headers['x-hermes-session-token'] = gw;
      headers['authorization'] = 'Bearer $gw';
    }
    return headers;
  }

  /// Ejecuta [send] identificada y devuelve [read].
  ///
  /// El gate renueva la sesión cookie **en la propia respuesta** de cualquier
  /// ruta autenticada y re-emite Set-Cookie (middleware.py:184-202 +
  /// _serve_refreshed): por eso [observeCookies] alimenta el tarro en cada
  /// respuesta, éxito o fallo.
  ///
  /// Ante 401 se reintenta UNA vez tras forzar /auth/native/refresh, y sólo
  /// cuando [replayOn401] es verdad (la lectura debe no tener efecto). Un 401
  /// sin bearer rotatable se propaga: eso es "sesión caducada" para la UI
  /// (connection-config.ts:99-108, 115-138).
  Future<T?> _authorized<T>({
    required Future<dio.Response<Object?>?> Function(
      Map<String, String> headers,
    )
    send,
    required T? Function(dio.Response<Object?>? response) read,
    bool replayOn401 = true,
  }) async {
    final first = await send(_authHeaders());
    final code = first?.statusCode ?? 0;
    if (first != null) observeCookies(first);
    if (code != 401) return read(first);
    if (!replayOn401) return read(first);
    // Sólo un 401 estructurado gana un giro de token; un 403 es una negativa
    // de política que un bearer nuevo no cambia
    // (native-auth-decisions.ts:239-256).
    if (!await _rotateBearer()) return read(first);
    final again = await send(_authHeaders());
    if (again != null) observeCookies(again);
    return read(again);
  }

  /// Fuerza un giro bearer con el RT guardado. true = bearer nuevo instalado.
  Future<bool> _rotateBearer() async {
    final rt = _refreshToken;
    if (rt == null || rt.isEmpty) return false;
    final result = await refreshSession(rt, provider: _providerHint);
    final session = result.session;
    if (!result.ok || session == null) return false;
    _bearer = session.accessToken;
    _refreshToken = session.refreshToken;
    if (session.provider.isNotEmpty) _providerHint = session.provider;
    _onSessionRotated?.call(session.toStored());
    return true;
  }

  /// Semilla la sesión bearer desde el almacén seguro (tokens que esta app
  /// ya obtuvo de /auth/native/refresh).
  void restoreSession(
    StoredSession session, {
    String provider = '',
    void Function(StoredSession)? onRotated,
  }) {
    _bearer = session.accessToken;
    _refreshToken = session.refreshToken;
    _providerHint = provider;
    _onSessionRotated = onRotated;
  }

  /// Session token de gateway loopback (`HERMES_DASHBOARD_SESSION_TOKEN`,
  /// web_server.py:351-357). Enviado como `X-Hermes-Session-Token`
  /// (web_routers/profiles.py:5-19: todas las /api/* lo aceptan en modo
  /// loopback; el legacy `Authorization: Bearer <token>` se manda también
  /// por compatibilidad con bundles antiguos, web_server.py:446-449).
  String? _gatewayToken;

  void adoptGatewayToken(String token) => _gatewayToken = token;

  void forgetGatewayToken() => _gatewayToken = null;

  /// Token activo (solo lectura para el WS `?token=`,
  /// web_server_chat.py:291-297). null = modo gated por ticket.
  String? get gatewayToken => _gatewayToken;

  /// true = la identificación activa NO es rotable por la app (token fijo).
  bool get hasGatewayToken => _gatewayToken != null;

  /// Refresh token en memoria (para persistirlo tras un giro).
  String? get refreshToken => _refreshToken;

  /// Descarta la sesión (cookie + bearer) tras un rechazo confirmado.
  void forgetSession() {
    _cookies?.clear();
    _bearer = null;
    _refreshToken = null;
  }

  AuthFailureCause _causeOf(int code) {
    if (code == 401 || code == 403) return AuthFailureCause.badCredentials;
    if (code == 429) return AuthFailureCause.rateLimited;
    if (code == 404 || code == 405) return AuthFailureCause.version;
    if (code >= 500) return AuthFailureCause.serverError;
    return AuthFailureCause.unknown;
  }

  AuthFailureCause _causeFrom(dio.DioException e) {
    final type = e.type;
    if (type == dio.DioExceptionType.connectionTimeout ||
        type == dio.DioExceptionType.connectionError ||
        type == dio.DioExceptionType.sendTimeout) {
      return AuthFailureCause.network;
    }
    if (type == dio.DioExceptionType.receiveTimeout) {
      return AuthFailureCause.serverError;
    }
    final code = e.response?.statusCode;
    if (code == null) return AuthFailureCause.network;
    return _causeOf(code);
  }

  /// Devuelve true si la respuesta trae la cookie de sesión access-token
  /// (`hermes_session_at` o cualquiera de sus variantes de prefijo
  /// `__Host-`/`__Secure-`, cookies.py:27,34,47-51). Ésa es la única señal de
  /// que el gate aceptó la sesión: el body no trae tokens
  /// (routes.py:413-417 + `_set_session` routes.py:103-107).
  bool observeCookies(dio.Response<Object?> r) {
    final setCookies =
        r.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
    if (setCookies.isEmpty) return false;
    _cookies ??= CookieJarForConnection();
    _cookies!.storeFromHeaders(setCookies);
    return _cookies!.hasSession();
  }

  /// Datos del envoltorio `dio.Response` o null si el status no es 2xx.
  Object? _unwrap(dio.Response<Object?>? r) {
    final code = r?.statusCode ?? 0;
    if (code < 200 || code >= 300) return null;
    return r?.data;
  }

  void dispose() => _dio.close();
}

/// Cookie jar mínimo por conexión (suficiente: hermes_session_at/rt/provider).
class CookieJarForConnection {
  final Map<String, String> _cookies = {};

  /// Guarda/borra cookies según el atributo `Max-Age` y el valor.
  ///
  /// El gate puede emitir el nombre con prefijo `__Host-` o `__Secure-` según
  /// la forma del despliegue (cookies.py:33-34, 47-51) y, al cerrar sesión,
  /// borrados `Max-Age=0` para TODAS las variantes (cookies.py:109-128).
  void storeFromHeaders(List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final first = header.split(';').first;
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (value.isEmpty || _isExpired(header)) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  static bool _isExpired(String setCookieHeader) {
    for (final attr in setCookieHeader.split(';').skip(1)) {
      final kv = attr.trim();
      if (kv.toLowerCase().startsWith('max-age=')) {
        return (int.tryParse(kv.substring(8).trim()) ?? 1) <= 0;
      }
      if (kv.toLowerCase().startsWith('expires=')) {
        // HttpDate.parse lanza con cualquier cosa que no sea IMF-fixdate;
        // un borrado cuyo formato no entendemos se aplica igualmente.
        try {
          return !HttpDate.parse(
            kv.substring(8).trim(),
          ).isAfter(DateTime.now());
        } on FormatException {
          return true;
        }
      }
    }
    return false;
  }

  /// True when the jar holds an access-token cookie, under any of its name
  /// variants (cookies.py:27,33-34).
  bool hasSession() => _sessionCookieName() != null;

  String? _sessionCookieName() {
    for (final variant in const ['__Host-', '__Secure-', '']) {
      final value = _cookies['${variant}hermes_session_at'];
      if (value != null && value.isNotEmpty) return variant;
    }
    return null;
  }

  String? header() {
    if (_cookies.isEmpty) return null;
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void clear() => _cookies.clear();
}

/// Utilidad para parsear JSON NDJSON del WS.
Stream<Map<String, Object?>> parseNdjson(Stream<String> lines) async* {
  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, Object?>) yield decoded;
    } on FormatException {
      // Frame inválido: ignorar y seguir (el backend manda NDJSON estricto).
    }
  }
}
