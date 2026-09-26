import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Logger mínimo que NUNCA imprime secretos (tokens, cookies, tickets).
/// Los llamadores nunca pasan material sensible; si se pasa, se enmascara.
class Logger {
  final String tag;
  static const _secrets = [
    'ticket',
    'token',
    'password',
    'cookie',
    'authorization',
    'secret',
  ];

  Logger(this.tag);

  void info(String message) => _log('INFO', message);
  void warning(String message, [Object? error, StackTrace? stack]) =>
      _log('WARN', '$message ${error ?? ''}', stack);
  void error(String message, [Object? error, StackTrace? stack]) =>
      _log('ERROR', '$message ${error ?? ''}', stack);

  void _log(String level, String message, [StackTrace? stack]) {
    final safe = _mask(message);
    // En debug también a logcat: dev.log no es visible sin VM service.
    assert(() {
      debugPrint('[$tag/$level] $safe');
      return true;
    }());
    dev.log(
      safe,
      name: tag,
      level: level == 'ERROR' ? 1000 : 800,
      error: null,
      stackTrace: stack,
    );
  }

  static String _mask(String message) {
    var out = message;
    for (final key in _secrets) {
      final pattern = RegExp('$key[=: ]+([^ ,;&"\']+)', caseSensitive: false);
      out = out.replaceAllMapped(pattern, (m) => '${m.group(1)}=${'*' * 6}');
    }
    return out.length > 600 ? '${out.substring(0, 600)}…' : out;
  }
}

String truncateForLog(Object? o, [int max = 300]) {
  final s = o is String ? o : (o == null ? '' : jsonEncode(o));
  return s.length > max ? '${s.substring(0, max)}…' : s;
}
