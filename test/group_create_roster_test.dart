import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión del roster que manda `group_create`. Historial de rechazos del
/// gateway (`groups.create` 5111 → sala no hosted → `groups.send` 4112 → «no
/// deja enviar en grupos»):
/// - 0.1.48: perfil en `name`, `target` string;
/// - 0.1.49: `name`/`installId`/`connectionLabel` de espejo viajaban al wire;
/// - 0.1.50: faltaba `member_id` (sonda real: «member N is missing fields:
///   member_id» — no es server-owned).
/// La proyección buena es la de `createGroup`: member_id + profile + handle
/// (+ display_name), sin target para miembros del gateway anfitrión.
void main() {
  const local = {'default', 'parker'};

  List<Map<String, Object?>> mirrorRows() => [
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
      'connectionId': 'inst-2',
    },
  ];

  test('las filas de espejo sin member_id son rechazadas', () {
    final err = validateRosterWire(mirrorRows(), local);
    expect(err, isNotNull);
    expect(err!.message, contains('member_id'));
  });

  test('la proyección real (member_id+profile+handle, locales sin target) pasa',
      () {
    final roomId = 'r1abcdef-xyz';
    final projected = [
      for (final (i, r) in mirrorRows().indexed)
        {
          'member_id': 'm$i-${roomId.substring(0, 8)}',
          'profile': r['profile'],
          'handle': r['handle'],
          'display_name': r['display_name'],
        },
    ];
    expect(validateRosterWire(projected, local), isNull);
    // member_id con el prefijo de sala es un identificador válido.
    for (final r in projected) {
      expect(r['member_id'], matches(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')));
    }
  });

  test('dos miembros del MISMO perfil en distinta clave member_id sigue siendo duplicado',
      () {
    final dup = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
      {'member_id': 'm2', 'profile': 'default', 'handle': 'default'},
    ];
    final err = validateRosterWire(dup, local);
    expect(err, isNotNull);
    expect(err!.message, contains('duplicate profile'));
  });
}
