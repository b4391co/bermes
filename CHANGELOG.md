## Release 0.1.56 (2026-10-08)

### fix: el `@` resuelve el nombre VISIBLE del bot (título canónico)

- Los miembros del canal legacy se persistían SIN su título — mencionar por
  el nombre visible (CLAUDIO, Bernardino, Richard…) no resolvía al perfil.
  Ahora el título canónico viaja en el JSON de miembros y el motor resuelve
  tanto `@CLAUDIO` como `@default`.

## Release 0.1.55 (2026-10-08)

### fix: el `@` ofrece bots en TODOS los chats y entrega turnos cruzados

- **`@` en chat 1:1**: el autocompletado sólo cargaba candidatos en grupos —
  en un chat con un bot, teclear `@` no mostraba NADA. Ahora el roster
  completo de bots (todas las conexiones) está disponible como candidato en
  cualquier chat; en grupos se fusionan miembros de la sala + roster sin
  duplicar.
- **Mencionar a OTRO bot en un chat 1:1 entrega el turno**: el mensaje sigue
  llegando al bot del chat (su sesión es el transporte) y, además, cada bot
  mencionado distinto recibe su turno por el mismo motor de grupos (prompt
  de sala de Desktop) y su respuesta se streamea en este chat con su autor.
- Suite: 115 verdes.

## Release 0.1.54 (2026-10-08)

### fix: MENCIONES en grupos de Desktop, «...» duplicado y avatares aplastados

- **MENCIONES (la de verdad)**: los grupos de Hermes Desktop NO son salas del
  gateway — el espejo `ui_meta['hermes-bots-groups']` es storage de cliente y
  la orquestación de turnos vive EN Desktop (verificado en el código fuente:
  `group-rounds.ts`/`group-turns.ts`, 0 llamadores a `groups.*`). Por eso un
  `@Aura` desde Pocket no hacía NUNCA nada: no había nadie escuchando. Ahora
  Pocket implementa el motor de turnos compatible: parse de menciones idéntico
  (perfil, handle, título Bot Mode, display_name, formas colapsadas,
  `@everyone`/`@all`), `prompt.submit` a la sesión canónica "Bot Chat" de cada
  bot mencionado en SU gateway, con el prompt de sala byte-por-byte el de
  Desktop (`buildGroupChatTurnPrompt`), y la respuesta streameada al timeline
  del grupo con el autor correcto. Los marcos de control de los miembros se
  re-etiquetan como Desktop (`member-quoted`). Alcance honesto v1: un mensaje
  → un turno por bot mencionado; el round-robin multi-ronda de Desktop sigue
  viviendo en Desktop.
- **«...» duplicado**: en streaming había DOS indicadores (bocadillo de puntos
  del avatar + «escribiendo…» al pie de la burbuja). El texto repetido
  eliminado; el bocadillo del avatar se queda solo.
- **Avatares aplastados**: ListTile limita el leading a 56 de alto — el aura
  orbital (81 px) quedaba aplastada a 23 px. `OverflowBox` le devuelve su caja
  real (fila de la lista y banda de Fijados, cuyo tile además pasa de 168 a
  176 px).
- Tests: +9 (parse de menciones, formato del prompt, líneas de transcript,
  re-etiquetado de marcos); suite 115 verdes.

## Release 0.1.53 (2026-10-08)

### fix: caras de grupo — las 3 causas restantes (sonda IconosProbe) + diseño de la referencia

- **Caras de grupo: 3 causas más tapadas** (sonda IconosProbe): (1) los
  descriptores que publica Pocket omitían `handle`; (2) las filas del canal
  legacy (`ui_meta.hermes-bots.groups`) NO guardaban miembros → icono SIEMPRE
  en iniciales — ahora se persisten con identidad (regresión
  `group_legacy_members_icon_test`); (3) el mapa installId→conexión se leía
  una sola vez en initState y el gateway lo envía después → se refresca en
  cada ciclo/stream. Y la cabecera del chat usa el índice de caras completo
  (antes sólo por id de fila).
- **Diseño bots según Hermes-Mobile-App** (repo analizado): dot de estado de
  los gateways con glow/pulso en la cabecera, primarios en píldora, y
  «Nuevo bot» (POST /api/profiles verificado por sonda, con validación de
  nombre y aviso de homónimos).

## Release 0.1.52 (2026-10-08)

