## Esquema de versionado (cambio, 2026-10-04)

A partir de la próxima entrega, versión ÚNICA creciente: **31, 32, 33…**
(versionName y versionCode iguales). Se abandona el esquema doble
`0.1.29+30` que leía como dos releases en uno.

## Release 0.1.29 (2026-10-04)

### fix(groups): salas del espejo sin `roomId` (clave `name:`) — 0.1.29

- **Síntoma real (gateway claudio 0.21.5)**: el grupo «Dual» publicado por
  Desktop en el espejo bajo la clave `name:Dual` (Desktop aún no le asignó
  `roomId`) aparecía un instante y desaparecía: el limpiador de filas legacy
  (0.1.25) lo borraba en cada ciclo como «superseded», porque una sala sin
  `roomId` se persiste igual que una fila legacy (groupRoomId NULL).
- **Fix 1**: `_writeRoom` marca las salas del espejo con su `groupSyncRevision`
  (> 0) y el limpiador legacy ya no toca filas con revisión — sólo borra filas
  legacy de membresía puras. Verificado en dos ciclos contra el espejo real.
- **Fix 2**: el gateway real NO hospeda las salas `name:` (`groups.state/log`
  → 4112/4114): su historial vive INCORPORADO en el propio espejo
  (`rooms[k].log`, como Desktop). `GroupRoom.embeddedLog` lo parsea y
  `syncGroupMirrors` lo persiste como timeline (`roomlog-<id>` estable, no
  duplica en re-sync). El chat no pide `groups.log` para esas salas.
- **E2E contra el gateway real**: «Dual» visible en Grupos («2 miembros ·
  claudio») y el chat muestra la historia real multi-gateway con autoría
  («default · Claudio», «default · Boneca», mensajes del usuario «Tú»).
- Descubierto de paso: `profiles.list` en gateway 0.21.5 exige handshake
  `gateway.ready` antes de responder (sin él devuelve lista vacía) — el
  cliente ya lo hacía bien; documentado en hermes-map.
- fake_gateway: bloque de rol B restaurado (regresión introducida al editar el
  modo `nomirror`); test nuevo `group_name_room_test` con espejo real
  anonimizado. Suite: 65 verdes.

## Release 0.1.28 (2026-10-04)

### fix(groups): canal legacy de membresía sin espejo — 0.1.28

- **Síntoma**: grupo compartido entre dos gateways (bots con el mismo nombre
  de perfil, p. ej. `default` en «claudio» y «boneca») que declara
  `ui_meta.hermes-bots.groups: ['comun']` no aparecía como conversación si
  NINGÚN gateway publica el espejo `hermes-bots-groups` (Desktop antiguo o
  grupo sin `roomId`).
- **Causa**: el canal legacy (membresía del bot) nunca materializaba filas;
  sólo pintaba «Grupos: X» en el subtítulo del bot. Con espejo, la sala la
  materializa `_writeRoom` (0.1.27); sin espejo, no había NINGUNA fila.
- **Fix**: `syncGroupMirrors` materializa UNA fila legacy por nombre no
  cubierto por el espejo: dueña = primera conexión (orden del usuario) con
  bot miembro; subtítulo con los bots de TODAS las conexiones (identidad por
  par (conexión, perfil), homónimos desambiguados «Bot (conn)»); título de
  cada bot resuelto con los títulos de SU conexión; sin `groupRoomId` (fila
  por nombre) — el purge de huérfanas no la toca y respeta ocultamiento
  local (`kind group-hidden`).
- Envío al grupo legacy va por el WS de la dueña con `room_id = nombre`
  (verificado E2E: `groups.state`/`groups.log`/`groups.send` contra el fake
  en modo `nomirror`); error de envío → fila «Reintentar», nunca reenvío
  automático.
- Test nuevo: membresía multi-gateway sin espejo materializa una fila
  (título «Bot Claudio, Bot Boneca», subtítulo «2 miembros», roomId null).
  Suite: 64 verdes.
- fake_gateway: modo `nomirror=1` reproduce el escenario exacto del reporte.

# Release 0.1.27 (2026-10-03)

