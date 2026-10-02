import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_pocket/features/chat/mention_menu.dart';

void main() {
  group('MentionToken.mentionStart', () {
    test('detecta @ al inicio y tras separador', () {
      expect(MentionToken.mentionStart('@Com', 4), 0);
      expect(MentionToken.mentionStart('hola @inv', 9), 5);
      expect(MentionToken.mentionStart('a, @b', 5), 3);
    });

    test('ignora @ pegado a otra palabra (emails, "a@b")', () {
      expect(MentionToken.mentionStart('a@b', 3), null);
      expect(MentionToken.mentionStart('user@host', 9), null);
    });

    test('el token se cierra en cuanto hay espacio', () {
      expect(MentionToken.mentionStart('@com pi', 7), null);
    });

    test('sin @ no hay mención', () {
      expect(MentionToken.mentionStart('hola', 4), null);
      expect(MentionToken.mentionStart('', 0), null);
    });
  });

  group('MentionToken.replace', () {
    test('sustituye el token y deja el caret tras el nombre', () {
      final (text, caret) = MentionToken.replace(
        'hola @inv',
        5,
        9,
        'Investigador',
      );
      expect(text, 'hola @Investigador ');
      expect(caret, 5 + 'Investigador'.length + 2);
    });

    test('conserva lo que había detrás del caret', () {
      final (text, _) = MentionToken.replace('@Co mundo', 0, 3, 'Compi');
      expect(
        text,
        '@Compi  mundo',
      ); // caret 3 deja el espacio del texto original
    });
  });
}
