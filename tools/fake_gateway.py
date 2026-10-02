#!/usr/bin/env python3
"""Fake gateway Hermes: implementa el contrato DOCUMENTADO en
docs/protocol/hermes-map.md para prueba de integración de Hermes Pocket.

Endpoints:
  POST /auth/password-login  {provider:"basic",username,password} → cookies hermes_session_at/rt
  POST /api/auth/ws-ticket   (requiere sesión) → {ticket, ttl_seconds:30}
  GET  /api/health           → 200 {ok:true}
  WS   /api/ws?ticket=<t>    → RPC {id,method,params} → {id,result} + eventos

RPC soportados: gateway.ping, prompt.submit, session.interrupt, groups.*,
messages.history. Tras prompt.submit emite message.start/delta*/complete.
"""
import asyncio, json, os, sys, time, uuid, base64
from aiohttp import web, WSMsgType

USERS = {"test": "hermespass"}
INTERRUPTED = set()  # session_ids con session.interrupt en vuelo
RUNTIME_SESSIONS: set[str] = set()  # ids vivos minteados por session.resume
USERS_PROVIDERS = {"basic"}
MODE = {"canonical": True, "prompt_error": False, "researcher_canonical": False, "approval": False,
        "session_token": False}
GATEWAY_TOKEN = "loopback-session-token-1"
SRQ = {"id": "srq-test000000", "pending": None, "answered": None}
SESSION_COOKIE = "hermes_session_at"
REFRESH_COOKIE = "hermes_session_rt"
TICKETS: dict[str, float] = {}
DISPLAY = {"state": "stopped", "lease": None}
DISPLAY_TICKETS: dict[str, float] = {}


async def display_ws(request: web.Request) -> web.WebSocketResponse:
    """WS hermana de pantalla (web_routers/display.py): valida el ticket
    single-use de display.observe y anuncia el cierre inmediato — el fake NO
    implementa RFB; sirve para verificar que la app pide el ticket correcto."""
    t = request.query.get("display_ticket", "")
    if t not in DISPLAY_TICKETS or DISPLAY_TICKETS[t] < time.time():
        return web.Response(status=401, text="invalid display ticket")
    del DISPLAY_TICKETS[t]
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    await ws.close(code=4000, message=b"fake-no-rfb")
    return ws
import hashlib
ROOMS: dict[str, dict] = {}
ROOM_LOGS: dict[str, list] = {}
LIVE_WS: list = []


def _room_ev(rid: str, seq: int, kind: str, actor: dict, payload: dict) -> dict:
    return {"room_id": rid, "seq": seq, "event_id": f"e{seq}",
            "kind": kind, "actor": actor, "authority_epoch": 1,
            "payload": payload, "created_at": time.time(), "idempotent": False}


async def _emit_turn(ws, sid: str, ack_id=None, seq_start: int = 2) -> None:
    """Emite un turno con deltas lentos; session.interrupt lo corta."""
    INTERRUPTED.discard(sid)
    print(f"EV emit start sid={sid}", flush=True)
    await ws.send_str(json.dumps({"method": "event", "params": {
        "type": "message.start", "session_id": sid, "payload": {}, "seq": 1}}))
    for n, chunk in enumerate(("Hola", ", soy ", "el bot ", "de prueba."), start=2):
        await asyncio.sleep(1.0)
        if sid in INTERRUPTED:
            INTERRUPTED.discard(sid)
            await ws.send_str(json.dumps({"method": "event", "params": {
                "type": "message.complete", "session_id": sid,
                "payload": {"text": " ".join(("Hola", ", soy ", "el bot ", "de prueba.")[:n-1]),
                           "status": "interrupted"}, "seq": n}}))
            if ack_id is not None:
                await ws.send_str(json.dumps({"id": ack_id, "result": {"status": "streaming"}}))
            return
        await ws.send_str(json.dumps({"method": "event", "params": {
            "type": "message.delta", "session_id": sid,
            "payload": {"text": chunk}, "seq": n}}))
    await ws.send_str(json.dumps({"method": "event", "params": {
        "type": "message.complete", "session_id": sid,
        "payload": {"text": "Hola, soy el bot de prueba."}, "seq": 6}}))
    if ack_id is not None:
        await ws.send_str(json.dumps({"id": ack_id, "result": {"status": "streaming"}}))