## Corregido
- **Los grupos con bots de VARIOS gateways se veían como mono-gateway**:
  dos capas del mismo defecto, verificadas E2E con dos gateways (fake en
  9120/9121, sala `room-3` «Conjunta» publicada por ambos espejos):
  1. La fila sólo llevaba los miembros resueltos por la conexión DUEÑA:
     el subtítulo decía «1 miembro · <dueña>» aunque el otro gateway
     aportara el suyo — el usuario lo leía como «el grupo mixto no
     aparece». La fila ahora agrega los miembros de TODAS las conexiones
     que los resuelven, en orden del usuario.
  2. Un miembro homónimo (`default` en los dos gateways) se resolvía en
     TODAS las conexiones (contando miembros de más) o secuestrado por el
     conjunto global de perfiles. Ahora cada miembro del espejo se asigna
     a UNA conexión: primero por `installId` del backend (contrato real de
     Desktop, `types.ts:130-147`, llega en el miembro del espejo), y si el
     espejo no lo trae, por nombre contra el roster de cada conexión en
     orden del usuario.
  3. El snapshot de roster sólo incluía el perfil portador del espejo
     (`default`): los demás bots del gateway no participaban en la
     resolución de miembros de grupos mixtos. Ahora el snapshot lleva el
     roster completo.
  Test nuevo: payloads reales de dos gateways → «2 miembros» (probe con
  drift en memoria); el de espejo COMPLETO ahora fija el subtítulo.

## Nota de verificación
- Las instalaciones `-r` silenciadas con `>/dev/null` ocultaban un fallo
  de firma (debug vs distribución): el E2E del emulador había estado
  corriendo un binario viejo. Ahora se verifica `lastUpdateTime`/hash tras
  cada install.

# Release 0.1.26 (2026-10-03)

## Corregido
- **Grupos con bots de varios gateways seguían sin aparecer (caso real)**:
  dos vías por las que un gateway dejaba de aportar su espejo al merge, que
  el fake con un solo gateway no reproducía:
  1. El `continue` por bot oculto (`hidden`) saltaba el parse del espejo
     `hermes-bots-groups` del perfil `default`: ocultar el BOT `default`
     despublicaba el REGISTRO de grupos de la Desktop entero (el espejo se
     lee antes del filtro ahora — ocultar un bot no toca los grupos).
  2. El roster se publicaba al final de `syncBots` (todo-o-nada): cualquier
     error al escribir un bot excluía al gateway del merge y, si el otro
     tampoco llevaba la sala, desaparecía. Se publica en cuanto el espejo
     está parseado.
  Tests nuevos: espejo COMPLETO en ambos gateways (caso Desktop real) y
  sala superviviente con `default` oculto. Fake gateway: modo
  `?hidden_default=1` que oculta el bot conservando el espejo; E2E verificado.
- **El editor de ficha no cerraba al guardar (iconos «mal guardados»)**:
  el gate de `_save` exigía `imageOk` SIEMPRE, pero `imageOk` sólo se
  evalúa tocando la imagen → un guardado de forma/color/nombre con CAS
  correcto caía siempre al aviso de fallo aunque el gateway lo hubiera
  aplicado. Meta-only cierra con `ok`; con imagen, exige ambos canales.
- **Cada guardado borraba la pertenencia del bot a grupos**: el editor no
  reenviaba `groups` y `toUiMetaSection` interpreta vacío como «quitar»
  (contrato de reemplazo de la sección, `methods_profiles.py:600-606`) →
  Desktop perdía al miembro. Ahora el editor reenvía las `groups` leídas.
  Test nuevo del contrato de reemplazo en `bot_avatar_meta_test.dart`.
  E2E en emulador: guardado cierra el sheet, CAS ok y el subtítulo
  conserva «Grupos: Equipo».

## Avatares e iconos (equivalente a Hermes Desktop)
- **Caras procedurales (blobatar) y formas de Desktop**: el editor y las
  listas renderizan el catálogo REAL de Desktop (`AVATAR_PICKER_SHAPES`:
  circle, blob, squircle, pill, triangle, hexagon, cloud, drop —
  `avatar.tsx:27`) más `blobatar` (cara derivada del nombre, siluetas
  `BLOB_KINDS`), con hash idéntico al de Desktop (`hash*31+code`, uint32) y
  hue determinista por nombre (`profile-color.ts`) — el mismo bot se ve con
  la misma cara y color que en Desktop.
