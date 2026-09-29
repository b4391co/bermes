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
