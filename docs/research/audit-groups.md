# GroupsFidelity — grupos / sincronización / pin / títulos

Fuente de verdad: `/tmp/research/hermes-agent` @ `e408d36`. App: `/root/bermes`.
Veredictos: `igual` · `difiere(arreglado)` · `difiere(pendiente <motivo>)`.

## Hallazgo central (cambia el diagnóstico de toda el área)

**El SPA de Hermes Desktop NO usa los métodos JSON-RPC `groups.*` en absoluto.**
`grep -rn "'groups\.[a-z.]*'" apps/ --include=*.ts --include=*.tsx` (excluyendo
`gateway-contract.generated.ts`) no devuelve NINGÚN llamador; los `groups.*` sí
existen y están documentados en el contrato generado
(`apps/shared/src/gateway-contract.generated.ts:4859-4893`, lista canónica en
`tui_gateway/methods_groups.py:18-22`), pero quien los sirve es el **driver de
rooms del backend** para su propio protocolo de réplica/autoridad
(`groups.replicate`, `groups.promote`, `groups.peer.*`), no para la UI.

Lo que Desktop llama, para grupos, son solo dos métodos:

| método | dónde | para qué |
|---|---|---|
| `profiles.list` | `apps/desktop/src/plugins/hermes-bots/group-chat.ts:1013-1017` | leer el espejo `ui_meta['hermes-bots-groups']` del perfil `default` |
| `profiles.configure` | `group-chat.ts:1174-1192` | publicarlo, con CAS por clave (`ui_meta_expected_revisions`) |

Y el espejo **no lo conoce el backend**: `grep -rn "hermes-bots-groups"
--include=*.py .` → 0 resultados. `_configure_ui_meta` la trata como una clave
opaca y la fusiona key-wise (`tui_gateway/methods_profiles.py:600-606`). Es
decir: **cliente-a-cliente, storage = la sección `ui_meta` del perfil `default`
de cada gateway.**

Consecuencia: el `RoomsClient` de Pocket (que existía) no estaba mal *por
campos*, estaba mal *por modelo*: prometía una sincronización de salas vía
`groups.*` que Desktop no hace. Se elimina en el cutover (§F).

## Tabla de alineación