- **Paleta del editor**: las 12 muestras de Desktop (`PROFILE_SWATCHES`,
  `hsl(i*30, 68%, 58%)`) + «sin color» (hue del nombre, «Match the name»).
  Los colores hex legacy siguen funcionando.
- Los iconos Material se mantienen como opción; la cara/forma tiene
  prioridad visual cuando el meta la define, igual que Desktop.

## APK de distribución
- `hermes-pocket-android-universal.apk` (~81 MB) — universal (todas las
  ABIs). Firma de distribución (`CN=Hermes Pocket, O=Bermes`),
  `versionName 0.1.26` / `versionCode 27`.

# Release 0.1.25 (2026-10-02)
## APK de distribución
- `hermes-pocket-android-universal.apk` (~81 MB) — universal (todas las
  ABIs), como en 0.1.24. Firma de distribución (`CN=Hermes Pocket,
  O=Bermes`), `versionName 0.1.25` / `versionCode 26`.

## Corregido
- **Grupos mixtos no listados / chat vacío**: la dueña de una sala se elegía
  como «primera conexión con miembros»; en una sala con bots de varios
  gateways la fila acababa en un gateway que NO hostea la sala y su
  `groups.log` respondía vacío. Ahora la dueña es la conexión cuyo espejo
  `hermes-bots-groups` del perfil `default` lleva la sala (host real del
  log); sin host conocido cae a la primera con miembros. Test unitario de
  colocación mixta (`test/group_sync_owner_test.dart`).
- **Salas ausentes al añadir/reanudar conexiones**: `connectAndSync` (guardar
  en el editor) y `bootstrap` (arrancada) aplicaban `syncBots` pero no el
  merge de espejos; las salas de la segunda gateway no aparecían hasta una
  reconexión. Ambos caminos llaman ahora a `_syncGroupMirrors`.
- **Composer deshabilitado sin señal visual tras «Reintentar»**: el gating del
  botón seguía la señal del `TextField`, que no emite `onChanged` al escribir
  el IME mientras el campo está deshabilitado. El composer pasa a
  `ValueListenableBuilder` sobre el controller: el alta se recupera al
  instante en cuanto hay texto.
- **Etiquetas del visor Screen**: el cierre del túnel VNC del fake (y
  cualquier cierre sin `reason`) se presentaba como «Desconectado
  (undefined)/(null)» y tapaba el código. `closeText` ahora ignora
  `reason` vacío, distingue undefined/null, y el puente Dart prioriza
  `reason` sólo cuando aporta texto.
- **Lease del visor al ocultar el panel**: `dispose` del `ScreenView` pedía
  `disconnectScreen()` en el JS del visor antes de tirar el servidor local;
  antes la RFB quedaba abierta y el lease de observación podía bloquear el
  takeover del control hasta expirar.

## Documentado
- **Lease humano real (comportamiento verificado, no inventado)**: al tomar
  control, el gateway corta el túnel VNC del observador con close 4000 +
  `control-taken` (web_routers/display.py:74-105); el visor lo traduce por
  su cuenta («Otro cliente tomó el control») y reconecta en view-only. El
  backend puede tener un cliente conectado — la política `shared: true` del
  visor lo permite — y el takeover humano es una capa de lease aparte:
  Android y Desktop pueden tener cada uno su conexión; no existe exclusión
  ni entrega «exactamente una vez» a nivel de VNC y la app no la promete.
- **Ficha del bot (editor de meta)**: el editor aborta el guardado cuando el
  `profiles.configure` devuelve `ui_meta: false`. Antes el fallo se tragaba
  tras `ok()` silencioso y la ficha guardaba sin meta aplicada.
- **Adjuntos**: el botón «Nota de voz» oculto y deshabilitado en grupos, con
  tooltip que explica el motivo; la transcripción no está soportada en salas.

## E2E verificado (emulador Android, fake gateway)
- Grupo mixto «Mezcla» listado y con conversación real: `dos-gateways` → eco.
- Envío 1-a-1 por canonical session (`bottest`), reintento tras caída del
  gateway, recuperación del borrador al reabrir.
- Ciclo completo del visor Screen: Iniciar → en vivo → Tomar control →
  ocultar → reabrir → «en vivo» con reconexión.

# Release 0.1.24 (2026-10-01)

## Nuevo
- **Nota de voz**: micrófono → m4a local → `POST /api/audio/transcribe` →
  texto editable antes de enviar. La app NUNCA promete oír audio: el backend
  no lo persiste; sólo el texto entra al chat (contrato verificado).
