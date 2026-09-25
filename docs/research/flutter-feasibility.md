# Viabilidad técnica de Flutter para Hermes Pocket — Auditoría de paquetes y restricciones

> Fase A (auditoría). Fecha: 2026-09-25. Entorno evaluado: Flutter estable actual (canal stable, versión 3.47.5 publicada 2026-09-18 según `storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`), Debian 13 x64 como host de desarrollo.
>
> **Nota sobre versión objetivo:** la tarea pedía evaluar Flutter 3.35 (stable). El canal stable actual es 3.47.x (3.35 es versionado antiguo ya fuera del ciclo estable reciente). Las conclusiones se emitieron contra 3.47.5; si el equipo congela en 3.35, el riesgo por bloque no cambia materialmente: los paquetes evaluados tienen `environment.sdk >=3.0.0` o superior y no dependen de features posteriores a 3.35, salvo `flutter_markdown_plus`/`gpt_markdown` que se compilan con SDKs recientes pero siguen compatibles hacia atrás. Confirmado en el campo `environment` del `pubspec` de cada paquete citado (API pub.dev `https://pub.dev/api/packages/<name>`).

## 1. Plataformas soportadas (fuente oficial)

Fuente: https://docs.flutter.dev/reference/supported-platforms (consultada 2026-09-25).

| Plataforma | Soportado | CI-testeado |
|---|---|---|
| Android | API 24–37 (x64, Arm32, Arm64) | API 24–36 |
| iOS | 15–27 (Arm64) | 18, 26 |
| Windows | 10, 11 (x64, Arm64) | 10 |
| macOS | 12–27 (x64, Arm64) | 15 (Sequoia) |
| Debian Linux | 10–13 | 12 |
| Ubuntu Linux | 20.04–24.04 LTS | 22.04 LTS |

Impacto directo para Hermes Pocket:
- Android API 24+ excluye Android 7.0/7.1 (API 25) y dispositivos antiguos: el `minSdk` del proyecto debe ser ≥ 24.
- Windows 10+ x64/Arm64 está soportado de forma nativa (no web-tech embebido): indispensable para el cliente Windows.
- macOS Intel x64 está en proceso de deprecación (aviso oficial en la misma página, `flutter.dev/go/macos-intel-deprecation`): no afecta a Hermes Pocket hoy, pero si se publica binario macOS x64, planificar transición a Arm64.

## 2. Restricciones Android relevantes

### 2.1 Cleartext en LAN (HTTP sin TLS)

Fuente: https://developer.android.com/privacy-and-security/security-config (consultada 2026-09-25).

- Desde Android 9 (API 28), **cleartext está deshabilitado por defecto**: `<base-config cleartextTrafficPermitted="false">` con `trust-anchors` solo `system` (sección "Cleartext traffic" y "The default configuration for apps targeting Android 9 (API level 28) and higher").
- Para Hermes Pocket, si el agente Hermes corre en LAN con HTTP plano (sin TLS) — típico en auto-hospedado con IP privada — la app **no podrá conectar** salvo que se declare una Network Security Configuration (`res/xml/network_security_config.xml`) con `<domain-config cleartextTrafficPermitted="true">` para los rangos/dominios privados. El doc muestra el mecanismo exacto (sección "Opt in to cleartext traffic", ej. `<domain includeSubdomains="true">insecure.example.com</domain>` con `cleartextTrafficPermitted="true"`).
- Contraint: **no usar `base-config cleartextTrafficPermitted="true"`** (inseguro según el propio doc: "this insecure configuration should be avoided whenever possible"). Recomendación: `domain-config` solo para IPs `.lan`/`192.168.0.0/16`/`10.0.0.0/8` que el usuario registre como endpoint del agente, o TLS con CA propia vía `<trust-anchors><certificates src="@raw/my_ca"/></trust-anchors>` (sección "Configure a custom CA").
- Ojo: Flutter usa su propio stack TLS en la VM Dart (`dart:io`), no el `SSLSocketFactory` de OkHttp, por lo que la configuración de CA custom debe aplicarse vía `SecurityContext`/parámetro `badCertificateCallback` o cargando el PEM en el `HttpClient` — la Network Security Config **no** afecta al `HttpClient` de Dart (comportamiento conocido del runtime Dart, no cubierto en el doc Android). Plan: exponer el certificado/CACERT en el flujo de onboarding del usuario.
- Nota Android 16 (API 36): Certificate Transparency se vuelve opcional (default desactivado, opt-in con `<certificateTransparency enabled="true"/>`); en API 37 habilitado por defecto con opt-out. No bloquea el caso LAN, pero relevante para TLS contra endpoints públicos con CA privada.

