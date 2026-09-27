import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/profile_canonical.dart';

void main() {
  group('canonical_session', () {
    test('CanonicalSessionInfo real: resolved_id tiene prioridad', () {
      expect(
        canonicalFromProfile({
          'canonical_session': {
            'id': 'sess-a',
            'resolved_id': 'sess-a-live',
            'title': 'Bot Chat',
          },
        }),
        'sess-a-live',
      );
    });
    test('sin resolved_id usa id', () {
      expect(
        canonicalFromProfile({
          'canonical_session': {'id': 'sess-b', 'title': 'Bot Chat'},
        }),
        'sess-b',
      );
    });
    test('forma string (versiones antiguas)', () {
      expect(canonicalFromProfile({'canonical_session': 'sess-c'}), 'sess-c');
    });
    test('null o vacío → null (no inventar sesión)', () {
      expect(canonicalFromProfile({'canonical_session': null}), isNull);
      expect(canonicalFromProfile({'canonical_session': {}}), isNull);
      expect(canonicalFromProfile({'canonical_session': ''}), isNull);
      expect(canonicalFromProfile({}), isNull);
    });
  });
}