async def _broadcast_room(rid: str, ev: dict) -> None:
    frame = json.dumps({"method": "event", "params": {
        "type": "room.event", "payload": {"room_id": rid, "event": ev}, "seq": ev["seq"]}})
    for ws in list(LIVE_WS):
        try:
            await ws.send_str(frame)
        except Exception:
            LIVE_WS.remove(ws)


async def _bot_reply(rid: str, user_ev: dict) -> None:
    """El driver del fake: contesta al usuario como 'default' tras 0.6s."""
    await asyncio.sleep(0.6)
    logs = ROOM_LOGS.get(rid) or []
    ev = _room_ev(rid, (logs[-1]["seq"] if logs else 0) + 1, "message.member",
                  {"kind": "member", "profile": "default", "handle": "default",
                   "display_name": "Compi"},
                  {"text": f"(hosted) Eco de Compi: {user_ev['payload']['text']}",
                   "thread_id": user_ev["payload"]["thread_id"]})
    logs.append(ev)
    await _broadcast_room(rid, ev)

# Sala hosted REAL equivalente al espejo del Desktop (roomId 'room-1'):
ROOMS["room-1"] = {"room_id": "room-1", "name": "Equipo",
                   "members": [{"profile": "default", "handle": "default"},
                               {"profile": "researcher", "handle": "researcher"}]}
ROOMS["room-2"] = {"room_id": "room-2", "name": "Mezcla",
                   "members": [{"profile": "default", "handle": "default"},
                               {"profile": "researcher", "handle": "researcher"}]}
ROOM_LOGS["room-2"] = [
    _room_ev("room-2", 1, "room.created", {"kind": "gateway", "id": "fake-gw-1"},
             {"name": "Mezcla"}),
]
ROOM_LOGS["room-1"] = [
    _room_ev("room-1", 1, "room.created", {"kind": "gateway", "id": "fake-gw-1"},
             {"name": "Equipo"}),
    _room_ev("room-1", 2, "message.user", {"kind": "user", "id": "desktop"},
             {"text": "hola equipo", "thread_id": "t-seed"}),
    _room_ev("room-1", 3, "message.member",
             {"kind": "member", "profile": "default", "handle": "default",
              "display_name": "Compi"},
             {"text": "(hosted) ¡Hola! Soy Compi en la sala.", "thread_id": "t-seed"}),
]


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def now_ms() -> float:
    # El envelope v3 del espejo usa ms de época (group-chat.ts:306,335).
    return time.time() * 1000



def authed(request: web.Request) -> bool:
    if request.cookies.get(SESSION_COOKIE) == "valid-session":
        return True
    # Modo loopback (web_server.py:440-449): X-Hermes-Session-Token o Bearer.
    if MODE["session_token"]:
        header = request.headers.get("x-hermes-session-token") or ""
        auth = request.headers.get("authorization") or ""
        if header == GATEWAY_TOKEN or auth == f"Bearer {GATEWAY_TOKEN}":
            return True
    return False


@web.middleware
async def log_middleware(request: web.Request, handler):
    resp = await handler(request)
    print(f"GW {request.method} {request.path_qs} -> {resp.status}", flush=True)
    return resp


async def auth_me(request: web.Request) -> web.Response:
    """GET /api/auth/me (routes.py:449-455): identidad de la sesión vigente.
    En modo loopback el session token basta (401 sin él)."""
    print("AUTHME headers:",
          {k: v[:22] for k, v in request.headers.items()
           if k.lower() in ("x-hermes-session-token", "authorization",
                            "cookie", "user-agent")},
          flush=True)
    if not authed(request):
        return web.json_response({"detail": "Unauthorized"}, status=401)
    return web.json_response({
        "user_id": "user-1", "email": "test@local", "display_name": "Test",
        "org_id": None, "provider": "basic", "expires_at": None})

async def auth_providers(request: web.Request) -> web.Response:
    # Contrato real: GET /api/auth/providers (dashboard_auth/routes.py:183-192).
    return web.json_response({
        "providers": [{"name": "basic", "display_name": "Basic",
                       "supports_password": True}],
    })


async def api_status(request: web.Request) -> web.Response:
    # Contrato real: GET /api/status público (web_routers/status.py:366-380).
    return web.json_response({"auth_required": True, "version": "0.18.0-fake",
                              "providers": ["basic"]})


async def health(request: web.Request) -> web.Response:
    return web.json_response({"ok": True, "service": "hermes-gateway-fake"})


