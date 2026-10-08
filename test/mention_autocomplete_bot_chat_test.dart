import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/features/chat/mention_menu.dart';

/// El guard del autocompletado usaba SOLO los candidatos de sala (grupos):
/// en un chat 1:1 el menú jamás abría. Contrato nuevo: la lista FUSIONADA
/// (sala + roster) decide; el `@` ofrece bots en todos los chats.
void main() {
  test('mentionStart detecta @ recién tecleada', () {
    expect(MentionToken.mentionStart('hola @', 6), 5);
    expect(MentionToken.mentionStart('@', 1), 0);
    expect(MentionToken.mentionStart('a@b', 3), isNull); // email-like
    expect(MentionToken.mentionStart('hola @cla', 9), 5);
    expect(MentionToken.mentionStart('hola @cla undis', 15), isNull); // token cerrado
  });

  test('replace inserta @Nombre con espacio y caret correcto', () {
    final (text, caret) = MentionToken.replace('hola @cla', 5, 9, 'CLAUDIO');
    expect(text, 'hola @CLAUDIO ');
    expect(caret, 'hola @CLAUDIO '.length);
  });
}