| área | desktop (fichero:línea) | bermes (fichero:línea) | veredicto |
|---|---|---|---|
| Fuente de grupos para la UI | `group-chat.ts:49` (clave `hermes-bots-groups`), `:1019` | `clients/hermes/connection_manager.dart:288-310` (leo esa clave de `default`) · `features/conversations/group_rooms.dart:164-215` | difiere(arreglado): antes la única fuente era `ui_meta['hermes-bots'].groups` (membresía, no sala) |
| `groups.*` como API de UI | 0 llamadores en `apps/` (ver hallazgo) | `clients/hermes/rooms_client.dart` (258 líneas, muerto, nunca instanciado) | difiere(arreglado): borrado |
| Identidad del grupo | `group-chat.ts:216-223` (`id:<roomId>`, legacy `name:<name>`) · `types.ts:203` («roomId inmutable, un rename no bifurca la sala») | `features/conversations/group_rooms.dart:80-84` (`identity`) · `group_sync.dart:244-247` (PK = roomId) | difiere(arreglado): antes PK = nombre visible (`connection_manager.dart` viejo l.262-267) → rename duplicaba la sala y huérfanos pin/mensajes |
| Identidad del miembro | `data.ts:1286-1288` (`botRosterKey = connectionId::name`) · `group-chat.ts:446-448` | `group_rooms.dart:108-120` (`rosterKey` literal, `profileKey` portable) | difiere(arreglado): antes `title: g, gatewayId: g` sin miembro alguno |
| Miembros multi-gateway | `types.ts:130-147` (`GroupMember = Pick<RosterRow, connectionId/installId/targetProfile/previous_names/…>`), espejo publicado en CADA gateway (`group-chat.ts:88-91`) | `group_rooms.dart:66-107,305-320` (`memberProfileHere`) · `group_sync.dart:120-176` | difiere(arreglado): un miembro de otro gateway ya no secuestra la fila; se resuelve por perfil y `previous_names` (`gateway-contract.generated.ts:1786`) |
| Merge sin pisar metadatos ajenos | `group-chat.ts:457-620` (`mergeGroupChatSyncSnapshots`: revisión manda, empate = unión de miembros, ausente ≠ borrado) | `group_rooms.dart:243-281` (`mergeGroupRooms`) · `group_sync.dart:84-97` | difiere(arreglado): antes no había merge (última escritura ganaba sobre un solo perfil) |
| Tombstones / disband | `group-chat.ts:607-617` (`id:` final, `name:` por revisión) · `:99-104` (memoria durable) | `group_rooms.dart:196-215` (`liveRooms`) · `group_sync.dart:189-215` | difiere(arreglado): antes «ausente» no se distinguía de borrado y no había tombstone local |
| No duplicar al importar/refsincronizar | `group-chat.ts:1140-1163` (si el remoto ya iguala, no se avanza revisión ni se duplica) | `group_sync.dart:244-252` (corte por revisión + `insertOnConflictUpdate` sobre PK durable) | difiere(arreglado): el ciclo de roster viejo re-creaba la sala en cada sync si Desktop cambiaba el nombre |
| Pin de grupos | `group-pin.ts:4-8` (pin LOCAL, fuera del espejo) · `group-order.ts:16-24` (pin = banda exterior, antes del `rosterOrder`) | `data/database/tables.dart:52-60` (`pinned`/`pinnedGateway` preservados en `localConvPrefs`) · `features/conversations/conversations_screen.dart:169-190` | difiere(arreglado): el pin existía pero la sección «Grupos» lo ignoraba (se filtraba `!c.isGroup`, l.172 viejo) → fijar un grupo no lo subía |
| Pin global vs por gateway | Desktop solo tiene UNA banda de pin por sala (`group-order.ts:19`) | `conversations_screen.dart:174-179` (`pinnedGateway` dentro de «Grupos» también) | difiere(arreglado): se conserva el modelo de dos bandas de Pocket (subconjunto correcto del de Desktop: pin global = sección «Fijados» y sigue siendo local) |
| Orden de salas | `group-order.ts:7-24` (`rosterOrder` local) · `:26-47` (swap de vecinos sin perder salas filtradas) | `conversations_screen.dart:186-211` (subsecciones por gateway + `withinSection`) | difiere(pendiente: `rosterOrder` drag-and-drop no está en el alcance de Pocket; `sortOrder` existe en la tabla pero Desktop tampoco lo exporta, `types.ts:222-225`) |
| Título canónico de bot | `labels.ts:34-62` (`meta.title` > `display_name` > `title`/`name` humanizado) | `connection_manager.dart:276-281` | igual (era `hermes-mobile`-equivalente; se anota la cita de Desktop) |
| Nombre del grupo | `group-chat.ts:66-71` (`name` del snapshot; sin derivados) | `group_sync.dart:253-259` (nombre del espejo; fallback = títulos de miembros vía `canonicalGroupName`) | difiere(arreglado): el fallback nuevo solo se usa si Desktop no proyecta `name` |
| `ui_meta['hermes-bots'].groups` | `types.ts:75` (`groups?: string[]`) · `group-membership.ts:152-171` (lectura canónica con fallback `group`) · `:178-191` (escritura deja `group` = proyección del primero) | `clients/hermes/bot_meta.dart:76-88` (lectura array+`group`) | igual en lectura; difiere(pendiente: `group` como proyección al ESCRIBIR lo aplica ChatFidelity en `bot_meta.dart`/`gateway_client.dart`, fichero de su propiedad) |
| Pertenencia visible | `bot-row.tsx:417` + `i18n.ts:188` (la lista de nombres se muestra como subtítulo del bot, no como sala) | `connection_manager.dart:328-341` (ahora viaja en `subtitle` del bot) | difiere(arreglado): antes cada nombre se materializaba como conversación propia |
| `profiles.configure` CAS | `group-chat.ts:1184-1206` (usa `ui_meta_expected_revisions` + verifica `applied.ui_meta_revisions` y read-back) | `gateway_client.dart:414-440` (`configureBot` sin CAS) | difiere(pendiente: `profiles.configure` es propiedad de ChatFidelity; la nota de la pérdida está en §G y el `foreign` propuesto se la paseé a esa área) |
| `profiles.configure` pisa claves ajenas | El servidor REEMPLAZA la sección (`methods_profiles.py:600-606`); Desktop envía la sección completa desde `next[key]` (`data.ts:355-361`) | `bot_meta.dart` (`BotRosterMeta` no modela `pinned`/`sectionId`/`screenAutoOpen`) · `gateway_client.dart:414-440` | difiere(pendiente → ChatFidelity): un guardado desde Pocket borra `pinned`, `sectionId`, `sectionName`, `screenAutoOpen`, `created`. Verificado que es real: `ui_meta: dict[str, JsonDict]` abierto y reemplazo por clave. Confirmado por ChatFidelity por IRC y aceptado para su edición |
| Sidebar REST `/api/profiles/sessions/sidebar` | `api/sessions.ts:311-345` (batch `recents_profile`/`recents_limit`/`cron_limit`/`messaging_limit` + fallback legacy por 404, `:237-307`) | no consumido por Pocket | igual (no aplica: Pocket no lista sesiones en la barra lateral; `session.list` viejo se purga, `connection_manager.dart:252-255`) |
| Pin de sesión espejado al backend | `api/sessions.ts:391-407` (`PATCH /api/sessions/{id} {pinned, profile}` en el BODY, «mejor-effort, la barra sigue siendo localStorage») | n/a (Pocket no muestra sesiones) | igual |
| Nombres de eventos de sala | `gateway/hosted_rooms.py:49-57` (taxonomía por actor: `message.user`/`message.member`/`turn.*`/`room.*`/`authority.*`) | n/a tras borrar `rooms_client.dart` | igual (fuera de alcance real) |
| `Room`/`RoomEvent` payloads | `gateway-contract.generated.ts:1331-1352` (`Room`), `:1364-1376` (`RoomEvent`) | n/a | igual (ya no se modelan: nada en la app los consumía) |