async def password_login(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": {"code": "bad_request", "message": "json"}}, status=400)
    # El contrato real (routes.py:372) exige `provider` == el nombre del
    # proveedor registrado. Aceptamos el nombre real ('basic') sin alias:
    # los clientes deben resolver el nombre vía GET /api/auth/providers.
    if body.get("provider") not in USERS_PROVIDERS:
        return web.json_response({"error": {"code": "unsupported_provider", "message": "provider"}}, status=400)
    if USERS.get(body.get("username")) != body.get("password"):
        # 401 genérico como el real (routes.py:400-410: no distingue usuario
        # inexistente de contraseña mala).
        return web.json_response({"error": {"code": "invalid_credentials", "message": "Credenciales inválidas"}}, status=401)
    resp = web.json_response({"ok": True, "next": "/"})
    resp.set_cookie(SESSION_COOKIE, "valid-session", max_age=12 * 3600, path="/")
    resp.set_cookie(REFRESH_COOKIE, "refresh-token-1", max_age=30 * 24 * 3600, path="/", httponly=True)
    return resp


async def native_refresh(request: web.Request) -> web.Response:
    body = await request.json()
    if body.get("refresh_token") != "refresh-token-1":
        return web.json_response({"error": {"code": "invalid_refresh", "message": "rt"}}, status=401)
    return web.json_response({
        "access_token": "access-2", "refresh_token": "refresh-token-2",
        "expires_at": now(), "provider": "basic", "user_id": "u1",
    })


async def ws_ticket(request: web.Request) -> web.Response:
    # Auth real: cookie de sesión O Bearer (middleware.py:166-174).
    bearer = (request.headers.get("Authorization") or "").removeprefix("Bearer ")
    if not authed(request) and not bearer.startswith("tok"):
        return web.json_response({"error": {"code": "unauthorized", "message": "no session"}}, status=401)
    ticket = uuid.uuid4().hex
    TICKETS[ticket] = time.time() + 30
    print(f"GW mint ticket={ticket}", flush=True)
    return web.json_response({"ticket": ticket, "ttl_seconds": 30})


BOT_META = {"title": "Compi", "description": "Bot con meta hermes-mobile",
           "avatar": {"shape": "circle", "color": "#1a7f5a"},
           "groups": ["Equipo"], "group": "Equipo"}
META_REVS = {"hermes-bots": 1}  # CAS por clave ui_meta (methods_profiles.py:575-611)
GROUPS_META: dict = {}

# Modelo vigente del perfil (ProfileRow.model/provider; PUT /profiles/{n}/model lo escribe).
PROFILE_MODEL = {"provider": "nous", "model": "Hermes-4-405B"}


def rpc_result(method: str, params: dict) -> object:
    if method == "model.options":
        # Contrato real (config_free_tier_control.py:213-281): providers con
        # slug/models/is_current/authenticated + model/provider vigentes.
        return {"providers": [
            {"slug": "nous", "name": "Nous Research", "authenticated": True,
             "models": ["Hermes-4-405B", "Hermes-4-70B"],
             "is_current": PROFILE_MODEL["provider"] == "nous"},
            {"slug": "openrouter", "name": "OpenRouter", "authenticated": True,
             "models": ["anthropic/claude-sonnet-4", "openai/gpt-5-mini"],
             "is_current": PROFILE_MODEL["provider"] == "openrouter"},
        ], "model": PROFILE_MODEL["model"], "provider": PROFILE_MODEL["provider"]}
    if method == "gateway.ping":
        return {"pong": True, "ts": now()}
    # --- Screen (contrato display.* verificado en hermes-map §6 y fuente real
    #     e408d36: tui_gateway display.py). El fake emula status/observe/lease;
    #     la RFB hermana NO se emula: el visor fallará al conectar (esperado).
    if method == "display.status":
        return {"status": DISPLAY["state"], "lease": DISPLAY["lease"], "vnc_available": True}
    if method == "display.start":
        DISPLAY["state"] = "running"
        return {"status": "running", "lease": DISPLAY["lease"]}
    if method == "display.stop":
        DISPLAY["state"] = "stopped"
        DISPLAY["lease"] = None
        return {"status": "stopped", "lease": None}
    if method == "display.observe":
        if DISPLAY["state"] != "running":
            return {"error": {"code": "display_not_running", "message": "stopped"}}
        t = uuid.uuid4().hex
        DISPLAY_TICKETS[t] = time.time() + 30
        return {"ticket": t, "path": "/api/display/ws",
                "viewer_id": params.get("viewer_id"), "status": "running"}
    if method == "display.lease.acquire":
        DISPLAY["lease"] = {"holder": "human", "viewer_id": params.get("viewer_id"),
                            "reason": params.get("reason"), "epoch": int(time.time())}
        return {"status": DISPLAY["state"], "lease": DISPLAY["lease"]}
    if method == "display.lease.release":
        DISPLAY["lease"] = None
        return {"status": DISPLAY["state"], "lease": None}
    if method == "prompt.submit":
        if MODE["prompt_error"]:
            return {"error": {"code": "session_not_found",
                              "message": f"unknown session {params.get('session_id')!r}"}}
        # Contrato REAL (_sess_nowait, tui_gateway/server.py:1173-1187): sólo
        # sesiones VIVAS aceptan turnos. Un id no minteado por resume → 4001.
        sid = str(params.get("session_id") or "")
        if sid not in RUNTIME_SESSIONS:
            return {"error": {"code": 4001, "message": "session not found"}}
        return {"status": "streaming"}
    if method == "session.interrupt":
        return {"interrupted": True}  # el corte real lo aplica el emisor (ws_handler)
    if method == "messages.history":
        return {"messages": [], "pagination": {"has_more": False}}
    if method == "profiles.list":
        return {"profiles": [
            {
                "name": "default",
                "display_name": "Default Bot",
                "description": "Bot principal de pruebas",
                "is_default": True,
                # Envelope REAL v3 del espejo (group-chat.ts:68-80,296-320), no {groups:[...]}.
                "ui_meta": {
                    "hermes-bots": dict(BOT_META),
                    # El espejo PUBLICADO si hay; si no, el de fábrica.
                    **({"hermes-bots-groups": dict(GROUPS_META)} if GROUPS_META else {
                        "hermes-bots-groups": {
                            "version": 3, "updatedAt": now_ms(),
                            "rooms": {
                                "id:room-1": {
                                    "name": "Equipo", "roomId": "room-1", "revision": 1,
                                    "members": [{"name": "default"}, {"name": "researcher"}],
                                    "log": [{"at": now_ms(), "from": {"kind": "user", "name": "You"}, "text": "hola"}],
                                },
                                # Sala mixta del escenario del usuario (0.1.24):
                                # dos bots del MISMO espejo multi-gateway. El
                                # fake es un solo gateway, así que ambos perfiles
                                # viven aquí; la dueña la elige el orden del sync.
                                "id:room-2": {
                                    "name": "Mezcla", "roomId": "room-2", "revision": 1,
                                    "members": [{"name": "default"}, {"name": "researcher"}],
                                },
                            },
                            "deleted": {},
                        },
                    }),
                },
                "ui_meta_revisions": dict(META_REVS),
                "canonical_session": ({"id": "sess-canonical-default", "resolved_id": "sess-canonical-default-r", "title": "Bot Chat"} if MODE["canonical"] else None),
            },
            {
                "name": "researcher",
                "display_name": "Researcher",
                "is_default": False,
                "ui_meta": {"hermes-bots": {"description": "Bot de investigación", "avatar": {"shape": "square", "color": "#7a3fd0"}}},
                "canonical_session": ({"id": "sess-canonical-researcher", "resolved_id": "sess-canonical-researcher-r", "title": "Bot Chat"} if MODE["canonical"] else None),
            },
        ]}
    if method == "profiles.configure":
        um = params.get("ui_meta", {})
        expected = params.get("ui_meta_expected_revisions")
        if isinstance(expected, dict):
            for key, want in expected.items():
                actual = META_REVS.get(key, 0)
                if want != actual:
                    return {"ok": False,
                            "applied": {"ui_meta": False, "ui_meta_conflicts":
                                        {key: {"expected": want, "actual": actual}},
                                        "ui_meta_revisions": dict(META_REVS)}}
        for key, val in um.items():
            if key == "hermes-bots":
                # El gateway REAL reemplaza la sección entera (methods_profiles.py
                # :575-611): el cliente manda la proyección completa ya fusionada
                # con las claves crudas. Merge + filtro de vacíos era mentira del
                # fake: impedía borrar `groups` y enmascaraba el CAS.
                BOT_META.clear()
                BOT_META.update(val or {})
            elif key == "hermes-bots-groups":
                GROUPS_META.clear()
                GROUPS_META.update(val or {})
            META_REVS[key] = META_REVS.get(key, 0) + 1
        return {"ok": True, "applied": {"ui_meta": True}}
    if method == "profiles.get_asset":
        if params.get("name") != "default":
            raise ValueError("no avatar")
        # PNG 8x8 rojo (visible en screenshots, a diferencia del 1x1).
        png = ("iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4"
               "nGN47JP5Hx9mGBkKAG7jpcHQzqtjAAAAAElFTkSuQmCC")
        return {"data_url": f"data:image/png;base64,{png}"}
    if method == "session.list":
        prof = params.get("profile", "default")
        return {"sessions": [
            {"session_id": f"sess-{prof}-1", "title": "Refactor parser",
             "preview": "último mensaje de prueba", "message_count": 12},
            {"session_id": f"sess-{prof}-2", "title": "Ideas bot",
             "preview": "otra sesión", "message_count": 3},
        ]}
    if method == "session.resume":
        if not MODE["canonical"]:
            return {"error": {"code": "not_found", "message": "no bot chat"}}
        prof = params.get("profile", "default")
        # Cada perfil tiene SU propio Bot Chat (canonical_session con
        # resolved_id distinto). Contrato REAL (methods_session.py:65-67,
        # 819-835): el resume mintea un RUNTIME id NUEVO y el cliente debe
        # usarlo en prompt.submit/session.interrupt; un submit con otro id
        # devuelve 4001 "session not found" (_sess_nowait, server.py:1173+).
        sid = f"rt-{uuid.uuid4().hex[:8]}"
        RUNTIME_SESSIONS.add(sid)
        return {"session_id": sid, "session_key": f"sess-canonical-{prof}",
                "status": "idle", "message_count": 0, "messages": [],
                "info": {}, "inflight": None, "running": False,
                "started_at": time.time()}
    if method == "groups.capabilities":
        return {"protocol_version": 2, "driver": "hosted",
                "authority_gateway_id": "fake-gw-1",
                "methods": ["groups.capabilities", "groups.list", "groups.create",
                            "groups.state", "groups.send", "groups.log",
                            "groups.rename", "groups.disband", "groups.approve"]}
    if method == "groups.state":
        rid = params.get("room_id")
        room = ROOMS.get(rid) or {"room_id": rid, "name": "Test Room",
                                  "members": [{"profile": "default", "handle": "default"}]}
        return {"room": {**room, "authority_gateway_id": "fake-gw-1",
                         "authority_epoch": 1, "revision": 1},
                "driver_status": {"state": "idle"}}
    if method == "groups.log":
        rid = params.get("room_id")
        since = int(params.get("since_seq") or 0)
        evs = ROOM_LOGS.get(rid, [])
        page = [e for e in evs if e["seq"] > since][:int(params.get("limit") or 100)]
        return {"events": page,
                "cursor": page[-1]["seq"] if page else since,
                "latest_seq": evs[-1]["seq"] if evs else 0,
                "has_more": False,
                "authority": {"gateway_id": "fake-gw-1", "epoch": 1}}
    if method == "groups.create":
        rid = params.get("room_id")
        if not rid or not isinstance(rid, str):
            raise ValueError("room_id required")
        if rid in ROOMS:
            # idempotencia por contenido: mismo id+mismo contenido -> mismo room
            same = ROOMS[rid]["name"] == params.get("name")
            if not same:
                return {"error": {"code": "conflict", "message": "room_id busy"}}
        else:
            ROOMS[rid] = {"room_id": rid, "name": params.get("name"),
                          "members": params.get("members") or []}
            ROOM_LOGS[rid] = [_room_ev(rid, 1, "room.created",
                                       {"gateway_id": "fake-gw-1"},
                                       {"name": params.get("name")})]
        return {"room": {**ROOMS[rid], "authority_gateway_id": "fake-gw-1",
                         "authority_epoch": 1, "revision": 1},
                "idempotent": True}
    if method == "groups.send":
        rid = params.get("room_id")
        ev_id = params.get("event_id")
        payload = params.get("payload") or {}
        # Validación EXACTA como hosted_room_discussion._validate_user_payload:
        # campos {text, thread_id} justemente.
        if set(payload.keys()) != {"text", "thread_id"}:
            return {"error": {"code": "invalid", "message": "user payload fields"}}
        room = ROOMS.get(rid)
        if room is None:
            return {"error": {"code": "not_found", "message": "no room"}}
        logs = ROOM_LOGS.setdefault(rid, [])
        # idempotencia por event_id del cliente -> user:<sha>
        key = "user:" + hashlib.sha256(str(ev_id).encode()).hexdigest()
        for e in logs:
            if e["event_id"] == key:
                return {"event": e, "client_event_id": ev_id, "accepted": True,
                        "driver_started": True}
        ev = _room_ev(rid, (logs[-1]["seq"] if logs else 0) + 1, "message.user",
                      {"kind": "user", "id": "desktop"}, payload)
        ev["event_id"] = key
        logs.append(ev)
        # El driver del fake responde al cabo de un momento (message.member):
        asyncio.ensure_future(_bot_reply(rid, ev))
        return {"event": ev, "client_event_id": ev_id, "accepted": True,
                "driver_started": True}
    if method == "groups.rename":
        rid = params.get("room_id")
        if not params.get("event_id"):
            return {"error": {"code": "invalid", "message": "event_id required"}}
        if rid in ROOMS:
            ROOMS[rid]["name"] = params.get("name")
            ev = _room_ev(rid, len(ROOM_LOGS.get(rid, [])) + 1, "room.renamed",
                          {"kind": "gateway", "id": "fake-gw-1"},
                          {"name": params.get("name")})
            ROOM_LOGS.setdefault(rid, []).append(ev)
        return {"room": {**(ROOMS.get(rid) or {}), "revision": 2}}
async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    # Modo loopback: ?token= vale como credencial de upgrade
    _t = request.query.get("ticket", "")
    if _t:
        print(f"WSDIAG ticket={_t} presente={_t in TICKETS} edad={round(time.time()-TICKETS.get(_t,0),1) if _t in TICKETS else '-'}s", flush=True)
        print("WSDIAG headers:", dict(request.headers), flush=True)
    # (web_server_chat.py:291-297). Modo gated: ticket single-use.
    if MODE["session_token"]:
        if request.query.get("token", "") != GATEWAY_TOKEN:
            # Antes del upgrade no hay WS: rechazar la petición HTTP
            # (el gateway real responde 401 en el handshake).
            return web.Response(status=401, text="invalid token")
    else:
        ticket = request.query.get("ticket", "")
        if ticket not in TICKETS or TICKETS[ticket] < time.time():
            return web.Response(status=401, text="invalid ticket")
        del TICKETS[ticket]  # single-use

    ws = web.WebSocketResponse()
    await ws.prepare(request)
    LIVE_WS.append(ws)
    # Primer frame servidor→cliente: gateway.ready (tui_gateway/ws.py:324-331).
    await ws.send_str(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {
        "type": "gateway.ready", "payload": {"skin": "default", "change_events": True,
                                             "heartbeat": True, "replay_epoch": uuid.uuid4().hex}, "seq": 0}}))

    async for msg in ws:
        if msg.type != WSMsgType.TEXT:
            continue
        try:
            frame = json.loads(msg.data)
        except Exception:
            continue
        rid, method, params = frame.get("id"), frame.get("method", ""), frame.get("params") or {}
        print(f"GW-RPC {method} {json.dumps(params)[:400]}", flush=True)
        if method == "client.capabilities":
            # El gateway real CONTESTA el rpc (response con el id) además de
            # habilitar server-requests: sin respuesta, el await del cliente
            # se queda hasta el timeout.
            await ws.send_str(json.dumps({"id": rid, "result": {"ok": True}}))
            if MODE.get("approval"):
                # Server-request `approval` real (server_requests.py:61-63):
                await ws.send_str(json.dumps({
                    "jsonrpc": "2.0", "id": SRQ["id"], "method": "approval",
                    "params": {"session_id": "sess-canonical-default-r",
                               "request_id": "apr-1",
                               "tool_name": "bash",
                               "command": "sudo rm -rf /tmp/x",
                               "description": "Borrar dir de prueba",
                               "choices": ["once", "session", "always", "deny"]}}))
            continue
        if "result" in frame and isinstance(rid, str) and rid.startswith("srq-"):
            # Frame de RESULTADO de un server-request: el backend lo resuelve
            # en resolve_response (server_requests.py:201+).
            SRQ["answered"] = frame.get("result")
            print(f"GW-SRQ answered {rid}: {json.dumps(frame.get('result'))[:200]}",
                  flush=True)
            continue
        if method == "prompt.submit":
            sid = str(params.get("session_id", "s1"))
            # Contrato REAL (_sess_nowait): sólo sesiones vivas aceptan turnos.
            if sid not in RUNTIME_SESSIONS:
                await ws.send_str(json.dumps({"id": rid, "error": {
                    "code": 4001, "message": "session not found"}}))
                continue
            if not MODE.get("slow_turn"):
                # ACK inmediato y turno de 1s: deja ventana limpia para
                # verificar 'Detener' + session.interrupt E2E.
                await ws.send_str(json.dumps({"id": rid, "result": {"status": "streaming"}}))
                asyncio.ensure_future(_emit_turn(ws, sid, seq_start=1))
                continue
            # Turno LARGO: NO se responde hasta message.complete (comportamiento
            # de gateway real con turnos lentos) — pone a prueba el camino de
            # timeout de ACK. El bucle sigue leyendo session.interrupt.
            asyncio.ensure_future(_emit_turn(ws, sid, ack_id=rid, seq_start=1))
            continue
        if method == "prompt.fail_test":
            await ws.send_str(json.dumps({"id": rid, "error": {"code": 500, "message": "boom"}}))
            continue
        if method == "session.interrupt":
            sid = params.get("session_id", "s1")
            print(f"EV interrupt pedido sid={sid}", flush=True)
            INTERRUPTED.add(sid)
            await ws.send_str(json.dumps({"id": rid, "result": {"status": "interrupted",
                                                                 "interrupted": [sid]}}))
            continue
        # (El gateway real 0.18 no publica session.create/session.list por WS
        #  -> rpc_result cae en {"ok": true}, que el cliente descarta por
        #  no traer session_id. Solo HTTP publica la sesión.)
        if method == "session.list":
            # El contrato real admite {profile, title} como filtro.
            p = params or {}
            if "title" in p:
                # La lista filtrada dice la VERDAD por perfil: 'Bot Chat'
                # existe solo si resume no mintió con otro perfil (se usa el
                # mismo modo researcher_canonical que controla resume).
                prof = p.get("profile", "default")
                exists = (prof != "researcher") or MODE.get("researcher_canonical")
                if p["title"] == "Bot Chat" and MODE["canonical"] and exists:
                    await ws.send_str(json.dumps({"id": rid, "result": {"sessions": [
                        {"session_id": f"sess-canonical-{prof}-r", "title": "Bot Chat"}]}}))
                else:
                    await ws.send_str(json.dumps({"id": rid, "result": {"sessions": []}}))
                continue
        if method == "session.events.since":
            # Contrato real (tui_gateway): {events:[...], latest_seq, truncated}.
            # El fake NO mantiene anillo de eventos por sesión: responder vacío
            # y coherente, nunca {"ok":true} (que dejaría el hold de la app sin
            # flush y perdería los eventos en vivo de esa sesión).
            await ws.send_str(json.dumps({"id": rid, "result": {
                "events": [], "latest_seq": 0, "truncated": False}}))
            continue
        res = rpc_result(method, params)
        if isinstance(res, dict) and "error" in res:
            await ws.send_str(json.dumps({"id": rid, "error": {
                "code": -32001, "message": res["error"].get("code", "error")}}))
        else:
            await ws.send_str(json.dumps({"id": rid, "result": res}))
    LIVE_WS.remove(ws)
    return ws



