import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión 0.1.50: `RoomsClient.create` debe mandar al gateway SOLO las
/// claves que `validate_roster` admite (`_exact_fields`: profile/handle/
/// display_name/target). En 0.1.48/0.1.49 se enviaban además name/installId/
/// connectionLabel y el backend rechazaba la sala SIEMPRE → `groups.send`
/// 4112 → «no deja enviar en grupos».
void main() {
  test('validateRosterWire rechaza cualquier clave de espejo (name/installId)',
      () {
    final mirrorRows = [
      {
        'profile': 'default',
        'name': 'default',
        'handle': 'default',
        'installId': 'inst-1',
        'connectionLabel': 'Claudio',
      },
      {
        'profile': 'parker',
        'name': 'parker',
        'handle': 'parker',
        'target': {'connection_id': 'inst-2', 'profile': 'parker'},
      },
    ];
    final err = validateRosterWire(mirrorRows, {'default'});
    expect(err, isNotNull);
    expect(err!.message, contains('unknown member field'));
  });

  test('la proyección wire (solo las 4 claves) pasa', () {
    const local = {'default'};
    final wire = [
      {
        'profile': 'default',
        'handle': 'default',
        // display_name opcional
      },
      {
        'profile': 'parker',
        'handle': 'parker',
        'target': {'connection_id': 'inst-2', 'profile': 'parker'},
      },
    ];
    expect(validateRosterWire(wire, local), isNull);
  });

  test('identificadores de reintentos válidos para el backend', () {
    // IDENTIFIER_RE: ^[A-Za-z0-9][A-Za-z0-9._:-]*$ y <=128 chars.
    final re = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
    expect(RoomsClient.newClientEventId(), matches(re));
    expect(RoomsClient.newThreadId(), matches(re));
    expect(RoomsClient.newRoomId(), matches(re));
  });
}
