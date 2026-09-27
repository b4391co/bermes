# Release 0.1.14 (2026-09-28)
Alineación con Hermes Desktop (historial compartido) + correcciones de flota y UI.

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
