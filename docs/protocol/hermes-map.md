# Mapa de contratos Hermes — guías de implementación

> Fuente: `docs/research/hermes-protocol.md` (commit `3be17b1d5ca1388c1aba6da625144b48f95d7570`).
> Este doc extrae SOLO lo accionable para el código.

## 1. Autenticación (dashboard `hermes serve` :9119)

Flujo password (el del usuario):
1. `POST /auth/password-login` `{provider, username, password, next}` → cookies `hermes_session_at` (12h) + `hermes_session_rt` (30d). El `provider` NO se hardcodea: se resuelve en `GET /api/auth/providers` (`routes.py:183-192`); `basic` es el único nombre de contraseña conocido (`plugins/dashboard_auth/basic/__init__.py:117`). Un 200 sin `Set-Cookie` NO es sesión válida — Desktop confirma minteando un ticket.
2. Middleware refresca transparente con RT; para clientes nativos usar `POST /auth/native/refresh` `{refresh_token, provider}` → `{access_token, refresh_token, expires_at, provider, user_id}`. El refresh_token es de un solo uso (rotación; ver `refresh_singleflight.py`).
3. 401 `{"error":"session_expired"}` = todos los RT rechazados → re-login.
4. Rate limit: 10/60s por IP → diferenciar 429 de credenciales malas.

WS: `POST /api/auth/ws-ticket` (con sesión) → `{ticket, ttl_seconds:30}` single-use.
Upgrade: `wss://host/api/ws?ticket=<t>` (o subprotocolo `hermes-gateway-ticket.<t>`).
Close codes: 4401 credencial inválida · 4403 guard (chat deshabilitado / Host-Origin / peer no-loopback) — `chat_ws.py:139-151`. 4400 es de `/api/pub`+`/api/events` (canal ausente), NO de `/api/ws`.

## 2. WS JSON-RPC (chat y eventos)

Frame NDJSON JSON-RPC 2.0. El servidor anuncia capacidades al conectar con un
evento `gateway.ready` (`payload` incluye `replay_epoch`); puede no ser el primer
frame y no está garantizado — la app no debe bloquear sobre él.

- Ping: `gateway.ping` → `{"result":{"ok":true}}`.
- Eventos: `{"method":"event","params":{"type","session_id","payload"}}`; seq monótono por sesión.
- Replay: si `replay_epoch` cambia → backend reinició → reset watermark.
- Errores: -32601 método desconocido · 4000 params inválidos (extra_forbid) · 4006 missing session_id.
- Declarar `client.capabilities {server_requests:true}` tras `gateway.ready` para recibir server-requests (aprobaciones).

### Métodos clave para Hermes Pocket
Registrados en `tui_gateway/` (`@method(...)`). Confirmados en la fuente real `e408d36`: `session.create` (`methods_session.py:463`), `session.list` (`:520`, filas compactas con `tip_row`/`resolved_id` — `:119`), `session.resume` (`contracts/sessions.py:174`).
- `profiles.list[].canonical_session` (verificado 2026-09-27, hermes-mobile Profile.kt `CanonicalSessionInfo`): puede venir como **objeto** `{id, resolved_id, title, preview, started_at, last_active, message_count}` (forma real del gateway) o string (versiones antiguas). Identidad del REGISTRO = `id`; `resolved_id` es la punta viva del linaje que Desktop abre — el chat se dirige a `resolved_id`, se persiste `id`. `session.resume{title}` PUEDE MENTIR: el título se resuelve por índice global sin filtro de perfil (`tui_gateway/server.py:2882`, `db.get_session_title(key)`), así que puede devolver la sesión de otro perfil — se valida siempre contra `session.list{profile,title}` + roster.
- Prompt: `prompt.submit {session_id?, text, profile?}` → `PromptSubmitResult {status: streaming|queued|steered|redirected, user_row_id?}` (fire-and-forget; el turno cierra por eventos `message.*`, no por el ACK).
- Aprobaciones: server-request `approval {session_id, request_id, command, description, choices[once|session|always|deny], …}`; responder `approval.respond {request_id, choice}`; cancelación → evento `request.cancel {id, reason}`. `approval.pending` al reconectar.
- Perfiles (bots): `profiles.list` → `ProfileRow {name, display_name, description, has_avatar, ui_meta, bot_mode_protocol, …}`; `profiles.get_asset` (avatar data-url).
- Screen: `display.status`, `display.observe {viewer_id}` → `{ticket, path:"/api/display/ws", viewer_id, status}`, `display.lease.acquire/release {viewer_id}`, `display.thumbnail` (JPEG one-shot).

