import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:dio/io.dart';

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

/// Cliente HTTP del dashboard Hermes (`hermes serve`).
///
/// Contratos usados (verificados en commit 3be17b1d, docs/protocol/hermes-map.md §1):
/// - POST /auth/password-login {provider:"basic", username, password} → cookies hermes_session_at/rt
/// - POST /auth/native/refresh {refresh_token} → {access_token, refresh_token, expires_at}
/// - POST /api/auth/ws-ticket → {ticket, ttl_seconds:30}
/// - GET /api/health (público, liveness)
class HermesHttpClient {
  final ConnectionProfile profile;
  final dio.Dio _dio;
  CookieJarForConnection? _cookies;

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

  /// Prueba de conexión REAL en dos etapas (contratos de
  /// docs/protocol/hermes-map.md §1; NO inventa endpoints):
  /// 1. POST /auth/password-login con las credenciales del formulario.
  ///    - 200 → gateway vivo + credenciales válidas (cookies recibidas).
  ///    - 401/403 → gateway vivo, credenciales malas.
  ///    - 404/405 → responde un servidor pero NO es un gateway Hermes
  ///      de esta versión (o ruta base mal configurada).
  /// 2. Si el login no es concluyente (5xx/timeout), fallback GET /
  ///    para distinguir «servidor vivo pero no-Hermes» de «red caída».
  Future<AuthResult> probeTransport({String? username, String? password}) async {
    try {
      final r = await _dio.post<Object?>(
        '/auth/password-login',
        data: {
          'provider': 'basic',
          'username': username ?? '',
          'password': password ?? '',
        },
        options: dio.Options(validateStatus: (c) => c != null && c < 600),
      );
      final code = r.statusCode ?? 0;
      if (code == 200 || code == 204) {
        return const AuthResult.ok();
      }
      if (code == 401 || code == 403) {
        return const AuthResult.fail(
          AuthFailureCause.badCredentials,
          'El gateway responde pero rechazó las credenciales',
        );
      }
      if (code == 404 || code == 405) {
        return const AuthResult.fail(
          AuthFailureCause.version,
          'Hay un servidor en esa dirección pero no responde como un gateway '
          'Hermes (revisa la ruta base, p. ej. /hermes)',
        );
      }
      if (code == 429) {
        return const AuthResult.fail(
          AuthFailureCause.rateLimited,
          'Demasiados intentos; espera un minuto',
        );
      }
      // 5xx u otro código: ¿es siquiera un servidor Hermes? GET / como pista.
      try {
        final root = await _dio.get<String>(
          '/',
          options: dio.Options(
            validateStatus: (c) => c != null && c < 600,
            responseType: dio.ResponseType.plain,
          ),
        );
        final body = root.data ?? '';
        final looksHermes = body.contains('hermes') ||
            body.contains('Hermes') ||
            (root.headers.value('server')?.contains('hermes') ?? false);
        if (root.statusCode == 200 && looksHermes) {
          return AuthResult.fail(
            AuthFailureCause.serverError,
            'El gateway responde ($code en login) pero falló el inicio de '
            'sesión; revisa usuario y contraseña',
          );
        }
        if (root.statusCode == 200) {
          return const AuthResult.fail(
            AuthFailureCause.version,
            'Hay un servidor web pero no parece un gateway Hermes',
          );
        }
      } on dio.DioException {
        // GET / también falló → el problema es de red/servidor.
      }
      return AuthResult.fail(
        AuthFailureCause.serverError,
        'El gateway respondió $code en el login',
      );
    } on dio.DioException catch (e) {
      return AuthResult.fail(_causeFrom(e), e.message);
    } catch (e) {
      return AuthResult.fail(AuthFailureCause.unknown, e.toString());
    }
  }

  AuthFailureCause _causeFrom(dio.DioException e) {
    final type = e.type;
    if (type == dio.DioExceptionType.connectionTimeout ||
        type == dio.DioExceptionType.connectionError) {
      return AuthFailureCause.network;
    }
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) return AuthFailureCause.badCredentials;
    if (code == 429) return AuthFailureCause.rateLimited;
    if (code == 404) {
      return AuthFailureCause.version; // endpoint no existe en esta versión
    }
    if (code != null && code >= 500) return AuthFailureCause.serverError;
    return AuthFailureCause.unknown;
  }

  /// Login usuario/contraseña → cookies hermes_session_at/rt + bearer payload.
  Future<AuthResult> login(String username, String password) async {
    try {
      final r = await _dio.post<Object?>(
        '/auth/password-login',
        data: {
          'provider': 'basic',
          'username': username,
          'password': password,
          'next': '/',
        },
      );
      if (r.statusCode != 200) {
        return AuthResult.fail(
          AuthFailureCause.badCredentials,
          'status ${r.statusCode}',
        );
      }
      // Capturar cookies Set-Cookie para las siguientes peticiones.
      final setCookies = r.headers['set-cookie'] ?? const <String>[];
      _cookies ??= CookieJarForConnection();
      _cookies!.storeFromHeaders(setCookies);
      return const AuthResult.ok();
    } on dio.DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) return AuthResult.fail(AuthFailureCause.badCredentials);
      if (code == 429) {
        return AuthResult.fail(
          AuthFailureCause.rateLimited,
          'demasiados intentos',
        );
      }
      if (code == 404) {
        return AuthResult.fail(
          AuthFailureCause.version,
          '/auth/password-login no existe en este gateway',
        );
      }
      return AuthResult.fail(_causeFrom(e), e.message);
    }
  }

  /// Renovación nativa (para clientes sin cookies).
  Future<AuthResult> refreshSession(String refreshToken) async {
    try {
      final r = await _dio.post<Object?>(
        '/auth/native/refresh',
        data: {'refresh_token': refreshToken},
      );
      if (r.statusCode != 200) {
        return AuthResult.fail(AuthFailureCause.badCredentials);
      }
      return const AuthResult.ok();
    } on dio.DioException catch (e) {
      return AuthResult.fail(_causeFrom(e), e.message);
    }
  }

  /// Mintea ticket WS single-use (requiere sesión).
  Future<String?> mintWsTicket() async {
    try {
      final headers = <String, String>{};
      final cookie = _cookies?.header();
      if (cookie != null) headers['cookie'] = cookie;
      final r = await _dio.post<Object?>(
        '/api/auth/ws-ticket',
        options: dio.Options(headers: headers),
      );
      final data = r.data;
      if (data is Map<String, Object?>) return data['ticket'] as String?;
      if (data is Map) return data['ticket']?.toString();
      return null;
    } on dio.DioException {
      return null;
    }
  }

  void dispose() => _dio.close();
}

/// Cookie jar mínimo por conexión (suficiente: hermes_session_at/rt/provider).
class CookieJarForConnection {
  final Map<String, String> _cookies = {};

  void storeFromHeaders(List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final first = header.split(';').first;
      final eq = first.indexOf('=');
      if (eq > 0) {
        _cookies[first.substring(0, eq).trim()] = first
            .substring(eq + 1)
            .trim();
      }
    }
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