### fix: lote de los reportes 0.1.50/0.1.51 — reparación de grupos, aura de inicio a fin, hora legible, caras de grupo

- **Grupos zombis se reparan SOLOS**: al abrir un grupo que ningún gateway
  hospeda (creados con 0.1.48–0.1.50, sin `member_id`), la app re-crea la
  sala EN SITIO con el MISMO `room_id` y el roster correcto (sonda real:
  `groups.create` es idempotente — misma sala; 4110 si el contenido
  difiere). Ya no hay que borrar y recrear: abrir el chat basta. Si algún
  gateway tiene ≥2 bots del grupo, ahí queda hosted; las menciones `@` y
  `groups.send` pasan a funcionar con la misma fila.
- **Aura y «…» de INICIO a FIN aunque salgas del chat**: el watchdog de
  silencio vivía en el controller del chat, que se destruye al salir —
  mataba el aura en la lista. Ahora es global por conversación
  (`TurnActivity`), se rearma con cada evento vivo y cierra a los 4 min de
  silencio real. Salir del chat NO la apaga; los eventos terminales
  (`message.complete`/cancel/error) sí.
- **Hora de los mensajes legible**: 12pt con contraste pleno (antes 11pt
  gris muy claro). En grupos, el timestamp del log (`created_at`, epoch
  seconds) ya se convertía bien — verificado con sonda.
- **Iconos de grupo con caras reales**: homónimos (`default` en 4
  gateways) caían a iniciales; ahora la conexión de la fila del grupo
  desambigua. Widget test de pila (3 caras + badge +N) incluido.
- **Screen**: en hosts sin TigerVNC/Xfce el botón «Iniciar» ya no se
  muestra (siempre fallaba); se ofrece «Instalar» con la lista de paquetes
  que faltan (verificado contra 9112/9113: `installed:false, missing:[7]`).
  El flujo completo start→running verificado contra 9110.
- **Cookies con prefijo de nombre** (9113 emite
  `hermes_richard_session_at/_rt/_provider`): la sesión se reconoce como
  propia y el flujo login→ticket→WS completo verificado por curl.
- **Lista estilo Hermes-Mobile-App**: hairline entre filas, avatar 48.

- **Caras de grupo: 3 causas más tapadas** (sonda IconosProbe): (1) los
  descriptores que publica Pocket omitían `handle`; (2) las filas del canal
  legacy (`ui_meta.hermes-bots.groups`) NO guardaban miembros → icono SIEMPRE
  en iniciales — ahora se persisten con identidad (regresión
  `group_legacy_members_icon_test`); (3) el mapa installId→conexión se leía
  una sola vez en initState y el gateway lo envía después → se refresca en
  cada ciclo/stream. Y la cabecera del chat usa el índice de caras completo
  (antes sólo por id de fila).
- **Diseño bots según Hermes-Mobile-App** (repo analizado): dot de estado de
  los gateways con glow/pulso en la cabecera, primarios en píldora, y
  «Nuevo bot» (POST /api/profiles verificado por sonda, con validación de
  nombre y aviso de homónimos).

## Release 0.1.51 (2026-10-07)

### fix(grupos): causa raíz de «no deja enviar» — `groups.create` exigía `member_id`

Sonda WS directa contra los gateways reales (0.21.5) del contrato de
`groups.create`: cada miembro debe incluir `member_id` + `profile` + `handle`
(5111 «member N is missing fields: member_id»). 0.1.48–0.1.50 lo omitían
(creían que era server-owned): **toda** sala hosted era rechazada, nunca
existía en el backend, y `groups.send` respondía 4112 → «no deja enviar en
grupos». E2E real verde: crear → `groups.state` → `groups.send` →
`groups.log` con el mensaje visible.

- `create` genera `member_id` estables por sala y manda sólo claves del wire.
- Validador local reescrito sobre el contrato real (`roster_validator.dart`):
  locales sin `target`; remotos con `target:{kind:'peer', peer_id,
  installation_id, capability_digest, profile}`; 2..6 miembros.
- `RoomMember.target` es objeto (el cast a String reventaba el parseo de
  `groups.create`).
- Cross-gateway: el registro de pares exige HTTPS (5120 «target_url must use
  https outside the local machine») — en LAN http:// los miembros de otros
  gateways no pueden entrar en la sala. `createGroup` elige un host con ≥2
  bots y, si ninguno autoriza la sala, el usuario ve el motivo concreto
  (espejo creado, turnos no enrutan) en vez de un fallo mudo.