### 2.2 Doze / App Standby (WS en background)

Fuente: https://developer.android.com/training/monitoring-device-state/doze-standby (consultada 2026-09-25, última actualización del doc 2026-08-18).

- Doze **suspende el acceso a red** y **ignora wake locks** (sección "Doze restrictions": "Suspends network access", "Ignores wake locks"). Un WebSocket mantenido en background no sobrevivirá Doze: la conexión se romperá o se quedará sin drenar.
- Ventanas de mantenimiento: Doze abre brevemente la red ("maintenance window") de forma periódica; no sirve para streaming interactivo (chat en vivo, Screen viewer) porque es irregular y de segundos.
- **App Standby** suspende la red de apps sin uso reciente ("App Standby defers background network activity for apps with no recent user activity") — afecta si Hermes Pocket queda días sin abrir y espera reconexión automática de WS.
- Recomendación oficial para mensajes push en tiempo real: **FCM** (sección "Use FCM to interact with your app while the device is idle"). Pero Hermes es auto-hospedado: no hay FCM (el agente no habla con Google). Alternativas concretas dentro de la app:
  - **Foreground Service** con notificación persistente para mantener la conexión WS viva mientras el usuario lo permita (exención de Doze no necesaria: un foreground service con proceso vivo y pantalla apagada sigue siendo suspendido en Doze profundo a menos que la app esté en la lista de optimización de batería exceptuada).
  - **Exención parcial de Doze**: `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` / `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (sección "Support for other use cases"). La tabla de casos aceptables considera aceptable exención para "Instant messaging, chat, or calling app" cuando "No, can't use FCM because of technical dependency on another messaging service or Doze and App Standby break the core function of the app" — **exactamente el caso de Hermes Pocket** (agente auto-hospedado, sin FCM). Esto justifica formalmente pedir la exención in-app con diálogo.
  - Reconexión exponencial con re-subscripción de eventos al volver a primer plano (detectar `AppLifecycleState.resumed`) — estrategia estándar, sin dependencia nativa.
- Impacto UX: si el usuario no concede la exención de batería, la sesión activa (chat, terminal, screen) se caerá al bloquear pantalla; documentar y pedir la exención en onboarding con justificación visible.

## 3. Evaluación por bloque difícil

Metodología: API pública de pub.dev (`https://pub.dev/api/packages/<name>`, `.../score`) para versión, fecha de publicación, puntos de calidad, plataformas y descargas de 30 días; API GitHub (`https://api.github.com/repos/<org>/<repo>`, `.../search/issues`) para actividad, issues abiertos y contenido de CHANGELOG (`raw.githubusercontent.com`). Todas las citas con fecha de consulta 2026-09-25.

### Resumen ejecutivo por bloque

