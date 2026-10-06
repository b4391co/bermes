import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/data/settings/settings_package.dart';

void main() {
  test('paquete propio: parse OK y conserva includes_secrets', () {
    final pkg = SettingsPackage(
      data: {
        'connections': [
          {
            'id': 'x',
            'name': 'claudio',
            'host': '10.20.20.67',
            'port': 9110,
          },
        ],
      },
      includesSecrets: false,
    );
    final parsed = SettingsPackage.parse(
      const JsonEncoder().convert(pkg.toJson()),
    );
    expect(parsed.data['format'], SettingsPackage.format);
    expect(parsed.includesSecrets, isFalse);
  });

  test('config.yaml REAL de un gateway hermes → HermesServerConfigException '
      'con el usuario del panel', () {
    // Estructura fiel del export real (boneca): dashboard + agent + providers,
    // SIN la clave 'format'.
    const hermesServerConfig = '''
    {
      "model": "LOCAL-MEDIUM",
      "providers": {"litellm": {"name": "liteLLM"}},
      "agent": {"max_turns": 160},
      "dashboard": {
        "basic_auth": {
          "username": "breo",
          "password_hash": "scrypt\$16384\$8\$1\$AA==\$BB=="
        },
        "public_url": ""
      },
      "attachments": {"storage": "hermes-home"}
    }
    ''';
    expect(
      () => SettingsPackage.parse(hermesServerConfig),
      throwsA(
        isA<HermesServerConfigException>().having(
          (e) => e.dashboardUsername,
          'dashboardUsername',
          'breo',
        ),
      ),
    );
  });

  test('JSON desconocido sin marcas de hermes → formato no reconocido', () {
    expect(
      () => SettingsPackage.parse('{"hola": 1}'),
      throwsA(isA<SettingsFormatException>()),
    );
  });
}
