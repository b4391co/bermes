import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../clients/hermes/gateway_client.dart';
import '../../clients/hermes/http_client.dart';
import '../../core/app_services.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';
import '../../domain/connection/connection_profile.dart';
import '../settings/appearance_section.dart';

/// Editor de conexión a pantalla completa: alta y edición reales.
///
/// - La contraseña vive SOLO en SecureStore (recordar), nunca en la DB.
/// - "Probar conexión" llama probeTransport() y muestra la causa real
///   diferenciada (red / credenciales / versión / servidor).
/// - Guardar escribe la fila en drift y registra el runtime en el
///   ConnectionManager con un profile actualizado.
class ConnectionEditor extends StatefulWidget {
  /// Fila existente (edición) o null (alta).
  final Connection? existing;

  const ConnectionEditor({super.key, this.existing});

  @override
  State<ConnectionEditor> createState() => _ConnectionEditorState();
}

class _ConnectionEditorState extends State<ConnectionEditor> {
  final _log = Logger('ConnEditor');
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _basePath;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late String _scheme;
  late bool _insecureTls;
  late HermesAuthKind _authKind;
  late final TextEditingController _gatewayToken;
  bool _rememberPassword = true;
  bool _testing = false;
  AuthResult? _testResult;
  bool _diagLoading = false;
  Map<String, Object?>? _rosterDiag;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: e?.port.toString() ?? '9119');
    _basePath = TextEditingController(text: e?.basePath ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _scheme = e?.scheme ?? 'http';
    _insecureTls = e?.allowInsecureTls ?? false;
    _authKind =
        HermesAuthKind.values.asNameMap()[e?.authKind] ??
        HermesAuthKind.password;
    _password = TextEditingController();
    _gatewayToken = TextEditingController();
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    if (!_isEdit) return;
    final pw = await AppServices.secrets.readRememberedPassword(
      widget.existing!.id,
    );
    if (pw != null && mounted) {
      setState(() {
        _password.text = pw;
        _rememberPassword = true;
      });
    }
    final token = await AppServices.secrets.readGatewayToken(
      widget.existing!.id,
    );
    if (token != null && mounted) {
      setState(() => _gatewayToken.text = token);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _basePath.dispose();
    _username.dispose();
    _password.dispose();
    _gatewayToken.dispose();
    super.dispose();
  }

  bool get _formValid =>
      _name.text.trim().isNotEmpty &&
      _host.text.trim().isNotEmpty &&
      int.tryParse(_port.text.trim()) != null;

  ConnectionProfile _profileFromForm(String id) => ConnectionProfile(
    id: id,
    name: _name.text.trim(),
    scheme: _scheme,
    host: _host.text.trim(),
    port: int.parse(_port.text.trim()),
    basePath: _basePath.text.trim(),
    authKind: _authKind,
    username: _username.text.trim(),
    allowInsecureTls: _insecureTls,
    enabled: widget.existing?.enabled ?? true,
  );

  /// Probe REAL contra el transporte: usa un cliente efímero con el
  /// profile del formulario (sin tocar el runtime persistente).
  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = HermesHttpClient(_profileFromForm(_currentId));
    final result = await client.probeTransport(
      username: _username.text.trim(),
      password: _password.text,
    );
    client.dispose();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  String? _uuid;

  String get _currentId => widget.existing?.id ?? (_uuid ??= const Uuid().v4());

  Future<void> _save() async {
    if (!_formValid) {
      final missing = <String>[
        if (_name.text.trim().isEmpty) 'nombre',
        if (_host.text.trim().isEmpty) 'host',
        if (int.tryParse(_port.text.trim()) == null) 'puerto válido',
      ];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falta por completar: ${missing.join(', ')}')),
        );
      }
      return;
    }
    final db = AppServices.db;
    final connections = AppServices.connections;
    try {
      final id = _currentId;
      final profile = _profileFromForm(id);
      final row = ConnectionsCompanion.insert(
        id: id,
        name: profile.name,
        scheme: profile.scheme,
        host: profile.host,
        port: profile.port,
        basePath: Value(profile.basePath),
        authKind: profile.authKind.name,
        username: Value(profile.username),
        allowInsecureTls: Value(profile.allowInsecureTls),
        enabled: Value(profile.enabled),
      );
      await db.into(db.connections).insertOnConflictUpdate(row);

      if (_rememberPassword && _password.text.isNotEmpty) {
        await AppServices.secrets.writeRememberedPassword(id, _password.text);
      } else {
        await AppServices.secrets.deleteRememberedPassword(id);
      }

      final gwToken = _gatewayToken.text.trim();
      if (_authKind == HermesAuthKind.sessionToken && gwToken.isNotEmpty) {
        await AppServices.secrets.writeGatewayToken(id, gwToken);
      } else {
        // Contraseña, o método token con campo vacío: no arrastrar viejo.
        await AppServices.secrets.deleteGatewayToken(id);
      }
      // Runtime actualizado: si ya existía, se reemplaza; si no, se crea.
      final existingRuntime = connections.runtimeFor(id);
      if (existingRuntime != null &&
          (existingRuntime.profile.scheme != profile.scheme ||
              existingRuntime.profile.host != profile.host ||
              existingRuntime.profile.port != profile.port ||
              existingRuntime.profile.basePath != profile.basePath ||
              existingRuntime.profile.allowInsecureTls !=
                  profile.allowInsecureTls ||
              existingRuntime.profile.authKind != profile.authKind)) {
        await connections.removeRuntime(id);
      }
      final runtime = connections.ensureRuntime(profile);
      connections.registerRows(const [], db, secrets: AppServices.secrets);
      if (_authKind == HermesAuthKind.sessionToken &&
          _gatewayToken.text.trim().isNotEmpty) {
        // Modo token: NO hay password-login. Sembrar el token en el cliente
        // del runtime y conectar (WS con ?token=). La comprobación de vida
        // real es el propio sync contra /api (authMe la hace el gestor).
        try {
          runtime.http.adoptGatewayToken(_gatewayToken.text.trim());
          final savedRow = Connection(
            id: id,
            name: profile.name,
            scheme: profile.scheme,
            host: profile.host,
            port: profile.port,
            basePath: profile.basePath,
            authKind: profile.authKind.name,
            username: profile.username,
            allowInsecureTls: profile.allowInsecureTls,
            enabled: profile.enabled,
            displayOrder: await _nextDisplayOrder(db),
            createdAt: DateTime.now(),
          );
          await connections.connectAndSync(runtime, savedRow);
        } catch (e) {
          _log.warning('post-save token connect falló', e);
        }
      } else if (_password.text.isNotEmpty) {
        try {
          // El gestor resuelve el nombre real del proveedor y CONFIRMA la
          // sesión minteando un ticket WS (routes.py:458-466), en vez de
          // asumir que un 200 del login significa sesión viva.
          final result = await connections.login(
            runtime,
            username: profile.username,
            password: _password.text,
          );
          if (result.ok) {
            // Auto-sync en ready: registra la fila (con la password ya
            // persistida, el roster se refresca en cada reconexión).
            final savedRow = Connection(
              id: id,
              name: profile.name,
              scheme: profile.scheme,
              host: profile.host,
              port: profile.port,
              basePath: profile.basePath,
              authKind: profile.authKind.name,
              username: profile.username,
              allowInsecureTls: profile.allowInsecureTls,
              enabled: profile.enabled,
              displayOrder: await _nextDisplayOrder(db),
              createdAt: DateTime.now(),
            );
            await connections.connectAndSync(runtime, savedRow);
          }
        } catch (e) {
          _log.warning('post-save connect falló', e);
        }
      }

      _log.info('connection saved ${profile.name}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _log.error('save failed', e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(asAppException(e).message)));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conexión'),
        content: Text(
          'Se eliminará "${widget.existing!.name}" de este dispositivo. '
          'No toca nada del servidor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Hp.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.existing!.id;
    try {
      await (AppServices.db.delete(
        AppServices.db.connections,
      )..where((c) => c.id.equals(id))).go();
      await AppServices.secrets.deleteRememberedPassword(id);
      await AppServices.secrets.deleteSession(id);
      await AppServices.connections.removeRuntime(id);
      _log.info('connection deleted $id');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _log.error('delete failed', e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(asAppException(e).message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar conexión' : 'Nueva conexión'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Hp.s8),
        children: [
          _sectionCard([
            _field(_name, 'Nombre', hint: 'Mi gateway', autofocus: !_isEdit),
            _field(_host, 'Host', hint: '192.168.1.10'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Label('Esquema'),
                        const SizedBox(height: Hp.s1),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'http', label: Text('http')),
                            ButtonSegment(value: 'https', label: Text('https')),
                          ],
                          selected: {_scheme},
                          onSelectionChanged: (s) =>
                              setState(() => _scheme = s.first),
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Hp.s3),
                  Expanded(
                    child: _field(
                      _port,
                      'Puerto',
                      hint: '9119',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ),
            _field(_basePath, 'Ruta base', hint: '/hermes'),
            Padding(
              padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s2, Hp.s4, Hp.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('Método de acceso'),
                  const SizedBox(height: Hp.s1),
                  SegmentedButton<HermesAuthKind>(
                    segments: const [
                      ButtonSegment(
                        value: HermesAuthKind.password,
                        label: Text('Usuario'),
                      ),
                      ButtonSegment(
                        value: HermesAuthKind.sessionToken,
                        label: Text('Token'),
                      ),
                    ],
                    selected: {_authKind},
                    onSelectionChanged: (s) =>
                        setState(() => _authKind = s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Text(
                    _authKind == HermesAuthKind.sessionToken
                        ? 'Pega el session token del gateway '
                              '(HERMES_DASHBOARD_SESSION_TOKEN en su .env). '
                              'Válido solo en gateways sin portal OAuth.'
                        : 'Inicio de sesión con usuario y contraseña '
                              '(sesión renovada automáticamente).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (_authKind == HermesAuthKind.sessionToken)
              _field(
                _gatewayToken,
                'Session token',
                hint: 'Pega el token del gateway',
                obscure: true,
              ),
            if (_authKind == HermesAuthKind.password) ...[
              _field(_username, 'Usuario', hint: 'opcional'),
              _field(
                _password,
                'Contraseña',
                hint: _rememberPassword ? '' : 'opcional',
                obscure: true,
                trailing: SwitchListTileLike(
                  title: 'Recordar en este dispositivo',
                  value: _rememberPassword,
                  onChanged: (v) => setState(() => _rememberPassword = v),
                ),
              ),
            ],
          ]),
          if (_insecureTlsBannerVisible) _insecureBanner(cs),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s3, Hp.s4, Hp.s2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TLS inseguro (solo LAN)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Switch(
                      value: _insecureTls,
                      onChanged: (v) => setState(() => _insecureTls = v),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Hp.s4, 0, Hp.s4, Hp.s3),
                child: Text(
                  'Acepta certificados autofirmados de ESTE host. Úsalo solo '
                  'en redes de confianza; nadie valida la identidad del '
                  'servidor.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          _testResultCard(cs),
          if (_rosterDiag != null) _rosterDiagCard(cs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
            child: OutlinedButton.icon(
              onPressed: _formValid && !_diagLoading ? _diagRoster : null,
              icon: _diagLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rule_rounded),
              label: const Text('Diagnóstico de grupos y bots'),
            ),
          ),
          const SizedBox(height: Hp.s2),
          Padding(
            padding: const EdgeInsets.all(Hp.s4),
            child: Row(
              children: [
                if (_isEdit) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Hp.error,
                        side: BorderSide(
                          color: Hp.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text('Eliminar'),
                    ),
                  ),
                  const SizedBox(width: Hp.s3),
                ],
                Expanded(
                  flex: _isEdit ? 2 : 1,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_isEdit ? 'Guardar cambios' : 'Guardar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _insecureTlsBannerVisible => _insecureTls && _scheme == 'https';

  Widget _insecureBanner(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hp.s4, 0, Hp.s4, Hp.s2),
      child: Container(
        padding: const EdgeInsets.all(Hp.s3),
        decoration: BoxDecoration(
          color: Hp.connecting.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Hp.rMd),
          border: Border.all(color: Hp.connecting.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: Hp.connecting),
            const SizedBox(width: Hp.s2),
            Expanded(
              child: Text(
                'HTTPS con certificado sin validar: la conexión no podrá '
                'demostrar que habla con tu servidor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) => SettingsCard(
    children: [
      const SizedBox(height: Hp.s1),
      ...children,
      const SizedBox(height: Hp.s1),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    bool autofocus = false,
    TextInputType? keyboardType,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s2, Hp.s4, Hp.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          const SizedBox(height: Hp.s1),
          TextField(
            controller: controller,
            obscureText: obscure,
            autofocus: autofocus,
            keyboardType: keyboardType,
            autocorrect: false,
            enableSuggestions: !obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: hint),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _testResultCard(ColorScheme cs) {
    final r = _testResult;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
        child: OutlinedButton.icon(
          onPressed: _formValid && !_testing ? _test : null,
          icon: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check_rounded),
          label: const Text('Probar conexión'),
        ),
      );
    }
    final (color, icon, title, detail) = _describeResult(r);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(Hp.s3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Hp.rMd),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: Hp.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Repetir',
                  onPressed: _testing ? null : _test,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: Hp.s2),
        ],
      ),
    );
  }

  /// Diagnóstico del roster contra el gateway del formulario: fuente
  /// (WS/REST), presencia del espejo de grupos y sesión canónica.
  Future<void> _diagRoster() async {
    // Preferir el runtime vivo de la conexión guardada: su cliente ya tiene
    // sesión y WS listo. El efímero solo sirve si aún no existe runtime
    // (formulario de alta): en ese caso hay que iniciar sesión primero.
    final existingId = widget.existing?.id;
    final runtime = existingId == null
        ? null
        : AppServices.connections.runtimeFor(existingId);
    final profile = _profileFromForm(_currentId);
    final client =
        runtime?.gateway ??
        HermesGatewayClient(profile, HermesHttpClient(profile));
    final ephemeral = runtime == null;
    try {
      await client.connect();
      await client.readyOrTimeout(const Duration(seconds: 8));
      final d = await client.rosterDiagnostic();
      if (!mounted) return;
      setState(() {
        _rosterDiag = d;
        _diagLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rosterDiag = {'source': 'connect-error: $e'};
        _diagLoading = false;
      });
    } finally {
      // El runtime vivo pertenece a la app: NO se cierra.
      if (ephemeral) client.dispose();
    }
  }

  Widget _rosterDiagCard(ColorScheme cs) {
    final d = _rosterDiag!;
    String v(String k) => '${d[k] ?? '—'}';
    final ok = d['groups_mirror_present'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      child: Container(
        padding: const EdgeInsets.all(Hp.s3),
        decoration: BoxDecoration(
          color: (ok ? Hp.online : Hp.error).withValues(alpha: 0.08),
          border: Border.all(
            color: (ok ? Hp.online : Hp.error).withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(Hp.rMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Roster: ${v('source')} · credencial: ${v('auth_kind')} '
              '(${d['auth_ok'] == true ? 'ACEPTADA' : 'RECHAZADA'})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: d['auth_ok'] == true ? cs.onSurface : Hp.error,
              ),
            ),
            const SizedBox(height: Hp.s1),
            Text(
              'perfiles: ${v('profiles')} · default: ${d['default_present'] == true ? 'sí' : 'NO'}\n'
              'espejo de grupos: ${ok ? 'presente' : 'AUSENTE'} · salas: ${v('rooms')} · '
              'borrados: ${v('tombstones')}\n'
              'sesión canónica: ${d['canonical_session'] == true ? 'sí' : 'no'} · '
              'meta de bot: ${d['bot_meta'] == true ? 'sí' : 'no'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (d['auth_ok'] != true)
              Padding(
                padding: const EdgeInsets.only(top: Hp.s1),
                child: Text(
                  d['auth_kind'] == 'sessionToken'
                      ? 'El gateway RECHAZA el token. Si el gateway está tras '
                            'un portal OAuth, cambia el método a «Usuario». Si '
                            'es loopback, el token del .env cambió o expiró.'
                      : 'La sesión no está activa: prueba de nuevo el login.',
                  style: TextStyle(color: Hp.error, fontSize: 12.5),
                ),
              ),
            if (!ok)
              Padding(
                padding: const EdgeInsets.only(top: Hp.s1),
                child: Text(
                  'Sin espejo: abre Hermes Desktop con este gateway; Desktop '
                  'publica los grupos al conectar. Si Desktop ya está '
                  'conectado y sigue ausente, este gateway es otra URL.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  (Color, IconData, String, String?) _describeResult(AuthResult r) {
    if (r.ok) {
      return (
        Hp.online,
        Icons.check_circle_rounded,
        'Gateway Hermes alcanzable',
        // «Probar conexión» NO comprueba credenciales: sondea GET /api/status,
        // que es público aunque el panel esté tras el gate
        // (hermes_cli/dashboard_auth/public_paths.py:15). Disparar el login
        // desde aquí gastaría el anti-fuerza-bruta de 10 intentos/60 s
        // (routes.py:338-339) y bloquearía el inicio de sesión real.
        'El servidor responde como gateway en $_scheme://${_host.text.trim()}. '
            'Guarda la conexión para comprobar las credenciales.',
      );
    }
    return switch (r.cause) {
      AuthFailureCause.network => (
        Hp.error,
        Icons.wifi_off_rounded,
        'No se pudo conectar',
        'El host no responde: revisa dirección, puerto y red.',
      ),
      AuthFailureCause.badCredentials => (
        Hp.error,
        Icons.lock_outline_rounded,
        'Acceso denegado',
        r.detail ?? 'El servidor rechazó el acceso (401/403).',
      ),
      AuthFailureCause.rateLimited => (
        Hp.connecting,
        Icons.hourglass_top_rounded,
        'Demasiados intentos',
        'El servidor limita la frecuencia (429). Espera un momento.',
      ),
      AuthFailureCause.version => (
        Hp.connecting,
        Icons.update_rounded,
        'Versión incompatible',
        r.detail ?? 'Este gateway no expone los endpoints esperados (404).',
      ),
      AuthFailureCause.serverError => (
        Hp.error,
        Icons.dns_rounded,
        'Error del servidor',
        r.detail,
      ),
      AuthFailureCause.unknown || null => (
        Hp.error,
        Icons.help_outline_rounded,
        'Error desconocido',
        r.detail,
      ),
    };
  }
}

/// Etiqueta de campo.
class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelSmall);
  }
}

/// Fila tipo ajuste con switch (etiqueta corta, sin dependencias).
class SwitchListTileLike extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchListTileLike({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.bodySmall),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Próximo orden de sección para una conexión nueva (máx+1).
Future<int> _nextDisplayOrder(AppDatabase db) async {
  final rows = await db.select(db.connections).get();
  if (rows.isEmpty) return 0;
  return rows.map((r) => r.displayOrder).reduce((a, b) => a > b ? a : b) + 1;
}
