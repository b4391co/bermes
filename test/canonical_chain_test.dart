import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';

/// Cadena de resolución de la sesión canónica ("Bot Chat") contra el bug REAL
/// del gateway: el índice de títulos es GLOBAL (web_routers/history.py:80 —
/// `get_session_title` sin filtro de perfil), así que `session.resume {title,
/// profile}` puede devolver la sesión de OTRO perfil. El cliente NUNCA usa el
/// `resume` ciego: primero el roster (`canonical_session` de profiles.list,
/// enrutado por perfil) y luego `session.list {profile, title:'Bot Chat'}`.
/// Aquí se fija esa precedencia y los fallos honestos.
void main() {
  test('lista encuentra "Bot Chat" del perfil => se usa, sin crear', () async {
    final r = await CanonicalChain.resolve(
      listByTitle: () async => [
        {'title': 'Bot Chat', 'id': 'sess-from-list'},
      ],
      rosterConfirmsCanonical: () async => false,
      create: () async => {'session_id': 'NEVER'},
    );
    expect(r.sessionId, 'sess-from-list');
    expect(r.created, isFalse);
  });

  test(
    'resume mentiroso de otro perfil: la verificación por lista manda',
    () async {
      // `resume` contestó 'sess-canonical-default' (el de default). Para
      // researcher la lista no tiene ninguna fila canónica y el roster tampoco
      // la confirma => NO se usa la mentira, se crea sobre el perfil correcto.
      final liar = {'session_id': 'sess-canonical-default'};
      final r = await CanonicalChain.resolve(
        listByTitle: () async => const [],
        rosterConfirmsCanonical: () async => false,
        create: () async => {'session_id': 'sess-new-researcher'},
      );
      expect(r.sessionId, isNot(equals(CanonicalChain.registryId(liar))));
      expect(r.sessionId, 'sess-new-researcher');
      expect(r.created, isTrue);
    },
  );

  test(
    'fila con título distinto => se descarta; manda la canónica exacta',
    () async {
      final r = await CanonicalChain.resolve(
        listByTitle: () async => [
          {'title': 'Otra sesión', 'session_id': 'sess-wrong'},
          {'title': 'Bot Chat', 'session_id': 'sess-right'},
        ],
        rosterConfirmsCanonical: () async => false,
        create: () async => {'session_id': 'NEVER'},
      );
      expect(r.sessionId, 'sess-right');
    },
  );

  test(
    'lista vacía + roster la confirma (gateway antiguo) => sin crear a ciegas',
    () async {
      // El roster ya anunció canonical_session: no hay nada que crear.
      expect(
        () => CanonicalChain.resolve(
          listByTitle: () async => const [],
          rosterConfirmsCanonical: () async => true,
          create: () async => {'session_id': 'NEVER'},
        ),
        throwsA(isA<CanonicalResolutionFailed>()),
      );
    },
  );

  test(
    'fallo de lista => CanonicalResolutionFailed con causa legible',
    () async {
      await expectLater(
        CanonicalChain.resolve(
          listByTitle: () async => throw StateError('offline'),
          rosterConfirmsCanonical: () async => false,
          create: () async => {'session_id': 'NEVER'},
        ),
        throwsA(isA<CanonicalResolutionFailed>()),
      );
    },
  );

  test('registryId: id del registro manda sobre resolved_id (punta viva)', () {
    expect(
      CanonicalChain.registryId({
        'id': 'sess-canon',
        'resolved_id': 'sess-canon-r',
      }),
      'sess-canon',
    );
    expect(CanonicalChain.registryId({'session_id': 'sess-x'}), 'sess-x');
    expect(CanonicalChain.registryId({'foo': 1}), isNull);
  });
}