### Eventos clave
`message.start` · `message.delta {text}` · `message.complete {text, status, …}` · `tool.start {tool_id, name, args, …}` · `tool.complete {tool_id, …}` · `approval` (server-request) · `request.cancel` · `session.title` · `error {message}` · `display.lease {profile_key, lease}` · `display.status`.

## 3. Historial REST (paginación)

- `GET /api/sessions/{id}/messages?limit≤500&offset&order=oldest|latest` → `{messages, pagination}`.
- `GET /api/sessions/{id}/timeline?limit≤500&after_row_id` → cursor `next_cursor`.
- `GET /api/sessions/{id}/messages/around?row_id&limit≤120` (salto a mensaje).
- `session.resume` responde snapshot con `messages` (historial real hasta el límite del gateway, `contracts/sessions.py:174`). No hay endpoint que exponga historial anterior a ese límite — la app no promete más.
- Transcripción: `TranscriptMessage {role, text?, content?, timestamp?, row_id?, …}`.

## 4. Bots

- Roster: `profiles.list`; bot con `bot_mode_protocol` y chat canónico sesión título exacto `Bot Chat`.
- Avatares: `has_avatar` + `profiles.get_asset {name, asset:"avatar"}` (data-url).
- Rutinas: cron jobs `[bot:<slug>] …` vía `cron.manage` / REST `/api/cron/jobs`.
- DM bot→bot: `message_agent` (tool, fire-and-forget) — no es una API de cliente.

## 5. Grupos (hosted rooms)

> ⚠️ **CORREGIDO (auditoría 2026-09-29, `e408d36`)**: Hermes Desktop NO usa `groups.*`
> para su UI (0 llamadores en `apps/`). Los grupos de Desktop son el espejo
> `ui_meta['hermes-bots-groups']` del perfil `default`: lectura `profiles.list`
> (`group-chat.ts:1013-1017`), escritura `profiles.configure` con CAS por
> `ui_meta_expected_revisions` (`:1174-1192`). El servidor REEMPLAZA la sección enviada
> (`methods_profiles.py:600-606`): leer-mergear-escribir o se pierden claves ajenas
> (`pinned`, `sectionId`, `screenAutoOpen`). Pocket consume ese espejo (ver
> `docs/research/audit-groups.md`). Lo que sigue describe el protocolo del driver de
> rooms del backend, por si algún gateway llegara a exponer salas nativas.

- `groups.capabilities` → `{protocol_version, driver, authority_gateway_id, methods[]}`.
- `groups.create {name, members[]}` · `groups.state {room_id}` (replay + driver_status) · `groups.send {room_id, text}` → `{event, accepted, driver_started}` · `groups.rename` · `groups.log {room_id, since_seq, limit}` → `{events[], cursor, latest_seq, has_more, authority}` · `groups.disband {room_id}` (tumba 90 días).
- Room `{room_id, name, members[], authority_gateway_id, authority_epoch, revision}`; Member `{member_id?, profile?, handle?, display_name?, target?}`.
- Eventos de room: `message.user` · `message.member` · `turn.started/settled/deferred/reassigned/cancelled/failed` · `authority.claimed/lost` · `room.created/disbanded/renamed/members_changed` · `member.unavailable`.
- **Aprobaciones en room**: server-request `approval` con `room` context, o `groups.approve {room_id, member_id, task_id, execution_generation, choice, request_id}`.
- Multi-gateway: los grupos se crean en UN gateway (autoridad); otros gateways obtienen réplicas vía `groups.replicate` (hecho por el gateway/Desktop, no por esta app). Esta app consume `groups.log` delta de la conexión autoridad (o réplica legible).
- Turnos: los dirige el driver del gateway (lease). El cliente solo envía mensajes de usuario. Doble-disparo: `groups.send` es append idempotente con `client_event_id`.

