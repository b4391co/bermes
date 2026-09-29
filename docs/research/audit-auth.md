# AuthFidelity — auditoría de autenticación/transporte

Referencia real: `/tmp/research/hermes-agent` @ `e408d36` (SPA autorizado de Hermes Desktop).
Cliente auditado: `/root/bermes` — `lib/clients/hermes/{http_client,connection_manager}.dart`,
`lib/domain/connection/connection_profile.dart`, `lib/data/secure/secure_store.dart`,
`lib/features/connections/connection_editor.dart`.

`gateway_client.dart` es propiedad de ChatFidelity: ahí sólo se listan **hallazgos**, sin editar.

## Tabla de veredictos

| área | desktop (fichero:línea) | bermes (fichero:línea) | veredicto |
|---|---|---|---|
| Sondeo de transporte | `connection-config.ts:18` + `main.ts:10615` leen `/api/status` público (`public_paths.py:15`, `web_routers/status.py:458-502`) | `http_client.dart:152-235` (`probeTransport` → `GET /api/status`) | difiere(arreglado): antes disparaba `POST /auth/password-login` con credenciales, consumiendo el anti-fuerza-bruta (`routes.py:338-339, 382-384`) y confundiendo 401/404 |
| Proveedor del login de contraseña | SPA resuelve el nombre en `GET /api/auth/providers` (`routes.py:183-192`; `native-auth-decisions.ts:183-195`) | `http_client.dart:237-281` (`authProviders`, `passwordProviderName`) | difiere(arreglado): bermes hardcodeaba `provider:"basic"` → 404 «Unknown provider» contra un gateway real (`routes.py:385-388`) |
| Body de `/auth/password-login` | `{provider,username,password,next}` (`routes.py:365-369`) | `http_client.dart:306-317` envía las 4 claves | difiere(arreglado): faltaba `next` → 422 de Pydantic |
| Señal de sesión válida | el gate sólo emite `Set-Cookie` al completar (`routes.py:411-417`, `cookies.py:90-106`); Desktop confirma minteando un ticket (`oauth-rest-request.ts:130-186`, `connection-config.ts:1119`) | `http_client.dart:319-345` (`observeCookies` + variantes) y `connection_manager.dart:313-345` (`login` → `mintWsTicket`) | difiere(arreglado): bermes daba por buena cualquier 200 y persistía `access_token:''` (sesión fantasma) |
| Variantes de nombre de cookie | `__Host-`/`__Secure-`/bare (`cookies.py:33-34, 47-51`); borrados de todas las variantes al logout (`cookies.py:109-128`) | `http_client.dart:694-757` (`CookieJarForConnection.storeFromHeaders`, `hasSession`) | difiere(arreglado): el tarro guardaba cualquier cookie, ignoraba `Max-Age=0` y buscaba sólo `hermes_session_at` pelado |
| Autenticación bearer | el gate acepta `Authorization: Bearer` en rutas privadas (`middleware.py:166-174`, `request_utils.py:25-30`) y NO lo rota server-side (`native-auth-decisions.ts:243-247`) | `http_client.dart:141-166, 573-585` (`_bearer`, `_authHeaders`) | difiere(arreglado): bermes nunca enviaba bearer pese a tener `HermesAuthKind.bearerToken` |
| Renovación de sesión | `POST /auth/native/refresh {refresh_token,provider}` → body bearer (`routes.py:491-519`, `_bearer_payload` `routes.py:110-115`); 401 `session_expired` = re-login, 503 = transitorio | `http_client.dart:347-455` (`refreshSession`/`_doRefresh`, `RefreshOutcome`) | difiere(arreglado): bermes no mandaba `provider`, tiraba el body (no devolvía los tokens rotados) y trataba 401 y 503 igual → re-login innecesario contra 503 |
| Coalescencia de la rotación | `refresh_singleflight.py` (RT de un solo uso) | `http_client.dart:347-361` (`_refreshInFlight`) | igual (espejo local) |
| Reintento ante 401 | 1 solo reintento tras rotación forzada, y sólo si la petición es replay-segura; un 403 NO rota (`oauth-rest-request.ts:157-176`, `native-auth-decisions.ts:239-256`) | `http_client.dart:586-633` (`_authorized`, `replayOn401`) | difiere(arreglado): no existía ningún re-intento ni区分 401/403 |
| Mint del ticket WS | `POST /api/auth/ws-ticket` sin body, timeout 8 s, `replayOn401: true` (`oauth-rest-request.ts:135-137`) | `http_client.dart:472-503` | difiere(arreglado): bermes usaba el timeout global de 30 s y no distinguía ticket-muerto de red-caída |
| Ticket single-use 30 s | `routes.py:458-466`, `ws_tickets.py:21,36-46` | `connection_manager.dart:313-345` (un mint por login = una conexión) | igual |
| URL WS + credencial | `${basePath}/api/ws?ticket=…` (`connection-config.ts:91-97`) | `gateway_client.dart:79-84` | igual (hallazgo, sin cambios míos) |
| Subprotocolo `hermes-gateway-ticket.<t>` / `hermes-gateway-v1` | **el SPA no lo usa**: sólo lo consume el servidor (`web_server_chat.py:202-217, 265-284`); ningún `new WebSocket(url, protocols…)` en `apps/` | `gateway_client.dart:81-84` (query) | igual: bermes va por query, que el gate acepta (`web_server_chat.py:268`) |
| Heartbeat | `gateway.ping` cada 15 s con deadline 45 s, sólo si `gateway.ready.heartbeat` (`json-rpc-channel.ts:143-144, 490-536`, `json-rpc-gateway.ts:160-186`) | `gateway_client.dart:163-166` | difiere(pendiente): bermes nunca comprueba `payload.heartbeat` y no tiene deadline de 45 s → chat con backend colgado queda «ready» (es de ChatFidelity) |
| Códigos de cierre 4401 / 4403 / 4400 | `chat_ws.py:139-151`: 4401 credencial mala, 4403 chat deshabilitado / Host-Origin / peer no-loopback; 4400 sólo en `/api/pub`+`/api/events` por canal inválido (`chat_ws.py:623-631`) | `gateway_client.dart` (ningún manejo) | difiere(pendiente): sin dueño asignado en esta capa — ver hallazgos |
| Terminación «reauth requerido» | el rechazo del mint es confirmado y **latcheable**, no rediscado (`connection-config.ts:115-138`, `main.ts:13440-13458`) | `connection_manager.dart:34-35` + `gateway_client.dart:96` (`authExpired`) | difiere(arreglado) en HTTP: `login()` confirma con el mint; en WS queda pendiente (ChatFidelity) |
| Backoff de reconexión | el `JsonRpcGatewayClient` NO rediala: `invalidate()` deja la decisión al dueño de la conexión (`json-rpc-gateway.ts:348-373`) | `gateway_client.dart:632-654` (0.5 s → 30 s, factor 1.6) | difiere(pendiente, aceptable): el backoff vive en el cliente WS en vez del gestor; sin jitter |
| Timeout de `prompt.submit` | 1 800 000 ms = techo del turno del agente (`client.ts:19-27`) | `_request` genérico con 30 s | difiere(pendiente): es de ChatFidelity |
| Persistencia de sesión | Desktop guarda tokens en su partición/llavero nativo; la app web no lee cookies HttpOnly | `secure_store.dart:20-48` (claves `session/<id>`) | igual |