- Tests de roster reescritos contra la sonda real; `group_e2e_test.dart`
  (tag `real`) cubre el ciclo completo contra gateways del usuario.

## Release 0.1.50 (2026-10-07)

### fix(grupos): claves de espejo sanitizadas en el wire, dueño de sala resuelto, hora en burbujas

- **Enviar en grupos**: `RoomsClient.create` filtraba a las claves del wire
  (`profile/handle/display_name/target`) y el reintento probaba gateway por
  gateway y shape completo→mínimo. El validador local de esta versión además
  RECHAZABA `member_id` («server-owned»): el contrato real lo exige — 0.1.51
  corrige la causa raíz (ver arriba).
- **Dueño de sala**: al abrir un chat grupal la app localiza el gateway que
  autoriza la sala (`groups.state` en dueña + conexiones de los miembros) y
  usa ése para log, eventos, menciones y `groups.send`.
- **Menciones**: miembros del gateway dueño + handles del espejo, fusionados.
- **Hora en cada mensaje** bajo la burbuja.
- **Aura**: se apaga con cualquier evento terminal y con el eco `message.user`;
  la lista de chats escucha `TurnActivity` global.

## Release 0.1.49 (2026-10-07)

### fix(grupos): shape real de roster, caras por identidad de conexión

- `groups.create` con filas `{profile, handle, display_name, target}` (en
  0.1.48 viajaba el perfil en `name` y `target` como string → rechazado).
- Iconos de grupo resueltos por identidad (installId → conexión → perfil).
- Login con cookies legacy.

## Release 0.1.48 (2026-10-07)

### fix: grupos funcionales (hosted rooms), iconos de grupo, vida del turno, gateways sin auth

- **Grupos**: al crear un grupo la app ahora HOSTEA la sala en el gateway
  (`groups.create` → `groups.send`/`groups.log` con turnos reales). Antes
  sólo se publicaba en el espejo de Desktop y el backend no conocía la
  sala: los mensajes fallaban con 4112 «room not found» y «no había turno».
  Las salas del espejo que Desktop dirige siguen siendo de sólo-lectura
  (el driver de turnos es de quien creó la sala).
- **Iconos de grupo**: resueltos por identidad de miembro (installId →
  conexión local → perfil), no sólo por id de conversación: las caras
  reales aparecen también para grupos llegados del espejo de Desktop.
- **Thinking continuo**: el aura del avatar y la fila «escribiendo…» del
  chat ya no dependen de que el gateway emita `message.start` — gateways
  como 0.15.0 no lo emiten hasta el primer delta; ahora cubren
  `status.update`/`tool.*`/`thinking.delta` y grupos tras `groups.send`,
  con watchdog de 4 min de silencio.
- **Contraste**: en tema claro la burbuja del usuario pasa de negro tinta
  a grafito suave (token dedicado); el contraste bot/usuario es de tono.
- **Gateways sin autenticación** (`auth_required: false`, p. ej. LAN
  0.15.0): nuevo método «Sin acceso» — el probe de conexión lo detecta y
  lo sugiere. REST/WS se abren sin credenciales (ni ticket ni token).
- **Screen**: la detección de «sin Bot Screen» acepta también «not
  found» con códigos distintos de -32601 (0.15.0); el visor ya no se
  queda en blanco.

## Release 0.1.47 (2026-10-06)

### feat(chat): PDF y vídeo integrados, iconos de grupo con miembros, vida del bot completa

- **PDF**: visor integrado (flutter_pdfview) — pasar páginas, contador, y
  compartir/guardar desde la barra. Ya no depende de apps externas.
- **Vídeo**: reproductor a pantalla completa con controles (play/pausa,
  barra de progreso arrastrable, tiempos) + botón **compartir/guardar**
  (hoja de compartir de Android: Drive, Archivos, mensajería).
- **Iconos de grupo**: ahora muestran las CARAS REALES de los bots
  miembros (hasta 3: una grande + dos pequeñas) y badge `+N` con el resto
  — un grupo de 10 bots se identifica de un vistazo. En lista, fijados y
  cabecera del chat.
- **DM entre bots**: mientras un bot habla con otro (`message_agent`), el
  chat muestra «Esperando a <bot>…» y el avatar mantiene aura + «…»
  (la vida del bot va desde que arranca el turno hasta que termina,
  incluidas las fases de contexto/skills/herramientas sin deltas).