async def session_messages(request: web.Request) -> web.Response:
    if not authed(request):
        return web.json_response({"error": "unauthorized"}, status=401)
    sid = request.match_info["sid"]
    limit = int(request.query.get("limit", "50"))
    return web.json_response({
        "messages": [
            {"id": f"{sid}-m1", "role": "user", "text": "hola bot",
             "created_at": 1770000000},
            {"id": f"{sid}-m2", "role": "assistant", "text": "Hola, soy el bot de prueba.",
             "created_at": 1770000001},
            # Historial "de Desktop": demuestra que la app ve la MISMA sesión
            {"id": f"{sid}-m3", "role": "user", "text": "quien eres",
             "created_at": 1770000002},
            {"id": f"{sid}-m4", "role": "assistant", "text": "Soy Compi, tu bot.",
             "created_at": 1770000003},
        ][:limit],
        "pagination": {"has_more": False, "offset": 0},
    })

async def session_create(request: web.Request) -> web.Response:
    body = await request.json()
    prof = body.get("profile", "default")
    sid = f"sess-canonical-{prof}"
    # UNIQUE(title) por perfil: la misma fila que ya ve Desktop (canonical=1).
    return web.json_response({"session_id": sid, "id": sid,
                              "title": body.get("title", "Bot Chat")})