## Hallazgos sobre ficheros de otros (no editados por AuthFidelity)

1. **`gateway_client.dart:92-104`** — `_setState(authExpired)` cuando `mintWsTicket()` devuelve null, pero
   `_scheduleReconnect()` no se dispara en esa rama: correcto por contrato (un 401/403 confirmado es terminal,
   `connection-config.ts:129-138`), **pero** el `catch` de `_openSocket` (`gateway_client.dart:169-171`) sí rediala
   con backoff ante un fallo de red: coincide con Desktop. Lo que falta es comprobar `heartbeat` en
   `gateway.ready` y el deadline de 45 s.
2. **`gateway_client.dart:57`** — `_ready = GatewayReady.fromPayload(payload)`: verificar que lee `replay_epoch`
   y `heartbeat` (`tui_gateway/ws.py:318-324`, `gateway-contract.generated.ts:4369-4374`).
3. **`rfb_client.dart:45-51`** — usa `?display_ticket=`, que el gateway real sí acepta en
   `/api/display/ws` (`web_routers/display.py:60-74`) y un ticket de display **no** vale como login de gateway
   (`web_server_chat.py:274-277`). Correcto tal cual.

## Cambios aplicados (diff resumido)

### `lib/clients/hermes/http_client.dart` (reescrito el capas de auth)
- `probeTransport()` → `GET /api/status` público, sin credenciales, timeout 8 s; identifica por `auth_required`/`version`.
- Nuevos `authProviders()` / `passwordProviderName()` (`GET /api/auth/providers`).
- `login(user, pass, {provider})`: body `{provider,username,password,next}` completo, `followRedirects:false`,
  3xx → fallo claro, éxito determinado por la cookie AT (`observeCookies`), 404→`version`, 429→`rateLimited`.
- Sesión bearer: `_bearer`/`_refreshToken`/`_providerHint`, `restoreSession()`, `adoptBearerSession()`,
  `forgetSession()`, `refreshToken`, `accessToken`, callback `_onSessionRotated`.