- **Cuadros de texto del chat**: campo de mensaje con caja y relleno
  propios (el texto ya no choca contra el borde); burbujas con más margen
  interior y separación del avatar.
- **Screen en gateways viejos**: si el gateway no tiene Bot Screen
  (métodos `display.*` ausentes, p. ej. 0.21.4), el panel lo dice claro
  («sin Bot Screen») en vez de un error genérico.
- **Login**: el fallo «sin cookie de sesión» ahora indica también cuántas
  Set-Cookie envió el gateway (diagnóstico del caso 9113).

## Release 0.1.46 (2026-10-06)

### fix(conversations): aura y bocadillo «…» solo en los bots trabajando

- El aura orbital y el bocadillo «…» de la banda de Fijados ahora
  aparecen SOLO en los bots con un turno en vivo (streaming real);
  antes se pintaban en todos los fijados siempre.
- Los tiles grandes de Fijados quedan alineados al centro de verdad
  (el `Wrap` encogía a su ancho y la banda lo pegaba a la izquierda).
- Registro `TurnActivity` (memoria, por conversación): la cabecera del
  chat y las burbujas ya lo usaban; ahora la lista también.

## Release 0.1.45 (2026-10-06)

### fix(screen): contrato real de DisplayStatus + flujo de instalación

El panel de Pantalla mapeaba el resultado de `display.status` como si
trajera una cadena `state`; el contrato real
(`tui_gateway/contracts/display.py::DisplayStatus`) trae
`running/installed/missing[]/blocker/install_command`. La app mostraba
«el escritorio del bot está parado» para un host sin instalar y no
ofrecía remedio.

- `ScreenStatus.fromRpc` ahora respeta el contrato: `running`,
  `needsInstall` (`installed == false`), `error` (blocker) y lease.
- Flujo de instalación real: RPC `display.install` → eventos
  `display.install.log`/`display.install.done` → server-request
  `display.install.sudo` con tarjeta de contraseña → arranque automático
  del escritorio al terminar (`code == 0`).
- Insignia «sin instalar» y botón «Instalar en el host» con registro de
  progreso; el arranque manual sigue sin arrancar escritorios por sorpresa.

### feat(notifications): aviso local al terminar la respuesta del bot

- Notificación local (flutter_local_notifications, canal `turns`) cuando
  un turno termina (`message.complete`) y el usuario NO está mirando ese
  chat con la app en primer plano. Sin push externo: el gateway no
  ofrece push y la app no abre servicios a Internet.
- Permiso `POST_NOTIFICATIONS` en el manifest (Android 13+ lo pide en
  runtime); sin el permiso la app funciona igual, sólo no avisa.

## Release 0.1.44 (2026-10-06)

### fix(connections): el editor de conexión se abría en blanco (0.1.44)

Regresión introducida en 0.1.41: al refactorizar el editor se borró por
accidente la inicialización `_scheme = e?.scheme ?? 'http'` del `initState`,
y cualquier lectura de `_scheme` (build, chips http/https, banner TLS,
diagnóstico) lanzaba `LateInitializationError` → pantalla en blanco al
añadir O editar una conexión. Restaurada la inicialización y verificado en
emulador: editor renderiza, guarda, y la conexión funciona (alta fake +
login + roster).

Nota de instalación: los APKs de release usan el keystore real
(CN=Hermes Pocket). Los de CI no tienen `android/key.properties` y salen
firmados en debug — si tu app instalada viene de una build por adb/CI, el
release no se instala encima (firmas distintas): exporta ajustes,
desinstala, instala el release, importa.

pubspec: 0.1.43+43 → 0.1.44+44.

## Release 0.1.43 (2026-10-06)

### style(conversations): densidad y acentos de lista como la referencia (0.1.43)

Segunda pasada de estilo: forma y estructura, no solo colores.

- Filas de la lista de chats compactas (`VisualDensity.compact`, avatar
  46→42): la lista se acerca a la densidad de la referencia y caben más
  conversaciones por pantalla.
