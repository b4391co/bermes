import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/domain/entity/entity_ref.dart';
import 'package:hermes_pocket/domain/message/chat_models.dart';
import 'package:hermes_pocket/features/chat/message_bubble.dart';

/// La hora del mensaje debe verse SIEMPRE en mensajes terminados (bot y
/// usuario), no sólo durante el tránsito de envío.
void main() {
  ChatMessage msg(MessageRole role, {DateTime? ts, bool streaming = false}) =>
      ChatMessage(
        id: 'm1',
        path: const EntityRefPath(
          connectionId: 'c1',
          kind: EntityKind.bot,
          gatewayId: 'default',
        ),
        role: role,
        text: 'hola',
        timestamp: ts ?? DateTime(2026, 10, 7, 15, 7),
        streaming: streaming,
      );

  Future<void> pump(WidgetTester tester, Widget bubble) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: bubble)),
  );

  testWidgets('asistente terminado muestra la hora', (tester) async {
    await pump(tester, MessageBubble(message: msg(MessageRole.assistant)));
    expect(find.textContaining('3:07'), findsOneWidget);
  });

  testWidgets('usuario enviado muestra la hora', (tester) async {
    await pump(tester, MessageBubble(message: msg(MessageRole.user)));
    expect(find.textContaining('3:07'), findsOneWidget);
  });

  testWidgets('en streaming no se pinta la hora ni el meta duplicado',
      (tester) async {
    // 0.1.53: «escribiendo…» al pie de la burbuja ELIMINADO — el bocadillo
    // «…» del avatar ya señala el turno (dos indicadores = «dos veces los
    // ...» reportado). El contrato: sin hora, sin texto.
    await pump(
      tester,
      MessageBubble(message: msg(MessageRole.assistant, streaming: true)),
    );
    expect(find.textContaining('3:07'), findsNothing);
    expect(find.text('escribiendo…'), findsNothing);
  });
}