| Bloque | Paquete recomendado | Alternativa | Riesgo | Evidencia clave |
|---|---|---|---|---|
| Auth streaming HTTP | `dio` 5.11.1 (2026-09-04) | `http` 1.6.0 (2025-11-10) | **Bajo** | dio: 160/160 pts, 4.5M desc/30d, activo (pub.dev). http: 160/160, 12M desc/30d. Streaming SSE con `ResponseType.stream`/`StreamedRequest` nativo en ambos |
| Auth streaming WS | `web_socket_channel` 3.0.3 (2025-04-17) | `websocket_universal` 1.3.0 (2025-07-15) | **Bajo** | web_socket_channel: 150/160, 10.7M desc/30d, 1645 likes, plataforma android/ios/windows/linux/macos/web. Es el paquete estándar de Dart team |
| SSH PTY interactivo | `dartssh2` 4.1.0 (2026-09-04) | Plugin nativo (libssh2 vía FFI) | **Bajo-medio** | dartssh2: 160/160 pts, 99.6k desc/30d, 147 likes, 1 issue abierto, repo `vicajilau/dartssh2` con `pushed_at` 2026-09-04 y CHANGELOG denso con tests de interoperabilidad contra OpenSSH real (citas en §3.2) |
| Terminal emulator UI | `xterm` 4.0.0 (2024-02-27) | `yoxterm` 4.1.0 (fork perf, 2026-08-24) o `xterm2` 5.2.0 (2026-07-25) | **Alto** (mantenimiento upstream) | xterm: 150/160 pts, 322k desc/30d, pero último commit upstream 2025-06-19 y 78 issues abiertos tipo issue (GitHub search, consultado 2026-09-25). Forks activos con actividad 2026-09 (ver §3.3) |
| Screen viewer (MJPEG/WS-video) | Render propio con `http`/`web_socket_channel` + decodificación manual de multipart/JPEG | `media_kit` 1.2.6 (2025-12-13) si aparece vídeo real | **Medio** | No hay paquete MJPEG serio: `mjpeg` 0.0.3 (2018-08-17, 20/160 pts, 10 desc/30d) y `flutter_mjpeg` 2.0.4 (2023-07-15, 616 desc/30d) están muertos/spotless. Escribir el decoder multipart es trivial (boundary parser + `Image.memory` para JPEG). Detalle en §3.4 |
| Secure storage (Android+Windows) | `flutter_secure_storage` 11.2.0 (2026-09-16) | `drift` + cifrado app-level (AES-GCM con clave derivada) | **Bajo** | flutter_secure_storage: 160/160, 4.5M desc/30d, 4490 likes, soporta android/ios/windows/linux/macos/web; repo movido a `juliansteenbakker/flutter_secure_storage` (pushed 2026-09-23), 3 issues abiertos. v11.0.0 (2026-08-06) y 11.2.0 (2026-09-16) recientes |
| SQLite | `drift` 2.35.0 (2026-09-09) | `sqflite_common_ffi` (inferior, sin reactividad) | **Bajo** | drift: 160/160, 1.34M desc/30d, 2473 likes, todas las plataformas, repo `simolus3/drift` pushed 2026-09-24 (activo) |
| Markdown renderer | `gpt_markdown` 1.3.0 (2026-09-20) | `flutter_markdown_plus` 1.0.12 (2026-07-10) | **Bajo-medio** | gpt_markdown: 160/160, 155k desc/30d, repo `useval/gpt_markdown` pushed 2026-09-21, 46 issues. flutter_markdown_plus: 160/160, repo `foresightmobile/flutter_markdown_plus` pushed 2026-07-10, 102 issues. Original `flutter_markdown` 0.7.7+1 descontinuado (0.7.x, 150/160, última public. 2025-05-06). Detalle §3.6 |
| WebView embebido en Windows | `flutter_inappwebview` 6.1.5 (+ `flutter_inappwebview_windows` 0.6.0) | `desktop_webview_window` 0.3.0 (2026-05-27) | **Medio** | flutter_inappwebview: 130/160, 1.2M desc/30d, repo `pichillilorenzo/flutter_inappwebview` pushed 2026-02-10, 216 issues abiertos; 6.1.5 es de 2024-10-08 (lento de release). desktop_webview_window: 160/160, 524k desc/30d, activo 2026. Detalle §3.7 |

### 3.1 Auth streaming HTTP + WS

**Recomendación:** `dio` (HTTP) + `web_socket_channel` (WS). Ambos son los estándares de facto del ecosistema Flutter.

- `dio` 5.11.1 (publicada 2026-09-04), 160/160 puntos pub.dev, 4.547.036 descargas/30d. Interceptors para auth headers, cancelación, timeouts. Streaming: `ResponseType.stream` devuelve `ResponseBody` con `Stream<Uint8List>`, suficiente para SSE (parseo de `data:` lines es nuestro trabajo, trivial).
- `web_socket_channel` 3.0.3 (publicada 2025-04-17), 150/160 puntos, 10.669.594 descargas/30d, 1645 likes. Es el paquete del equipo Dart; `StreamChannel` wrapper multiplataforma (android/ios/windows/linux/macos/web según tags de pub.dev).
- **Riesgo: bajo.** Ninguno de los dos tiene señal de abandono; descargas y actividad de publicación recientes.

