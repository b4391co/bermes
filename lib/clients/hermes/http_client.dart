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

  /// Prueba de conexión REAL: comprueba /api/health y /api/status (públicos)
  /// y que el transporte funcione; NO basta con que cualquier página responda.
  Future<AuthResult> probeTransport() async {
    try {
      final r = await _dio.get<Object?>('/api/health');
      if (r.statusCode == 200) return const AuthResult.ok();
      return AuthResult.fail(
        AuthFailureCause.serverError,
        'health status ${r.statusCode}',
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
