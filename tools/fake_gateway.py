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
import asyncio, json, time, uuid, base64
from aiohttp import web, WSMsgType

USERS = {"test": "hermespass"}
MODE = {"canonical": True, "prompt_error": False}
SESSION_COOKIE = "hermes_session_at"
REFRESH_COOKIE = "hermes_session_rt"
TICKETS: dict[str, float] = {}


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def authed(request: web.Request) -> bool:
    return request.cookies.get(SESSION_COOKIE) == "valid-session"


@web.middleware
async def log_middleware(request: web.Request, handler):
    resp = await handler(request)
    print(f"GW {request.method} {request.path_qs} -> {resp.status}", flush=True)
    return resp


async def health(request: web.Request) -> web.Response:
    return web.json_response({"ok": True, "service": "hermes-gateway-fake"})


async def password_login(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": {"code": "bad_request", "message": "json"}}, status=400)
    if body.get("provider") != "basic":
        return web.json_response({"error": {"code": "unsupported_provider", "message": "provider"}}, status=400)
    if USERS.get(body.get("username")) != body.get("password"):
        return web.json_response({"error": {"code": "invalid_credentials", "message": "bad user/pass"}}, status=401)
    resp = web.json_response({"user": {"id": "u1", "username": body["username"]}})
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
    if not authed(request):
        return web.json_response({"error": {"code": "unauthorized", "message": "no session"}}, status=401)
    ticket = uuid.uuid4().hex
    TICKETS[ticket] = time.time() + 30
    return web.json_response({"ticket": ticket, "ttl_seconds": 30})


BOT_META = {"title": "Compi", "description": "Bot con meta hermes-mobile",
           "avatar": {"shape": "circle", "color": "#1a7f5a"}}


def rpc_result(method: str, params: dict) -> object:
    if method == "gateway.ping":
        return {"pong": True, "ts": now()}
    if method == "prompt.submit":
        if MODE["prompt_error"]:
            return {"error": {"code": "session_not_found",
                              "message": f"unknown session {params.get('session_id')!r}"}}
        return {"status": "streaming"}
    if method == "session.interrupt":
        return {"interrupted": True}
    if method == "messages.history":
        return {"messages": [], "pagination": {"has_more": False}}
    if method == "profiles.list":
        return {"profiles": [
            {
                "name": "default",
                "display_name": "Default Bot",
                "description": "Bot principal de pruebas",
                "is_default": True,
                "ui_meta": {"hermes-bots": dict(BOT_META)},
                "canonical_session": ({"id": "sess-canonical-default", "resolved_id": "sess-canonical-default-r", "title": "Bot Chat"} if MODE["canonical"] else None),
            },
            {
                "name": "researcher",
                "display_name": "Researcher",
                "description": "Bot de investigación",
                "is_default": False,
                "canonical_session": ({"id": "sess-canonical-researcher", "title": "Bot Chat"} if MODE["canonical"] else None),
            },
        ]}
    if method == "profiles.configure":
        um = params.get("ui_meta", {}).get("hermes-bots", {})
        BOT_META.update({k: v for k, v in um.items() if v})
        return {"ok": True}
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
    if method == "session.create":
        return {"session_id": f"sess-created-{params.get('profile', 'default')}"}
    if method == "session.resume":
        if not MODE["canonical"]:
            return {"error": {"code": "not_found", "message": "no bot chat"}}
        if params.get("profile") == "researcher":
            return {"session_id": "sess-canonical-researcher"}
        return {"session_id": "sess-canonical-default"}
    if method == "groups.capabilities":
        return {"groups": True, "approval": ["once", "session", "always", "deny"]}
    if method == "groups.state":
        return {"room": {"id": params.get("room_id"), "name": "Test Room", "members": [
            {"id": "bot-1", "kind": "bot", "name": "default", "gateway": "fake"}]}}
    if method == "groups.log":
        return {"events": [], "latest_seq": 0, "has_more": False}
    if method == "groups.create":
        return {"room": {"id": "room-1", "name": params.get("name"), "members": params.get("members", [])}}
    if method in ("groups.rename", "groups.disband", "groups.send", "groups.approve"):
        return {"ok": True}
    return {"ok": True}


async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    ticket = request.query.get("ticket", "")
    if ticket not in TICKETS or TICKETS[ticket] < time.time():
        await request.send_str(json.dumps({"error": "invalid ticket"}))
        return web.WebSocketResponse()
    del TICKETS[ticket]  # single-use
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    await ws.send_str(json.dumps({"method": "event", "params": {
        "type": "gateway.hello", "payload": {"server": "fake", "ts": now()}, "seq": 0}}))

    async for msg in ws:
        if msg.type != WSMsgType.TEXT:
            continue
        try:
            frame = json.loads(msg.data)
        except Exception:
            continue
        rid, method, params = frame.get("id"), frame.get("method", ""), frame.get("params") or {}
        if method == "prompt.submit":
            await ws.send_str(json.dumps({"id": rid, "result": {"status": "streaming"}}))
            sid = params.get("session_id", "s1")
            await ws.send_str(json.dumps({"method": "event", "params": {
                "type": "message.start", "session_id": sid, "payload": {}, "seq": 1}}))
            for chunk in ("Hola", ", soy ", "el bot ", "de prueba."):
                await asyncio.sleep(0.2)
                await ws.send_str(json.dumps({"method": "event", "params": {
                    "type": "message.delta", "session_id": sid,
                    "payload": {"text": chunk}, "seq": 2}}))
            await ws.send_str(json.dumps({"method": "event", "params": {
                "type": "message.complete", "session_id": sid,
                "payload": {"text": "Hola, soy el bot de prueba."}, "seq": 3}}))
            continue
        if method == "prompt.fail_test":
            await ws.send_str(json.dumps({"id": rid, "error": {"code": 500, "message": "boom"}}))
            continue
        res = rpc_result(method, params)
        if isinstance(res, dict) and "error" in res:
            await ws.send_str(json.dumps({"id": rid, "error": {
                "code": -32001, "message": res["error"].get("code", "error")}}))
        else:
            await ws.send_str(json.dumps({"id": rid, "result": res}))
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
        ][:limit],
        "pagination": {"has_more": False, "offset": 0},
    })