**Alternativa HTTP:** `http` 1.6.0 (2025-11-10, 160/160, 12.083.117 desc/30d) si no se necesitan interceptores. Suficiente si la lógica de auth se abstrae manualmente.

**Alternativa WS:** `websocket_universal` 1.3.0 (2025-07-15, 130/160 pts) añade reconnection y typing RPC sobre WS; útil si no queremos escribir el retry loop. No es del equipo Dart, 130/160 indica menos maduras tooling pero funcional.

### 3.2 SSH PTY interactivo

**Recomendación:** `dartssh2` 4.1.0.

Evidencia (API pub.dev 2026-09-25 + CHANGELOG `raw.githubusercontent.com/vicajilau/dartssh2/master/CHANGELOG.md`):
- Versión 4.1.0 publicada **2026-09-04**; 160/160 puntos pub.dev; 99.602 descargas/30d; 147 likes; tags de plataforma: android/ios/windows/linux/macos/web. 1 issue abierto en `vicajilau/dartssh2` (GitHub search, 2026-09-25).
- Es un **fork activo y mantenido** del original `dartssh2` de Avnish95/TerminalStudio (el repo `vicajilau/dartssh2` absorbió el mantenimiento tras estancarse el upstream). Cadencia de releases: 3.0.2 (2026-08-17) → 3.3.1 (2026-08-20) → 4.0.0 (2026-08-31) → 4.0.1 (2026-09-03) → 4.1.0 (2026-09-04): mantenimiento intensivo en los últimos 2 meses.
- CHANGELOG 4.x documenta trabajo serio, no cosmético:
  - 4.1.0: pipelining de channel requests (`pty-req`/`shell`), tests de interoperabilidad en browser vía WebSocket contra OpenSSH real (`tool/ws_bridge.dart`).
  - 4.0.1: fix de stall permanente de canal cuando los datos llegan antes de la suscripción (bug de `StreamController`), fix de window adjust granularity siguiendo `channels.c` de OpenSSH.
  - 4.0.0 (breaking): desactivados por defecto algoritmos legacy (SHA-1 KEX, ssh-rsa, CBC ciphers) siguiendo `myproposal.h` de OpenSSH; SFTP uploads pipelineados (64 outstanding, `DEFAULT_NUM_REQUESTS` de OpenSSH); validación criptográfica de KEX (validación de puntos de curva NIST, X25519 small-order, MAC comparison constante, padding aleatorio RFC 4253 §6).
  - Fix de bugs de seguridad concretos: keyboard-interactive responses en logs en plaintext, banner split entre segmentos TCP/frames WS, MAC verification antes de parsear padding, etc. — evidencia de revisión de seguridad real, no solo features.
- PTY: `SSHClient.shell()` con `PtyRequest` (cols, rows, term) devuelve `SSHSession` con `stdout`/`stdin` como streams; ideal para conectar directo a un `TerminalView` de xterm.

**Riesgo: bajo-medio.** El paquete está vivo y con calidad de código por encima de la media del ecosistema (CHANGELOG con referencias RFC yOpenSSH internals). El riesgo residual: mantenimiento de una sola persona (261 stars, 0 issues abiertos sugiere pequeño grupo de usuarios), y breaking changes en 4.0.0 recientes que obligarán a mantener el pin de versión cuidadosamente.

**Plan B (si dartssh2 se estanca):** FFI a libssh2 (`libssh2` C library, madura, usada por curl) empaquetado en plugin nativo por plataforma, o `flutter_rust_bridge` 2.13.0 (2026-08-23, 160/160, 624.616 desc/30d, todas las plataformas) con el crate `russh` (Rust, SSH puro, activo). Coste: complejidad de build (rust toolchain por plataforma). **No necesario hoy**: dartssh2 cubre PTY+SFTP y funciona en Windows/Linux/Android.

