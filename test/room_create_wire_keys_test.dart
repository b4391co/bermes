import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión del wire de `groups.create`: las filas de espejo del Pocket
/// (con `name`/`installId`/`connectionLabel`) NO pueden viajar tal cual, y
/// toda fila debe llevar `member_id` — clave REAL requerida por el backend
/// (sonda 2026-10-07: 5111 «member N is missing fields: member_id»). Antes
/// de crear la sala, `createGroup` proyecta las filas y las pasa por
/// [validateRosterWire]; este test fija el resultado de esa proyección.
void main() {
  test('una fila con member_id y sin claves extra pasa', () {
    final wire = [
      {'member_id': 'm0-r1abcdef', 'profile': 'default', 'handle': 'default'},
      {'member_id': 'm1-r1abcdef', 'profile': 'parker', 'handle': 'parker'},
    ];
    expect(validateRosterWire(wire, {'default', 'parker'}), isNull);
  });

  test('la fila de espejo SIN member_id es rechazada (rega de 0.1.49/0.1.50)',
      () {
    final mirrorRows = [
      {
        'profile': 'default',
        'name': 'default',
        'handle': 'default',
        'installId': 'inst-1',
        'connectionLabel': 'Claudio',
      },
      {'profile': 'parker', 'name': 'parker', 'handle': 'parker'},
    ];
    final err = validateRosterWire(mirrorRows, {'default'});
    expect(err, isNotNull);
    expect(err!.message, contains('member_id'));
  });

  test('identificadores de reintentos válidos para el backend', () {
    // IDENTIFIER_RE: ^[A-Za-z0-9][A-Za-z0-9._:-]*$ y <=128 chars.
    final re = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
    expect(RoomsClient.newClientEventId(), matches(re));
    expect(RoomsClient.newThreadId(), matches(re));
    expect(RoomsClient.newRoomId(), matches(re));
    // Los member_ids que genera createGroup también deben ser válidos.
    final roomId = RoomsClient.newRoomId();
    expect('m0-${roomId.substring(0, 8)}', matches(re));
  });
}
