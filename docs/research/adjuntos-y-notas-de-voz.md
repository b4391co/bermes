# Adjuntos (imágenes) y notas de voz — investigación y plan

Verificado contra la fuente `main` de NousResearch/hermes-agent (GitHub raw),
descargada y leída directamente (no de memoria):

- `tui_gateway/contracts/prompt_voice.py` (adjuntos: líneas 80-215)
- `tui_gateway/contracts/common.py:224-228` (`SessionParams`)
- `hermes_cli/web_routers/audio.py` (693 líneas: transcribe, voice-config, speak, tts-lease, stt-lease, speak-stream)
- `docs/research/hermes-protocol.md` §1.5/§2.5 (citas de commit `3be17b1`/`e408d36` ya en este repo)

## A. Adjuntos de imagen (chat 1-a-1)

Contrato WS JSON-RPC (todos `params = SessionParams` → **exigen `session_id`
obligatorio y `profile?` opcional**, common.py:224-228):

|Método|Params|Result|
|---|---|---|
|`image.attach`|`{path}` (ruta gateway-visible, admite "remainder text")|`AttachedImageResult`|
|`image.attach_bytes`|`{content_base64 \| data, filename?, ext?}` — **magic bytes deciden el tipo**|`AttachedImageResult`|
|`pdf.attach`|`{path \| content_base64, first_page?, last_page?}` → PNGs|`PdfAttachResult {attached, filename, pages_attached, pages[], count, text}`|
|`file.attach`|`{path \| data_url, name?}`|`FileAttachResult {attached, name, path, ref_path, ref_text, uploaded}`|
|`image.detach`|`{path}`|`{detached, count}`|

`AttachedImageResult` (prompt_voice.py:83-101):
`{attached: bool, path?, count?, remainder?, text?, bytes?, message?, name?, width?, height?, token_estimate?}`
— la imagen queda **en cola para el siguiente turno** (`methods_prompt.py::_attached_image_result`),
no se envía sola: hay que mandar después `prompt.submit`.

**Flujo correcto del Pocket** (es lo que hace Desktop, session-states.ts:1426):
1. `session.resume` → runtime id vivo (el Pocket ya lo tiene: `_ensureResumed`).
2. `image.attach_bytes {session_id: runtimeId, profile, content_base64, filename}`.
3. `prompt.submit {session_id, text}` (el texto puede ser vacío: la imagen adjunta
   ya constituye el turno; si no hay texto se omite la validación del composer).
4. Si el usuario cancela antes de enviar: `image.detach {session_id, path}`.

**Límites**: no hay tope declarado en el contrato Pydantic para
`image.attach_bytes`; referencia cercana: `profiles.set_asset` 2 MB
(`methods_profiles.py:431`). **El Pocket pone el suyo propio y lo anuncia
(8 MB antes de base64), no lo infiere del backend.**

**Recuperación para pintar**: el `path` devuelto es gateway-visible;
hermes-protocol.md §1.5 lista `GET /api/media` y `GET /api/fs/read-data-url`
(files.py:251-757) como las rutas de lectura. **La forma exacta del query no
está verificada en el commit objetivo** → el Pocket la resuelve en tiempo de
ejecución y, si `/api/media` 404, guarda la imagen local (bytes ya en RAM) y
muestra una burbuja con `🖼 nombre` en vez de fallar. No se pinta un spinner
eterno ni se inventa una URL.

**Grupos (rooms/hosted): NO soportado.** `groups.send` valida el payload con
`extra="forbid"` y exige exactamente `{text, thread_id}`
(`hosted_room_discussion._validate_user_payload`, replicada en
`tools/fake_gateway.py:478-479`). `RoomLinkCatalog.attachments: bool` es sóla
la capability del canal peer HTTP, no un canal de subida del cliente. → El
botón de adjunto se oculta en grupos, con motivo explícito en el tooltip.

## B. Notas de voz

**No existe tipo «nota de voz» en el contrato.** Ni `audio.attach`, ni campo
de audio en `RoomEvent`, ni `TranscriptMessage` con binario. La voz del
backend es STT→texto, nunca un adjunto persistido. Lo que sí existe:

