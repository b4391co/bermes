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
  SSHClient _ssh;
  String _resolvedBinary; // ruta absoluta resuelta por isAvailable()

  HerdrClient({required SSHClient ssh, String binary = 'herdr'})
    : _ssh = ssh,
      _resolvedBinary = binary;

  String get binary => _resolvedBinary;

  /// true si herdr está instalado en el host remoto.
  ///
  /// Shell NO interactiva de SSH no carga .profile/.bashrc: herdr instalado en
  /// ~/.local/bin o ~/.cargo/bin (cargo install, el camino documentado) no se
  /// encuentra con `command -v` a secas. Moshi/TermRover resuelven igual:
  /// rutas típicas + login shell. Verificado en este host: herdr vive en
  /// /root/.local/bin y `ssh host command -v herdr` NO lo ve.
  static const _pathFallback =
      '\$HOME/.local/bin:\$HOME/.cargo/bin:\$HOME/bin:/usr/local/bin:/opt/bin';

  Future<bool> isAvailable() async {
    // Candidatos: PATH extendida (no-interactiva) y, si no, login shell.
    // Comprobados con `test -x` en el REMOTO: la ruta solo vale si existe.
    // La salida de `command -v` por sí sola no basta: un .bashrc con eco
    final script =
        'for p in \$PATH:$_pathFallback; do '
        'for c in "\$p/$binary" \$(bash -lc "command -v $binary" 2>/dev/null); do '
        'test -x "\$c" && echo "\$c" && exit 0; done; done; true';
    final r = await _run(script);
    String? path;
    for (final line in r.split('\n')) {
      final l = line.trim();
      if (l.startsWith('/') && l.endsWith('/$binary')) path = l;
    }
    if (path == null) return false;
    _resolvedBinary = path;
    return true;
  }

  /// Versión (o cadena vacía si falla).
  Future<String> version() => _run('$binary --version 2>/dev/null || true');

  /// Inventario de agentes: herdr session snapshot → parse SessionSnapshot.
  /// Devuelve la lista normalizada de agentes con estado.
  Future<List<HerdrAgent>> listAgents() async {
    // OJO: `herdr api snapshot` no acepta --json (su salida ya es JSON);
    // con el flag la CLI imprime usage y el fallback pierde los paneles vivos.
    // La CLI `herdr api snapshot` espera al daemon: si no está levantado, el
    // comando CUELGA (verificado aquí: sin daemon no termina nunca). `timeout`
    // (coreutils) lo remata en el host; si no existe, el techo de _run cubre.
    final raw = await _run(
      '$binary api snapshot 2>/dev/null',
      timeout: const Duration(seconds: 12),
    );
    if (raw.trim().isEmpty) {
      // Fallback a session list --json (formato {"sessions":[...]}, cli.rs:459).
      final sessionsRaw = await _run('$binary session list --json 2>/dev/null');
      return _parseSessionsFallback(sessionsRaw);
    }
    return parseSnapshot(raw);
  }

  /// Parseo del SessionSnapshot (herdr api snapshot). Público y sin IO:
  /// testeable y reutilizable.
  static List<HerdrAgent> parseSnapshot(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      // Envoltorio RPC: {"id":..., "result":{"snapshot":{"agents":[...]}}}.
      final result = json['result'];
      final snapshot = result is Map<String, Object?>
          ? (result['snapshot'] ?? result)
          : json;
      final agents = snapshot is Map<String, Object?>
          ? snapshot['agents']
          : null;
      if (agents is! List) return const [];
      return agents
          .whereType<Map<String, Object?>>()
          .map(HerdrAgent.fromJson)
          .toList();
    } on FormatException {
      // salida no-JSON (usage de la CLI, error del daemon): sin agentes.
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
    // NOTA: sin environment: — OpenSSH con AcceptEnv por defecto rechaza la
    // petición env y la sesión muere (SSHChannelRequestError).
    // CON PTY: sin pty-req, la CLI herdr detecta stdin no-tty y cierra el
    // stream al instante ({type:"terminal.closed",reason:"detached"} —
    // verificado empíricamente contra v0.9.1). El PTY mantiene el stream vivo.
    final session = await _ssh.shell(pty: const SSHPtyConfig());
    final mode = takeover ? 'control' : 'observe';
    final flags = takeover ? '--takeover' : '';
    session.write(
      utf8.encode(
        '$binary terminal session $mode $paneId $flags --cols $cols --rows $rows\n',
      ),
    );
    return HerdrTerminalBridge._(session);
  }

  Future<String> _run(String command, {Duration? timeout}) async {
    final limit = timeout ?? const Duration(seconds: 8);
    // execute (no run()): run() no cancela el proceso remoto al expirar el
    // techo local — `herdr api snapshot` esperando un daemon inexistente
    // queda vivo en el host. Cerrar la SSHSession fuerza el cierre del canal.
    final session = await _ssh.execute(command);
    final out = <int>[];
    final sub = session.stdout.listen(out.addAll);
    session.stderr.listen(out.addAll);
    try {
      await session.done.timeout(limit);
      await sub.cancel();
      return utf8.decode(out, allowMalformed: true);
    } on TimeoutException {
      await sub.cancel();
      session.close();
      rethrow;
    }
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

  factory HerdrAgent.fromJson(Map<String, Object?> j) {
    // Snapshot REAL v0.9.1: NO hay 'name' ni 'title'. Identidad = agent +
    // pane_id; etiqueta legible = terminal_title_stripped. Se respeta 'name'
    // solo si la fuente ya lo provee (formato de sesión alternativa).
    final agent = j['agent'] as String?;
    // El stripped puede empezar con el glifo π del título de Hermes, un
    // prefijo '> ' y/o un glifo de spinner (U+2800-U+28FF). Se recortan a mano
    // (el regex de rangos \u no es fiable en el parser de dart2js/kernel).
    var stripped = ((j['terminal_title_stripped'] as String?) ?? '').trim();
    const junk = 'πϖ›·•\u00a0';
    while (stripped.isNotEmpty) {
      final c = stripped[0];
      final cp = stripped.codeUnitAt(0);
      // Solo el PREFIJO de decoración: π/ϖ/›/·/•, spinner (U+2800-28FF),
      // '>' o espacio. 'Fix bot...' conserva su F.
      final decorative =
          junk.contains(c) ||
          c == '>' ||
          c == ' ' ||
          (cp >= 0x2800 && cp <= 0x28ff);
      if (!decorative) break;
      stripped = stripped.substring(1).trim();
    }
    final name =
        (j['name'] as String?) ??
        (stripped.isNotEmpty
            ? stripped
            : agent != null && j['pane_id'] != null
            ? '$agent @ ${j['pane_id']}'
            : agent ?? 'agent');
    return HerdrAgent(
      name: name,
      status: HerdrStatusX.fromWire(j['agent_status'] as String?),
      paneId: j['pane_id'] as String?,
      workspaceId: j['workspace_id'] as String?,
      title: j['title'] as String? ?? agent,
    );
  }
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
/// Frames que llegan por stdout del comando (verificado contra herdr v0.9.1):
///   {"type":"terminal.frame","bytes":"(b64 ANSI)","seq":N,"full":bool,
///    "width":N,"height":N,"encoding":"ansi"}
///   {"type":"terminal.closed","reason":"..."}
/// Comandos que se envían por stdin (verificado empíricamente):
///   {"type":"terminal.input","text":"..."}
///   {"type":"terminal.resize","cols":N,"rows":M} / {"type":"terminal.release"}
class HerdrTerminalBridge {
  final SSHSession _session;
  final _log = Logger('HerdrTerm');

  final _output = StreamController<Uint8ListAdapter>.broadcast();
  final _closed = StreamController<void>.broadcast();
  StreamSubscription<String>? _stdoutSub;

  // El contrato del stream es binario: cada evento es una lista de bytes ANSI
  // crudos. Quien consume decide la decodificación (latin1 → code units, que
  // es lo que xterm2.write espera). Nunca utf8.decoder aquí: un multibyte
  // partido entre frames se corrompería.
  Stream<List<int>> get output => _output.stream;

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
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      final frame = decoded.cast<String, Object?>();
      switch (frame['type']) {
        case 'terminal.frame':
          // Campo real v0.9.1: bytes (b64 ANSI); "data" era el contrato supuesto.
          final data = frame['bytes'] as String?;
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
      utf8.encode('${jsonEncode({'type': 'terminal.input', 'text': text})}\n'),
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
    // Devolver el control ANTES de cerrar: si no, el pane queda tomado
    // (takeover) y Herdr Desktop no puede adjuntarse hasta que muera el shell.
    try {
      release();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } catch (_) {}
    await _stdoutSub?.cancel();
    _session.close();
    await _output.close();
    await _closed.close();
  }
}

// Alias de compatibilidad de tipos.
typedef Uint8ListAdapter = List<int>;