async def set_mode(request: web.Request) -> web.Response:
    if "canonical" in request.query:
        MODE["canonical"] = request.query["canonical"] == "1"
    if "prompt_error" in request.query:
        MODE["prompt_error"] = request.query["prompt_error"] == "1"
    if "researcher" in request.query:
        MODE["researcher_canonical"] = request.query["researcher"] == "1"
    if "approval" in request.query:
        MODE["approval"] = request.query["approval"] == "1"
    if "session_token" in request.query:
        MODE["session_token"] = request.query["session_token"] == "1"
    return web.json_response(dict(MODE))

async def test_srq(request: web.Request) -> web.Response:
    """Emite un server-request `approval` al WS vivo más reciente (prueba E2E)."""
    if not LIVE_WS:
        return web.json_response({"error": "no live ws"}, status=409)
    ws = LIVE_WS[-1]
    await ws.send_str(json.dumps({
        "jsonrpc": "2.0", "id": SRQ["id"], "method": "approval",
        "params": {"session_id": request.query.get("sid", "sess-canonical-default-r"),
                   "request_id": "apr-1", "tool_name": "bash",
                   "command": "sudo rm -rf /tmp/x",
                   "description": "Borrar dir de prueba",
                   "choices": ["once", "session", "always", "deny"]}}))
    return web.json_response({"sent": SRQ["id"]})


