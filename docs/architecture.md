# Hermes Pocket — Arquitectura

> Última actualización: 2026-09-25 · Estado: fundación + entrega C en curso

## Decisiones

| Decisión | Elección | Justificación |
|---|---|---|
| Tecnología | Flutter (stable) + Dart | Verificado viable en `docs/research/flutter-feasibility.md`. Android nativo compilado (no PWA/WebView). Windows factible con la misma base. |
| Cliente de protocolo | JSON-RPC NDJSON sobre WS `/api/ws` (protocolo `hermes-gateway-v1`) | Es el transporte real del Desktop (`apps/desktop/src/api/client.ts`, commit `3be17b1d`). |
| Auth | Login usuario/contraseña (`POST /auth/password-login`) + cookies `hermes_session_at/rt` + `POST /auth/native/refresh` | Contratos verificados en `hermes_cli/dashboard_auth/*`. |
| WS auth | Ticket single-use 30 s vía `POST /api/auth/ws-ticket`, consumido como `?ticket=` o subprotocolo `hermes-gateway-ticket.<t>` | `web_server_chat.py:220-295`. |
| Persistencia local | drift (SQLite) con migraciones versionadas | Reactividad, multiplataforma, mantenimiento activo. |
| Secretos | flutter_secure_storage (Keystore/DPAPI) | Fuera de DB, de logs y de backups. |
| Markdown | gpt_markdown | Diseñado para respuestas LLM, activo. |
| Terminal | dartssh2 (SSH/PTY) + spike de emulador (xterm2/yoxterm) | Ver §3.3 de feasibility; spike obligatorio antes de comprometer. |
| Screen | RFB (VNC) sobre WS `/api/display/ws?display_ticket=` — visor propio | **No es MJPEG**: Desktop usa noVNC; el stream es RFB crudo en frames binarios WS. Implementar decoder RFB mínimo (FramebufferUpdate → widgets). |
| Estado app | Riverpod | Compile-safe, testable, sin dependencia de widgets en la capa de datos. |

## Capas

```
lib/
  core/           utilidades transversales (fechas, logging, result types)
  domain/         modelos tipados puros (sin Flutter)
    connection/   ConnectionProfile, ConnectionState, AuthSecret
    entity/       identidad estable de bots/grupos (gateway_id + entity_key)
    message/      Message, MessageRole, ToolActivity, Approval, SendState
  clients/        clientes de protocolo puros (sin widgets)
    hermes/       gateway_client: auth, ws, rpc, eventos, replay
    herdr/        herdr_adapter: control-plane NDJSON + terminal data-plane
  data/           persistencia
    database/     drift: tablas, DAOs, migraciones
    secure/       secure_storage wrapper
    settings/     export/import versionado
  features/       UI por feature (screens + widgets + controllers)
    conversations/  lista unificada bots+grupos
    chat/           chat con streaming, markdown, adjuntos, aprobaciones
    terminal/       SSH/PTY + Herdr attach
    screen/         visor Screen (RFB over WS)
    connections/    CRUD de conexiones, diagnóstico, prueba
    settings/       ajustes, export/import, tema
  design/         sistema visual: tokens, tema claro/oscuro, avatares
```

Reglas:
- `domain` y `clients` no importan Flutter ni Riverpod (Dart puro salvo tipos de Riverpod en providers intermedios).
- Un gateway caído no bloquea el resto: cada conexión tiene su cliente y estado independientes.
- Identidad estable: `(connection_id, entity_kind, entity_key)`; nunca el nombre visible.

## Identidad y sincronización con Desktop

Ver `docs/protocol/hermes-map.md` para el mapa completo. Puntos clave:
- Bot = perfil. El chat canónico de un bot es la sesión con título EXACTO `Bot Chat` (UNIQUE(title) por perfil).
- Grupos = hosted rooms (`groups.*`, protocol_version 2, store `shared-state.db` en el gateway). Los grupos viven en el gateway, no en el cliente: cualquier cliente que hable `groups.*` ve los mismos grupos.
- Event log de rooms con `seq` monótono y cursor: sincronización delta por `groups.log {since_seq}`; idempotencia por `event_id`.
- Autoridad de turnos: fencing por `authority_epoch`; cliente solo manda `groups.send` (actor user) — nunca simula turnos de miembros.
- Aprobaciones: server-requests `approval` por sesión; responder con `approval.respond {request_id, choice}` a la MISMA conexión/sesión. En rooms: `groups.approve {member_id, task_id, execution_generation, choice, request_id}`.
- Screen: `display.observe {viewer_id}` → ticket 30 s → WS `/api/display/ws` (RFB). Lease `{holder, epoch}`: `display.lease.acquire` toma control, `display.lease.release` devuelve. Close codes: 4000 control-taken, 4001 desktop gone, 4401 ticket, 4403.

## Lo que NO está resuelto (honestidad)

- Notificaciones con app cerrada: sin FCM no hay push real. Solo foreground service + reconexión en resume. Documentado en feasibility §2.2.
- Windows: no compilado ni probado (no hay entorno Windows aquí). Pendiente explícito.
- Terminal emulator: riesgo alto de paquete; spike antes de Entrega E.
- Bot_relay cross-gateway: Desktop es el courier (`bot_relay.*`); esta app lo consume, no reemplaza ese rol.