- **Imágenes en bot 1-a-1**: botón clip → `image.attach_bytes` (WS, runtime
  id) → `prompt.submit`; miniatura en burbuja con fallback a bytes locales
  si `/api/media` no responde. Límite propio anunciado: 8 MB. Oculto en
  grupos (motivo en tooltip).

## Corregido
- **Congelación al abrir un chat (Android)**: el `CompositedTransformFollower`
  del menú de menciones se montaba ANTES de su `CompositedTransformTarget`
  (el composer); la aserción de paint-order de FollowerLayer lanzaba un error
  por frame y el reporte estructurado de Flutter se autoalimentaba → UI loop
  al 100 % de CPU con el hilo raster colgado (pantalla congelada, sin frames).
  El menú ahora vive en un `OverlayEntry` (root overlay) creado después del
  composer: se pinta encima sin ocupar layout y sin violar la aserción.
  Efecto secundario eliminado: el bloque in-line del follower ensanchaba el
  Column del composer y deshabilitaba el botón Enviar sin señal visual.
- Errores de framework en debug se vuelcan crudos vía `FlutterError.onError`
  (log legible, sin bucle de inspección de widgets).

## Corregido (continuación)
- **Credencial en el borde**: un bearer viejo de otra sesión ya no reaparece
  tras un 401 — `restartSession()` limpia cookies Y bearer (el reintento
  con contraseña era saboteado por la sesión nativa anterior).
- Transcripción: `transcript` vacío (silencio) ya no pasa por ok.

## Docs / contratos
- `docs/research/adjuntos-y-notas-de-voz.md`: cuerpo de `/api/audio/transcribe`
  corregido contra la fuente real `main @ 5f23cac` (`{data_url}` con prefijo,
  NO `{data, mime_type}`); sin STT → 400 (no 503); tope real 25 MB → 413;
  `transcript: ""` por silencio.
- `docs/protocol/hermes-map.md` §6b: audio/adjuntos accionables.
- Fake gateway: `transcribe`, `image.attach_bytes`, `file.attach`,
  `GET /api/media` (binario + JSON `data_url`), modos `?stt=off` /
  `?no_media=1`; contrato de error del 413 documentado en el propio fake.

## Infra
- `record` pinchado en `^6.2.1`: con 5.x el federado `record_linux 0.7.2` no
  compila contra `record_platform_interface` y el build dart rechaza TODO
  los federados (también linux en un build android).


# Release 0.1.15 (2026-09-29)
Fase de fidelidad con Hermes Desktop cerrada (auditoría contra el backend
real `e408d36`): transporte, bots, grupos y aprobaciones comportan como
Desktop, verificado E2E en emulador.

## APKs por arquitectura
- `app-arm64-v8a-release.apk` — móviles modernos (recomendado).
- `app-armeabi-v7a-release.apk` — móviles antiguos 32 bits.
- `app-x86_64-release.apk` — emulador Android x86_64.
- `app-release.apk` — universal (todas las ABIs).

Todos firmados con la clave de distribución (`CN=Hermes Pocket, O=Bermes`).

## Cambios
- **Transporte**: `prompt.submit` con timeout de 30 min (techo de turno de
  Desktop); burbuja optimista sellada por eventos aunque el gateway ACKee
  tarde. Heartbeat con deadline: 45 s sin respuesta a los pings fuerzan
  reconexión (un socket half-open dejaba el canal mudo para siempre); las
  peticiones en vuelo fallan al desconectar en vez de colgar.
- **Bots**: guardado del editor con CAS (`ui_meta_expected_revisions`) — si
  Desktop tocó la ficha desde que se abrió, el gateway rechaza y Pocket avisa
  en vez de pisar el cambio. Se preservan las claves que Pocket no edita
  (`pinned`, `sectionId`, `sectionName`, `screenAutoOpen`, `created`), que el
  gateway reemplaza por sección entera. La descripción base se lee del
  gateway; el subtítulo compuesto ya no duplica "· Grupos: …".
- **Chat**: renombrar la sesión desde Desktop actualiza el título en vivo
  (`session.title`).
- **Aprobaciones**: nuevas tarjetas accionables con las `choices` exactas del
  gateway (una vez/sesión/siempre/denegar); la respuesta viaja por el frame
  de resultado del server-request. `request.cancel` retira la tarjeta
  (acepta las dos formas del backend).
