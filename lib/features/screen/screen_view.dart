import 'dart:async';

import 'package:flutter/material.dart';

import '../../clients/hermes/rfb_client.dart';
import '../../design/tokens.dart';
import 'screen_controller.dart';
import 'screen_viewer.dart';

import '../../clients/hermes/rpc_types.dart';

/// Convierte la base HTTP del gateway en la URL del WS de pantalla.
/// Mismo patrón que `sibling-ws-url.ts` de Hermes Desktop; el ticket viaja en
/// QUERY a propósito (web_routers/display.py: noVNC no negocia subprotocolos).
String buildDisplayWsUrl(String httpBaseUrl, String path, String ticket) {
  final base = httpBaseUrl
      .replaceFirst(RegExp(r'^https'), 'wss')
      .replaceFirst(RegExp(r'^http'), 'ws');
  return '$base$path?display_ticket=${Uri.encodeQueryComponent(ticket)}';
}

/// Visor Screen del bot: RFB (VNC) NATIVO sobre el WebSocket del gateway
/// (`HermesRfbClient`), con los controles de lease de Hermes Desktop
/// (Observar / Tomar control / Devolver).
///
/// 0.1.61 — adiós al WebView+noVNC. El pipeline viejo (WebView → servercito
/// shelf de loopback → bundle JS de noVNC → bridge) nunca llegaba a conectar
/// en el móvil — «el modo escritorio no va» repetido del usuario. El cliente
/// RFB nativo está PROBADO contra el gateway real (handshake 3.8 →
/// SecurityNone → SetPixelFormat/Encodings → FramebufferUpdate; 1440x900 con
/// frames y control por lease). `assets/screen/*` queda fuera de la ruta.
class ScreenView extends StatefulWidget {
  final ScreenController controller;
  final String botTitle;

  /// `full` = ruta con su propia barra (back + título + botón cerrar).
  /// `pane` = franja embebible para el split del chat: sin Scaffold, barra
  /// fina propia (estado + controles + maximizar).
  final ScreenViewMode mode;

  /// Sólo modo pane: el panel ocupa todo el chat (el chat queda oculto).
  final bool maximized;

  /// Sólo modo pane: pedir al padre maximizar/restaurar.
  final VoidCallback? onToggleMaximize;

  const ScreenView({
    super.key,
    required this.controller,
    required this.botTitle,
    this.mode = ScreenViewMode.full,
    this.maximized = false,
    this.onToggleMaximize,
  });

  @override
  State<ScreenView> createState() => _ScreenViewState();
}

enum ScreenViewMode { full, pane }

class _ScreenViewState extends State<ScreenView> {
  final _statusKey = GlobalKey<_ScreenStateBadgeState>();

  StreamSubscription<ScreenStatus>? _statusSub;
  StreamSubscription<GatewayEvent>? _installLogSub;
  StreamSubscription<ServerRequest>? _sudoSub;
  final List<String> _installLog = <String>[];
  bool _installing = false;
  String _message = 'Preparando escritorio…';

  /// Cliente RFB nativo + su suscripción de estados (4000 → re-observar).
  HermesRfbClient? _rfb;
  StreamSubscription<RfbState>? _rfbSub;

