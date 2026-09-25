import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../core/logger.dart';

/// Adapter de Herdr sobre SSH (contrato verificado en docs/research/herdr-and-ux.md).
///
/// DISEÑO (según el código de herdr v0.9.1, commit 21d0ce60):
/// - La API socket de Herdr es LOCAL al host (Unix socket). No hay HTTP/WS público.
/// - El transporte correcto desde móvil es SSH: ejecutar comandos del CLI
///   heredr sobre SSH y consumir su salida.
/// - Control-plane (inventario): `herdr api snapshot --json` → SessionSnapshot
///   con workspaces/tabs/panes/agents + estados (idle|working|blocked|done|unknown).
///   Alternativa ligera: `herdr session list --json` → {"sessions":[...]}.
/// - Data-plane (terminal real): `herdr terminal session control w1:p1 --takeover
///   --cols N --rows M` → NDJSON por stdout: {type:"terminal.frame", data:"(b64 ANSI)"}
///   y acepta comandos por stdin: {type:"terminal.input", data:"..."} /
///   {type:"terminal.resize", cols, rows} / {type:"terminal.release"}.
///   Read-only: `herdr terminal session observe ...` (varios observers sin input).
///
/// Un agente detectado por Herdr NO es automáticamente un bot de Hermes:
/// identidades separadas; la vinculación es explícita (agentSession source herdr:hermes).
class HerdrClient {
  final _log = Logger('Herdr');
  SSHClient _ssh;
  final String binary; // nombre/binario remoto

  HerdrClient({required SSHClient ssh, this.binary = 'herdr'}) : _ssh = ssh;

  /// true si herdr está instalado en el host remoto.
  Future<bool> isAvailable() async {
    final r = await _run('command -v $binary');
    return r.trim().isNotEmpty;
  }

  /// Versión (o cadena vacía si falla).
  Future<String> version() => _run('$binary --version 2>/dev/null || true');

  /// Inventario de agentes: herdr session snapshot → parse SessionSnapshot.
  /// Devuelve la lista normalizada de agentes con estado.
  Future<List<HerdrAgent>> listAgents() async {
    final raw = await _run('$binary api snapshot --json 2>/dev/null');
    if (raw.trim().isEmpty) {
      // Fallback a session list --json (formato {"sessions":[...]}, cli.rs:459).
      final sessionsRaw = await _run('$binary session list --json 2>/dev/null');
      return _parseSessionsFallback(sessionsRaw);
    }
    return _parseSnapshot(raw);
  }