- **UI**: los 4 bottom sheets ganan `SafeArea` inferior — el botón Guardar
  ya no queda bajo la gesture-bar del sistema.

## Known limitations
- El CAS cubre la sección `hermes-bots`; el espejo de grupos
  (`hermes-bots-groups`) sigue siendo propiedad de Desktop.
- Turnos de grupo dirigidos por Desktop (sin cambio).

# Release 0.1.14 (2026-09-28)
Alineación con Hermes Desktop (historial compartido) + correcciones de flota y UI.

## APKs por arquitectura
- `app-arm64-v8a-release.apk` (~31 MB) — móviles modernos (recomendado).
- `app-armeabi-v7a-release.apk` (~29 MB) — móviles antiguos 32 bits.
- `app-x86_64-release.apk` (~33 MB) — emulador Android x86_64.
- `app-release.apk` (~79 MB) — universal (todas las ABIs), por si necesitas una sola build.

Todos firmados con la clave de distribución (`CN=Hermes Pocket, O=Bermes`).

## Cambios
- **Sesión canónica compartida**: el móvil se une a la sesión "Bot Chat" del
  gateway vía `session.resume{title}`; nunca crea sesiones paralelas. Abre un
  bot una vez en Desktop y móvil y Desktop comparten historial en tiempo real.
- **Historial del Desktop visible**: al abrir un chat se arrastra
  `session.history` y se reconcilia sin duplicar lo enviado localmente.
- **Grupos de Desktop**: aparecen listados en la misma lista unificada
  (p. ej. "Equipo · Grupo de Casa") sin duplicarse. El envío a grupos queda
  bloqueado con aviso honesto: los dirige Desktop.
- **Flota Herdr**: el binario se resuelve solo por rutas absolutas válidas;
  un `.bashrc` con banner ya no deja la flota vacía.
- **Terminal**: sin título duplicado en la lista de hosts.
- Bot sin sesión canónica todavía → se marca "requiere sesión en Desktop"
  en vez de inventar una conversación paralela.

## Known limitations
- Grupos: lectura/escritura de turnos de grupo no está soportada (el backend
  no expone endpoint de room en 0.18; solo Desktop los dirige).
- La sesión canónica la crea Desktop; el móvil no puede fabricarla (requisito
  de no-duplicación).
- Herdr: depende de que el host tenga el binario instalado y accesible por
  SSH no interactivo.

# Release 0.1.16 (2026-09-29)

## Diagnóstico de grupos y bots
- Nuevo botón «Diagnóstico de grupos y bots» en el editor de conexión.
  Muestra contra el gateway real: fuente del roster (`profiles.list` por WS
  o REST), nº de perfiles, si `default` está presente, si el espejo de
  grupos de Desktop está publicado (nº de salas y borrados), si hay sesión
  canónica y si el bot trae meta (título/avatar).
- Usa el runtime vivo de la conexión (sesión y WS ya establecidos); el
  cliente efímero solo cubre el alta, y espera `gateway.ready` antes de
  consultar.

## Notas
- La renderización de la terminal SSH se verificó en emulador (mono, UTF-8,
  prompt); si tu caso concreto sigue "viéndose mal", necesito una captura.

# Release 0.1.17 (2026-09-29)

## Inicio de sesión por session token
- Nuevo método «Token» en el editor de conexión, junto a «Usuario»:
  pega el session token del gateway (el valor de
  `HERMES_DASHBOARD_SESSION_TOKEN` en el `.env` del gateway; el mismo que
  acepta Hermes Desktop en «Paste session token»).
- Válido para gateways en modo loopback (sin portal OAuth). REST usa el
  header `X-Hermes-Session-Token` (y `Bearer` como compatibilidad) y el
  WebSocket `?token=` — el mismo contrato que Desktop.
- El token se guarda en el almacenamiento seguro del dispositivo, nunca
  en la base de datos.
- El método por usuario y contraseña queda exactamente como estaba.

## Corrección
- `/api/auth/me` con 401 ya no se interpreta como sesión válida.

# Release 0.1.18 (2026-09-29)

## Resiliencia de credenciales
- Si el gateway rechaza el session token, la app reintenta con la
  contraseña recordada antes de quedarse sin conexión.
