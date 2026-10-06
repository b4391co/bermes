import 'dart:async';
import 'dart:convert';

import '../../clients/hermes/connection_manager.dart';
import '../../core/app_services.dart';
import '../../data/database/app_database.dart';

/// Estado del escritorio del bot, según el contrato REAL del gateway
/// (`tui_gateway/contracts/display.py::DisplayStatus`): el resultado no trae
/// una cadena `state`, sino `running: bool`, `installed: bool`, `missing[]`,
/// `blocker` y `install_command`. El mapeo a estados de UI es nuestro:
/// running | needsInstall | starting | stopped | error.
class ScreenStatus {
  final String state;
  final bool hasLease;
  final String? leaseHolder; // agent | human
  final String? error;
  final Map<String, Object?> raw;

  const ScreenStatus({
    required this.state,
    required this.hasLease,
    this.leaseHolder,
    this.error,
    required this.raw,
  });

  bool get running => state == 'running' || state == 'starting';
  bool get needsInstall => state == 'needsInstall';
  bool get humanControls => hasLease && leaseHolder == 'human';

  factory ScreenStatus.fromRpc(Object? result) {
    final m = result is Map
        ? Map<String, Object?>.from(result)
        : const <String, Object?>{};
    final lease = m['lease'] is Map
        ? Map<String, Object?>.from(m['lease'] as Map)
        : null;
    final supported = m['supported'] as bool? ?? true;
    final installed = m['installed'] as bool? ?? true;
    final running = m['running'] as bool? ?? false;
    final blocker = m['blocker'] as String?;

    // Mapeo del contrato real (`tools/bot_desktop/runtime.py::status`):
    // `running` gana; sin binarios (Xvnc/Xfce) el arranque SIEMPRE falla →
    // needsInstall (el panel ofrece display.install); `blocker` = razón por
    // la que start() se negaría (p. ej. memoria del host).
    String state;
    if (running) {
      state = 'running';
    } else if (!supported || !installed) {
      state = 'needsInstall';
    } else if (blocker != null) {
      state = 'error';
    } else if (m['status'] is String || m['state'] is String) {
      // Gateways futuros que añadan `state`/`status` explícito: respetarlo.
      state = (m['status'] ?? m['state'])! as String;
    } else {
      state = 'stopped';
    }
    return ScreenStatus(
      state: state,
      hasLease: lease != null,
      leaseHolder: lease?['holder'] as String?,
      error: m['error'] as String? ?? blocker,
      raw: m,
    );
  }
}

/// Resultado de display.observe: ticket single-use (30 s) + ruta del WS.
class ScreenObserve {
  final String ticket;
  final String path;
  final String viewerId;

  const ScreenObserve({
    required this.ticket,
    required this.path,
    required this.viewerId,
  });

  /// URL del WS hermana: `ws(s)://<gateway><path>?display_ticket=…`
  /// (apps/desktop `sibling-ws-url.ts` hace exactamente esto con la base del
  /// gateway; el ticket va en QUERY a propósito — noVNC no negocia
  /// subprotocols y el ticket es single-use 30 s: web_routers/display.py).
  String wsUrlOf(String httpBaseUrl) {
    final base = httpBaseUrl
        .replaceFirst(RegExp(r'^https'), 'wss')
        .replaceFirst(RegExp(r'^http'), 'ws');
    return '$base$path?display_ticket=${Uri.encodeQueryComponent(ticket)}';
  }
}

/// Cliente de los métodos `display.*` del perfil de UN bot.
///
/// Todos por el socket pool del bot (JSON-RPC, `ProfileParams`), como hace
/// Hermes Desktop; la RFB va aparte por el WS hermana. `viewer_id` se genera
/// una vez por controlador y NUNCA viaja al gateway (sólo su hash de 12 hex).
class ScreenController {
  final ConnectionRuntime runtime;
  final String profile;
  final String viewerId;

  ScreenStatus? _status;
  ScreenStatus? get status => _status;

  /// Cambios de estado para refrescar la UI (incl. lease).
  final _changes = StreamController<ScreenStatus>.broadcast();
  Stream<ScreenStatus> get changes => _changes.stream;

