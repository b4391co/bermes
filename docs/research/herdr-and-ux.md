# Herdr (herdr.dev) y referencias de experiencia — auditoría de contratos

Fecha: 2026-09-25 · Fase A (auditoría de contratos) · Proyecto Hermes Pocket.

Fuentes: docs oficiales de herdr.dev (versión **Latest 0.9.1**), repositorio público
`github.com/herdrdev/herdr` (clon shallow en `/tmp/research/herdr`, commit
`21d0ce60267ad947c081d3d3fba401c859f06dd2`, 2026-09-25, `Cargo.toml` versión `0.9.1`),
docs de Moshi (getmoshi.app), TermRover (termrover.sh) y Grok Bot (docs.x.ai).
Todas las afirmaciones citan su fuente exacta. Nada inventado.

---

## 1. Qué es Herdr

"Terminal workspace manager for AI coding agents" — un multiplexer tipo tmux con
awareness de agentes de código ([https://herdr.dev/docs/](https://herdr.dev/docs/),
[https://herdr.dev/agent-guide.md](https://herdr.dev/agent-guide.md)).

Arquitectura (verificada en docs y código):

- Un **servidor background** posee las PTYs y procesos reales; los **clientes**
  se attachan para renderizarlos ([agent-guide.md, "What Herdr is"]).
- Modelo de conceptos: **Session** (namespace de servidor background; named sessions
  separadas), **Workspace** (contenedor de proyecto, "Space" en UI), **Tab** (layout
  dentro de workspace), **Pane** (terminal real, splittable right/down), **Agent**
  (proceso reconocido dentro de un pane con estados `working | blocked | done | idle
  | unknown`) ([agent-guide.md "Concept model"]).
- Desde 0.9, la UI exterior se renderiza en el **cliente**; los servidores siguen
  poseyendo sus sesiones y suministran las vistas de terminal. Un cliente puede
  federar varios servidores SSH ("Connecting the machines",
  [https://herdr.dev/blog/connecting-the-machines/](https://herdr.dev/blog/connecting-the-machines/)).

Repositorio: `https://github.com/herdrdev/herdr` (enlazado desde el header de todas
las docs). No es el código del cliente móvil (Herdr es una TUI de escritorio); el
relevamiento de apps móviles está en §6–§7.

---

## 2. Transporte del control-plane: socket local JSON-RPC

### 2.1 Transporte y rutas

- **Protocolo**: JSON delimitado por saltos de línea (NDJSON) sobre un socket local.
  Unix domain socket; en Windows, named pipe. Un request por línea:
  `{"id":"req_1","method":"ping","params":{}}` → respuesta con el mismo `id`:
  `{"id":"req_1","result":{"type":"pong"}}`. Errores:
  `{"id":"req_1","error":{"code":"not_found","message":"..."}}`
  ([https://herdr.dev/docs/socket-api/#socket-transport](https://herdr.dev/docs/socket-api/#socket-transport) y
  [#response-shapes](https://herdr.dev/docs/socket-api/#response-shapes)).
- **Rutas**: `~/.config/herdr/herdr.sock` y
  `~/.config/herdr/sessions/<name>/herdr.sock` para sesiones nombradas. Orden de
  resolución: (1) `--session <name>` CLI, (2) `HERDR_SOCKET_PATH`, (3)
  `HERDR_SESSION=<name>`, (4) socket default
  ([socket-api/#socket-paths](https://herdr.dev/docs/socket-api/#socket-paths)).
  En código: `src/server/socket_paths.rs` define el override adicional
  `HERDR_CLIENT_SOCKET_PATH` y deriva `herdr-client.sock` del socket API (hay un
  socket separado para el protocolo de cliente binario). Permisos del socket
  `0o600` (`src/server/socket_paths.rs:11`).
- **Importante para un cliente móvil**: la API de socket es **local**. No hay
  endpoint HTTP ni WS público documentado. Un cliente remoto accede vía SSH
  (ver §4) o ejecutando el CLI sobre SSH como hacen Moshi/TermRover (ver §6).

### 2.2 Esquema auto-descriptivo

```
herdr api schema            # resumen textual
herdr api schema --json     # JSON Schema completo
herdr api schema --output PATH
```
El esquema cubre "raw requests, success responses, error responses, emitted events,
and subscription events" ([socket-api/#schema](https://herdr.dev/docs/socket-api/#schema)).
Verificado en código: el binario incluye el JSON Schema empaquetado
(`src/cli/api.rs:1` → `include_str!("../../docs/next/api/herdr-api.schema.json")`,
271 KB, `"protocol": 22, "schema_version": 1`). **El esquema completo es
verificable sin instalar herdr**: está commiteado en el repo.

Del esquema empaquetado extraímos **98 métodos request** con `const` (excluyendo
nombres de eventos):

- Server: `ping` (implícito), `server.stop`, `server.reload_config`,
  `server.agent_manifests`, `server.reload_agent_manifests`, `server.live_handoff`,
  `server.ssh_agent.register`
- Session: `session.snapshot`
- Workspace: `workspace.create|list|get|focus|rename|move|move_block|close|report_metadata`
- Worktree: `worktree.list|create|open|remove`
- Tab: `tab.create|list|get|focus|rename|move|close`
- Pane: `pane.split|swap|move|zoom|layout|process_info|neighbor|edges|focus_direction|
  resize|list|current|get|rename|send_text|send_keys|send_input|read|graphics.info|
  graphics.set|graphics.clear|graphics.stream|report_agent|report_agent_session|
  report_metadata|clear_agent_authority|release_agent|close|wait_for_output|
  scroll|selection.read|copy_motion|copy_search|edit_scrollback|input.set|focus|
  link.resolve|link.activate|clear`
- Popup: `popup.close`
- Layout: `layout.export|apply|set_split_ratio`
- Agent: `agent.list|get|read|explain|send_keys|prompt|wait|rename|focus|start|
  view.set|view.clear`
- Events: `events.subscribe`, `events.wait`
- Integrations: `integration.install|list|uninstall`
- Plugins: `plugin.link|list|unlink|enable|disable|action.list|action.invoke|
  log.list|pane.open|pane.focus|pane.close`
- Otros: `notification.show`, `client.window_title.set|clear`, `command.invoke`

La tabla "Raw methods" de la doc
([socket-api/#raw-methods](https://herdr.dev/docs/socket-api/#raw-methods)) coincide;
encontramos en el esquema algunos extras no listados en la tabla de la doc
(`pane.scroll`, `pane.selection.read`, `pane.copy_motion`, `pane.copy_search`,
`pane.edit_scrollback`, `pane.link.resolve/activate`, `pane.clear`,
`pane.focus`, `server.live_handoff`, `server.ssh_agent.register`,
`integration.list`, `command.invoke`). **Discrepancia menor doc vs código**: la
tabla doc omite esos métodos; el esquema bundled es la fuente autoritativa.

### 2.3 Bootstrap: `session.snapshot`

`session.snapshot` devuelve un snapshot one-shot para clientes que mantienen su
propia cache runtime. Contiene (doc + código):

```json
// src/api/schema/session.rs — SessionSnapshot
{
  "version": "...", "protocol": 22,
  "focused_workspace_id": "...", "focused_tab_id": "...", "focused_pane_id": "...",
  "workspaces": [WorkspaceInfo], "tabs": [TabInfo],
  "panes": [PaneInfo], "layouts": [PaneLayoutSnapshot], "agents": [AgentInfo]
}
```
Patrón de arranque sin gap (doc
[socket-api/#raw-methods](https://herdr.dev/docs/socket-api/#raw-methods), "What you
can control"): abrir `events.subscribe` en otra conexión, esperar el ack, bufferizar
el stream, llamar `session.snapshot`, instalarlo, aplicar los eventos bufferizados en
orden y seguir streaming. En reconexión: `session.snapshot` de nuevo. CLI:
`herdr api snapshot` imprime la respuesta como JSON.

### 2.4 Modelo de datos (registros verificados en `src/api/schema/*.rs`)

- `WorkspaceInfo` (`src/api/schema/workspaces.rs`): `workspace_id`, `number`,
  `label`, `focused`, `pane_count`, `tab_count`, `active_tab_id`,
  `agent_status: AgentStatus`, `tokens: HashMap<String,String>` (metadata display),
  `worktree: Option<WorkspaceWorktreeInfo>` (`repo_key`, `repo_name`, `repo_root`,
  `checkout_path`, `is_linked_worktree`).
- `PaneInfo` (`src/api/schema/panes.rs:441`): `pane_id` (público, formato `w1:p1`),
  `terminal_id`, `workspace_id`, `tab_id`, `focused`, `cwd`, `foreground_cwd`,
  `restore_error`, `label`, `agent`, `title`, `terminal_title`,
  `terminal_title_stripped`, `display_agent`, `agent_status: AgentStatus`,
  `state_labels`, `tokens`, `agent_session: Option<AgentSessionInfo>`,
  `scroll: Option<PaneScrollInfo>`, `revision: u64`.
- `PaneScrollInfo`: `offset_from_bottom`, `max_offset_from_bottom`, `viewport_rows`.
  `offset_from_bottom == 0` = "at bottom" (doc socket-api).
- `AgentInfo` (`src/api/schema/agents.rs:187`): `terminal_id`, `name`, `agent`,
  `title`, `terminal_title(_stripped)`, `display_agent`, `agent_status`,
  `screen_detection_skipped`, `state_labels`, `tokens`, `agent_session`,
  `workspace_id`, `tab_id`, `pane_id`, `focused`, `launch_pending`.
- `AgentStatus` (`src/api/schema/common.rs:160`): enum `idle | working | blocked |
  done | unknown` (serde snake_case). `done` = idle y no visto aún (doc agent view).
- `AgentSessionInfo`: `{source, agent, kind, value}` — referencia de sesión nativa
  (p.ej. `{"source":"herdr:codex","agent":"codex","kind":"id","value":"..."}`),
  expuesta read-only en pane/agent get/list.
- IDs: pane `w1:p1`, tab `w1:t1`, workspace `w1`, terminal `term_abc123`.
  IDs y nombres de agent están **scoped al servidor**; dos máquinas pueden tener
  `w1:p1` duplicados ([connecting-machines, "Settings and automation"]).

### 2.5 Eventos

`events.subscribe` con suscripciones por tipo + filtros
(`{"subscriptions":[{"type":"pane.agent_status_changed","pane_id":"w1:p1",
"agent_status":"blocked"}]}`); la primera respuesta es el ack, luego se pushean
eventos. No hay replay de eventos previos al subscribe
([socket-api/#event-subscriptions](https://herdr.dev/docs/socket-api/#event-subscriptions)).

Lista de eventos verificada en `src/api/schema/events.rs` (`EventKind`,
snake_case) y doc:

- Workspace: `workspace.created`, `workspace.updated`, `workspace.metadata_updated`,
  `workspace.renamed`, `workspace.moved`, `workspace.reordered`, `workspace.closed`,
  `workspace.focused`
- Worktree: `worktree.created`, `worktree.opened`, `worktree.removed`
- Tab: `tab.created`, `tab.closed`, `tab.focused`, `tab.renamed`, `tab.moved`
- Pane: `pane.created`, `pane.updated`, `pane.closed`, `pane.focused`, `pane.moved`,
  `pane.exited`, `pane.agent_detected`, `pane.output_matched`,
  `pane.agent_status_changed`, `pane.scroll_changed`
- Layout: `layout.updated` (payload `PaneLayoutSnapshot` por tab)

Payloads clave en código (`SubscriptionEventData`): `pane.agent_status_changed`
→ `{pane_id, workspace_id, agent_status, agent?, title?, display_agent?,
state_labels?}`; `pane.scroll_changed` → `{pane_id, workspace_id, scroll}`;
`pane.output_matched` → `{pane_id, matched_line, read: PaneReadResult}`.
Nota: `workspace.metadata_updated` existe para subscribers de API pero **no**
dispara hooks de plugins (doc socket-api).

### 2.6 Lectura de panes y waits

- `pane.read` con `source`: `visible | recent | recent-unwrapped | detection`
  (`detection` = snapshot del bottom-buffer que usa la detección de agentes).
  Respuesta `PaneReadResult` (esquema): `{pane_id, workspace_id, tab_id, source,
  format, text, revision, truncated}`.
  [socket-api/#reading-panes](https://herdr.dev/docs/socket-api/#reading-panes)
- `agent.wait <target> --until done|blocked` — observan estado semántico, no
  terminación de comando. `agent.wait` es server-owned y event-driven; fija el
  ocupante del pane. `agent.prompt` acepta `wait {until, timeout_ms}` en un solo
  request; si el agente ya está `blocked` devuelve `agent_blocked` sin enviar input
  ([socket-api](https://herdr.dev/docs/socket-api/)).
- `pane.send_keys` / `pane.send_input.keys`: strings de combos
  (`enter`, `esc`, `ctrl+h`, `alt+x`, `shift+tab`, `f1`, `minus`...); no aceptan
  strings de binding `prefix+`.

### 2.7 Estado de agentes: autoridades

- Cada pane tiene **una autoridad de estado**. Integraciones con lifecycle hooks
  completos (Pi, OMP, Kimi, OpenCode/Kilo vía plugin, MastraCode) son
  autoritativas; el resto usa **screen detection**: identificación del proceso
  foreground + matcheo de manifiestos TOML contra el snapshot del bottom-buffer.
  ([agents/#status-authority](https://herdr.dev/docs/agents/#status-authority))
- **Hermes Agent** en la tabla de agentes soportados: "screen manifest",
  rol de integración "session" (provee identidad de sesión nativa para restore;
  NO es autoridad de estado). Detectado por proceso `hermes`/`hermes-agent`
  (`src/detect/mod.rs:218`). Resume tras restart: `hermes --resume <id>`,
  versión mínima de integración `2`
  ([session-state/#native-agent-session-restore](https://herdr.dev/docs/session-state/#native-agent-session-restore)).
- Manifiesto de detección de Hermes incluido en el repo:
  `src/detect/manifests/hermes.toml` (id `hermes`, version `2026.07.24.1`,
  aliases `["hermes-agent"]`), también distribuido en
  `distribution/agent-detection/hermes.toml`. Reglas por región
  `osc_title` y `bottom_non_empty_lines(14)`; ejemplos: OSC title `^⚠` → blocked,
  `^⏳` → working; `dangerous_command_approval` requiere `dangerous`/`approval`/
  `allow once, deny` **y** confirmación visible; `clarification_prompt` matchea
  "hermes needs your", `ask ...`, "type your answer". Fallback de agente conocido
  sin match: `idle` con label `default_known_agent_idle_fallback`
  ([agents/#blocked-state](https://herdr.dev/docs/agents/#blocked-state)).
- Reporting desde fuera: `pane.report_agent` (estado semántico: `state` ∈
  idle/working/blocked/done/unknown), `pane.report_agent_session` (referencia
  nativa de sesión), `pane.report_metadata` (display-only: `title`,
  `display_agent`, `state_labels`, `tokens`, `ttl_ms`, `seq`) — todo con
  `source` y guards `agent`/`applies_to_source`. Tokens: patch por clave
  (string set / null clear), TTL 1–86 400 000 ms, máx 16 tokens por report,
  32 por recurso, nombres `[A-Za-z0-9_-]{1,32}`
  ([socket-api/#agent-state-reporting](https://herdr.dev/docs/socket-api/#agent-state-reporting)).
- Estado de agente con `HERDR_AGENT=<agent>` como hint para wrappers/VMs
  ([agents/#vms-and-sandbox-wrappers](https://herdr.dev/docs/agents/#vms-and-sandbox-wrappers)).
- Variables inyectadas en procesos gestionados: `HERDR_SOCKET_PATH`,
  `HERDR_ENV=1`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID`
  (y para plugins `HERDR_BIN_PATH`, `HERDR_PLUGIN_*`) — doc socket-api y
  agent-guide ("If `HERDR_ENV=1` is set, you are already running inside a Herdr pane").

### 2.8 Proyección de vista de agentes (para sidebars móviles)

`agent.view.set` instala una proyección declarativa transitoria que controla
sidebar expandida/colapsada, lista móvil de Agents, mouse targets y navegación.
Filtro declarativo (`op: all|any|not|eq|in|exists`; campos `status`,
`workspace_id`, `tab_id`, `pane_id`, `agent`, `seen`, `state_change_seq`, más
tokens por plugin con `{"token":"name"}`; valores contexto
`current_workspace_id`/`current_tab_id`), orden estable multi-campo
(`workspace_order|tab_order|pane_order|attention|status|agent|seen|
state_change_seq|token`, `asc|desc`)
([socket-api/#agent-view-queries](https://herdr.dev/docs/socket-api/#agent-view-queries)).
Relevante: en un cliente federado, la vista del servidor seleccionado aplica a la
lista combinada; el contexto de workspace/tab incluye la máquina seleccionada.

---

## 3. Data-plane de terminales: dos protocolos

La doc distingue claramente dos planos
([socket-api/#protocol-stability](https://herdr.dev/docs/socket-api/#protocol-stability)):

1. **API JSON (control-plane)**: lo de §2, sobre el socket local, para scripts y
   agentes.
2. **Endpoint generation 1 (data-plane)**: el contrato estable que usa la UI
   client-rendered para renderizar terminales, local y SSH. "The client-rendered
   Herdr UI uses a stable endpoint generation for local and SSH servers. Client
   and server builds do not need to match. During connection setup, they agree on
   the core snapshot, screen, input, and blob codecs, and the server advertises the
   API methods and optional capabilities it supports."

En código (`src/protocol/endpoint.rs`), el handshake del endpoint es:

- `ENDPOINT_PROTOCOL_GENERATION = 1`, handshake `endpoint.hello.v1` /
  `endpoint.welcome.v1`.
- Codecs: snapshot `shell.snapshot.v1`, surface `shell.surface.v1`, input
  `shell.input.semantic.v1`, blob `shell.blob.v1`.
- `EndpointClientHello` envía `generation`, `cell_width_px`, `cell_height_px`,
  `surface_size {cols, rows}`, `pixel_mouse`, `direct_graphics`,
  `endpoint_keybindings`, `mouse_capture`, `surface_active`, y codecs aceptados
  opcionales (`surface_reuse`, `surface_delta`, listas `*_codecs`).
- `EndpointServerWelcome` responde con `generation`, `server_version`, codecs
  elegidos, `methods: Vec<String>` y `capabilities: Vec<String>`.
- Capacidades nombradas: `surface_interest`, `presentation_effects_fence`,
  `health_check` (ping/pong `endpoint.health.ping.v1`/`pong`),
  `agent_view_projection`, `agent_completions`, `surface_delta`.
- `ClientShellSnapshot` (`src/protocol/wire.rs:922`): proyección completa del shell
  del cliente — `boot_id`, `revision`, focused ids, `workspaces/tabs/panes/agents/
  commands`, tab bar segments, agent view label, worktree directory, release notes,
  update info. Es el equivalente endpoint de `session.snapshot` enriquecido con UI.
- `PaneSurfaceFrame` (`wire.rs:1274`): superficie server-rendered de la pestaña
  activa **sin sidebar, tab bar ni overlays** — `boot_id`,
  `projection_revision`, `surface_revision` (monotónica), `frame: FrameData`,
  `panes: Vec<PaneSurfacePane>`, `splits: Vec<PaneSurfaceSplit>`,
  `popup: Option<...>`, `graphics: SurfaceGraphicsScene`. Parches incrementales:
  `PaneSurfacePatch` (`base_surface_revision`, `rows: Vec<PaneSurfacePatchRow>`
  con celdas `{x, y, cells}`, metadata de panes cambiados, cursor). El codec
  opcional `surface_delta` es la codificación cell-retaining de parches
  (`src/protocol/surface_delta.rs`, capability `surface_delta`).
- Transporte binario interno (no-endpoint): length-prefixed frames u32-LE,
  `PROTOCOL_VERSION = 22`, `MAX_FRAME_SIZE` 2 MiB, `MAX_GRAPHICS_FRAME_SIZE` 32 MiB
  (`src/protocol/wire.rs`). La doc: "The numbered binary protocol remains for
  same-install and internal operations, including direct terminal attach and live
  handoff."

**Conclusión de diseño**: el data-plane de terminal no es "PTY over WebSocket" ni
SSH crudo. Es un protocolo propio de superficies de celdas (snapshots + parches
delta + semántica de input + blobs gráficos kitty) negociado por capacidades sobre
el socket/bridge, con la PTY viva en el servidor. Para Hermes Pocket esto implica
que la reproducción fiel del surface stream de Herdr requeriría implementar el
endpoint protocol (doc público, pero codecs binarios; `FrameData`/`CellData` en
`wire.rs`) — alternativa pragmática: los observadores NDJSON de §3.1.

### 3.1 Bridge NDJSON de observación/control de terminal (bridge empírico)

Para terceros que solo necesitan bytes de terminal renderizados, el CLI expone un
puente NDJSON documentado
([persistence-remote/#direct-terminal-attach](https://herdr.dev/docs/persistence-remote/#direct-terminal-attach)):

- `herdr terminal session observe w1:p1 --cols 120 --rows 40` — observer read-only:
  imprime registros NDJSON `terminal.frame` con bytes ANSI base64, y
  `terminal.closed` al cerrar el stream. Varios observers sin afectar input/resize/
  takeover.
- `herdr terminal session control w1:p1 --takeover --cols 120 --rows 40` — control
  writable: mismos frames, lee comandos NDJSON por stdin: `terminal.input` (texto o
  bytes base64), `terminal.resize`, `terminal.scroll`, `terminal.release`. Un solo
  controlador dueño de input/resize.
- Attach directo interactivo: `herdr agent attach <name|pane_id>` /
  `herdr terminal attach <terminal_id>` con `--takeover` para robar el ownership.

Este es el **contrato más simple y verificable** para un cliente móvil tipo
"screen viewer": attach sobre SSH y consumir frames ANSI NDJSON.

---

## 4. Conexión a terminales reales: SSH como transporte, no WS

- **Local**: servidor y cliente en la misma máquina, socket Unix/pipe.
- **`herdr --remote <host>` (thin client)**: el servidor remoto posee los panes y
  envía "their terminal content and session state over SSH"; el cliente local dibuja
  la UI. Setup no interactivo con `ssh-agent` para claves passphrase-protected;
  binario remoto auto-instalado en `~/.local/bin/herdr` (Linux/macOS) descargándolo
  de `https://herdr.dev/latest.json` si hace falta
  ([persistence-remote/#remote-attach-over-ssh](https://herdr.dev/docs/persistence-remote/#remote-attach-over-ssh)).
- **Saved SSH machines (federación multi-máquina, 0.9)**: `herdr machine add
  <ssh-target> --label ... --remote-session <name>`; el cliente mantiene un puente
  por máquina; cada servidor remoto conserva sus sesiones; la máquina seleccionada
  recibe input y tamaño de terminal y provee el contenido visible; **las otras
  máquinas siguen actualizando workspace info, estados de agente y notificaciones
  sin streamear sus pantallas** — eso es exactamente la capability
  `surface_interest`
  ([connecting-machines](https://herdr.dev/docs/connecting-machines/); código:
  `src/client/endpoint/activation.rs` con `surface_interest_request(...)`).
- **Mecánica del puente SSH (verificada en código)**: `src/remote/attach.rs` —
  "Remote thin-client launcher over SSH command stdio". Herdr lanza `ssh`
  (`Command::new("ssh")`, con `scp` para copiar binario) y multiplexa su protocolo
  por **stdio del comando SSH** (`SshStdioBridge::start`), creando un socket local
  hacia adelante (`local_forward_socket_path`), con control socket SSH privado
  (`SSH_CONTROL_SOCKET_NAME = "ctl"`) para reuso de conexión autenticada,
  `remote.manage_ssh_config` para config temporal con keepalives, y marcadores de
  protocolo en la salida (`herdr-remote-output-ready:1`, etc.). No hay WebSocket ni
  librería SSH embebida: `grep russh|ssh2|websocket Cargo.toml` → vacío;
  dependencia clave de transporte: `interprocess` (local sockets) + `Command::ssh`.
- **Reconexión** (doc connecting-machines "Connection problems"): retry automático
  con backoff hasta 2 minutos; una conexión debe estar sana 1 minuto para que la
  próxima interrupción tenga retry rápido; probes de actividad cuando el SSH está
  quieto (`health_check` capability) para que una conexión rota no quede "Online";
  al perder conexión el último workspace queda visible pero **atenuado** (cache,
  no estado vivo), input deshabilitado hasta pantalla fresca; máquina "Attention"
  cuando hace falta acción interactiva (host-key, auth, server update) — se
  resuelve corriendo `herdr --remote <target>` interactivo; idle cleanup cierra el
  puente tras 1 minuto sin tráfico en ambas direcciones dejando el servidor remoto
  corriendo.
- **Versionado/compat**: cliente y servidor negocian compatibilidad; no necesitan
  versión idéntica; federation requiere `surface_interest` + `health_check`; otros
  métodos faltantes deshabilitan solo sus acciones
  ([connecting-machines "Updates and saved data"]). Perfiles guardados contienen
  solo ID opaco, label, SSH target, remote session y enabled state; **no almacenan
  claves ni secretos** — autenticación queda en OpenSSH.
- **CLI remota**: `herdr --machine <label-or-id> agent list` opera contra la
  máquina guardada sin TUI abierta; IDs remotos requieren el mismo prefijo
  (`--machine`) para desambiguar de IDs locales.
- **Estado que sobrevive** ([session-state](https://herdr.dev/docs/session-state/)):
  detach → procesos viven (mejor camino); restart del server → restore de forma
  (layout, cwd, focus), pantallas recientes solo con `pane_history` experimental
  (`[experimental] pane_history = true`, `session-history.json`), conversaciones de
  agentes con restore nativo vía sesión reportada; live handoff experimental
  (`herdr update --handoff`, batches >64 panes) transfiere PTYs vivas al server
  nuevo.

---

## 5. Flujo real: control-plane vs data-plane

```
                 ┌──────────────────────────── host remoto ───────────────────────────┐
                 │  herdr server (daemon)                                             │
                 │   ├─ PTYs + agentes (claude, hermes, ...) en workspaces/tabs/panes │
                 │   ├─ socket API NDJSON (control-plane)  herdr.sock / -client.sock  │
                 │   └─ endpoint v1 (data-plane): snapshot/surface/input/blob codecs  │
                 └────────▲──────────────────────▲────────────────────────────────────┘
                          │ stdio del comando ssh│ stdio del comando ssh (bridge)
                 ┌────────┴──────────┐  ┌────────┴──────────────┐
                 │ cliente TUI local │  │ wrapper CLI (--machine)│
                 └───────────────────┘  └───────────────────────┘
```

1. **Descubrimiento**: el cliente estático conoce máquinas guardadas (perfiles
   SSH). No hay mDNS ni registro central; `herdr machine add` verifica binario y
   server remotos y arranca el server de fondo.
2. **Bootstrap**: conexión de endpoint (`endpoint.hello.v1` ↔ `welcome.v1`) →
   snapshot (`ClientShellSnapshot` / `session.snapshot`) + subscribe de eventos
   bufferizado para evitar gaps.
3. **Control-plane continuo**: eventos de ciclo de vida (workspace/tab/pane/agent)
   + estados de agente (`agent_status_changed`) + scroll + metadata → sidebar/lista
   de agentes federada. Solo la máquina seleccionada streamea superficie.
4. **Data-plane**: al seleccionar un workspace, `surface_interest` activa el stream
   de superficie de esa máquina (surface frames + delta patches + input semántico +
   gráficos kitty). El input va por `shell.input.semantic.v1` (keys semánticos),
   no por tty crudo.
5. **Interacción con un agente**: `agent.prompt` (con wait integrado),
   `agent.wait --until done|blocked`, `agent.read`, o attach directo/`terminal
   session control` para interacción TUI cruda.

---

## 6. Moshi (getmoshi.app) — patrones UX relevantes

App iOS/Android nativa (no open-source encontrada): "The mobile terminal for AI
coding agents... Native mosh, push notifications, voice input. Zero desktop
install" ([https://getmoshi.app/](https://getmoshi.app/)).

### 6.1 Arquitectura

- Conexión directa SSH/Mosh/ET del teléfono a la máquina propia; **sin session
  relay**: "There's no session relay: your shell, repositories, files, and agent
  processes stay on machines you control. You don't need a wrapper command or host
  daemon" (homepage, "moshi core"). (El daemon sí existe para hooks: `moshi-hook`,
  opcional.)
- Persistencia de sesión: el multiplexer (tmux/Zellij/Herdr) en el host; Mosh/ET
  para sobrevivir a sleep, network switch y app kill ("Mosh & ET Connections —
  Stays alive across sleep, network switches, even app kills"; "Session Recovery —
  App got killed? Reconnect and reattach without the ritual").
- `moshi-hook` (daemon opcional en host): socket Unix local para eventos de hooks
  de agentes + gateway `127.0.0.1:24543` que la app reenvía por SSH; mantiene
  WebSocket hacia el server de notificaciones de Moshi solo con **resúmenes**
  (categorías inbox: `approval_required`, `task_complete`, `session_started`,
  `tool_running`, `tool_finished`; máx 200 chars prompt, 80 chars respuesta, 256
  chars comando de approval; metadatos). Transcripciones completas, diffs y
  terminal van host→teléfono por el gateway SSH-forwarded, **nunca por el backend**
  ([https://getmoshi.app/docs/hooks](https://getmoshi.app/docs/hooks), "Data
  privacy").
- Webhook de terceros: `POST https://api.getmoshi.app/api/webhook` con
  `{token, title, message}` (docs/hooks "Third-party harnesses").

### 6.2 Integración con Herdr (verificable: la app usa el CLI, no el socket)

- "Moshi detects `herdr`, lists running sessions via **`herdr session list
  --json`**, and ships a Herdr shortcut panel pre-bound to the default `Ctrl-B`
  prefix" ([https://getmoshi.app/docs/multiplexer](https://getmoshi.app/docs/multiplexer)).
  Es decir: la integración de session-picker es **probe SSH no interactivo**
  (`command -v herdr`) + salida `--json` del CLI — `{"sessions": [...]}` (verificado
  en `src/cli.rs:459-471`: JSON `{"sessions": sessions}`). Solo se listan sesiones
  con server corriendo; el entry `default` se filtra si está parado
  ([docs/herdr "Session list is empty..."]).
- Picker: pestañas por multiplexer (Herdr/tmux/Zellij) con sesiones; tap =
  attach; **Skip** = shell de login plano ([docs/herdr "Start or attach"]).
- Reconexión: para Herdr/tmux, "Auto-attach same session after reconnect — if the
  phone kills Moshi or the connection has to start fresh, Pro remembers the tmux
  session or Herdr session and workspace behind that terminal card and attaches it
  again automatically" ([docs/multiplexer]).
- Remote approvals: tap Approve/Deny **inyecta las teclas correctas en el pane
  exacto** tras que moshi-hook recapture la pantalla y verifique que el prompt siga
  siendo el mismo; responder en el host limpia el teléfono (daemon detecta la
  desaparición del prompt) ([docs/multiplexer]).
- `moshi://herdr?workspace=<id>&session=<name>` — deep links para abrir la card
  activa de una sesión/workspace; omite sesión = `default`; nunca abre sesión nueva
  ([docs/herdr "Agent workflow"]).
- Contexto de hook: `moshi-hook` lee `$HERDR_ENV` y `$HERDR_SESSION` y reporta
  `kind=herdr` + session/workspace/tab en eventos de inbox; `moshi-hook context`
  imprime `{kind, session, pane, cwd}` leyendo `$TMUX_PANE`, `$ZELLIJ`,
  `$HERDR_ENV` ([docs/herdr](https://getmoshi.app/docs/herdr), [docs/hooks "Works
  without serve"]).
- Gestos y panels: swipe = next/prev tab; two-finger swipe = pane; two-finger
  vertical = workspace (compone `prefix+w`); pinch = zoom pane; shortcut panel
  pre-binding `Ctrl+B c/n/p/w/g/z/x/q`; prefijo configurable en Settings
  ([docs/herdr "Workspaces, tabs, panes", "Gestures"]).

### 6.3 Chat View (lista estilo mensajería + screen viewer)

- "The agent TUI, rendered as a phone-native conversation": header (agente,
  sesión de multiplexer, modelo), mensajes (Markdown, código, imágenes, thinking
  separados), **tool cards** (comandos, lecturas/ediciones de archivo, mini diffs),
  status "Working" (cerrar = envía Escape), composer con dictado e imagen.
  ([https://getmoshi.app/docs/chat-view](https://getmoshi.app/docs/chat-view))
- Filosofía clave: **"Not a protocol bridge"** — no ACP ni API del vendor; hay una
  sola sesión (la TUI viva del terminal); Chat View es otra vista del mismo
  transcript local leído por el gateway. "The terminal remains the source of
  truth". Consecuencias: las dos vistas nunca divergen, el agente conserva toda su
  config, y lo que una card no puede representar sigue en el terminal a un tap.
- Requisito duro: el agente debe correr **dentro de tmux o herdr** ("Chat View
  sends prompts back through the multiplexer, so an agent started in a plain shell
  cannot be opened as a chat").
- **Hermes Agent está en Tier A** (Chat View nativo) junto a Claude Code, Codex,
  OpenCode, Antigravity, Cursor, Kimi, Grok Build, Pi, OMP
  ([docs/chat-view "Supported agents"]; el hook de Moshi se instala en
  `~/.hermes/plugins/moshi-hooks` + entrada en `~/.hermes/config.yaml`
  [docs/hooks "What install changes"]).
- Otros surfaces agent-aware: Agents & Usages ("A live kanban of every agent's
  tasks, asks, and context budget"), Diff Viewer, File Browser, Browser Preview,
  Lock Screen/Live Activity/Apple Watch approve-from-anywhere (homepage §"moshi-hook").

---

## 7. TermRover (termrover.sh) — patrones UX

Terminal nativo SSH+Mosh para iPhone/Android "tmux-first"
([https://termrover.sh/](https://termrover.sh/)).

- **Quick row de prefix actions**: acciones comunes (zoom pane, nueva window,
  moverse entre windows) a un tap, sin tocar el prefijo Ctrl-b.
- **Scrolling táctil**: swipe para scrollear; si tmux mouse mode está off, lo
  activa sin editar `.tmux.conf`, con indicador ámbar cuando está activo.
- **Session picker** con favoritos arriba; browser-style tabs (reorder/rename/pin);
  pestañas por host y sesión.
- **Input para agentes**: tap abre teclado, composer multilínea para prompts
  largos, dictado on-device, adjuntar/anotar screenshots para el agente
  ("sending a screenshot to a coding agent should be as easy as sending one in a
  chat").
- **Herdr Agents Fleet (v1.1.0)**: "TermRover probes the saved SSH hosts you
  choose, looks for Herdr, and brings their agents together in one view. See what's
  working and who needs your input... Tap an agent to start typing in a fullscreen
  terminal over SSH or Mosh. Need the surrounding panes? Open its workspace in the
  same terminal."
  ([https://termrover.sh/blog/herdr-agent-fleet-mobile/](https://termrover.sh/blog/herdr-agent-fleet-mobile/))
  — patrón directo de "fleet view": lista federada de agentes por host → tap →
  terminal fullscreen del agente → opción de abrir el workspace completo.
- Pane-aware text selection: arrastrar para seleccionar copia solo el texto del
  pane tocado, sin agarrar la salida del vecino (v1.0.10, blog v1.0.9).
- Conectividad: SSH jump hosts (hasta 3 hops), Tailscale SSH keyless, biometric
  lock; soporta **Herdr y Zellij** como multiplexer alternativo a tmux, elegible
  por host.
- Filosofía anti-notificaciones: "TermRover deliberately stays away from agent
  notifications... The agent can wait" (contraste interesante con Moshi).

---

## 8. Grok Bot (docs.x.ai) — patrones UX de producto conversacional

Fuente: [https://docs.x.ai/grok-bot/overview](https://docs.x.ai/grok-bot/overview)
y [https://docs.x.ai/grok-bot/mobile](https://docs.x.ai/grok-bot/mobile) (leídas vía
`.md`).

- Modelo: **Bots nombrados y persistentes** con identidad, trabajo y contexto que
  compone: "AI teammates with names, jobs, and context that compounds over time".
  Cada Bot corre en una **computadora cloud persistente** (browser, filesystem,
  terminal); el trabajo continúa con la laptop cerrada.
- Interacción 100% por **mensajería**: "You work with a Bot by messaging it. Type,
  dictate, or start a voice chat." Multi-step work, actualizaciones en la
  conversación (voice memos, drafts), vuelve cuando requiere approval.
- **Bots coordinan entre sí**: paralelos, se mensajean, comparten contexto en
  group chats, se pasan ownership — "so you aren't the router between tools".
  Todos comparten una misma computadora cloud (archivos, browser sessions, logins).
- Mobile app: misma lista de Bots/conversaciones/rutinas/conectores sincronizada
  con desktop; composer con texto/dictado/voice chat/foto/archivo/menciones
  (`@otro-bot`, `@everyone`)/threads/reacciones; drafts por conversación; share
  sheet del SO hacia un chat; home screen con `+ New Bot` / `New Group Chat`,
  pin/hide conversaciones; búsqueda global sobre Messages, Bots, Group Chats,
  Files, Routines; **Review the computer** desde la conversación para ver la
  pantalla del trabajo, tomar el control para passwords/2FA/CAPTCHA y devolver el
  control al Bot; push notifications para resultados/preguntas/approvals con
  fallback a in-app attention states.
- Lección para Hermes Pocket: la metáfora "conversación con un bot que tiene una
  máquina" con toma de control manual de la pantalla es el espejo exacto de
  "agent pane + screen viewer + take over input".

---

## 9. Verificable sin instalar herdr / no verificable

### 9.1 Verificado SIN instalar herdr (evidencia directa)

| Contrato | Fuente |
|---|---|
| Transporte NDJSON sobre Unix socket/pipe + rutas + env vars | doc socket-api + `src/server/socket_paths.rs`, `src/api/server.rs` |
| JSON Schema completo de la API (protocol 22, schema_version 1) | repo `docs/next/api/herdr-api.schema.json` incluido por `src/cli/api.rs` |
| 98 métodos request + lista completa de eventos | extracción del esquema + `src/api/schema/events.rs` |
| Modelos `WorkspaceInfo`/`PaneInfo`/`AgentInfo`/`AgentStatus`/`SessionSnapshot`/tokens/scroll | `src/api/schema/*.rs` |
| Handshake endpoint v1, codecs, capacidades (`surface_interest`, `health_check`, `surface_delta`...) | `src/protocol/endpoint.rs`, `wire.rs` |
| Estructuras de superficie: `ClientShellSnapshot`, `PaneSurfaceFrame`, `PaneSurfacePatch` | `src/protocol/wire.rs` |
| Puente SSH por stdio, control socket, forwards locales | `src/remote/attach.rs` |
| Puente NDJSON de observación/control (`terminal.session observe/control`) | doc persistence-remote (sección "Direct terminal attach") |
| Manifiesto de detección de Hermes (reglas OSC title + bottom buffer) | `src/detect/manifests/hermes.toml` |
| Resume de Hermes: `hermes --resume <id>`, source `herdr:hermes` | doc session-state + `src/agent_resume.rs:179,460` |
| `session list --json` → `{"sessions":[...]}` | `src/cli.rs:459-471` |
| Comandos `machine` | `src/cli/machine.rs` |
| Resume commands de otros agentes (tabla session-state) | doc session-state |

### 9.2 NO verificable sin instalar herdr (requiere binario/ejecución)

- La salida real de `herdr api schema --json` de la versión instalada del usuario
  (puede diferir del commit; el esquema es por-binario por diseño — doc socket-api
  "The installed CLI can print the socket protocol schema bundled with that Herdr
  binary").
- Comportamiento runtime del endpoint: negociación real de codecs, framing exacto
  de `FrameData`/`CellData` en el wire binario (hay que codificar contra el código
  o correr el servidor), rendimiento de delta patches.
- Comportamiento de reconnect real (timings de backoff) y handoff.
- Sockets reales: no hay servidor público; todo es localhost/SSH propio.

### 9.3 Riesgos de contrato para Hermes Pocket

- `herdr api schema` es **por versión de binario**; un cliente Android no puede
  asumir schema_version 1 para siempre. Mitigación: leer `protocol`/`schema_version`
  del snapshot y degradar.
- La API socket es local: un cliente móvil **debe** ir por SSH (stdio bridge) o
  copiar el enfoque de Moshi/TermRover (probe CLI + attach). No existe surface HTTP
  pública.
- IDs de pane/workspace/agent no son únicos entre máquinas federadas: cualquier UI
  necesita clave compuesta `(machine_id, server_session, id)`.

---

## 10. Síntesis de patrones UX para los tres frentes de Hermes Pocket

1. **Lista de bots/conversaciones estilo mensajería**
   - Moshi: una fila viva por sesión de agente en el Inbox (`approval_required`,
     `task_complete`, ...), actualizada in-place; Chat View convierte el TUI en
     conversación con tool cards y barra de approval; "terminal remains the source
     of truth" — la vista chat lee el transcript local y no bifurca la sesión.
   - Grok Bot: lista de Bots persistentes con contexto compuesto, threads,
     reacciones, menciones entre bots, approvals embebidos en la conversación.
   - Herdr aporta el dato que alimenta la lista: estados semánticos
     `idle|working|blocked|done` + `attention` + `seen`, con rollup por
     workspace/tab y eventos push (`pane.agent_status_changed`), y la proyección
     declarativa `agent.view.set` con filtros/sorts.
2. **Terminal móvil**
   - TermRover/Moshi: prefijos como quick row/panels de una tapa; gestos mapeados
     a la jerarquía Herdr (swipe tab, 2-finger pane, vertical workspace, pinch
     zoom); composer multilínea + dictado + imágenes anotadas; Mosh/ET para
     movilidad + auto-attach a la misma sesión/workspace tras reconnect;jump directo
     ("Jump to... any tmux window or herdr tab — no cycling").
   - Reconexión: caché atenuada del último estado visible (patrón Herdr) +
     auto-reattach (Moshi Pro) + probes de salud para no mostrar "Online" muerto.
3. **Screen viewer**
   - Opciones concretas de contrato Herdr: (a) stream de superficie del endpoint v1
     (fidelidad total, coste alto); (b) `herdr terminal session observe` NDJSON
     ANSI (sencillo, read-only, multiples observers); (c) `pane.read --source
     visible|detection` + `pane.scroll_changed` para un "screen summary" barato;
     (d) `pane.graphics.*` si se quiere capa de imágenes kitty.
   - Grok Bot "Review the computer": tomar control puntual (takeover) y devolverlo
     — Herdr expone exactamente ese par observe/control con ownership único de
     input/resize.
   - Moshi remote approvals como referencia de seguridad: re-capturar la pantalla y
     verificar que el prompt sigue siendo el mismo antes de inyectar teclas.

## 11. Discrepancias y notas doc vs código encontradas

1. Tabla "Raw methods" de la doc omite varios métodos presentes en el esquema
   bundled (`pane.scroll`, `pane.selection.read`, `pane.copy_motion`,
   `pane.copy_search`, `pane.edit_scrollback`, `pane.link.resolve|activate`,
   `pane.clear`, `pane.focus`, `server.live_handoff`, `server.ssh_agent.register`,
   `integration.list`, `command.invoke`). El esquema commiteado es autoritativo.
2. `docs/next/` (fuente del esquema incluido) es el árbol de docs "next" del repo;
   la doc pública muestra 0.9.1. El esquema dice `protocol: 22`, igual que
   `PROTOCOL_VERSION` en `src/protocol/wire.rs` — consistentes.
3. La doc de Moshi llama a la config de Herdr `~/.config/herdr/config` (docs/herdr
   troubleshooting); la doc y el código de Herdr dicen `~/.config/herdr/config.toml`
   (agent-guide "Configuration"). Trivial, pero conviene usar el `.toml`.
4. Moshi afirma que el "default" entry aparece siempre en `herdr session list
   --json` y lo filtra si su server está parado; el código imprime
   `{"sessions": [...]}` sin filtrar en el CLI — el filtrado es de Moshi. Coherente.
5. El repositorio enlazado por las docs es `github.com/herdrdev/herdr`; Moshi
   menciona releases en `github.com/ogulcancelik/herdr/releases`. Verificado:
   esa URL responde HTTP 301 → `github.com/herdrdev/herdr` (mismo repo).

---

### Apéndice: referencias exactas

- Docs: https://herdr.dev/docs/ · https://herdr.dev/docs/socket-api/ ·
  https://herdr.dev/docs/connecting-machines/ · https://herdr.dev/docs/agents/ ·
  https://herdr.dev/docs/session-state/ ·
  https://herdr.dev/docs/persistence-remote/#remote-attach-over-ssh ·
  https://herdr.dev/agent-guide.md ·
  https://herdr.dev/blog/connecting-the-machines/
- Repo: https://github.com/herdrdev/herdr @ 21d0ce60267ad947c081d3d3fba401c859f06dd2
  — ficheros citados: `Cargo.toml`, `src/api/schema/{agents,common,events,panes,
  session,workspaces}.rs`, `src/server/socket_paths.rs`, `src/cli/api.rs`,
  `src/cli.rs`, `src/cli/machine.rs`,
  `src/protocol/{endpoint,wire,surface_delta}.rs`, `src/remote/attach.rs`,
  `src/client/endpoint/activation.rs`, `src/detect/mod.rs`,
  `src/detect/manifests/hermes.toml`, `src/agent_resume.rs`,
  `src/integration/registry.rs`, `docs/next/api/herdr-api.schema.json`
- Moshi: https://getmoshi.app/ · https://getmoshi.app/docs/multiplexer ·
  https://getmoshi.app/docs/herdr · https://getmoshi.app/docs/hooks ·
  https://getmoshi.app/docs/chat-view
- TermRover: https://termrover.sh/ ·
  https://termrover.sh/blog/herdr-agent-fleet-mobile/
- Grok Bot: https://docs.x.ai/grok-bot/overview · https://docs.x.ai/grok-bot/mobile