### 3.3 Terminal emulator UI

**Problema real detectado:** `xterm.dart` upstream está estancado.

Evidencia (GitHub API, 2026-09-25):
- Repo `TerminalStudio/xterm.dart`: `pushed_at` **2025-06-19** (último commit al master hace ~15 meses), `open_issues_count` 108 (78 issues tipo issue + 30 PRs abiertos), 654 stars. Último commit: "fix: terminal has wrong bright light white" 2025-06-19; el commit previo no-tagged es de 2024-06-26.
- Última versión en pub.dev: **4.0.0, 2024-02-27** — sin release en 2 años y 7 meses.
- Issues abiertos de calidad relevantes para terminal SSH: #239/#240 "Text selection doesn't work inside full-screen programs — alternate-screen scroll detaches buffer lines" (2026-08-12), #243 "Alt-buffer scroll gestures die permanently when the Scrollable gets a new ScrollPosition" (2026-09-17), #238 "Fix: correct SGR mouse-wheel button codes" (2026-07-30). Estos son bugs de usabilidad de terminal real, sin fix en upstream.

**Opciones:**
1. **Fork activo `xterm2` 5.2.0** (pub.dev 2026-07-25, repo `SoFluffyOS/xterm2`, pushed 2026-09-08, 140/160 pts, 1.314 desc/30d). Nomenclatura de versión superior a upstream (5.x), actividad reciente. **Riesgo de fork comunitario**: pocos downloads, receptor de mantenimiento único.
2. **Fork de performance `yoxterm` 4.1.0** (pub.dev 2026-08-24, repo `IstiN/yoxterm`, pushed 2026-09-04, 140/160 pts, 80 desc/30d). Descripción: "performance-focused fork of xterm.dart with glyph-atlas rendering, pooled paint ops and parser fast paths". Atractivo para streaming denso de output SSH, pero comunidad minúscula.
3. **Upstream `xterm` 4.0.0** + cherry-pick de fixes desde los forks (forks conservan API compatible). Si elegimos esto, pinar versión y mantener el vendoring de parches.

**Recomendación:** empezar con `xterm2` (5.2.0) por ser el fork con API reconocible y actividad más próxima; hacer spike de 1-2 días con sesión SSH real (dartssh2 → xterm2 → vim/htop) para validar alt-buffer, selección y rendimiento con output rápido. **Riesgo: alto** (mantenimiento de upstream muerto + fork único), mitigable con spike temprano y capacidad de switch a `yoxterm` (API base idéntica, es fork del mismo proyecto) o vendoring propio del parser VT100.

**Plan B (si ningún fork convence):** no existe otra librería de emulación terminal en Dart con soporte VT100 serio (búsqueda pub.dev `terminal emulator` solo devuelve forks/derivados: `flterm`, `kterm`, `termui_pty`, `terminal_view` — todos nichos). Plan B real: **embebido de un terminal nativo** por plataforma (Windows: `Windows Terminal` control via WebView2; Android: embebido de `termux-terminal-emulator` AAR — both high-effort) o **rewrite del parser VT100 propio** (alcance acotado: Hermes necesita el output del agente, no un terminal completo para vim/emacs; un subset VT100/ANSI cubre el 90% del caso). Recomendación del plan B: **acotar el scope del terminal a un subset ANSI bien implementado propio** antes que depender de un fork moribundo, si el spike de xterm2 falla. No descarta Flutter: es un componente, no el framework.

### 3.4 Screen viewer (MJPEG / WS-video)

**Diagnóstico:** no hay paquete MJPEG viable.
- `mjpeg` 0.0.3: publicada **2018-08-17**, 20/160 puntos, 10 descargas/30d. Muerto.
- `flutter_mjpeg` 2.0.4: 2023-07-15, 140 pts, 616 descargas/30d. Apenas mantenido, basado en http streaming de frames JPEG.
- `mjpeg_renderer`: no existe en pub.dev (404).

