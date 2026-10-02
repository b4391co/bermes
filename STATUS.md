# Hermes Pocket — estado del proyecto (2026-10-02)

App Android nativa (Flutter) cliente de gateways **Hermes Agent** (Nous
Research). Versión actual: **0.1.24**. Windows: plataforma habilitada en el
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