- Hora y badge de no leídos en verde `#3ECF8E` con texto oscuro: antes el
  badge usaba `cs.primary` (#242424) y era invisible sobre el fondo
  `#1A1A1A`.
- FAB circular neutro (`#2A2A2A`, icono claro) vía tema: el teal por
  defecto de M3 rompía la calma del fondo; la referencia no usa acentos
  de color en botones flotantes.

pubspec: 0.1.42+42 → 0.1.43+43.

## Release 0.1.42 (2026-10-06)

### feat(theme): tema oscuro calibrado contra Hermes Desktop (0.1.42)

El tema oscuro era un carbón genérico (#101114); la referencia visual del
encargo es la de Hermes Desktop. Recalibrado con los valores medidos de la
captura: fondo `#1A1A1A` (sidebar+chat), chrome superior `#141414`,
burbuja del bot `#212121` (el texto del bot ahora va en tarjeta redondeada,
como en Desktop; antes era prosa plana sin burbuja), burbuja del usuario
`#242424` con texto `#EDEDED`, campos `#242424`, secundario `#747474`,
filas `#262626` y verde de estado `#3ECF8E` (también `Hp.online`). Tema
claro intacto. Verificado en emulador contra el gateway real: home, chat y
burbujas renderizan la paleta exacta; `flutter analyze` sin incidencias
nuevas.

pubspec: 0.1.41+41 → 0.1.42+42.

## Release 0.1.41 (2026-10-06)

### feat(settings): importar un config.yaml REAL de Hermes ya no es «formato no reconocido» (0.1.41)

Importabas el `config.yaml` de tu gateway (boneca) y la app soltaba un
«Formato no reconocido» seco. Era cierto a medias: ese archivo NO es un
paquete de ajustes de Pocket (y no contiene la URL del gateway — el
dashboard escucha donde arranque `hermes serve`), pero el mensaje no
ayudaba y tiraba lo único aprovechable.

- Detección del config real de servidor (claves `dashboard`+`agent`/
  `providers`): diálogo explicando QUÉ es y por qué no basta, y el
  usuario del panel (`dashboard.basic_auth.username`, p. ej. `breo`)
  se PRECARGA en el editor de conexión — solo te falta host, puerto y
  contraseña.
- El paquete propio de Pocket sigue importándose igual (con previews
  y dedupe), y un JSON desconocido sigue avisando de formato inválido.
- Pruebas: 3 casos nuevos (paquete propio OK / config hermes detectado
  con usuario / JSON ajeno rechazado). Suite: 80 verdes.

Nota de fondo: el hash `scrypt` del `basic_auth` de tu boneca CONFIRMA
que el usuario/contraseña del panel 9119 son los mismos que claudio —
tu tesis de las credenciales era correcta; el bloqueo real era el
header `Origin` (arreglado en 0.1.40).

## Release 0.1.40 (2026-10-05)

### fix(connections): Origin/Referer en las peticiones — los gateways «webapp» aceptan el login (0.1.40)

Caso real descubierto con TU configuración (breo en ambas): 9110 y 9119 son
DOS instalaciones hermes en la misma máquina con credenciales idénticas —
tenías razón, el login SÍ funciona en las dos a nivel HTTP. Pero la app
fallaba en 9119 en un paso posterior: el mint del ticket WS
(`POST /api/auth/ws-ticket`) responde **403 «Cookie-authenticated writes
must come from the dashboard's own origin»** cuando la petición no trae
header `Origin`. Un navegador (Desktop) siempre lo manda; un cliente
nativo no — y la app interpretaba el 403 como «sesión no utilizable» y
eliminaba el login.

- `HermesHttpClient` envía ahora `Origin`/`Referer` del propio gateway en
  todas las peticiones (`ConnectionProfile.schemeOrigin`).
- Verificado contra tu 9119: «Probar conexión» → **Login correcto**; el
  mint responde con ticket igual que en 9110.
- La versión visible en Ajustes sigue siendo la real del paquete (0.1.39).

## Release 0.1.39 (2026-10-05)

### fix(settings): la versión mostrada es la REAL del paquete instalado (0.1.39)

- «Acerca de» leía una constante hardcodeada en `0.1.24` — llevaba seis
  releases sin actualizarse: instalabas la última y dentro ponía una
  versión vieja, haciendo pensar que la release no se publicaba bien.
  Las releases SÍ estaban bien (el manifiesto del APK traía la correcta;
  solo el cartel era mentira).
- Ahora usa `package_info_plus`: lee versión y build del paquete real en
  el dispositivo. Impossible que se desincronice.

## Release 0.1.38 (2026-10-05)

### fix(connections): «Probar conexión» y «Guardar» ya comprueban el login de verdad (0.1.38)

El caso que lo destapa: **misma máquina, dos gateways**. 9110 y 9119 en
10.20.20.67 son DOS instalaciones Hermes distintas (`install_id`
diferente): 9110=claudio, 9119=otro servidor (boneca) con SUS propios
usuarios. Con credenciales correctas para 9110, el 9119 responde
`401 Invalid credentials` — y la app lo tragaba en silencio.

- **Probar conexión**: con Usuario+Contraseña rellenos hace el login
  COMPLETO (proveedor → password-login → cookie), como Desktop. Muestra
  «Login correcto» o «Acceso denegado · HTTP 401» con la causa real.
  Sin contraseña sigue sondeando solo el transporte (GET /api/status).
- **Guardar**: si el login falla, la conexión NO se guarda — snackbar
  rojo con la causa. Nueva → no se crea nada; edición → la conexión
  original queda EXACTAMENTE como estaba (rollback de fila y secretos).
- **Lista de chats**: una conexión guardada sin conversaciones ya NO es
  invisible: fila honesta con su estado real («sin sesión · toca para
  revisar usuario y contraseña», «conectando…», etc.) y salto directo
  al editor.

Probado en el emulador contra el gateway real de boneca (9119):
prueba → «Acceso denegado · HTTP 401»; guardar → no se crea nada;
la conexión sin sesión aparece en la lista con su estado.

## Release 0.1.37 (2026-10-05)

### feat(chat): los bots entregan imagen, vídeo, audio y archivos — y se ven bien (0.1.37)

- El bot entrega archivos escribiendo `MEDIA: <ruta>` en su respuesta
  (contrato real de Hermes, verificado contra Desktop `parts.ts` y el
  gateway en vivo). La app lo parsea fielmente: líneas dedicadas o en
  prosa, rutas con espacios, Windows, comillas; nunca verás el texto
  crudo `MEDIA: …`.
- Imagen → miniatura en la burbuja + visor a pantalla completa con zoom.
- Vídeo → tarjeta con play + reproductor real (pantalla completa).
- Audio → fila reproduciéndose (alto-parlante del móvil).
- Documento/archivo (PDF, zip, epub…) → se abre con la app que tengas
  instalada; si no hay ninguna, se comparte.
- Cascada de lectura como Desktop: `/api/media` y si 403 (fuera de las
  raíces del dashboard — típico en multiperfil), `/api/fs/read-data-url`
  con el perfil dueño. Caché local: no se repite la descarga.
- Probado EN VIVO de punta a punta: el bot de claudio creó un PNG, lo
  entregó por `MEDIA:` y la app lo renderizó (inline y en el visor).
- El diagnóstico de credenciales rechazadas lista los métodos de acceso
  que anuncia el gateway (heredado de 0.1.36).

## Release 0.1.36 (2026-10-05)

### diag(connections): el panel de prueba lista los métodos de acceso del gateway (0.1.36)

- Al rechazar credenciales, la prueba de conexión ahora muestra QUÉ
  proveedores anuncia el gateway (`GET /api/auth/providers`): si ninguno
  admite contraseña, el problema es de configuración del SERVIDOR (no hay
  usuario/contraseña que valga); si los hay, la credencial guardada no es
  válida para ese gateway concreto.
- Responde al caso boneca: mismo usuario/contraseña que claudio pero
  rechazo — el panel dirá si es que boneca no admite login por contraseña.

## Release 0.1.35 (2026-10-05)

### fix(connections): diagnóstico accionable de credenciales rechazadas (0.1.35)

- Cuando un gateway rechaza las credenciales, el panel ahora explica las
  causas reales: cada gateway tiene SUS propios usuarios (el login de
  boneca no tiene por qué ser el de claudio), y los paquetes de ajustes
  NO incluyen secretos — hay que re-introducirlos en el editor.
- Persistente del intento anterior: APKs firmados v1+v2+v3 (0.1.34).

## Release 0.1.34 (2026-10-05)

### fix(build): firma v1+v2+v3 para compatibilidad de instalación (0.1.34)

- Los APKs de release se firmaban sólo con el esquema v2. Ahora se
  habilitan v1 (JAR), v2 y v3: cubre ROMs y flujos de instalación que
  rechazan paquetes sin firma v1 (el fallo «no se puede instalar» sin
  más explicación).
- La MISMA clave de distribución (cert SHA-256 idéntico): se puede
  actualizar desde 0.1.33 sin desinstalar.
- Verificado: el asset publicado de 0.1.33 era íntegro (checksum idéntico
  al local); la causa del fallo en tu teléfono fue o bien una descarga
  cortada, o un APK previo instalado con otra firma (p. ej. un build de
  debug). Si vuelve a fallar: desinstala la app e instala la 0.1.34.

## Release 0.1.33 (2026-10-05)

### feat(groups): editar miembros de grupo — añadir y quitar (0.1.33)

- La ficha del grupo permite **añadir miembros** (botón «Añadir miembro»,
  selector con los bots de todas las conexiones) y **quitarlos** (icono por
  fila con confirmación).
- **Canal compatible**: la edición escribe el espejo de Desktop
  (`hermes-bots-groups`) por `profiles.configure` con CAS — el MISMO
  mecanismo que usa Desktop (group-chat.ts:1174-1192). Nada de métodos
  inventados: verificado en vivo contra el gateway real (añadir
  `solicitudes` a «Casa» y revertirlo, aplicado y leído de vuelta).
- **Conflicto honesto**: si Desktop tocó el espejo mientras editabas, el
  CAS lo detecta y avisa sin pisar su cambio.
- El descriptor del miembro nuevo clona `connectionId/connectionLabel` de
  un miembro existente del MISMO gateway (Desktop agrupa por
  `connectionId::profile`): inventar una conexión rompería su merge.
- La ficha de miembros cae al espejo persistido cuando `groups.state`
  responde 4112 (la sala no la hospeda ESTE gateway) — antes se quedaba
  cargando eternamente en salas autoridad de otro gateway (p. ej. «Casa»).
- Tras editar: resync de la conexión y releída FRESCA de la fila.

## Release 0.1.32 (2026-10-05)

### chore: denominación de versiones — 0.1.31 / 0.1.32

- El versionado vuelve al esquema 0.1.x: versionName = 0.1.32,
  versionCode = contador incremental (32). Las releases 31/32 de ayer
  se renombran retrospectivamente como 0.1.31 y 0.1.32.

## Release 32 (2026-10-04)

### fix(conexiones): renovación automática de sesión — 32

- **Síntoma**: las conexiones «se quedaban sin conexión»: si el gateway
  invalidaba la sesión (reinicio del servicio, rotación de secretos),
  el enlace WS moría con close 4401 y la app se quedaba en «sesión
  expirada» hasta reconectar a mano.
- **Fix**: al expirar, la app se re-autentica en silencio con la
  contraseña recordada y reconecta. Un enfriamiento de 2 minutos por
  conexión evita gastar el anti-fuerza-bruta del gate en bucles.
- **Nota de diagnóstico**: el gateway de claudio estaba PARADO
  (`gateway_running: false`) — el router web respondía y eso confundía.
  Con el gateway parado la app puede iniciar sesión pero el enlace cae.
- tools/fake_gateway.py: escenario por defecto del gateway A restaurado
  (regresión 0.1.28 con fakes recién iniciados); test E2E de renovación
  (4401 → re-login → reconexión, sin bucle).

## Release 31 (2026-10-04)

### fix(groups): miembros y menciones en salas sin roomId — 31

- **Síntoma**: en el grupo «Dual» (clave `name:` del espejo, no hospedada)
  no se veían los miembros en la ficha y el autocompletado `@` no aparecía:
  ambos leían `groups.state`, que el gateway rechaza (4112) para estas salas.
- **Fix**: syncGroupMirrors persiste los descriptores de miembros del espejo
  (`GroupRoom.members`) en la nueva columna `conversations.groupMembersJson`
  (migración v10). La ficha de miembros y el autocompletado `@` los usan
  como fuente; los homónimos se distinguen por handle (default-boneca /
  default-claudio) y el gateway de origen.
- **Subtítulo honesto**: el conteo de miembros ahora es el de la sala del
  espejo (miembros de TODOS los gateways): «Dual» = «4 miembros», no 2.
- E2E en emulador contra el gateway real: ficha con 4 miembros desambiguados;
  «@de» sugiere @default-boneca / @default-claudio; selección reemplaza el
  token. El envío en salas no hospedadas sigue el contrato del gateway
  (rechazo → fila Reintentar con la causa, nunca reenvío automático).
- Versionado: esquema de número único (31, 32, 33…; versionName = versionCode).

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