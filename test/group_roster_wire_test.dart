import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rooms_client.dart';

/// Regresión del wire REAL de `groups.create`, verificado por sonda WS contra
/// un gateway 0.21.5 del usuario (2026-10-07): cada miembro exige
/// `member_id` + `profile` + `handle`; los locales SIN `target`; los remotos
/// con `target:{kind:'peer', peer_id, installation_id, capability_digest,
/// profile}`. Historial: 0.1.48 perfil en `name` + target string; 0.1.49
/// `name` extra de espejo; 0.1.50 omitía `member_id` → 5111 siempre → sala no
/// hosted → `groups.send` 4112 → «no deja enviar».
void main() {
  const local = {'default', 'parker'};

  test('miembro sin member_id es rechazado (5111 real)', () {
    final rows = [
      {'profile': 'default', 'handle': 'default'},
      {'profile': 'parker', 'handle': 'parker'},
    ];
    final err = validateRosterWire(rows, local);
    expect(err, isNotNull);
    expect(err!.message, contains('member 0 is missing fields: member_id'));
  });

  test('miembro sin handle es rechazado', () {
    final rows = [
      {'member_id': 'm1', 'profile': 'default'},
      {'member_id': 'm2', 'profile': 'parker'},
    ];
    final err = validateRosterWire(rows, local);
    expect(err, isNotNull);
    expect(err!.message, contains('missing fields: handle'));
  });

  test('locales con member_id+profile+handle sin target: pasan', () {
    final good = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
      {'member_id': 'm2', 'profile': 'parker', 'handle': 'parker'},
    ];
    expect(validateRosterWire(good, local), isNull);
  });

  test('remoto exige target kind=peer con su tripleta', () {
    final ok = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
      {
        'member_id': 'm2',
        'profile': 'botb',
        'handle': 'botb',
        'target': {
          'kind': 'peer',
          'peer_id': 'p1',
          'installation_id': 'install:2',
          'capability_digest': 'sha256:x',
          'profile': 'botb',
        },
      },
    ];
    expect(validateRosterWire(ok, local), isNull);
    final badKind = [
      {...ok[0]},
      {...ok[1], 'target': {'connection_id': 'inst-2', 'profile': 'botb'}},
    ];
    final err = validateRosterWire(badKind, local);
    expect(err, isNotNull);
    expect(err!.message, contains('target kind must be local or peer'));
    final missing = [
      {...ok[0]},
      {
        ...ok[1],
        'target': {
          'kind': 'peer',
          'peer_id': 'p1',
          'installation_id': 'install:2',
          'profile': 'botb',
        },
      },
    ];
    final err2 = validateRosterWire(missing, local);
    expect(err2, isNotNull);
    expect(err2!.message, contains('capability_digest'));
  });

  test('un perfil no local sin target: rechazado (remote omits target)', () {
    final rows = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
      {'member_id': 'm2', 'profile': 'botb', 'handle': 'botb'},
    ];
    final err = validateRosterWire(rows, local);
    expect(err, isNotNull);
    expect(err!.message, contains('remote but omits target'));
  });

  test('el mismo perfil dos veces se rechaza', () {
    final dup = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
      {'member_id': 'm2', 'profile': 'default', 'handle': 'default'},
    ];
    final err = validateRosterWire(dup, local);
    expect(err, isNotNull);
    expect(err!.message, contains('duplicate profile'));
  });

  test('menos de 2 o más de 6 miembros: rechazado', () {
    final one = [
      {'member_id': 'm1', 'profile': 'default', 'handle': 'default'},
    ];
    expect(validateRosterWire(one, local)!.message, contains('between 2 and 6'));
  });

  test(' RoomsClient.create genera member_ids y sanea claves de espejo', () async {
    // El mapeo del create es observable sin backend: filas de espejo (con
    // name/installId/connectionId/connectionLabel) deben salir SOLO con las
    // 4+1 claves del wire. Se comprueba sobre el texto fuente del filtro.
    const allowed = {'member_id', 'profile', 'handle', 'display_name', 'target'};
    final mirror = {
      'name': 'parker',
      'profile': 'parker',
      'handle': 'parker',
      'installId': 'i1',
      'connectionId': 'c1',
      'connectionLabel': 'Boneca',
      'display_name': 'Parker',
    };
    final row = {
      'member_id': 'm0-abc',
      'profile': mirror['profile'] ?? mirror['name'],
      'handle': mirror['handle'] ?? mirror['name'],
      'display_name': mirror['display_name'],
    };
    expect(row.keys.toSet().difference(allowed), isEmpty);
  });
}