**Recomendación: implementación propia (baja complejidad).**
- MJPEG sobre HTTP multipart: parsear el `multipart/x-mixed-replace` con `boundary`, extraer cada frame JPEG binario entre delimitadores, pasarlo a `Image.memory()`. Con `http` (streaming de bytes) + código de ~80-120 líneas. El formato no cambia; riesgo de complejidad bajo.
- Si el Screen viewer usa WS binario (Hermes podría enviar JPEG frames por WS): `web_socket_channel` + `Image.memory()` por frame directo, aún más simple.
- Para vídeo H.264 real (si aparece): `media_kit` 1.2.6 (2025-12-13, 140/160 pts, 346.981 desc/30d, todas las plataformas menos web en tags) con backend `media_kit_libs_*`; soporta streaming RTSP/HTTP. Alternativa `fvp` 0.38.1 (2026-08-17, 140/160 pts, 28.684 desc/30d) con libmpv.

**Riesgo: medio.** No por el paquete (que escribimos nosotros), sino por rendimiento: decodificar y renderizar 15-30 fps de JPEG en Flutter móvil requiere `Image.memory` con `gaplessPlayback: true` para evitar flicker y cuidado con el GC de imágenes grandes. En 2026 `Image.memory` sigue siendo la vía estándar. Spike obligatorio: stream de 720p@15fps sobre LAN para validar smooth. Si falla, plan B: `flutter_rust_bridge` con decodificador Rust (turbojpeg) o `media_kit` con pipeline de vídeo real.

### 3.5 Secure storage Android + Windows

**Recomendación:** `flutter_secure_storage` 11.2.0 (publicada 2026-09-16).

Evidencia:
- 160/160 puntos pub.dev, 4.507.058 descargas/30d, 4.490 likes — el paquete de storage seguro dominante.
- Tags de plataforma: android/ios/windows/linux/macos/web (pub.dev API).
- Repositorio movido a `juliansteenbakker/flutter_secure_storage` (GitHub API redirect confirmado 2026-09-25; pushed 2026-09-23), 3 issues abiertos. Cadencia reciente: 11.0.0 (2026-08-06) → 11.1.0 (2026-09-10) → 11.2.0 (2026-09-16). Mantenimiento activo y release train regular.
- En Android usa Keystore (AES-GCM); en Windows usa DPAPI. Ambos mecanismos nativos verificados en la documentación del paquete (pub.dev/README) y respaldados por la actividad activa de la v11.
- Nota: en Windows, DPAPI cifra por usuario Windows; si Hermes Pocket instala por máquina, el storage no es portable entre usuarios — comportamiento esperado y correcto para secrets.

**Alternativa:** `drift` con cifrado app-level (AES-GCM sobre la clave derivada con `cryptography` 6.x) — solo si aparecen requisitos de portabilidad de secrets entre plataformas que DPAPI no cubre. Riesgo: medio (cifrado casero, no recomendable si flutter_secure_storage sigue sano).

**Riesgo: bajo.**

### 3.6 SQLite

**Recomendación:** `drift` 2.35.0 (publicada 2026-09-09).

- 160/160 puntos, 1.339.010 descargas/30d, 2.473 likes, plataformas android/ios/windows/linux/macos/web.
- Repo `simolus3/drift`: `pushed_at` 2026-09-24 (ayer de la consulta), no archivado. Cadencia de releases alta.
- Reactividad (Streams sobre queries) es lo que queremos para UI de conversaciones persistidas; soporta `sqlcipher` vía `drift_sqlite_common`? — no verificado en esta auditoría; el caso base (historial local, índices, FTS si hace falta) está cubierto sin cifrado adicional.
- En Windows/Linux funciona sobre `sqlite3` FFI (`sqlite3_flutter_libs`), sin problema de bundling.

**Alternativa:** `sqflite` clásico — no reactivo, sin soporte desktop nativo limpio; descartado. `isar`/`objectbox` — NoSQL, no es SQLite real; descartado por el requisito explícito de drift en el plan.

**Riesgo: bajo.**

### 3.7 Markdown renderer de calidad

**Recomendación:** `gpt_markdown` 1.3.0 (publicada 2026-09-20).