  /// El visor controla (lease humano) → teclado/ratón vivos; si no, view-only.
  bool _controlling = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());

    _statusSub = widget.controller.changes.listen((s) {
      if (!mounted) return;
      // El lease puede haber cambiado fuera (takeover por el bot, expiración,
      // otro cliente): el modo de input del visor SIGUE al gateway, no a un
      // toggle local que se quedaba desincronizado (el «Tomar control» vieja
      // escuela: badge verde sin lease real → toques ignorados).
      final human = s.humanControls;
      setState(() {
        _controlling = human;
        if (!s.running) _message = _messageFor(s);
      });
    });
    // Eventos globales de instalación (display.install.log/done) + el
    // server-request de sudo que el gateway dirige a ESTA conexión.
    _installLogSub = widget.controller.runtime.gateway.events.listen((ev) {
      if (ev.type == 'display.install.log') {
        final line = ev.payload['line']?.toString() ?? '';
        if (mounted) {
          setState(() {
            _installLog.add(line);
            _message = 'Instalando en el host… ${_installLog.length} líneas';
          });
        }
      } else if (ev.type == 'display.install.done') {
        final code = ev.payload['code'];
        if (mounted) {
          setState(() {
            _installing = false;
            _message = code == 0
                ? 'Instalación completada. Iniciando escritorio…'
                : 'La instalación terminó con código $code.';
          });
        }
        if (code == 0) {
          unawaited(_run('Iniciar', () async {
            await widget.controller.start();
            if (!mounted) return;
            if (await _awaitRunning()) await _startViewer();
          }));
        }
      }
    });
    _sudoSub = widget.controller.runtime.gateway.serverRequests.listen((sr) {
      if (sr.method != 'display.install.sudo') return;
      _askSudoPassword(sr);
    });
    unawaited(_startViewer());
  }

  Future<void> _askSudoPassword(ServerRequest sr) async {
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => _SudoPasswordDialog(host: widget.botTitle),
    );
    if (pw == null) {
      await widget.controller.runtime.gateway.failServerRequest(
        sr.id,
        -32000,
        'El usuario canceló la tarjeta de sudo.',
      );
      return;
    }
    await widget.controller.runtime.gateway.respondToServerRequest(sr.id, {
      'password': pw,
    });
  }
  Future<void> _boot() async {
    try {
      final st = await widget.controller.refresh();
      if (!mounted) return;
      setState(() => _message = _messageFor(st));
      if (st.state == 'stopped' || st.state == 'error') {
        // 0.1.61: ABRIR el panel Screen es una orden clara de ver el
        // escritorio. Antes Pocket se quedaba pasmado en «El escritorio del
        // bot está parado» hasta que el usuario pulsaba Iniciar — y no
        // arrancaba («el modo escritorio no va»). Ahora se arranca SOLO (el
        // gateway decide recursos; needsInstall sigue con su flujo de
        // instalación explícito) y se espera a `running` con progreso.
        if (st.state == 'stopped' && !st.needsInstall && !st.unsupported) {
          if (mounted) setState(() => _message = 'Iniciando el escritorio…');
          try {
            await widget.controller.start();
          } catch (_) {}
          if (!mounted) return;
          if (await _awaitRunning()) await _startViewer();
          return;
        }
        return;
      }
      if (st.needsInstall) return;
      await _startViewer();
    } catch (e) {
      if (mounted) setState(() => _message = 'El gateway no responde: $e');
    }
  }

  /// Pedir ticket fresco y abrir la RFB NATIVA. El ticket es single-use 30 s:
  /// se observa → se conecta de inmediato. Cada arranque reemplaza al cliente
  /// anterior (un takeover cambia de lease → conviene sesión RFB nueva).
  Future<void> _startViewer() async {
    try {
      setState(() => _message = 'Conectando con el escritorio…');
      final obs = await widget.controller.observe();
      await _teardownRfb();
      final rfb = HermesRfbClient();
      _rfb = rfb;
      _rfbSub = rfb.states.listen(_onRfbState);
      // buildDisplayWsUrl deja la URL SIN ticket (el cliente lo añade al
      // conectar; pasar la URL con query duplicaría `display_ticket`).
      final base = widget.controller.runtime.profile.baseUrl
          .replaceFirst(RegExp(r'^https'), 'wss')
          .replaceFirst(RegExp(r'^http'), 'ws');
      await rfb.connect(wsUrl: '$base${obs.path}', ticket: obs.ticket);
    } on JsonRpcError catch (e) {
      // Gateway sin Bot Screen (display.* no existe: -32601 o «not found»,
      // p. ej. 0.15.0/0.21.4). Decirlo claro; no dejar el visor en blanco.
      final missing =
          e.code == -32601 || e.message.toLowerCase().contains('not found');
      if (mounted) {
        setState(
          () => _message = missing
              ? 'Este gateway no tiene Bot Screen (requiere Hermes 0.21.5+).'
              : 'No se pudo abrir la pantalla: ${e.message}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'No se pudo abrir la pantalla: $e');
      }
    }
  }

  /// Estado del cliente RFB nativo. 4000 = otro cliente tomó el lease
  /// (display.py): volver a observar sin control. 4001 = el escritorio del
  /// bot murió. Cualquier corte inesperado ofrece recargar.
  void _onRfbState(RfbState st) {
    if (!mounted) return;
    switch (st) {
      case RfbState.ready:
        setState(() => _message = '');
      case RfbState.disconnected:
        final code = _rfb?.lastCloseCode;
        if (code == 4000) {
          setState(() {
            _controlling = false;
            _message = 'Otro cliente tomó el control. Volviendo a observar…';
          });
          unawaited(
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) _startViewer();
            }),
          );
        } else if (code == 4001) {
          setState(() {
            _controlling = false;
            _message = 'El escritorio del bot se detuvo.';
          });
        } else {
          final why = code != null ? '$code' : 'red';
          setState(() {
            _controlling = false;
            _message =
                'Conexión con el escritorio perdida ($why). '
                'Pulsa Recargar visor.';
          });
        }
      case RfbState.unauthorized:
        setState(
          () => _message =
              'El gateway rechazó el ticket de observación (sesión caducada '
              'o sin sesión (4401/4403)). Recarga el visor.',
        );
      case RfbState.unsupported:
        setState(
          () => _message =
              'El escritorio del bot usa un encoding RFB que Pocket no '
              'soporta todavía.',
        );
      case RfbState.error:
        setState(
          () => _message =
              'Fallo de transporte con el escritorio. Pulsa Recargar visor.',
        );
      case RfbState.connecting:
      case RfbState.handshaking:
        break;
    }
  }

  Future<void> _teardownRfb() async {
    await _rfbSub?.cancel();
    _rfbSub = null;
    final r = _rfb;
    _rfb = null;
    if (r != null) await r.dispose();
  }

  String _messageFor(ScreenStatus s) => switch (s.state) {
    'stopped' => 'El escritorio del bot está parado.',
    'unsupported' =>
      'Este gateway no incorpora Bot Screen (versión anterior a 0.21.5): '
          'actualiza el gateway para ver el escritorio del bot aquí.',
    'needsInstall' =>
      'Este host no tiene el escritorio instalado '
          '(falta TigerVNC/Xfce${s.error != null ? ': ${s.error}' : ''}). '
          'Pulsa Instalar en el host.',
    'starting' => 'Iniciando el escritorio…',
    'installing' => 'Instalando el entorno de escritorio en el host…',
    'error' => 'Error en el escritorio: ${s.error ?? 'desconocido'}',
    _ =>
      s.humanControls
          ? 'Tienes el control del escritorio.'
          : 'El bot está usando su escritorio.',
  };

  @override
  void dispose() {
    _statusSub?.cancel();
    _installLogSub?.cancel();
    _sudoSub?.cancel();
    // Ocultar el panel NO destruye el escritorio del bot: aquí solo se corta
    // el WebSocket RFB del visor. Si no se cierra, la sesión queda abierta y
    // el lease del observador vivo puede bloquear el takeover del control
    // hasta su expiración.
    unawaited(_teardownRfb());
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label falló: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Esperar a que el gateway reporte el escritorio en marcha. El arranque
  /// real (Xvnc + Xfce) tarda decenas de segundos: hasta 120 s. Informa el
  /// estado en el overlay a cada cambio (el síntoma de 0.1.24 era "Iniciar y
  /// no pasa nada": el botón de la barra esperaba 40 s a ciegas y al
  /// agotarse pedía un observe que el gateway rechazaba sin explicación).
  /// Devuelve false si el estado sigue sin ser `running`.
  Future<bool> _awaitRunning() async {
    String last = '';
    for (var i = 0; i < 60; i++) {
      final s = await widget.controller.refresh();
      if (s.state == 'running') return true;
      final msg = _messageFor(s);
      if (msg != last && mounted) {
        last = msg;
        setState(() => _message = msg);
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) {
      setState(
        () => _message =
            'El escritorio sigue tardando. Pulsa Recargar visor cuando '
            'Hermes Desktop lo muestre en marcha.',
      );
    }
    return false;
  }

  List<Widget> _controlActions() {
    final st = widget.controller.status;
    final running = st?.running ?? false;
    final humanControls = _controlling || (st?.humanControls ?? false);
    return [
      if (running && !humanControls)
        IconButton(
          tooltip: _controlling ? 'Devolver control' : 'Tomar control',
          onPressed: _busy
              ? null
              : () => _run('Tomar control', () async {
                  if (_controlling) {
                    await widget.controller.releaseLease();
                    if (!mounted) return;
                    setState(() => _controlling = false);
                    await _startViewer();
                  } else {
                    await widget.controller.acquireLease();
                    if (!mounted) return;
                    setState(() {
                      _controlling = true;
                      _message = '';
                    });
                    // El gateway RECHAZA el input sin lease (RfbClientFilter
                    // → close 4000 si no lo tienes): la sesión RFB vieja es
                    // view-only en el servidor. Se reconecta con ticket
                    // fresco para que el control sea REAL.
                    await _startViewer();
                  }
                }),
          icon: Icon(
            _controlling ? Icons.mouse_rounded : Icons.touch_app_rounded,
          ),
        ),
      IconButton(
        tooltip: 'Recargar visor',
        onPressed: () => _startViewer(),
        icon: const Icon(Icons.refresh_rounded),
      ),
      if (running)
        IconButton(
          tooltip: 'Parar escritorio',
          onPressed: _busy
              ? null
              : () => _run('Parar', () async {
                  await widget.controller.stop();
                  if (!mounted) return;
                  await _startViewer();
                }),
          icon: const Icon(Icons.stop_circle_outlined),
        )
      else if (!(st?.needsInstall ?? false) && !(st?.unsupported ?? false))
        // Sin binarios (needsInstall) el start SIEMPRE falla con un error
        // críptico: el CTA honesto es Instalar (abajo), no Iniciar.
        IconButton(
          tooltip: 'Iniciar escritorio',
          onPressed: _busy
              ? null
              : () => _run('Iniciar', () async {
                  await widget.controller.start();
                  if (!mounted) return;
                  // El arranque real tarda (Xvnc + Xfce, decenas de s):
                  // esperar con progreso visible y NO abrir el visor si el
                  // gateway sigue sin decir `running` (el observe fallaría
                  // con display_not_running sin explicación).
                  if (await _awaitRunning()) await _startViewer();
                }),
          icon: const Icon(Icons.desktop_windows_outlined),
        ),
    ];
  }

  /// Barra fina del modo pane: título + chip de estado + controles +
  /// maximizar. Sustituye al AppBar de la ruta completa.
  Widget _paneBar(ColorScheme cs) {
    return Container(
      height: 36,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Icon(
            Icons.desktop_windows_outlined,
            size: 15,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.botTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ScreenStateBadge(key: _statusKey, controller: widget.controller),
          const Spacer(),
          IconButton(
            tooltip: widget.maximized ? 'Restaurar' : 'Maximizar escritorio',
            onPressed: widget.onToggleMaximize,
            iconSize: 20,
            icon: Icon(
              widget.maximized
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
          ),
          ..._controlActions(),
        ],
      ),
    );
  }

  /// El visor en sí (webview + overlays). Se comparte entre la ruta completa
  /// y el panel embebido del chat.
  Widget _viewerBody() {
    final st = widget.controller.status;
    final running = st?.running ?? false;
    final humanControls = _controlling || (st?.humanControls ?? false);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_rfb != null)
          ScreenViewer(
            key: ValueKey(_rfb),
            client: _rfb!,
            showBar: false,
            controlling: humanControls,
            onBackToWatch: () {
              // 4000 (control-taken): el padre decide — volver a observar.
              setState(() => _controlling = false);
              unawaited(_startViewer());
            },
          ),
        if (_rfb == null) const ColoredBox(color: Colors.black),
        if (_message.isNotEmpty && running && humanControls)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.all(Hp.s3),
              padding: const EdgeInsets.symmetric(
                horizontal: Hp.s3,
                vertical: Hp.s2,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(Hp.rSm),
              ),
              child: Text(
                _message,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        if (_message.isNotEmpty && !running)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy || running)
                  const Padding(
                    padding: EdgeInsets.only(bottom: Hp.s3),
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Hp.s5),
                  child: Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (!running &&
                    st?.state != 'installing' &&
                    st?.unsupported != true)
                  Padding(
                    padding: const EdgeInsets.only(top: Hp.s4),
                    child: st?.needsInstall ?? false
                        ? FilledButton.icon(
                            onPressed: _busy || _installing
                                ? null
                                : () => _run('Instalar', () async {
                                    setState(() => _installing = true);
                                    await widget.controller.install();
                                    // El progreso llega por eventos
                                    // (display.install.log/done); el done
                                    // con code 0 dispara el start.
                                  }),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Instalar en el host'),
                          )
                        : FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run('Iniciar', () async {
                                    await widget.controller.start();
                                    if (!mounted) return;
                                    if (await _awaitRunning()) {
                                      await _startViewer();
                                    }
                                  }),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: const Text('Iniciar escritorio'),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ScreenViewMode.pane) {
      // Franja embebida en el chat: sin Scaffold (el chat ya lo aporta).
      return ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            _paneBar(Theme.of(context).colorScheme),
            Expanded(child: _viewerBody()),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Screen · ${widget.botTitle}',
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: Hp.s2),
            _ScreenStateBadge(key: _statusKey, controller: widget.controller),
          ],
        ),
        actions: _controlActions(),
      ),
      body: _viewerBody(),
    );
  }
}

