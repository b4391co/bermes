import 'package:flutter/foundation.dart';

/// Registro en memoria de conversaciones con turno EN VIVO (el bot está
/// escribiendo/herramientas corriendo). Lo llenan los `ChatSessionController`
/// al abrir/sellar un segmento de streaming; lo miran la banda de fijados,
/// la cabecera del chat y las burbujas para mostrar aura + bocadillo «…»
/// SOLO en los bots que están trabajando ahora mismo.
///
/// Clave: `EntityRefPath.storageId` == `conversations.id`
/// (`connectionId/kind/gatewayId`) — la misma identidad en toda la app.
class TurnActivity {
  TurnActivity._();

  /// Conversaciones con turno activo. Un único ValueNotifier: cualquier
  /// oyente (banda de fijados, chat) se reconstruye al cambiar.
  static final ValueNotifier<Set<String>> streaming = ValueNotifier(<String>{});

  static bool isStreaming(String conversationId) =>
      streaming.value.contains(conversationId);

  static void begin(String conversationId) {
    if (streaming.value.add(conversationId)) {
      streaming.value = Set.of(streaming.value);
    }
  }

  static void end(String conversationId) {
    if (streaming.value.remove(conversationId)) {
      streaming.value = Set.of(streaming.value);
    }
  }
}