## 6. Screen

1. JSON-RPC `display.observe {viewer_id}` (sobre la conexión del bot) → `{ticket, path:"/api/display/ws", viewer_id, status}`.
2. Abrir `ws(s)://host:9119/api/display/ws?display_ticket=<ticket>` — RFB crudo en frames binarios.
3. Implementar handshake RFB: `RFB 003.008\n`, negociación de seguridad (None si el gateway permite; si no, ticket ya autentica), ClientInit, SetEncodings (Raw/CopyRect; noVNC pide más pero Raw basta), FramebufferUpdate → pintar.
4. Control: `display.lease.acquire {viewer_id, reason}` → lease `{holder:"human", epoch}`. Devolver: `display.lease.release {viewer_id}`. Si otro toma control → close 4000 "control-taken" → volver a Watch.
5. Preview barato: `display.thumbnail` (JPEG data-url, `null` si humano al control).
6. Nunca loggear tickets. Nunca abrir puertos VNC.

## 7. Terminal

- WS `/api/pty?profile=&channel=` (bridge PTY POSIX del dashboard) — terminal del host del gateway, resize y resume vía query `resume`.
- SSH propio (dartssh2) es independiente: hosts SSH ≠ gateways ≠ credenciales.
- Herdr: ver `docs/research/herdr-and-ux.md` §3.1 — bridge NDJSON `herdr terminal session observe/control` sobre SSH; control-plane `session.snapshot` + eventos para lista de agentes.

## 8. Identidad estable en la app

```
ConnectionId  = uuid local (stable across restarts)
EntityKey     = bot:<profile_name> | group:<room_id> | session:<session_id>
EntityRef     = (connection_id, EntityKey)
```

- Mismo gateway por URL distinta (LAN vs VPN) → el usuario decide; no deduplicar automático (avisar en UI si dos conexiones reportan mismo `host.identity`).
- Export/import: las conexiones se importan con `connection_id` nuevo si colisiona, pero `EntityKey` estable → sin duplicados de grupos (viven en el gateway).

## 9. Discrepancias registradas (auditoría vs fuente real `e408d36`)

Auditorías completas con evidencias `ruta:línea` en
`docs/research/audit-auth.md` (auth/transporte) y `docs/research/audit-groups.md`
(grupos/identidad/pines). Resumen de lo que este mapa decía y la fuente real
desmiente o matiza:

- **§5 Grupos: dos modelos conviven, y hay que distinguirlos.**
  (a) **Grupos de Desktop** = espejo `ui_meta['hermes-bots-groups']` del perfil
  `default` (lectura `profiles.list`, escritura `profiles.configure` con CAS por
  `ui_meta_expected_revisions`; `group-chat.ts:1013-1017,1174-1192`). El SPA de
  Desktop NO llama ningún `groups.*` para su UI. Pocket los muestra (fila
  `kind='group'` sin `groupRoomId`), con orden/pin locales, y **NO permite
  escribir** en ellos: quien dirige las salas es Desktop (`group-turns.ts`).
  (b) **Hosted rooms nativos del gateway** = JSON-RPC `groups.*` REAL
  (`methods_groups.py:19-20`, `contracts/groups_bot_relay.py`), con protocolo
  version 2, autoridad y réplica. Pocket los soporta vía `RoomsClient` cuando el
  gateway los expone (`groups.capabilities`). Lo que estaba mal era pretender
  que (a) y (b) son el mismo canal: la app ahora los trata por separado.
- **Historial WS:** no existe `messages.history` (ni `.page`) como método del
  backend `e408d36` (0 registradores en `tui_gateway/`). La app NO usa
  `session.resume` para el historial: HTTP `GET /api/sessions/{id}/messages`
  (`chat_screen.dart:_pullRemoteHistory`) y, si el gateway no lo expone, la
  línea viva del WS cubre la sesión.
