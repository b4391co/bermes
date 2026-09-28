import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/gateway_client.dart';

/// Cadena de resolución de la sesión canónica ("Bot Chat") contra el bug REAL
/// reportado por el usuario: `session.resume {title,profile}` puede responder
/// la sesión de OTRO perfil (índice de título global). La app debe detectar la
/// mentira verificando por `session.list {profile, title:'Bot Chat'}` y, si no
/// existe, crearla por HTTP sobre el perfil correcto.
void main() {
  test('resume devuelve sesión de OTRO perfil => verification list manda', () async {
    // Perfil 'researcher': resume miente (devuelve la de default).
    final r = await CanonicalChain.resolve(
      resume: () async => {'session_id': 'sess-canonical-default'},
      listByTitle: () async => const [], // 'Bot Chat' no existe para researcher
      httpCreate: () async => {'session_id': 'sess-new-researcher'},
    );
    expect(r.sessionId, 'sess-new-researcher');
    expect(r.created, isTrue);
  });

  test('resume correcto (misma fila que lista) => se usa tal cual', () async {
    final r = await CanonicalChain.resolve(
      resume: () async => {'session_id': 'sess-canon-r'},
      listByTitle: () async => [
        {'title': 'Bot Chat', 'session_id': 'sess-canon-r'},
      ],
      httpCreate: () async => {'session_id': 'NEVER'},
    );
    expect(r.sessionId, 'sess-canon-r');
    expect(r.created, isFalse);
  });

  test('resume sin sesión + lista la encuentra => se usa la de la lista', () async {
    final r = await CanonicalChain.resolve(
      resume: () async => null,
      listByTitle: () async => [
        {'title': 'Bot Chat', 'session_id': 'sess-from-list'},
      ],
      httpCreate: () async => {'session_id': 'NEVER'},
    );
    expect(r.sessionId, 'sess-from-list');
    expect(r.created, isFalse);
  });

  test('todo falla => null (el chat reporta causa, nunca inventa)', () async {
    final r = await CanonicalChain.resolve(
      resume: () async => null,
      listByTitle: () async => const [],
      httpCreate: () async => null,
    );
    expect(r.sessionId, isNull);
  });

  test('fila de lista con título distinto => se descarta', () async {
    final r = await CanonicalChain.resolve(
      resume: () async => null,
      listByTitle: () async => [
        {'title': 'Otra sesión', 'session_id': 'sess-wrong'},
        {'title': 'Bot Chat', 'session_id': 'sess-right'},
      ],
      httpCreate: () async => {'session_id': 'NEVER'},
    );
    expect(r.sessionId, 'sess-right');
  });
}