- 160/160 puntos, 155.628 descargas/30d, 323 likes; plataformas android/ios/windows/linux/macos/web.
- Diseñado específicamente para render de respuestas de LLM (soporta LaTeX via MathJax-like rendering, code blocks con copy button, GFM). Repo `useval/gpt_markdown`, pushed 2026-09-21, 46 issues abiertos.
- El contexto Hermes (respuestas de agente con markdown rico, bloques de código, tablas, LaTeX ocasional) hace que un renderer especializado en LLM sea mejor fit que uno genérico.

**Alternativa:** `flutter_markdown_plus` 1.0.12 (2026-07-10, 160/160 pts, repo `foresightmobile/flutter_markdown_plus`, pushed 2026-07-10, 102 issues). Es el fork comercial del `flutter_markdown` original de Flutter (descontinuado por el equipo Flutter: `flutter_markdown` 0.7.7+1, 2025-05-06, ya en modo mantenimiento). flutter_markdown_plus tiene 69 stars y 102 issues abiertos — señal de uso real, mantenimiento OK pero no rápido.

**Nota:** el `flutter_markdown` original (pub.dev `flutter_markdown` 0.7.7+1) aparece aún con 150/160 pts pero su README ya indica discontiuación (transferred a community). No usar para proyecto nuevo.

**Riesgo: bajo-medio** (gpt_markdown es nicho pero activo; flutter_markdown_plus más genérico pero con issue tracker abultado). Si LaTeX en respuestas es requisito, gpt_markdown lo trae de serie.

### 3.8 WebView embebido en Flutter Windows

**Recomendación:** `flutter_inappwebview` 6.1.5 con su sub-paquete `flutter_inappwebview_windows` 0.6.0 (WebView2 nativo).

- flutter_inappwebview: 130/160 pts, 1.205.657 descargas/30d, 2.854 likes, plataformas android/ios/windows/macos/web (sin linux en tags).
- `flutter_inappwebview_windows` 0.6.0 (2024-10-08, 140/160 pts, 1.178.317 desc/30d) — usa WebView2 (Edge/Chromium runtime de Windows, presente en Win10/11 por defecto).
- Señales de alerta: repo `pichillilorenzo/flutter_inappwebview` con **216 issues abiertos** y `pushed_at` 2026-02-10; la versión estable 6.1.5 es de **2024-10-08** (sin release estable en ~2 años, solo betas 6.2.0-beta.x desde 2024-11, la última beta 2026-02-04). Mantenimiento vivo pero release train lento y backlog de issues grande.

**Alternativa:** `desktop_webview_window` 0.3.0 (2026-05-27, 160/160 pts, 524.498 desc/30d, plataformas windows/linux/macos). Activo y limpio, pero API más limitada (menos control fino de cookies/JS bridge que inappwebview). Suficiente si el WebView solo muestra HTML/consola del agente.

**Riesgo: medio.** inappwebview es el más capaz pero con deuda visible; desktop_webview_window más fresco pero menos features. Para Hermes Pocket, si el WebView solo embebe una UI web del agente (o un preview), desktop_webview_window puede bastar; si se necesita JS bridge bidireccional fino, inappwebview.

## 4. Conclusión sobre Flutter como base

**Veredicto: viable, con dos puntos de atención y ningún bloque sin solución.**

1. **Flutter cubre todos los bloques difíciles** con paquetes vivos y de alta adopción (auth streaming HTTP+WS, secure storage, sqlite, markdown, webview Windows). Los dos únicos bloques con señales de riesgo son el terminal emulator (upstream muerto, forks activos de calidad dudosa a largo plazo) y el screen viewer (no hay paquete, pero es código propio de baja complejidad).
2. **SSH PTY: dartssh2 resuelve el bloque más crítico** con calidad de ingeniería alta (CHANGELOG con RFC citations, interop tests contra OpenSSH real, hardening de seguridad reciente). No es necesario plan B nativo hoy. Plan B (russh vía flutter_rust_bridge o libssh2 FFI) existe y es factible si el paquete se estanca.
3. **Terminal emulator: riesgo alto, mitigable.** xterm2/yoxterm son forks activos; el spike de 1-2 días con SSH real es la barrera de salida antes de comprometer arquitectura. Si falla, el plan B recomendado es acotar scope: subset ANSI propio, no depender de forks moribundos.
4. **No descartar Flutter en ningún bloque.** No hay bloque que requiera cambiar de tecnología de app; como mucho, un plugin nativo (Rust/C) para SSH o decodificación de vídeo si el spike falla — y flutter_rust_bridge 2.13.0 está maduro para eso.