- **§2 «gateway.ready como primer frame»: no garantizado** — puede no ser el
  primer frame o no llegar; la app no bloquea sobre él. No existe
  `prompt.event_subscribe` en el backend (0 coincidencias en todo el repo): los
  eventos de sesión llegan por el canal del WS de chat sin declaración previa.
- **§1/§2 credencial WS según modo del gate** (`web_server_chat.py:220-241`):
  con `auth_required=True` (gated, el caso del usuario) sólo vale `?ticket=` (o
  `?internal=`); en loopback/`--insecure` el gate IGNORA el ticket y exige el
  `?token=` legado. Pocket asume modo gated; contra un `hermes serve` local sin
  auth habría que sondear `/api/status.auth_required` y elegir credencial
  (pendiente, no aplica al caso del usuario).
- **§2 close codes:** 4401/4403 sí (`chat_ws.py:139-151`); 4400 sólo aplica a
  `/api/pub`/`/api/events`, no a `/api/ws`. Implementado (2026-09-29):
  `gateway_client.dart` trata 4401 como `authExpired` y 4403 como error
  terminal con causa en log — sin reintento en bucle.
- **§2 identidad canónica:** `session.resume{title}` puede mentir — el título se
  resuelve por índice global sin filtro de perfil
  (`tui_gateway/server.py:2882`, `db.get_session_title(key)`), puede devolver la
  sesión de OTRO perfil. La app valida siempre contra
  `session.list{profile,title}` y el roster (`canonical_session`), nunca confía
  en el resume ciego. El id del REGISTRO es `id`; `resolved_id` es la punta viva
  que Desktop abre (`canonical-chat.ts:419,580-590`).
- **§2 timeout `prompt.submit`:** Desktop usa 1 800 000 ms (techo del turno);
  la app usaba 30 s genérico. Pendiente de alineación.
- **§2 heartbeat:** el WS del backend responde `{"ok":true}` a cualquier
  `gateway.ping` (`tui_gateway/ws.py:377`); el flag `heartbeat` del
  `gateway.ready` sólo condiciona al frontend del dashboard
  (`json-rpc-channel.ts:550`) y el intervalo/deadline (15 s / 45 s) es
  convención del cliente Desktop (`json-rpc-channel.ts:143-144,490-536`).
  Pocket hace ping cada 15 s: correcto; el deadline de 45 s queda opcional.
- **§1 refresh:** `/auth/native/refresh` exige `{refresh_token, provider}` y
  rotación de RT (singleflight). Un 401 `session_expired` ≠ 503 transitorio.
- **§1 `provider`:** el nombre del proveedor de contraseña NO es fijo: se
  resuelve en `GET /api/auth/providers`; `basic` es sólo el único nombre
  conocido del plugin estándar (`plugins/dashboard_auth/basic/__init__.py:117`).
- **§4 identidad de bot:** `name` del perfil es el id canónico; la app además
  usa `botRosterKey = connectionId::name` como clave estable local
  (`data.ts:1286-1288`), porque dos perfiles `default` en gateways distintos
  son bots distintos.
- **§8 pin/orden:** el pin de Desktop es LOCAL, fuera del espejo
  (`group-pin.ts:4-8`); Pocket replica ese modelo (bandas locales preservadas
  en `localConvPrefs`, nunca escritas al gateway).
- **`profiles.configure` reemplaza la sección** (`methods_profiles.py:600-606`):
  escribir `hermes-bots` sin llevar `pinned`/`sectionId`/`screenAutoOpen` los
  BORRA. Riesgo conocido; mitigation = leer-mergear-escribir con CAS.

Lo que SÍ se mantiene igual que este mapa: flujo de login/ticket WS single-use
30 s, URL `basePath/api/ws?ticket=`, frames NDJSON JSON-RPC, taxonomía de
eventos `message.*`/`tool.*`/`approval` server-request + `request.cancel`,
`session.interrupt`, REST de historial de sesión, screen `display.observe`/
lease, terminal `/api/pty`, Herdr sobre SSH.
