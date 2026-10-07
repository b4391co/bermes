import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión del wire real: `groups.create` del Pocket debe pasar la
/// validación de roster del backend (`validate_roster` + `_validate_target`,
/// tui_gateway/hosted_rooms.py). Con el shape de 0.1.48 — perfil en `name`
/// (clave desconocida) y `target` como string — el gateway rechazaba la sala
/// SIEMPRE: `groups.send` 4112 «room not found» → «no deja enviar».
void main() {
  const local = {'default', 'parker'};

  test('shape 0.1.48 (name/target-string) es rechazado por el backend', () {
    final bad = [
      {'name': 'default', 'installId': 'i1', 'target': 'default'},
      {'name': 'parker', 'installId': 'i2', 'target': 'parker'},
    ];
    final err = validateRosterWire(bad, local);
    expect(err, isNotNull, reason: 'target string → objeto inválido');
    expect(err!.message, 'target must be an object');
  });

  test('miembros locales pasan con profile/handle y sin target', () {
    final good = [
      {'profile': 'default', 'handle': 'default', 'installId': 'i1'},
      {'profile': 'parker', 'handle': 'parker', 'installId': 'i2'},
    ];
    expect(validateRosterWire(good, local), isNull);
  });

  test('remoto con target.connection_id pasa; sin route, rechazado', () {
    final ok = [
      {'profile': 'default'},
      {
        'profile': 'botb',
        'target': {'connection_id': 'inst-2', 'profile': 'botb'},
      },
    ];
    expect(validateRosterWire(ok, local), isNull);
    final noRoute = [
      {'profile': 'default'},
      {'profile': 'botb', 'target': {'profile': 'botb'}},
    ];
    final err = validateRosterWire(noRoute, local);
    expect(err, isNotNull);
    expect(err!.message, contains('connection_id or gateway_id'));
  });

  test('el mismo perfil dos veces se rechaza (el wire exige nombres únicos)',
      () {
    final dup = [
      {'profile': 'default'},
      {'profile': 'default'},
    ];
    final err = validateRosterWire(dup, local);
    expect(err, isNotNull);
    expect(err!.message, contains('duplicate profile'));
  });
}
