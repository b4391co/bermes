# Mapa de contratos Hermes — guías de implementación

> Fuente: `docs/research/hermes-protocol.md` (commit `3be17b1d5ca1388c1aba6da625144b48f95d7570`).
> Este doc extrae SOLO lo accionable para el código.

## 1. Autenticación (dashboard `hermes serve` :9119)

Flujo password (el del usuario):
1. `POST /auth/password-login` `{provider:"basic", username, password}` → cookies `hermes_session_at` (12h) + `hermes_session_rt` (30d).
2. Middleware refresca transparente con RT; para clientes nativos usar `POST /auth/native/refresh` `{refresh_token}` → `{access_token, refresh_token, expires_at, provider, user_id}`.
3. 401 `{"error":"session_expired"}` = todos los RT rechazados → re-login.
4. Rate limit: 10/60s por IP → diferenciar 429 de credenciales malas.

WS: `POST /api/auth/ws-ticket` (con sesión) → `{ticket, ttl_seconds:30}` single-use.
Upgrade: `wss://host/api/ws?ticket=<t>` (o subprotocolo `hermes-gateway-ticket.<t>`).
Close codes: 4401 ticket inválido · 4403 guard · 4400 canal ausente.

## 2. WS JSON-RPC (chat y eventos)

Frame NDJSON JSON-RPC 2.0. Primer frame servidor→cliente:
`{"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":…,"change_events":true,"heartbeat":true,"replay_epoch":"<uuid>"}}}`

- Ping: cliente → `gateway.ping` cada 15 s → `{"result":{"ok":true}}`.
- Eventos: `{"method":"event","params":{"type","session_id","payload"}}`; seq monótono por sesión.
- Replay: `session.events.since {session_id, last_seen}` → `{events[], latest_seq, truncated, count}`. Si `replay_epoch` cambia → backend reinició → reset watermark.
- Errores: -32601 método desconocido · 4000 params inválidos (extra_forbid) · 4006 missing session_id.
- Declarar `client.capabilities {server_requests:true}` tras `gateway.ready` para recibir server-requests (aprobaciones).

### Métodos clave para Hermes Pocket
- Sesiones: `session.list`, `session.resume {session_id|title}` → snapshot, `session.create`, `session.status`, `session.events.since`, `session.interrupt` (cancelación).
- Prompt: `prompt.submit {session_id?, text, …}` → ACK `{status: streaming|queued}` (fire-and-forget, timeout 1800 s).
- Aprobaciones: server-request `approval {session_id, request_id, command, description, choices[once|session|always|deny], …}`; responder `approval.respond {request_id, choice}`; cancelación → evento `request.cancel {id, reason}`. `approval.pending` al reconectar.
- Perfiles (bots): `profiles.list` → `ProfileRow {name, display_name, description, has_avatar, ui_meta, bot_mode_protocol, …}`; `profiles.get_asset` (avatar data-url).
- Screen: `display.status`, `display.observe {viewer_id}` → `{ticket, path:"/api/display/ws", viewer_id, status}`, `display.lease.acquire/release {viewer_id}`, `display.thumbnail` (JPEG one-shot).

### Eventos clave
`message.start` · `message.delta {text}` · `message.complete {text, status, …}` · `tool.start {tool_id, name, args, …}` · `tool.complete {tool_id, …}` · `approval` (server-request) · `request.cancel` · `session.title` · `error {message}` · `display.lease {profile_key, lease}` · `display.status`.

## 3. Historial REST (paginación)

- `GET /api/sessions/{id}/messages?limit≤500&offset&order=oldest|latest` → `{messages, pagination}`.
- `GET /api/sessions/{id}/timeline?limit≤500&after_row_id` → cursor `next_cursor`.
- `GET /api/sessions/{id}/messages/around?row_id&limit≤120` (salto a mensaje).
- Transcripción: `TranscriptMessage {role, text?, content?, timestamp?, row_id?, …}`.

## 4. Bots

- Roster: `profiles.list`; bot con `bot_mode_protocol` y chat canónico sesión título exacto `Bot Chat`.
- Identidad: nombre del perfil (`name`) + `connection_id`. Dos "default" en gateways distintos = bots distintos.
- Avatares: `has_avatar` + `profiles.get_asset {name, asset:"avatar"}` (data-url).
- Rutinas: cron jobs `[bot:<slug>] …` vía `cron.manage` / REST `/api/cron/jobs`.
- DM bot→bot: `message_agent` (tool, fire-and-forget) — no es una API de cliente.

## 5. Grupos (hosted rooms)

Todo por JSON-RPC `groups.*` (protocol_version 2). Store en el gateway (`shared-state.db`).

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