- El diagnóstico de conexión ahora muestra la credencial activa y si el
  gateway la acepta, con la causa más probable cuando la rechaza.

# Release 0.1.19 (2026-09-29)

## Fallo al enviar resuelto
- La app monta ahora la sesión viva del gateway (`session.resume`) antes
  de enviar, igual que Hermes Desktop. Sin ese paso el gateway rechazaba
  cualquier envío con «session not found»: fallaba en todos los bots.
- Si la sesión caduca (reinicio del gateway, expiración), el reintento
  re-monta la sesión automáticamente.
- El avatar del bot queda centrado con su burbuja.
- Los grupos se listan todos juntos bajo una única cabecera «Grupos»
  arriba de todo, sin subsecciones por gateway.

# Release 0.1.20 (2026-09-29)

## Crear grupos
- FAB → «Nuevo grupo»: nombre + bots de todas tus conexiones.
- Compatible con Hermes Desktop: la sala se publica en el mismo espejo y
  Desktop la verá al conectar (y tus grupos de Desktop siguen aquí).
- Sin duplicados: si dos gateways tienen bots con el mismo nombre, el
  selector muestra uno solo (elige el primero); el grupo multi-gateway
  conserva un miembro por identidad.

## Ajustes
- Tus mensajes vuelven a la derecha en el chat.
- Los iconos de bot se muestran sin fondo, sólo el icono.

# Release 0.1.21 (2026-09-30)

## Corregido
- **Grupos duplicados**: si el mismo grupo llega por varios gateways,
  ahora ves UNA fila. La dueña es tu primer gateway con miembros; si
  reordenas gateways, la fila migra y las copias se limpian.
- **Iconos de bot sin fondo**: se muestra solo el dibujo (imagen o
  icono), teñido del color del bot; sin cajas ni círculos de color.
  Las iniciales también van sin fondo.

# Release 0.1.22 (2026-09-30)

## Nuevo
- **Info de contacto**: toca el nombre arriba del chat y se abre la
  ficha del bot o del grupo (estilo WhatsApp).
- **Cambiar el modelo del bot** desde su ficha: proveedor y modelo, con
  la lista real del gateway (`model.options`) y guardado directo en el
  perfil (`PUT /api/profiles/{name}/model`).
- Los grupos muestran sus **miembros con su icono** en la ficha.
- Los iconos de los bots se ven también dentro del chat (cabecera y
  burbujas).

## Corregido
- Los iconos ya no parpadean al iniciar: el sync no reescribe filas
  sin cambios.


# Release 0.1.23 (2026-10-01)

## Nuevo
- **Screen real del bot**: panel "Pantalla del bot" en la cabecera de cada
  chat de bot. Observa el escritorio remoto del bot (RFB/VNC sobre el WS
  hermana del gateway, `display.observe` + `/api/display/ws`) con los
  controles de Hermes Desktop: iniciar/parar el escritorio, tomar el
  control (lease humano) y devolverlo. El bot conserva su pantalla aunque
  cierres el panel.
- **Autocompletado @ en grupos**: al escribir `@` aparece la lista de
  miembros de la sala (handles reales del backend de grupos) para dirigir
  el turno al bot correcto.

- **Grupos hosted ESCRIBIBLES**: los rooms nativos del gateway (`groups.*`)
  aceptan mensajes desde Pocket con append idempotente (`client_event_id`).

## Corregido
- **Visor Screen en Android**: el bundle noVNC (UMD con top-level await) se
  servía por `file://` y Chromium lo bloqueaba (CORS origin `null`). Ahora
  la app levanta un mini-servidor HTTP de loopback (`127.0.0.1`, sólo para
  los assets del visor, declarados en `network_security_config.xml`) y el
  bundle entra como módulo ES con dynamic import → `window.RFB`.
- **Fuga de listener en grupos**: al salir de un chat de grupo quedaba viva
  la suscripción a `room.event`; se cancela en `dispose()`.

## Infra
- Fake gateway (`tools/fake_gateway.py`) emula `display.status/start/stop/
  observe/lease.*` y la hermana `/api/display/ws` (valida ticket single-use
  de 30 s y cierra con 4000), bastante para probar handshake y ciclo de
  lease sin servidor VNC real.
- Contratos verificados y documentados en `docs/protocol/hermes-map.md` §6.