## Verificación
### Repro del contrato (parser + merge)

Repro desechable (`tool_tmp_group_check.dart`, **borrado** tras la ejecución —
no se deja test permanente porque el contrato no cambia de forma) alimentado
con el envelope v3 que Desktop escribe literalmente en
`group-chat.ts:296-320` + `:66-80`. 21/21 aserciones OK:

- parseo del envelope con `rooms`/`deleted`; identidad `roomId` inmutable y
  fallback `name:` solo para salas legacy;
- `rosterKey == connectionId::name` (idéntico a `data.ts:1287`);
- miembro de otro gateway resuelve por perfil; un `connectionId` ajeno **no**
  secuestra un perfil local; `previous_names` re-enlaza tras rename;
- rename id-keyed no duplica; **un espejo rezagado que proyecta la misma sala
  bajo otra clave (`name:Equipo`) tampoco la duplica** y no revierte
  nombre/revisión;
- empate de revisión: identidad del base + unión de miembros por `rosterKey`;
- `id:` tombstone final incluso con sala a revisión 42 vs tombstone 9; `name:`
  tombstone solo gana si la sala no es más nueva;
- reindexación de claves sin prefijo (envelopes antiguos).

**Bug real cazado por este repro y corregido:** `mergeGroupRooms` indexaba el
resultado con la clave del mapa entrante, así que la misma sala proyectada bajo
`name:` por un espejo viejo y bajo `id:` por uno nuevo aparecía dos veces en
`liveRooms()`. Ahora la clave canónica es siempre la del lado base
(`group_rooms.dart:251-279,301-305`).

`_confirmDelete` de grupos (ocultar, no borrar la fila) requiere runtime real:
**sin captura visual** — el `fake_gateway` del host está fuera de mi alcance
(ver §Pendiente-1 y el aviso de Main sobre el forward adb en 9119), así que el
flujo UI se valida por lectura del query (`kind='group-hidden'` excluido,
`conversations_screen.dart:62`) y de la guarda en `_writeRoom`
(`group_sync.dart:250-256`).

## Cambios aplicados

**Nuevos**
- `lib/features/conversations/group_rooms.dart` (355 l.) — decodificador del
  envelope v3 (`GroupSyncSnapshot.tryParse`, reindexación legacy
  `name:`→`id:`), `GroupRoom.identity`, `GroupMember` (subconjunto de
  `GroupMember = Pick<RosterRow,…>`), `mergeGroupRooms`, `liveRooms` con
  tombstones, `memberProfileHere`, `canonicalGroupName`,
  `groupConversationId`.
- `lib/features/conversations/group_sync.dart` (~300 l.) — `mergeGroupMirrors`
  (todos los gateways), `syncGroupMirrors` (colocar por conexión, escribir con
  corte por revisión, purgar solo tombstones, retirar el canal legacy solo
  cuando el espejo lo cubre), `_localIdForDeleted`.

**Modificados**
- `lib/data/database/tables.dart` — columnas `groupRoomId`,
  `groupSyncRevision`, `groupSyncName`; comentario de `Conversations`
  corregido (antes: «El source of truth de grupos es el gateway», falso).
- `lib/data/database/app_database.dart` — `schemaVersion` 6→7 con las 3
  `addColumn`; `localConvPrefs(id)` (preserva pin/orden en re-altas),
  `groupConversationRow(id)`, `groupSyncState(connectionId)` (incluye
  `group-hidden`).
- `lib/clients/hermes/connection_manager.dart` — `resyncAll()`/`resyncOne()`
  batched (los espejos se cruzan contra TODOS los rosters), `_ConnRoster` por
  conexión, `syncBots` ya NO materializa grupos (anota la pertenencia en el
  subtítulo del bot), limpieza de `_snapshotByConn` en `removeRuntime`,
  `_syncGroupMirrors(db)` al final de `bootstrap`.
- `lib/features/conversations/conversations_screen.dart` — consulta excluye
  `group-hidden`; «Grupos» con subsecciones por gateway y banda de pin
  (`withinSection`); borrar un grupo = ocultar (marcador local), con texto
  honesto; `_NewChatSheet` ya no puede crear grupos (solo `kind='bot'`).