  /// Eventos del visor (connected / disconnected / control-taken…).
  final _viewerEvents = StreamController<Map<String, Object?>>.broadcast();
  Stream<Map<String, Object?>> get viewerEvents => _viewerEvents.stream;

  ScreenController({
    required this.runtime,
    required this.profile,
    required this.viewerId,
  });

  void dispose() {
    _changes.close();
    _viewerEvents.close();
  }

  Future<ScreenStatus> refresh() async {
    final r = await runtime.gateway.rawCall(
      'display.status',
      params: {'profile': profile},
    );
    _status = ScreenStatus.fromRpc(r);
    _changes.add(_status!);
    return _status!;
  }

  Future<ScreenObserve> observe() async {
    final r = await runtime.gateway.rawCall(
      'display.observe',
      params: {'profile': profile, 'viewer_id': viewerId},
    );
    final m = r is Map ? Map<String, Object?>.from(r) : const {};
    final ticket = m['ticket'] as String?;
    if (ticket == null) {
      throw StateError('display.observe sin ticket: $r');
    }
    return ScreenObserve(
      ticket: ticket,
      path: (m['path'] ?? '/api/display/ws') as String,
      viewerId: viewerId,
    );
  }

  /// Lanza la instalación del entorno de escritorio en el host del gateway
  /// (Xvnc + Xfce vía el gestor de paquetes). Devuelve enseguida: el
  /// progreso llega por eventos `display.install.log`, y puede pedir la
  /// contraseña de sudo del host por server-request `display.install.sudo`.
  /// Fin: evento `display.install.done {code, status}` (0 = ok).
  Future<void> install() async {
    await runtime.gateway.rawCall(
      'display.install',
      params: {'profile': profile},
    );
  }

  Future<ScreenStatus> start() async {
    final r = await runtime.gateway.rawCall(
      'display.start',
      params: {'profile': profile},
    );
    _status = ScreenStatus.fromRpc(r);
    _changes.add(_status!);
    return _status!;
  }

  Future<ScreenStatus> stop({bool force = false}) async {
    final r = await runtime.gateway.rawCall(
      'display.stop',
      params: {'profile': profile, 'force': force},
    );
    _status = ScreenStatus.fromRpc(r);
    _changes.add(_status!);
    return _status!;
  }

  /// Devolver el control al bot (lease release). `force` desaloja.
  Future<void> releaseLease({bool force = false}) async {
    await runtime.gateway.rawCall(
      'display.lease.release',
      params: {'profile': profile, 'viewer_id': viewerId, 'force': force},
    );
    await refresh();
  }

  /// Tomar el control (lease acquire humano). El último takeover gana; el
  /// desalojado recibe close WS 4000 "control-taken" y vuelve a observar.
  Future<ScreenStatus> acquireLease({String reason = 'Hermes Pocket'}) async {
    final r = await runtime.gateway.rawCall(
      'display.lease.acquire',
      params: {'profile': profile, 'viewer_id': viewerId, 'reason': reason},
    );
    _status = ScreenStatus.fromRpc(r);
    _changes.add(_status!);
    return _status!;
  }

  /// Inyecta el evento que el visor emite por el JavaScriptChannel.
  void handleViewerEvent(String payload) {
    Map<String, Object?>? m;
    try {
      final d = jsonDecode(payload);
      if (d is Map) m = Map<String, Object?>.from(d);
    } on FormatException {
      return; // payload no JSON: ignorar (protección de canal).
    }
    if (m == null) return;
    _viewerEvents.add(m);
    if (m['event'] == 'disconnected') {
      // 4000 control-taken: refrescar para pintar quién manda.
      unawaited(refresh());
    }
  }
}

/// Resuelve la conversación → (runtime, profile name) o null si no es un bot
/// conectado. Los grupos NO tienen pantalla propia (Screen es por-perfil).
({ConnectionRuntime runtime, String profile})? screenTarget(Conversation conv) {
  if (conv.isGroup) return null;
  final runtime = AppServices.connections.runtimeFor(conv.connectionId);
  if (runtime == null) return null;
  return (runtime: runtime, profile: conv.gatewayId);
}
