import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/features/chat/mention_menu.dart';

void main() {
  group('filterMentionCandidates', () {
    const room = MentionCandidate(
      name: 'hermes-this-webapp',
      label: 'Boneca',
    );
    const rosterDup = MentionCandidate(
      name: 'hermes-this-webapp',
      label: 'Boneca',
    );
    const other = MentionCandidate(name: 'parker-01-casa', label: 'Parker');
    const todos = MentionCandidate(name: 'todos', label: 'todos');

    test('dedupe por token: sala + roster no duplican', () {
      final out = filterMentionCandidates(
        [todos, room, rosterDup, other],
        '',
      );
      expect(out.map((c) => c.name).toList(), [
        'todos',
        'hermes-this-webapp',
        'parker-01-casa',
      ]);
    });

    test('prefijo gana a contains; acentos se pliegan', () {
      final jose = const MentionCandidate(name: 'jose-bot', label: 'José');
      final otras = const MentionCandidate(name: 'aura', label: 'Aura');
      final out = filterMentionCandidates([otras, jose], 'josé');
      expect(out.map((c) => c.name).toList(), ['jose-bot']);
    });

    test('query vacía conserva orden de entrada (tras dedupe)', () {
      final out = filterMentionCandidates([todos, other, room], '');
      expect(out.first.name, 'todos');
    });
  });

  group('foldMentionKey', () {
    test('quita diacríticos españoles', () {
      expect(foldMentionKey('José'), 'jose');
      expect(foldMentionKey('Ñandú'), 'nandu');
    });
  });
}
