import 'dart:async';

import 'package:flutter/foundation.dart';

/// Registro en memoria de conversaciones con turno EN VIVO (el bot está
/// escribiendo/herramientas corriendo). Lo llenan los `ChatSessionController`
/// al abrir/sellar un segmento de streaming, y el envío de grupos al aceptar
/// `groups.send`; lo miran la banda de fijados, la cabecera del chat y las
/// burbujas para mostrar aura + bocadillo «…» SOLO en los bots que están
/// trabajando ahora mismo.
///
/// Clave: id de fila de `conversations` — bots (su `EntityRefPath.storageId`,
/// `connectionId/kind/gatewayId`) y grupos (su `conversations.id`).
class TurnActivity {
  TurnActivity._();

  /// Conversaciones con turno activo. Un único ValueNotifier: cualquier
  /// oyente (banda de fijados, chat) se reconstruye al cambiar.
  static final ValueNotifier<Set<String>> streaming = ValueNotifier(<String>{});

  static bool isStreaming(String conversationId) =>
      streaming.value.contains(conversationId);

  /// Último evento vivo visto por conversación. El stream de eventos ES el
  /// heartbeat del turno: si el gateway corta los deltas (thinking muy largo
  /// sin eventos, reconexión que pierde el `message.complete`), un watchdog
  /// que mire esta marca baja la vida tras N minutos de silencio. Sin
  /// watchdog el aura quedaría encendida para siempre.
  static final Map<String, DateTime> _lastEventAt = {};

  static DateTime? lastEvent(String conversationId) =>
      _lastEventAt[conversationId];

  /// Watchdog GLOBAL por conversación: si en 4 min no llega ningún evento
  /// vivo (delta/thinking/tool/status/room.event) el turno se considera
  /// terminado aunque el chat esté CERRADO. Vive aquí, no en el
  /// ChatSessionController, porque su anterior dueño se destruye al salir
  /// del chat y mataba el watchdog (y con él el aura «de inicio a fin»).
  static final Map<String, Timer> _watchdogs = {};

  static void _armWatchdog(String conversationId) {
    _watchdogs[conversationId]?.cancel();
    _watchdogs[conversationId] = Timer(const Duration(minutes: 4), () {
      end(conversationId);
    });
  }

  static void begin(String conversationId) {
    _lastEventAt[conversationId] = DateTime.now();
    _armWatchdog(conversationId);
    // El pulso del aura: todo evento vivo de turno re-publica el set (nueva
    // instancia) para que un oyente montado TARDÍAMENTE (chat abierto en
    // plena respuesta) se reconstruya y arranque. Se propaga por IDENTIDAD
    // (ValueNotifier no compara contenido): los listeners deben ser baratos
    // y no releer nada pesado en onChanged.
    streaming.value = Set.of(streaming.value)..add(conversationId);
  }

  static void end(String conversationId) {
    _watchdogs.remove(conversationId)?.cancel();
    _lastEventAt.remove(conversationId);
    if (streaming.value.remove(conversationId)) {
      streaming.value = Set.of(streaming.value);
    }
  }
}
