import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Export/import de ajustes versionado con validación.
///
/// REGLAS DE SEGURIDAD (contrato del encargo):
/// - Por defecto SIN secretos. Paquete con secretos SOLO con opción explícita
///   y cifrado autenticado con contraseña (AES-GCM-like via HMAC+XOR… NO:
///   se usa package:cryptography si está; aquí: cifrado PBKDF2+AES-GCM con
///   pointycastle sería dependencia extra — decisión: AES-GCM nativo no existe
///   en package:crypto, así que el modo con secretos usa HMAC-SHA256 con clave
///   derivada y cifrado XOR stream… NO. CORRECTO: usar package:cryptography.
///   (ver pubspec: cryptography ^6.x añadido).
/// - No exporta tickets efímeros (tickets WS son single-use 30s: nunca viajan).
/// - No incluye historiales ni borradores (consentimiento separado).
/// - Importar NUNCA ejecuta comandos ni toca máquinas remotas.
class SettingsPackage {
  static const format = 'hermes-pocket-settings';
  static const version = 1;

  final Map<String, Object?> data;
  final bool includesSecrets;

  const SettingsPackage({required this.data, required this.includesSecrets});

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'includes_secrets': includesSecrets,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    ...data,
  };

  /// Validación estricta al importar.
  static SettingsPackage parse(String rawJson) {
    final json = jsonDecode(rawJson);
    if (json is! Map<String, Object?>) {
      throw const SettingsFormatException(
        'El archivo no contiene un objeto JSON',
      );
    }
    // Un config.yaml EXPORTADO de un gateway Hermes real (server-side) no es
    // un paquete Pocket: no trae `format`, y NUNCA trae la URL del gateway
    // (el dashboard escucha donde arranque `hermes serve`). Detectarlo y
    // explicarlo vale más que un «formato no reconocido» seco. Lo útil que
    // sí aporta: el usuario del dashboard (dashboard.basic_auth.username).
    if (json['format'] != format) {
      final dashboard = json['dashboard'];
      final isHermesServerConfig =
          dashboard is Map &&
          (json['agent'] is Map || json['providers'] is Map);
      if (isHermesServerConfig) {
        final basicAuth = dashboard['basic_auth'];
        final username = basicAuth is Map ? basicAuth['username'] : null;
        throw HermesServerConfigException(
          username is String && username.isNotEmpty ? username : '',
        );
      }
      throw const SettingsFormatException('Formato no reconocido');
    }
    final v = json['version'];
    if (v is! int || v > version) {
      throw SettingsFormatException(
        'Versión $v no soportada (máxima $version)',
      );
    }
    // Migración entre versiones iría aquí cuando haya v2.
    return SettingsPackage(
      data: json,
      includesSecrets: json['includes_secrets'] as bool? ?? false,
    );
  }
}

/// El archivo es un config de SERVIDOR Hermes (config.yaml exportado), no un
/// paquete Pocket. [dashboardUsername] es el usuario del panel si constaba.
class HermesServerConfigException implements Exception {
  final String dashboardUsername;
  const HermesServerConfigException(this.dashboardUsername);

  @override
  String toString() =>
      'Es un config de servidor Hermes (config.yaml), no un paquete de '
      'ajustes de Hermes Pocket';
}

class SettingsFormatException implements Exception {
  final String message;
  const SettingsFormatException(this.message);

  @override
  String toString() => message;
}

/// Resultado de una importación con vista previa y detección de duplicados.
class ImportPreview {
  final List<Map<String, Object?>> newConnections;
  final List<Map<String, Object?>> duplicateConnections;
  final int settingsCount;
  final bool includesSecrets;

  const ImportPreview({
    required this.newConnections,
    required this.duplicateConnections,
    required this.settingsCount,
    required this.includesSecrets,
  });

  int get total => newConnections.length + duplicateConnections.length;
}

/// Cifrado autenticado del paquete con secretos.
///
/// Implementación: PBKDF2-HMAC-SHA256 para derivar clave de 32 bytes +
/// AES-256-GCM autenticado. package:cryptography lo provee multiplataforma.
class SecretPackageCrypto {
  static const _kdfIterations = 200000;

  /// Cifra el JSON con contraseña. Devuelve (salt + nonce + ciphertext) en base64.
  static Future<String> encrypt(String json, String password) async {
    final salt = Uint8List.fromList(
      List.generate(16, (_) => DateTime.now().microsecondsSinceEpoch & 0xFF),
    );
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      utf8.encode(json),
      secretKey: key,
      nonce: nonce,
    );
    final out = BytesBuilder()
      ..add(salt)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64.encode(out.toBytes());
  }

  /// Descifra. Lanza si la contraseña es incorrecta (MAC mismatch).
  static Future<String> decrypt(String encoded, String password) async {
    final raw = base64.decode(encoded);
    if (raw.length < 16 + 12 + 16) {
      throw const SettingsFormatException('Paquete cifrado corrupto');
    }
    final salt = raw.sublist(0, 16);
    final nonce = raw.sublist(16, 28);
    final cipherText = raw.sublist(28, raw.length - 16);
    final mac = raw.sublist(raw.length - 16);

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final algorithm = AesGcm.with256bits();
    final clear = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return utf8.decode(clear);
  }
}
