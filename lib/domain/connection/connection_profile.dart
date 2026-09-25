/// Modelo de conexión a un gateway Hermes.
///
/// Cada conexión tiene nombre, dirección, credenciales y estado INDEPENDIENTES.
/// Un gateway caído no bloquea el resto.
library;

enum HermesAuthKind { password, bearerToken }

enum ConnectionStatus {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
  authExpired,
  error,
}

/// Diagnóstico diferenciado: la UI decide mensaje según la causa real.
enum ConnectionErrorCause { network, auth, version, permissions, unknown }

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
    final p =
        (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443)
        ? ''
        : ':$port';
    return '$scheme://$host$p$b';
  }

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

/// Estado de sesión de autenticación de una conexión (secreto fuera de aquí).
class ConnectionSession {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  const ConnectionSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  bool get needsRefresh =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(minutes: 5)));
}