async def test_emit(request: web.Request) -> web.Response:
    """Inyección de prueba: emite un evento arbitrario a todos los WS vivos."""
    body = await request.json()
    frame = json.dumps({"method": "event", "params": {
        "type": body["type"], "session_id": body.get("session_id"),
        "payload": body.get("payload", {}), "seq": int(time.time())}})
    for ws in list(LIVE_WS):
        try:
            await ws.send_str(frame)
        except Exception:
            LIVE_WS.remove(ws)
    return web.json_response({"sent": frame[:80]})


async def rest_profiles(request: web.Request) -> web.Response:
    """GET /api/profiles: mismo roster que profiles.list (contrato Desktop)."""
    if not authed(request):
        return web.json_response({"error": "unauthorized"}, status=401)
    return web.json_response({"profiles": rpc_result("profiles.list", {})["profiles"]})

async def profile_model_put(request: web.Request) -> web.Response:
    # PUT /api/profiles/{name}/model (profiles.py:1040-1051): {provider, model}
    # required, ambos strip; 400 si faltan.
    body = await request.json()
    provider = str(body.get("provider") or "").strip()
    model = str(body.get("model") or "").strip()
    if not provider or not model:
        return web.json_response({"detail": "provider and model are required"}, status=400)
    PROFILE_MODEL["provider"] = provider
    PROFILE_MODEL["model"] = model
    print(f"GW PUT model {request.match_info['name']} -> {provider}/{model}", flush=True)
    return web.json_response({"ok": True, "provider": provider, "model": model})


def main() -> None:
    app = web.Application()
    app.middlewares.append(log_middleware)
    app.router.add_get("/api/health", health)
    app.router.add_post("/api/test/emit", test_emit)
    app.router.add_post("/api/test/srq", test_srq)
    app.router.add_get("/api/profiles", rest_profiles)
    app.router.add_get("/api/mode", set_mode)
    app.router.add_post("/api/sessions", session_create)

    app.router.add_get("/api/auth/providers", auth_providers)
    app.router.add_get("/api/auth/me", auth_me)
    app.router.add_post("/auth/password-login", password_login)
    app.router.add_post("/auth/native/refresh", native_refresh)
    app.router.add_post("/api/auth/ws-ticket", ws_ticket)
    app.router.add_put("/api/profiles/{name}/model", profile_model_put)
    app.router.add_get("/api/ws", ws_handler)
    app.router.add_get("/api/display/ws", display_ws)
    port = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FAKE_PORT", "9120"))
    web.run_app(app, host="0.0.0.0", port=port, print=None,
                access_log_format='%r -> %s')

if __name__ == "__main__":
    main()