**Eliminados**
- `lib/clients/hermes/rooms_client.dart` (258 l.) — `groups.*` JSON-RPC muerto
  y con contrato inventado: `send` mandaba `{'text', 'client_event_id'}` donde
  el contrato es `{'event_id', 'payload'}`
  (`gateway-contract.generated.ts:1417-1428`, `tui_gateway/methods_groups.py:382-393`);
  `rename` omitía el `event_id` OBLIGATORIO (`:1410-1414`,
  `methods_groups.py:484-487`); `approve` pasaba `execution_generation` como
  `String` donde es `int` (`:1497-1503`); `create` no mandaba `room_id`
  (obligatorio, `:1372-1377`); el doc afirmaba «`groups.log` es delta y
  `groups.state` la lista» cuando el contrato sí expone `groups.list`
  (`:1325-1330`, `methods_groups.py:345-354`).

### Build y analyze

- `dart run build_runner build` (drift_dev): limpio, 78→51 outputs, sin
  warnings; `app_database.g.dart` regenerado con las 3 columnas.
- `dart analyze lib/features/conversations/ lib/data/database/
  lib/clients/hermes/connection_manager.dart`: 0 errores, 0 warnings; quedan
  3 `info` `use_build_context_synchronously` **preexistentes** en
  `conversations_screen.dart` (l.495/559/567), no introducidos aquí.
- No toqué `tools/fake_gateway.py` (propiedad compartida + Main lo tiene
  ocupado por adb en 9119). Ver §Pendiente.

## Pendiente / no hecho a propósito

1. **`fake_gateway.py` — BLOQUEADOR compartido (no lo toco; es de Main y hay
   E2E en curso).** Dos problemas verificables en el working tree de ahora
   mismo:
   - `def now()` está **borrada** (`git diff tools/fake_gateway.py` muestra
     `-def now() -> str:` en el bloque de helpers) y sin embargo siguen 5
     llamadas: l.82 `expires_at`, l.103 `gateway.ping`, **l.124 `updatedAt`**,
     **l.129 `log[0].at`**, l.198 `gateway.hello`. El proceso revienta al
     importar/servir. Pinta a colisión de ediciones: quien reordenó los helpers
     de auth quitó la función; quien añadió el envelope v3 añadió dos usos
     nuevos.
   - Bug de tipo aun restaurándola: `now()` devuelve string ISO, pero el
     snapshot real usa **milisegundos de época numéricos** —
     `updatedAt: Date.now()` (`group-chat.ts:306`) y
     `at: Number(entry?.at || 0)` (`:335`); el ranking de salas hace
     `Number(left.log[…].at)` (`:289-294`) y con un ISO da `NaN`, así que la
     sala sale mal ordenada y el recorte por presupuesto puede comérsela.
     Mínimo: `def now_ms() -> float: return time.time() * 1000` y usarla en
     l.124 y l.129.
   La **forma** del envelope que ya aplicaste es correcta
   (`tools/fake_gateway.py:120-135`: `version`, `updatedAt`, `deleted`,
   `rooms["id:room-1"]{name,roomId,revision,members,log}`) y añade lo que la
   app usa para feature-detectar CAS: `ui_meta_revisions:
   {"hermes-bots-groups": 1}` (`group-chat.ts:1020`), que sí está puesto.
   Con ese envelope, `room-1` debe materializarse como
   `<connectionId>/group/room-1` con título «Equipo» y 2 miembros.
2. **CAS / `foreign` en `profiles.configure`** → ChatFidelity (dueño de
   `bot_meta.dart` y `gateway_client.dart`). Le pasé el hallazgo y lo acepta;
   la pérdida real es `pinned`/`sectionId`/`sectionName`/`screenAutoOpen`/
   `created` (`types.ts:60-88`).
3. **No prometo sync bidireccional de grupos.** Pocket NO publica
   `hermes-bots-groups`: el espejo es la única copia on-disk de las salas del
   Desktop (`group-chat.ts:180-183`) y publicar una proyección más pobre las
   degradaría. Tampoco crea ni disuelve grupos: la creación y el disband de
   salas son del Desktop (no hay superficie `groups.create` en su UI, ver
   hallazgo). Lo que sí hace Pocket: mostrar las salas del espejo, sus
   miembros, su título canónico, orden/pin locales, y ocultar localmente sin
   tocar el gateway.
4. **Chat de grupos**: `chat_screen.dart:477-481` sigue rechazando enviar a un
   grupo con `_showGroupNotice()`. Correcto contra el contrato real (Desktop
   dirige las salas por su propio motor de turnos, `group-turns.ts`, y no hay
   `groups.send` en su UI), pero significa que la sala no es chateable desde
   Pocket — no es una promesa nueva, es la que ya hacía la app.
