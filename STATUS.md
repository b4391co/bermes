# Hermes Pocket — estado del proyecto (2026-10-04)

App Android nativa (Flutter) cliente de gateways **Hermes Agent** (Nous
Research). Versión actual: **31** (esquema de número único). Windows: plataforma habilitada en el
workspace (adaptación de navegación pendiente de producto).

## Qué funciona (verificado contra gateway real + fake)

- **Conexiones múltiples**: alta URL+usuario/contraseña (login por cookie con
  sesión renovada y ticket WS), prueba de conexión que valida el transporte
  real (`/api/status` + handshake WS + roster), diagnóstico区分 red/auth/versión,
  aislado por conexión. Opción explícita y avisada de TLS inseguro por host
  (`network_security_config.xml`), sin desactivar validación global.
- **Identidad real**: bots = perfiles del gateway. Dos "default" de gateways
  distintos son dos entidades distintas (`connectionId + perfil`). Iconos desde
  `ui_meta['hermes-bots']` + `profiles.get_asset`.
- **Grupos**: dos mundos reales del backend, ambos soportados:
  - *hosted* (`groups.list/create/update/delete`, `groups.log`, `groups.post_message`
    con `client_event_id` idempotente): lectura + escritura + eventos `room.event`.
  - *Desktop* (agrupación `ui_meta.groups` sobre los perfiles): se listan y se
    abren sus bots miembros; el envío a la "sala" inventada está bloqueado a
    propósito porque no existe tal sesión.
  - Miembros inaccesibles se muestran como tales; los cambios compatibles
    aparecen en Desktop (rev CAS `ui_meta_revisions`, sin borrar campos ajenos:
    merge aditivo, `null` != borrar).
- **Chats**: streaming por WS (`prompt.submit/accept/status/cancel`),
  historial paginado (`GET /api/sessions/{id}/messages`), markdown+código,
  adjuntos de imagen, aprobaciones accionables (`server-request` approval con
  choices reales), cancelación, borrador persistente, estado de envío inequívoco,
  reconciliación en lugar de reenvío ciego tras desconexión.
  Chat canónico "Bot Chat" resuelto con la cadena exacta de Desktop
  (lookup por título → roster `canonical_session` → crear → adopt-before-mint).
- **Terminal**: SSH real (dartssh2) con PTY interactive, verificación de
  huella (TOFU), terminal xtermjs embebida vía WebView del gateway local,
  barra táctil, multi-sesión, pestañas, recuperación con reconexión.
- **Herdr**: adaptador sobre la API socket documentada (hosts, workspaces,
  agentes, paneles, atención) + puente WS→SSH a paneles reales.
- **Screen**: visor noVNC integrado (RFB sobre `/api/display/ws` con ticket),
  iniciar/parar, tomar/devolver el control (lease).
- **Ajustes**: export/import JSON (config + secretos opcional), diagnóstico
  completo, reinicio seguro de la base.

## Verificación 0.1.27 en emulador (2026-10-03)

- **Grupo mixto multi-gateway E2E**: dos fakes (9120 rol A / 9121 rol B),
  sala `room-3` «Conjunta» publicada por ambos espejos. La fila muestra
  «2 miembros · FakeA» (default de A + botb de B), dueña A, y el chat abre
  `groups.state`/`groups.log` por el WS de la dueña.
- **Lección**: `adb install -r` con salida silenciada escondía un fallo de
  firma (debug vs distribución); varios E2E anteriores corrieron binario
  viejo. Verificar `lastUpdateTime` tras cada install.

## Verificación 0.1.26 en emulador (2026-10-03)

- **Editor de ficha**: guardar forma/color/descripción cierra el sheet con
  CAS correcto (bug del gate tri-state corregido) y reenvía `groups` → el
  perfil del gateway conserva «Grupos: Equipo» (antes se borraba en cada
  guardado). Verificado contra el fake con inspección del RPC
  `profiles.configure` y del roster posterior.