1. `POST /api/audio/transcribe` (audio.py:83-145) — **verificado en fuente
   `main` @ `5f23cac` (2026-10-01)**:
   - body JSON `{data_url}` (campo `data_url`, NO `data`): debe empezar por
     `data:` y llevar `,` (`data:<mime>;base64,<b64>`); si no → 400 `bad_payload`
     (audio.py:87-91). `mime_type` NO se manda: se lee del prefijo del data-url.
   - tope `_MAX_TRANSCRIPTION_UPLOAD_BYTES` = 25 MB → 413 (`Audio recording is
     too large`, audio.py:108); `mime` del prefijo debe ser `audio/*` o
     `video/webm`, si no → 400.
   - sin STT configurado → **400 (NO 503)** con `detail: 'No STT provider
     configured'` + lista de proveedores; grabación no reconocida → 200 con
     `transcript: ""` (silencio: la app lo trata como fallo legible, no ok).
   - escribe un temporal con la extensión del mime (`.webm/.ogg/.m4a/.mp3/.wav/.flac`,
     audio.py:43-45) y llama `tools.voice_mode.transcribe_recording`
     (filtra alucinaciones de Whisper) **bajo el scope de config del perfil**
     (`_run_config_scoped`).
   - respuesta: `{ok: true, transcript, provider, ...}`.
   → **Android puede grabar `.m4a` (AAC) o `.ogg/opus` y mandarlo sin
   transcodificar**: la whitelist de extensiones del backend lo cubre.
2. `GET /api/audio/voice-config` (audio.py:146-175) — permite *client-direct
   voice*: el cliente llama al provider STT directamente y sólo el texto viaja.
   El Pocket **no** lo usa en la primera versión: depende de claves del
   proveedor en el teléfono; se queda en el relay.
3. `voice.record` / `voice.toggle` / `voice.tts` (prompt_voice.py:333-410) son
   el modo voz **del host** (micrófono en la máquina del gateway, VAD,
   wake-word): no aplican a un cliente remoto; `voice.record start` ordena
   grabar AL GATEWAY, no al teléfono. No usar.

**Decisión de producto**: la «nota de voz» del Pocket = grabación local →
transcripción vía `/api/audio/transcribe` → texto al chat, etiquetada
visualmente como nota de voz transcrita y **editable antes de enviar**
(el usuario decide si manda el texto tal cual). El audio NO se conserva como
historial (el backend no lo guarda); se dice en la UI, no se simula.
Si el gateway no tiene STT, `/api/audio/transcribe` falla con 400 (NO 503) +
`detail`: el error se clasifica (sin STT ≠ payload ≠ red ≠ sesión) en el
diagnóstico y se ofrece el camino mínimo alternativo: `file.attach` del audio
→ ref `@file:` (el bot puede leerlo si tiene herramienta de audio; NO es un
reproductor, y así se describe).

## C. Estado de la app (antes de este cambio)

- Composer: `chat_screen.dart:_composer` — sólo TextField + botón enviar/detener.
- Envío: `chat_screen.dart:_send` → `ChatSessionController.send(text)` (bot) o
  `_sendGroup` (rooms). `send()` usa `_ensureResumed()` y `prompt.submit` con el
  runtime id.
- Modelo `ChatMessage` y tabla `Messages`: sin campo de adjuntos.
- `HermesGatewayClient.rawCall(method, params)` ya existe (gateway_client.dart:525).
- `HermesHttpClient` ya tiene el transporte autenticado reutilizable
  (`_authorized`, cookies+bearer) — base para `/api/audio/transcribe` y `/api/media`.
- Dependencias: `file_picker ^13.1.0` (Android+Windows), `dio`, `path_provider`.
  Sin micrófono todavía (`record`) ni `RECORD_AUDIO` en el manifest.
- `tools/fake_gateway.py` no implementaba adjuntos ni audio.

## D. Implementación (dos entregables, ambos verificados contra fake)

1. **Imágenes (bots)**: botón clip → `FilePicker` → límite de tamaño propio →
   `image.attach_bytes` con el runtime id → `prompt.submit` → burbuja con
   miniatura (bytes de `/api/media` o fallback local). Persistencia en
   `Messages.attachmentsJson`. Oculto en grupos (motivo en tooltip).
2. **Notas de voz (bots)**: `record` (m4a) + permiso `RECORD_AUDIO` +
   grabación con temporizador/cancelación → `transcribeAudio()` →
   previsualización editable → envío como texto etiquetado.
   Diagnóstico differentiate (STT no configurado ≠ red ≠ sesión).
   Fake gateway: `POST /api/audio/transcribe` + `image.attach_bytes` +
   `file.attach` + `GET /api/media` + modo `?stt=off` para probar el 503.

No se implementa: reproductor de audio, voice-live, TTS, adjuntos en grupos,
`/api/chat/image-upload` (multipart HTTP) — el canal WS único
(`image.attach_bytes`) basta y evita un segundo camino de credenciales.
