/// Modelo de conexión a un gateway Hermes.
///
/// Cada conexión tiene nombre, dirección, credenciales y estado INDEPENDIENTES.
/// Un gateway caído no bloquea el resto.
library;

enum HermesAuthKind {
  /// `POST /auth/password-login` → cookies HttpOnly de sesión
  /// (`hermes_session_at/rt`, dashboard_auth/cookies.py:27-29).
  password,

  /// Sesión bearer (`Authorization: Bearer`) sembrada desde secure storage.
  /// El gate la acepta en cualquier ruta privada
  /// (dashboard_auth/middleware.py:166-174) pero NO la rota por nosotros: la
  /// app debe llamar `POST /auth/native/refresh` (routes.py:496-519).
  bearerToken,

  /// Session token de gateway en modo loopback: el valor de
  /// `HERMES_DASHBOARD_SESSION_TOKEN` (web_server.py:351-357). Se envía como
  /// `X-Hermes-Session-Token` en REST (todas las /api/* lo aceptan,
  /// web_routers/profiles.py:5-19) y `?token=` en el WS
  /// (web_server_chat.py:291-297). SOLO vale en gateways sin gate OAuth:
  /// en modo gated el token ni se inyecta ni se acepta.
  sessionToken,

  /// Gateway sin autenticación: `GET /api/status` responde
  /// `auth_required: false` (web_routers/status.py). REST y WS se abren sin
  /// credenciales. Típico de instalaciones LAN antiguas/loopback (p. ej.
  /// Hermes 0.15.0).
  none,
}

class ConnectionProfile {
  final String id; // UUID local estable
  final String name;
  final String scheme; // http | https
  final String host;
  final int port;
  final String basePath; // ej. '' o '/hermes'
  final HermesAuthKind authKind;
  final String username;
  final bool allowInsecureTls; // opción explícita y advertida, solo http LAN
  final bool enabled;

  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.scheme,
    required this.host,
    required this.port,
    this.basePath = '',
    this.authKind = HermesAuthKind.password,
    this.username = '',
    this.allowInsecureTls = false,
    this.enabled = true,
  });

  /// Base URL para HTTP: scheme://host:port/basePath
  String get baseUrl {
    final b = basePath.isEmpty
        ? ''
        : (basePath.startsWith('/') ? basePath : '/$basePath');
    return '$schemeOrigin$b';
  }

  /// `scheme://host:port` sin ruta base — el valor del header `Origin` que
  /// los gateways con `ui_surface: webapp` exigen en los writes con cookie
  /// (hermes_cli/dashboard_auth: 'Cookie-authenticated writes must come
  /// from the dashboard's own origin').
  String get schemeOrigin {
    final p =
        (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443)
        ? ''
        : ':$port';
    return '$scheme://$host$p';
  }

  /// Ruta WS del gateway JSON-RPC: `basePath` + `/api/ws`
  /// (hermes_cli/web_routers/chat_ws.py:595 `@router.websocket("/api/ws")`).
  String get wsPath => '$basePath/api/ws';

  /// URL WebSocket derivada: ws(s)://host:port/basePath/api/ws
  String get wsUrl {
    final wsScheme = scheme == 'https' ? 'wss' : 'ws';
    return '${baseUrl.replaceFirst(RegExp(r'^https?'), wsScheme)}/api/ws';
  }

  ConnectionProfile copyWith({
    String? name,
    String? scheme,
    String? host,
    int? port,
    String? basePath,
    HermesAuthKind? authKind,
    String? username,
    bool? allowInsecureTls,
    bool? enabled,
  }) {
    return ConnectionProfile(
      id: id,
      name: name ?? this.name,
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      basePath: basePath ?? this.basePath,
      authKind: authKind ?? this.authKind,
      username: username ?? this.username,
      allowInsecureTls: allowInsecureTls ?? this.allowInsecureTls,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'scheme': scheme,
    'host': host,
    'port': port,
    'basePath': basePath,
    'authKind': authKind.name,
    'username': username,
    'allowInsecureTls': allowInsecureTls,
    'enabled': enabled,
  };

  factory ConnectionProfile.fromJson(Map<String, Object?> json) =>
      ConnectionProfile(
        id: json['id']! as String,
        name: json['name']! as String,
        scheme: json['scheme']! as String,
        host: json['host']! as String,
        port: json['port']! as int,
        basePath: json['basePath'] as String? ?? '',
        authKind:
            HermesAuthKind.values.asNameMap()[json['authKind']] ??
            HermesAuthKind.password,
        username: json['username'] as String? ?? '',
        allowInsecureTls: json['allowInsecureTls'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
      );
}