- La forma `pill` sobre lienzo cuadrado se renderiza como cápsula ≈ círculo:
  NO es un fallo de render, es geometría (radio h/2). Verificado en
  `bot_face.dart:228-230`.

## Verificación de release en emulador (2026-10-02, corregida)

Emulador Android 15 x86_64 con GPU por software (swANGLE) — el host no tiene
GPU utilizable. Con el fake gateway del repo (`tools/fake_gateway.py`) en el
host y `adb forward tcp:9120 tcp:9120`:

- Arranque, bootstrap, login, sync de bots y grupos: OK.
- **El frame-freeze al abrir un chat estaba mal atribuido**: NO era swANGLE.
  La causa real era un `Leader/Follower` mal ordenado en el menú de menciones
  (ver CHANGELOG 0.1.24): la aserción de paint-order de `FollowerLayer`
  lanzaba un error por frame y el reporte estructurado de Flutter se
  retroalimentaba → bucle de UI al 100 % de CPU y raster colgado. Con el
  menú movido a un `OverlayEntry`, la traza de CPU vuelve a ~0 jiffies/s en
  reposo y los frames fluyen (20–25 frames en 5 s de actividad de typing).
  La hipótesis swANGLE queda descartada para este síntoma concreto.
- E2E tras el arreglo: abrir bot 1:1, escribir y enviar → respuesta del bot
  renderizada; abrir grupo hosted, `@` abre overlay con miembros reales
  (`@default`, `@researcher`), selección reemplaza el token, envío → eco del
  bot con la mención; back/entrada repetida sin bloqueos; 0 errores de
  framework en logcat.

## Verificación 0.1.28 en emulador (2026-10-04)

Escenario del reporte (dos gateways con bot homónimo `default` y grupo
«comun» declarado sólo por membresía, sin espejo) reproducido con
`fake_gateway.py` en modo `nomirror=1` (puertos 9120/9121):

- La fila del grupo legacy «Bot Claudio, Bot Boneca» aparece en «Grupos» con
  subtítulo «2 miembros · FakeA»; los bots muestran «Grupos: comun».
- Abrir la fila abre el chat por el WS de la dueña (`groups.state`/
  `groups.log` con `room_id=comun` sólo en la dueña, no en el segundo
  gateway).
- Enviar «hola» → `groups.send {room_id: comun}` a la dueña; con el fake
  rechazando (room desconocida) queda fila «Reintentar» (sin reenvío
  automático); aceptando el envío, el mensaje y el eco del bot se renderizan
  con autoría resuelta.

## Verificación 0.1.29 contra gateway REAL (2026-10-04)

Gateway real «claudio» 0.21.5 (LAN del usuario, vía socat + adb reverse):

- Login cookie (proveedor `basic`), roster WS con handshake `gateway.ready`,
  espejo real con Casa/Oficina (con roomId) y «Dual» (clave `name:Dual`,
  sin roomId, log incrustado).
- «Dual» persiste tras dos ciclos de sync (0.1.28 lo borraba como fila
  legacy) y el chat muestra su historia real: mensajes «Tú» y respuestas
  «default · Claudio» / «default · Boneca» con fuente etiquetada.
- Las salas `name:` no están hospedadas (groups.state/log → 4112/4114): el
  historial se sirve del log incrustado del espejo, igual que Desktop.

## Pendiente / roadmap honesto

- **swANGLE sin GPU**: este síntoma ya no aplica, pero el compositor por
  software sigue siendo lento en emulador; queda medir fluidez en gama baja
  real.
- **Mosh**: no implementado (etiqueta honesta: sólo SSH). Ampliación futura.
- **Windows**: compilación de release verificada (`flutter build windows`
  OK en CI local); navegación por teclado/ratón y paridad de gestos sin
  pulir.
- **Screen**: cobertura de casos raros (handshake RFB con encodings
  exóticos de servidores VNC reales del bot) sólo probada contra el fake.
- Notificaciones push: no hay (el backend Hermes no expone push propio; la
  app mantiene sesiones vivas en primer plano).
