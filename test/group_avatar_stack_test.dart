import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/design/group_avatar.dart';

void main() {
  testWidgets('pila de 3 caras + badge +N', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GroupAvatarStack(
              size: 48,
              totalMembers: 5,
              faces: [
                GroupFace(seed: 'a', label: 'Aura'),
                GroupFace(seed: 'b', label: 'Boneca'),
                GroupFace(seed: 'c', label: 'Claudio'),
                GroupFace(seed: 'd', label: 'Extra'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('+2'), findsOneWidget);
    // BotAvatar usa 2 letras del label (Aura→AU). La 4.ª cara no se pinta.
    expect(find.text('AU'), findsOneWidget);
    expect(find.text('BO'), findsOneWidget);
    expect(find.text('CL'), findsOneWidget);
    expect(find.text('EX'), findsNothing);
  });

  testWidgets('dos caras sin badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: GroupAvatarStack(
              size: 48,
              totalMembers: 2,
              faces: [
                GroupFace(seed: 'a', label: 'Aura'),
                GroupFace(seed: 'b', label: 'Boneca'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('+'), findsNothing);
    expect(find.text('AU'), findsOneWidget);
    expect(find.text('BO'), findsOneWidget);
  });
}