async def session_create(request: web.Request) -> web.Response:
    body = await request.json()
    return web.json_response(
        {"session_id": f"sess-created-{body.get('profile', 'default')}"})


async def set_mode(request: web.Request) -> web.Response:
    if "canonical" in request.query:
        MODE["canonical"] = request.query["canonical"] == "1"
    if "prompt_error" in request.query:
        MODE["prompt_error"] = request.query["prompt_error"] == "1"
    return web.json_response(dict(MODE))


async def rest_profiles(request: web.Request) -> web.Response:
    """GET /api/profiles: mismo roster que profiles.list (contrato Desktop)."""
    if not authed(request):
        return web.json_response({"error": "unauthorized"}, status=401)
    return web.json_response({"profiles": rpc_result("profiles.list", {})["profiles"]})


def main() -> None:
    app = web.Application()
    app.middlewares.append(log_middleware)
    app.router.add_get("/api/health", health)
    app.router.add_get("/api/profiles", rest_profiles)
    app.router.add_get("/api/mode", set_mode)
    app.router.add_post("/api/sessions", session_create)
    app.router.add_get("/api/sessions/{sid}/messages", session_messages)
    app.router.add_post("/auth/password-login", password_login)
    app.router.add_post("/auth/native/refresh", native_refresh)
    app.router.add_post("/api/auth/ws-ticket", ws_ticket)
    app.router.add_get("/api/ws", ws_handler)
    web.run_app(app, host="0.0.0.0", port=9119, print=None)


if __name__ == "__main__":
    main()
