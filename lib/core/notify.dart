import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones locales de Pocket: aviso cuando un turno del bot termina
/// y no estás mirando ese chat. Todo local: el gateway no emite push, y la
/// app no abre servicios a Internet.
class Notifier {
  Notifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Ids incremental: uno por conversación que avisa.
  static int _nextId = 1;

  /// Estado de la app + conversación actualmente visible. Las pantallas lo
  /// actualizan; el disparador de turnos decide si avisar o callar.
  static AppLifecycleState lifecycle = AppLifecycleState.resumed;
  static String? visibleConversationId;

  static Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
      _ready = true;
    } catch (e) {
      // Sin notificaciones la app funciona igual: sólo no avisa.
      assert(() {
        debugPrint('Notifier init failed: $e');
        return true;
      }());
    }
  }

  /// ¿Toca avisar? Sólo si la app NO está en primer plano sobre ESTE chat.
  static bool shouldNotify(String conversationId) =>
      _ready &&
      !(lifecycle == AppLifecycleState.resumed &&
          visibleConversationId == conversationId);

  /// Aviso de turno terminado. [ok] false → tono de error.
  static Future<void> turnDone({
    required String conversationId,
    required String botTitle,
    required String preview,
    required bool ok,
  }) async {
    if (!shouldNotify(conversationId)) return;
    final id = _nextId++;
    await _plugin.show(
      id,
      ok ? botTitle : '$botTitle · error',
      preview.isEmpty ? 'Respuesta lista.' : preview,
      NotificationDetails(
        android: const AndroidNotificationDetails(
          'turns',
          'Respuestas del bot',
          channelDescription: 'El bot terminó de responder.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
