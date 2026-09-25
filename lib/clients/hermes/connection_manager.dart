import 'dart:async';

import '../../core/logger.dart';
import '../../domain/connection/connection_profile.dart';
import 'gateway_client.dart';
import 'http_client.dart';

/// Instancia viva de UNA conexión: su cliente HTTP, su cliente WS y su estado.
class ConnectionRuntime {
  final ConnectionProfile profile;
  final HermesHttpClient http;
  final HermesGatewayClient gateway;

  ConnectionRuntime(this.profile)
    : http = HermesHttpClient(profile),
      gateway = HermesGatewayClient(profile, HermesHttpClient(profile));

  Future<void> dispose() async {
    await gateway.disconnect();
    gateway.dispose();
    http.dispose();
  }
}

/// Gestor de N conexiones simultáneas e independientes.
///
/// - Cada gateway tiene su runtime aislado: sesión, tokens, cookies, WS.
/// - Un gateway caído NO bloquea el resto.
/// - Eliminar una conexión local no toca nada del servidor.
class ConnectionManager {
  final _log = Logger('ConnManager');
  final _runtimes = <String, ConnectionRuntime>{};
  final _controller =
      StreamController<Map<String, ConnectionRuntime>>.broadcast();

  Map<String, ConnectionRuntime> get runtimes => Map.unmodifiable(_runtimes);
  Stream<Map<String, ConnectionRuntime>> get stream => _controller.stream;

  ConnectionRuntime? runtimeFor(String connectionId) => _runtimes[connectionId];

  ConnectionRuntime ensureRuntime(ConnectionProfile profile) {
    final existing = _runtimes[profile.id];
    if (existing != null) return existing;
    final runtime = ConnectionRuntime(profile);
    _runtimes[profile.id] = runtime;
    _notify();
    return runtime;
  }

  Future<void> removeRuntime(String connectionId) async {
    final runtime = _runtimes.remove(connectionId);
    if (runtime != null) {
      await runtime.dispose();
      _notify();
    }
    _log.info('runtime removed $connectionId');
  }

  void _notify() => _controller.add(Map.unmodifiable(_runtimes));

  Future<void> disposeAll() async {
    for (final r in _runtimes.values) {
      await r.dispose();
    }
    _runtimes.clear();
    await _controller.close();
  }
}