- `refreshSession(rt,{provider}) -> RefreshResult` con `RefreshOutcome{rotated,expired,providerUnavailable,rejected,transport}`,
  parseo de `_bearer_payload`, coalescencia `_refreshInFlight`.
- `_authorized()` unificado: cabeceras cookie+bearer, alimentación del tarro en cada respuesta, 1 reintento tras
  rotación sólo ante 401 (nunca 403) y sólo con `replayOn401`.
- `mintWsTicket()` re-identifica una vez y usa timeout 8 s; `getJson`/`postJson` pasan por `_authorized`;
  nuevo `authMe()`.
- `CookieJarForConnection`: respeta variantes `__Host-`/`__Secure-`, borra con `Max-Age=0`/`Expires`/valor vacío,
  `hasSession()`.
- Tipos nuevos: `NativeSession`, `RefreshResult`, `RefreshOutcome`; `_causeOf`/`_causeFrom` clasifican status.

### `lib/clients/hermes/connection_manager.dart`
- `bootstrap` conserva su firma pública (`secrets:`); el shadowing del método `login` se resuelve en `_restoreSession(..., SecureStore store)`. Guarda `_secrets` para que el login del editor pueda persistir el bearer rotado.
- Nuevo `_restoreSession()`: bearer guardado → `authMe()` → `refreshSession()` → contraseña recordada.
  503/transitorio **conserva** la sesión (no fuerza re-login); 401 `session_expired` la borra.
- Nuevo `login(runtime,{username,password,provider})`: delega en HTTP y **confirma** la sesión minteando ticket;
  persiste el bearer rotado en secure storage.
- Nuevo `connectAndSync(runtime,row)` para que el editor no replique el camino de conexión.
- `ConnectionRuntime.onSessionRotated` para persistir giros de token ocurridos a mitad de ruta.

### `lib/domain/connection/connection_profile.dart`
- `HermesAuthKind` documentado con las rutas reales; añadido `wsPath` (`basePath + /api/ws`, `chat_ws.py:595`).
- Borrado de código muerto sin ningún consumidor en el repo: `ConnectionStatus`, `ConnectionErrorCause`
  (duplicado del enum vivo `GatewayLinkState`) y `ConnectionSession`.

### `lib/data/secure/secure_store.dart`
- Quitada la extensión muerta `ConnectionSessionX.readConnectionSession` y su import.

### `lib/features/connections/connection_editor.dart`
- «Probar conexión» ya no promete credenciales válidas (texto del resultado).
- El guardado usa `connections.login(...)` (con confirmación por ticket) y `connections.connectAndSync(...)`.

## Lo que exige el fake de Main (puerto 9120, detrás del `adb forward` 9119)

El fake actual no sirve las dos rutas públicas que la app usa ahora (parche enviado a Main por hub).
**El nombre del proveedor de contraseña en el gateway real SÍ es `basic`**
(`plugins/dashboard_auth/basic/__init__.py:117` `name = "basic"`, y el Desktop lo tiene como único nombre
de contraseña conocido: `native-auth-decisions.ts:144` `PASSWORD_PROVIDER_NAMES = new Set(['basic'])`).
Lo que estaba mal en bermes no era el valor, sino **hardcodearlo sin preguntar**: un gateway con otro
proveedor instalado (portal OAuth, `nas`, …) responde 404 a `basic` (`routes.py:385-388`).

```python
PASSWORD_PROVIDER = "basic"          # plugins/dashboard_auth/basic/__init__.py:117

async def status(request):           # GET /api/status — public_paths.py:15
    return web.json_response({"ok": True, "version": "0.19.0-fake",
                              "auth_required": True})

async def auth_providers(request):   # GET /api/auth/providers — routes.py:183-192
    return web.json_response({"providers": [
        {"name": PASSWORD_PROVIDER, "display_name": "Contraseña local",
         "supports_password": True}]})
```
más `app.router.add_get("/api/status", status)` y `add_get("/api/auth/providers", auth_providers)`,
y que `password_login` valide `provider == "basic"` (routes.py:385-388 da 404 a cualquier otro nombre)
respondiendo `{"ok": true, "next": "/"}` + `Set-Cookie`.

## Verificación

- `dart analyze` sobre los 5 ficheros tocados: **No issues found!**
- `tools/fake_gateway.py` **no** se tocó (ocupado por Main con E2E por adb; ChatFidelity declaró la propiedad de
  sus cambios de auth). Consecuencia conocida: el fake sigue autenticando `/api/auth/ws-ticket` **sólo por cookie**
  (`fake_gateway.py:28-29`), así que una sesión bearer-only no pasaría el mint. El contrato real acepta bearer
  (`middleware.py:166-174`) — es un hueco del fake, no del cliente.
