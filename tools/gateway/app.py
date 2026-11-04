"""对外接口：与前端形态无关的 HTTP + SSE 契约。"""

from __future__ import annotations

import json
import logging
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from . import __version__
from .phone import PhoneError

MAX_BODY = 1024 * 1024
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Authorization, Content-Type, Last-Event-ID",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}

log = logging.getLogger("gateway.http")


class Handler(BaseHTTPRequestHandler):
    manager = None   # set by make_server
    phone = None
    protocol_version = "HTTP/1.0"

    # ---- 基础工具 ----

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)

    def _send(self, status: int, body: bytes, content_type: str, extra: dict | None = None, close=True):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if close:
            self.send_header("Connection", "close")
        for key, value in {**CORS, **(extra or {})}.items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, status: int, payload: dict, extra: dict | None = None):
        self._send(status, json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8", extra)

    def _error(self, status: int, code: str, message: str, **extra):
        self._json(status, {"error": {"code": code, "message": message}, **extra})

    def _read_body(self) -> dict:
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/json":
            raise PhoneError("invalid_request", "Content-Type 必须是 application/json。", 400)
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            raise PhoneError("invalid_request", "请求体过大。", 413)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw.decode("utf-8")) if raw else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise PhoneError("invalid_request", "请求体不是合法 JSON。", 400) from None
        if not isinstance(body, dict):
            raise PhoneError("invalid_request", "请求体必须是 JSON 对象。", 400)
        return body

    # ---- 路由 ----

    def do_OPTIONS(self):
        self._send(204, b"", "text/plain", close=True)

    def do_GET(self):
        parts = urlsplit(self.path)
        path, query = parts.path.rstrip("/") or "/", parse_qs(parts.query)
        try:
            if path == "/":
                return self._json(200, {
                    "service": "xiaole-mika-gateway", "version": __version__,
                    "endpoints": ["POST /goal", "GET /task/{task_id}", "GET /task/{task_id}/events",
                                  "POST /task/{task_id}/cancel", "POST /task/{task_id}/answer",
                                  "GET /tasks", "GET /health"],
                })
            if path == "/health":
                return self._json(200, self._health())
            if path == "/tasks":
                limit = int(query.get("limit", ["20"])[0])
                if not 1 <= limit <= 100:
                    raise PhoneError("invalid_request", "limit 必须是 1..100。", 400)
                return self._json(200, {"tasks": self.manager.list(limit)})
            if path.startswith("/task/"):
                rest = path[len("/task/"):].split("/")
                if len(rest) == 1:
                    return self._json(200, self.manager.get(rest[0]).snapshot())
                if len(rest) == 2 and rest[1] == "events":
                    return self._events(rest[0], query)
            raise PhoneError("not_found", "没有这个接口。", 404)
        except PhoneError as exc:
            return self._error(exc.http_status, exc.code, exc.message, **exc.details)
        except Exception as exc:  # noqa: BLE001 - 兜底避免连接悬空
            log.error("GET %s 失败：%r", self.path, exc)
            return self._error(500, "internal_error", "网关内部错误。")

    def do_POST(self):
        parts = urlsplit(self.path)
        path = parts.path.rstrip("/") or "/"
        try:
            if path == "/goal":
                return self._submit()
            if path.startswith("/task/") and (path.endswith("/cancel") or path.endswith("/answer")):
                action = path.rsplit("/", 1)[1]
                task_id = path[len("/task/"):-(len(action) + 1)].rstrip("/")
                if not task_id or "/" in task_id:
                    raise PhoneError("not_found", "没有这个接口。", 404)
                body = self._read_body_if_any() or {}
                if action == "cancel":
                    return self._json(200, self.manager.cancel(task_id))
                return self._json(200, self.manager.answer(task_id, body.get("text")))
            raise PhoneError("not_found", "没有这个接口。", 404)
        except PhoneError as exc:
            return self._error(exc.http_status, exc.code, exc.message, **exc.details)
        except Exception as exc:  # noqa: BLE001
            log.error("POST %s 失败：%r", self.path, exc)
            return self._error(500, "internal_error", "网关内部错误。")

    def _read_body_if_any(self) -> dict:
        if int(self.headers.get("Content-Length") or 0) > 0:
            return self._read_body()
        return {}

    def _submit(self):
        body = self._read_body()
        allowed = {"goal", "session_id", "conversation", "timeout_s", "request_id"}
        unknown = set(body) - allowed
        if unknown:
            raise PhoneError("invalid_request", "不支持的字段：" + ", ".join(sorted(unknown)), 400)
        snapshot, created = self.manager.submit(
            body.get("goal"), body.get("session_id"), body.get("conversation"),
            body.get("timeout_s"), body.get("request_id"),
        )
        snapshot = {**snapshot, "idempotent_replay": not created}
        self._json(202 if created else 200, snapshot)

    def _health(self) -> dict:
        try:
            info = self.phone.probe_fast()
            return {"status": "ok", "gateway_version": __version__, "api_version": info.get("api_version"),
                    "server_version": info.get("server_version"), "capabilities": info.get("capabilities"),
                    "device": getattr(self.phone, "device", None),
                    "phone_port": getattr(self.phone, "phone_port", None),
                    "forward_port": getattr(self.phone, "local_port", None)}
        except PhoneError as exc:
            return {"status": "degraded", "gateway_version": __version__, "code": exc.code,
                    "message": exc.message, "device": getattr(self.phone, "device", None)}

    # ---- SSE ----

    def _events(self, task_id: str, query: dict):
        since = 0
        header = self.headers.get("Last-Event-ID")
        raw = query.get("since", [None])[0]
        try:
            since = int(raw if raw is not None else (header or 0))
        except ValueError:
            raise PhoneError("invalid_request", "since 必须是整数。", 400) from None
        self.manager.get(task_id)  # 不存在就 404

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        for key, value in CORS.items():
            self.send_header(key, value)
        self.end_headers()

        rec = self.manager.get(task_id)
        self._write_event(0, "snapshot", rec.snapshot())
        last = since
        idle = time.time()
        while True:
            events = self.manager.wait_event(task_id, last, timeout=10)
            if events:
                for event in events:
                    self._write_event(event["seq"], event["event"], event["data"])
                    last = event["seq"]
                idle = time.time()
            else:
                if time.time() - idle > 10:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    idle = time.time()
            if self.manager.get(task_id).finished and not events:
                break
        self.wfile.flush()
        self.close_connection = True

    def _write_event(self, seq: int, kind: str, data: dict):
        payload = json.dumps(data, ensure_ascii=False)
        chunk = f"id: {seq}\nevent: {kind}\ndata: {payload}\n\n".encode("utf-8")
        self.wfile.write(chunk)
        self.wfile.flush()


def make_server(host: str, port: int, manager, phone) -> ThreadingHTTPServer:
    handler = type("BoundHandler", (Handler,), {"manager": manager, "phone": phone})
    server = ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    return server