/// Chip de estado (running/lease) que se refresca con los cambios del
/// controlador.
class _ScreenStateBadge extends StatefulWidget {
  final ScreenController controller;
  const _ScreenStateBadge({super.key, required this.controller});

  @override
  State<_ScreenStateBadge> createState() => _ScreenStateBadgeState();
}

class _ScreenStateBadgeState extends State<_ScreenStateBadge> {
  StreamSubscription<ScreenStatus>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.status;
    final cs = Theme.of(context).colorScheme;
    if (s == null) return const SizedBox.shrink();
    final (label, color) = switch (s.state) {
      'running' => (
        s.humanControls ? 'control humano' : 'en vivo',
        s.humanControls ? Colors.orange : Colors.green,
      ),
      'stopped' => ('parado', cs.onSurfaceVariant),
      'needsInstall' => ('sin instalar', Colors.deepOrange),
      'unsupported' => ('sin Bot Screen', cs.onSurfaceVariant),
      'starting' || 'installing' => ('arrancando', Colors.blueGrey),
      _ => ('error', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Tarjeta de contraseña sudo del HOST (server-request `display.install.sudo`).
/// La contraseña viaja al gateway que pidió instalar; no se guarda.
class _SudoPasswordDialog extends StatefulWidget {
  final String host;

  const _SudoPasswordDialog({required this.host});

  @override
  State<_SudoPasswordDialog> createState() => _SudoPasswordDialogState();
}

class _SudoPasswordDialogState extends State<_SudoPasswordDialog> {
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Contraseña de sudo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'El gateway de ${widget.host} necesita permiso de administrador '
            'para instalar TigerVNC (Xvnc) y Xfce en su máquina.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Hp.s4),
          TextField(
            controller: _pw,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña sudo del host',
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: Hp.s2),
          Text(
            'Va solo a esta máquina; no se guarda en el teléfono.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_pw.text),
          child: const Text('Instalar'),
        ),
      ],
    );
  }
}
