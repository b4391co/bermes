# Alineación móvil ↔ Hermes Desktop (verificado 2026-09-28)

## Sesión canónica de bot ("Bot Chat")
- La **crea el Desktop** al abrir el bot por primera vez (título único por
  perfil, `UNIQUE(title)` en el backend). El gateway 0.18 **no** la crea al
  hacer `session.resume{title}` si todavía no existe.
- `session.resume{title}` es la **única** forma correcta de adjuntarse: el
  móvil nunca debe crear sesiones por perfil desde el WS
  (`session.create{profile}` no existe en 0.18 → `-32000`; y el HTTP
  `POST /api/sessions` del fake creaba duplicados "Bot Chat (2)" que
  ocultaban el historial real).
- **Procedimiento para el usuario**: abrir cada bot una vez en Hermes Desktop
  (o enviarle un mensaje desde Desktop). A partir de ahí, móvil y Desktop
  comparten siempre la misma sesión e historial.
- Si un perfil aún no tiene sesión canónica, la app lo muestra honestamente
  (bot marcado `requiere sesión en Desktop` en la lista) en lugar de inventar
  una sesión paralela.

## Historial
- `session.resume{title}` responde con `messages` (el historial real del
  Desktop, hasta el límite del gateway). La app lo arrastra al abrir el chat
  (`SyncService.pull`), reconciliando por `role+text+ts≈` y deduplicando lo
  ya enviado localmente.
- No hay endpoint que exponga historial anterior al límite del gateway; la app
  no promete más de lo que `session.history` da.

## Grupos
- Grupos de Desktop (`ui_meta.groups`) = metadatos **locales de Desktop**: no
  existe endpoint de room en el gateway que el móvil pueda usar para escribir
  en ellos. La app los **lista** (vía `GET /api/groups` donde el gateway lo
  expone; en 0.18 real solo aparecen si el gateway los sincroniza) y bloquea
  el envío con aviso: *lo dirige Desktop*. Los bots miembros se siguen
  pudiendo abrir individualmente (misma sesión canónica).
- No se crea NINGÚN grupo desde el móvil: cero duplicados, cero riesgo de
  pisar metadatos ajenos.

## Herdr
- La resolución del binario via SSH exige rutas absolutas que terminen en
  `/herdr` (un `.bashrc` con banner/prompt contaminante ya no rompe el
  snapshot de la flota).
