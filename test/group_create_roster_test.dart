import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión del roster que manda `group_create`: en 0.1.49 las filas llevaban
/// `name` además de `profile` (clave desconocida por `validate_roster`,
/// extra="forbid") → el gateway rechazaba `groups.create` SIEMPRE → la sala
/// nunca quedaba hosted → `groups.send` 4112 → «no deja enviar».
void main() {
  const local = {'default', 'claudio'};

  List<Map<String, Object?>> rows0149() => [
    {
      'profile': 'default',
      'handle': 'default',
      'name': 'default',
      'display_name': 'Default',
      'installId': 'inst-1',
      'connectionLabel': 'Claudio',
    },
    {
      'profile': 'parker',
      'handle': 'parker',
      'name': 'parker',
      'display_name': 'Parker',
      'target': {'connection_id': 'inst-2', 'profile': 'parker'},
    },
  ];

  test('el shape de 0.1.49 (name extra) es rechazado por el validador', () {
    final err = validateRosterWire(rows0149(), local);
    expect(err, isNotNull);
    expect(err!.message, contains('name'));
  });

  test('el shape actual (profile/handle/target) pasa', () {
    final fixed = [
      for (final r in rows0149())
        {
          'profile': r['profile'],
          'handle': r['handle'],
          'display_name': r['display_name'],
          if (r['target'] != null) 'target': r['target'],
        },
    ];
    expect(validateRosterWire(fixed, local), isNull);
  });

  test('la variante mínima (profile + handle + target) pasa', () {
    final minimal = [
      {'profile': 'default', 'handle': 'default'},
      {
        'profile': 'parker',
        'handle': 'parker',
        'target': {'connection_id': 'inst-2', 'profile': 'parker'},
      },
    ];
    expect(validateRosterWire(minimal, local), isNull);
  });
}