  List<HerdrAgent> _parseSnapshot(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final agents = json['agents'];
      if (agents is! List) return const [];
      return agents
          .whereType<Map<String, Object?>>()
          .map(HerdrAgent.fromJson)
          .toList();
    } on FormatException catch (e) {
      _log.warning('snapshot no es JSON: ${e.message}');
      return const [];
    }
  }

  List<HerdrAgent> _parseSessionsFallback(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final sessions = json['sessions'];
      if (sessions is! List) return const [];
      return sessions
          .whereType<Map<String, Object?>>()
          .map(
            (s) => HerdrAgent(
              name: s['name'] as String? ?? 'session',
              status: HerdrStatus.unknown,
              paneId: null,
              workspaceId: null,
            ),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Abrir terminal REAL de un pane con control (NDJSON bridge sobre SSH).
  ///
  /// Devuelve un HerdrTerminalBridge con streams ya decodificados.
  Future<HerdrTerminalBridge> attachTerminal({
    required String paneId,
    required int cols,
    required int rows,
    bool takeover = true,
  }) async {
    final session = await _ssh.shell(environment: {'TERM': 'xterm-256color'});
    final mode = takeover ? 'control' : 'observe';
    final flags = takeover ? '--takeover' : '';
    session.write(
      utf8.encode(
        '$binary terminal session $mode $paneId $flags --cols $cols --rows $rows\n',
      ),
    );
    return HerdrTerminalBridge._(session);
  }

  Future<String> _run(String command) async {
    final result = await _ssh.run(command);
    return utf8.decode(result, allowMalformed: true);
  }

  void updateClient(SSHClient ssh) => _ssh = ssh;
}

/// Agente Herdr normalizado (de SessionSnapshot.agents o session list).
class HerdrAgent {
  final String name;
  final HerdrStatus status;
  final String? paneId;
  final String? workspaceId;
  final String? title;

  const HerdrAgent({
    required this.name,
    required this.status,
    this.paneId,
    this.workspaceId,
    this.title,
  });

  factory HerdrAgent.fromJson(Map<String, Object?> j) => HerdrAgent(
    name: j['name'] as String? ?? j['agent'] as String? ?? 'agent',
    status: HerdrStatusX.fromWire(j['agent_status'] as String?),
    paneId: j['pane_id'] as String?,
    workspaceId: j['workspace_id'] as String?,
    title: j['title'] as String?,
  );
}

enum HerdrStatus { idle, working, blocked, done, unknown }

extension HerdrStatusX on HerdrStatus {
  static HerdrStatus fromWire(String? s) => switch (s) {
    'idle' => HerdrStatus.idle,
    'working' => HerdrStatus.working,
    'blocked' => HerdrStatus.blocked,
    'done' => HerdrStatus.done,
    _ => HerdrStatus.unknown,
  };

  bool get needsAttention => this == HerdrStatus.blocked;
}

/// Puente NDJSON del terminal de Herdr sobre un shell SSH.
///
/// Frames que llegan por stdout del comando:
///   {"type":"terminal.frame","data":"(base64 ANSI)"}   → bytes de terminal
///   {"type":"terminal.closed"}                          → fin del stream
/// Comandos que se envían por stdin:
///   {"type":"terminal.input","data":"(texto o b64)"}
///   {"type":"terminal.resize","cols":N,"rows":M}
///   {"type":"terminal.release"}
class HerdrTerminalBridge {
  final SSHSession _session;
  final _log = Logger('HerdrTerm');

  final _output = StreamController<Uint8ListAdapter>.broadcast();
  final _closed = StreamController<void>.broadcast();
  StreamSubscription<String>? _stdoutSub;

  // Se usa dynamic para evitar dependencia circular; en la práctica Uint8List.
  // (El adaptador existe para mantener el stream tipado simple.)
  Stream<dynamic> get output => _output.stream;
  Stream<void> get onClosed => _closed.stream;

  HerdrTerminalBridge._(this._session) {
    _stdoutSub = _session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: () => _closed.add(null));
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final frame = jsonDecode(line) as Map<String, Object?>;
      switch (frame['type']) {
        case 'terminal.frame':
          final data = frame['data'] as String?;
          if (data != null) {
            final bytes = base64.decode(data);
            _output.add(bytes);
          }
          break;
        case 'terminal.closed':
          _closed.add(null);
          break;
        default:
          // Otros frames (diagnóstico) se registran y ignoran.
          _log.info('frame ${frame['type']}');
      }
    } on FormatException {
      // Línea no-JSON (p.ej. banner del shell) — ignorar.
    }
  }

  void sendInput(String text) {
    _session.write(
      utf8.encode('${jsonEncode({'type': 'terminal.input', 'data': text})}\n'),
    );
  }

  void resize(int cols, int rows) {
    _session.write(
      utf8.encode(
        '${jsonEncode({'type': 'terminal.resize', 'cols': cols, 'rows': rows})}\n',
      ),
    );
  }

  /// Devolver el control (release). Otro cliente podrá tomar takeover.
  void release() {
    _session.write(
      utf8.encode('${jsonEncode({'type': 'terminal.release'})}\n'),
    );
  }

  /// Cerrar el shell SSH del bridge. El proceso remoto sigue vivo en herdr
  /// (detach ≠ kill).
  Future<void> close() async {
    await _stdoutSub?.cancel();
    _session.close();
    await _output.close();
    await _closed.close();
  }
}

// Alias de compatibilidad de tipos.
typedef Uint8ListAdapter = List<int>;