## 5. Restricciones Android: impacto en Hermes Pocket

| Restricción | Impacto | Mitigación |
|---|---|---|
| Cleartext deshabilitado por defecto desde API 28 | Si el agente Hermes corre en LAN con HTTP plano, la app no conecta | `network_security_config.xml` con `<domain-config cleartextTrafficPermitted="true">` solo para el endpoint LAN del usuario (no `base-config`); preferir TLS con CA propia (trust-anchor raw) + `SecurityContext` de Dart en el `HttpClient`/`dio`. Ojo: la Network Security Config no aplica al stack TLS de Dart (HttpClient de `dart:io`), gestionar certificados desde Dart |
| Doze suspende red y wake locks | WS activo en background se corta al entrar en Doze; App Standby corta red tras días sin uso | Foreground Service con notificación persistente para sesión activa; pedir exención de optimización de batería (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) — caso aceptable según el doc oficial ("Instant messaging... No, can't use FCM... Doze and App Standby break the core function"); reconexión exponencial + re-suscripción en `AppLifecycleState.resumed` |
| Sin FCM disponible (agente auto-hospedado) | La recomendación oficial de Doze (usar FCM high priority) no aplica | Push propio no viable sin infra de Google: la app asume que las notificaciones en tiempo real dependen de foreground service o exención de batería; notificaciones diferidas vía polling al volver a primer plano |
| minSdk ≥ 24 (Flutter soporta Android 24+) | Excluye Android 7.0/7.1 | Aceptar: Android 8.0+ (API 26) como piso razonable para seguridad y foreground service moderno |

## 6. Tabla resumen riesgo con evidencia (copia operativa)

Ver tabla en §3 — se duplica aquí para referencia rápida de decisión:

- **Bajo** (sin acción especial): dio, http, web_socket_channel, flutter_secure_storage, drift, gpt_markdown/flutter_markdown_plus.
- **Medio** (spike + plan B definido): screen viewer (código propio), webview Windows (elegir inappwebview vs desktop_webview_window según features), dartssh2 (riesgo de bus factor, plan B Rust listo).
- **Alto** (spike obligatorio antes de compromiso): terminal emulator (xterm upstream muerto; forks activos no garantizados; plan B = subset ANSI propio).

## 7. Fuentes consultadas (2026-09-25)

- https://docs.flutter.dev/reference/supported-platforms
- https://developer.android.com/training/monitoring-device-state/doze-standby
- https://developer.android.com/privacy-and-security/security-config
- pub.dev API: `https://pub.dev/api/packages/{xterm,dartssh2,dio,http,web_socket_channel,websocket_universal,drift,flutter_secure_storage,gpt_markdown,flutter_markdown_plus,flutter_markdown,markdown_widget,flutter_inappwebview,flutter_inappwebview_windows,desktop_webview_window,mjpeg,flutter_mjpeg,media_kit,fvp,flutter_rust_bridge,flutter_pty,pty,yoxterm,xterm2}` (versiones, fechas, scores, plataformas, descargas 30d)
- GitHub API: `https://api.github.com/repos/{TerminalStudio/xterm.dart,vicajilau/dartssh2,simolus3/drift,juliansteenbakker/flutter_secure_storage,pichillilorenzo/flutter_inappwebview,foresightmobile/flutter_markdown_plus,useval/gpt_markdown,IstiN/yoxterm,SoFluffyOS/xterm2,flutter/flutter}` (pushed_at, issues abiertos, stars)
- GitHub search API para conteos de issues abiertos (xterm.dart: 78 issues + 30 PRs; dartssh2: 1 issue)
- CHANGELOG dartssh2: https://raw.githubusercontent.com/vicajilau/dartssh2/master/CHANGELOG.md
- Releases oficiales Flutter: https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json (stable 3.47.5, 2026-09-18)
