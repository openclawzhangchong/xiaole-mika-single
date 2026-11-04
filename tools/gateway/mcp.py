"""MCP 服务端（websocket + query token）。主契约：小智云端作为 MCP 客户端来调我们的工具。

协议：JSON-RPC 2.0 over WebSocket 文本帧，MCP 版本 2024-11-05。
支持 initialize / notifications/initialized / tools/list / tools/call / ping。
"""

from __future__ import annotations

import hmac
import json
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from . import __version__
from .phone import PhoneError
from .ws import WsConnection, WsError, accept_key

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "xiaole-mika-gateway"

log = logging.getLogger("gateway.mcp")

TOOLS = [
    {
        "name": "mika.submit_goal",
        "description": "把一段文字目标交给手机上的 Mika 执行，立即返回 task_id（不等待执行完成）。"
                       "结果用 mika.get_task 轮询获取。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "goal": {"type": "string", "description": "要手机完成的目标，纯自然语言。"},
                "session_id": {"type": "string", "description": "同一段对话的标识，可选，便于前端归组。"},
                "conversation": {"type": "string", "description": "继续之前的 Mika 对话（mcp-<uuid>），可选。"},
                "timeout_s": {"type": "integer", "minimum": 30, "maximum": 1800,
                              "description": "该任务的网关时限，默认 300 秒。"},
            },
            "required": ["goal"],
        },
    },
    {
        "name": "mika.get_task",
        "description": "查一个已提交任务的状态与结果。status 为 done 时 answer 是最终结果；"
                       "waiting_for_answer 时可用 phone 侧回答。",
        "inputSchema": {
            "type": "object",
            "properties": {"task_id": {"type": "string", "description": "mika.submit_goal 返回的 task_id。"}},
            "required": ["task_id"],
        },
    },
    {
        "name": "mika.cancel_task",
        "description": "取消一个尚未结束的任务。已进入终态时返回 accepted=false。",
        "inputSchema": {
            "type": "object",
            "properties": {"task_id": {"type": "string"}},
            "required": ["task_id"],
        },
    },
    {
        "name": "mika.answer_task",
        "description": "任务处于 waiting_for_answer（Mika 在手机上反问）时，用这段文字回答它，任务会继续执行。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "text": {"type": "string", "description": "给 Mika 的回答内容。"},
            },
            "required": ["task_id", "text"],
        },
    },
    {
        "name": "mika.list_tasks",
        "description": "列出网关里最近的任务快照，新的在前。",
        "inputSchema": {
            "type": "object",
            "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 100}},
        },
    },
]

# 下游 hub 可能按自己的命名规则（不允许点号）去调，这里把去掉前缀的写法映射回来。
# 只在 tools/call 入口做别名，tools/list 仍只暴露 5 个规范工具名。
TOOL_ALIASES = {
    "submit_goal": "mika.submit_goal",
    "get_task": "mika.get_task",
    "cancel_task": "mika.cancel_task",
    "answer_task": "mika.answer_task",
    "list_tasks": "mika.list_tasks",
}


class McpService:
    def __init__(self, manager, expected_serial: str | None = None, log_fn=None):
        self.manager = manager
        self.expected_serial = expected_serial
        self.log = log_fn or log.info

    # ---- JSON-RPC 分发 ----

    def handle(self, message: dict) -> dict | None:
        method = message.get("method")
        msg_id = message.get("id")
        if not isinstance(method, str):
            return self._error(msg_id, -32600, "Invalid Request", id_present="id" in message)
        try:
            if method == "initialize":
                return self._result(msg_id, {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": SERVER_NAME, "version": __version__},
                })
            if method == "notifications/initialized":
                self.log("客户端已初始化（notifications/initialized）")
                return None
            if method == "ping":
                return self._result(msg_id, {})
            if method == "tools/list":
                return self._result(msg_id, {"tools": TOOLS})
            if method == "tools/call":
                return self._tools_call(msg_id, message.get("params") or {})
            return self._error(msg_id, -32601, f"Method not found: {method}")
        except Exception as exc:  # noqa: BLE001 - 协议层不能因为一个请求把连接弄断
            log.error("MCP 处理 %s 出错：%r", method, exc)
            return self._error(msg_id, -32603, "Internal error")

    def _tools_call(self, msg_id, params: dict) -> dict:
        if not isinstance(params, dict):
            return self._error(msg_id, -32602, "params must be an object")
        name = params.get("name")
        args = params.get("arguments") or {}
        if not isinstance(name, str):
            return self._error(msg_id, -32602, "Tool name is required")
        if not isinstance(args, dict):
            return self._error(msg_id, -32602, "arguments must be an object")
        serial = params.get("serialNumber") or args.get("serialNumber")
        if serial is not None:
            if self.expected_serial and serial != self.expected_serial:
                log.warning("tools/call 收到的 serialNumber=%s 与本地配置不一致（继续处理）", serial)
            else:
                self.log(f"tools/call serialNumber={serial}")
        unknown = {k for k in args if k not in {"goal", "session_id", "conversation", "timeout_s",
                                                 "task_id", "text", "limit", "serialNumber"}}
        if unknown:
            log.debug("忽略未知参数：%s", ", ".join(sorted(unknown)))
        try:
            payload, is_error = self.call(name, args)
        except PhoneError as exc:
            payload, is_error = {"error": {"code": exc.code, "message": exc.message}}, True
        return self._result(msg_id, {
            "content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}],
            "isError": is_error,
        })

    def call(self, name: str, args: dict) -> tuple[dict, bool]:
        name = TOOL_ALIASES.get(name, name)  # 兼容下游 hub 把点号规范化的写法
        if name == "mika.submit_goal":
            snapshot, created = self.manager.submit(
                args.get("goal"), args.get("session_id"), args.get("conversation"),
                args.get("timeout_s"), args.get("request_id"),
            )
            return {
                "task_id": snapshot["task_id"],
                "status": snapshot["status"],
                "created": created,
                "poll_with": "mika.get_task",
                "poll_interval_s": 2,
                "hint": "任务已交给手机，用 mika.get_task 轮询；done 时读 answer。",
            }, False
        if name == "mika.get_task":
            task_id = args.get("task_id")
            if not isinstance(task_id, str) or not task_id:
                raise PhoneError("invalid_request", "task_id 必填。", 400)
            return self.manager.get(task_id).snapshot(), False
        if name == "mika.cancel_task":
            task_id = args.get("task_id")
            if not isinstance(task_id, str) or not task_id:
                raise PhoneError("invalid_request", "task_id 必填。", 400)
            return self.manager.cancel(task_id), False
        if name == "mika.answer_task":
            task_id = args.get("task_id")
            if not isinstance(task_id, str) or not task_id:
                raise PhoneError("invalid_request", "task_id 必填。", 400)
            return self.manager.answer(task_id, args.get("text")), False
        if name == "mika.list_tasks":
            limit = args.get("limit", 20)
            if not isinstance(limit, int) or not 1 <= limit <= 100:
                raise PhoneError("invalid_request", "limit 必须是 1..100 的整数。", 400)
            return {"tasks": self.manager.list(limit)}, False
        raise PhoneError("unknown_tool", f"没有工具 {name}", -32602)

    @staticmethod
    def _result(msg_id, result: dict) -> dict | None:
        if msg_id is None:
            return None
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    @staticmethod
    def _error(msg_id, code: int, message: str, *, id_present: bool = True) -> dict | None:
        if msg_id is None and not id_present:
            return None
        return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


class McpWsServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, service: McpService, token: str):
        super().__init__(address, McpHandler)
        self.service = service
        self.token = token


class McpHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        log.debug("%s %s", self.address_string(), fmt % args)

    def do_GET(self):
        parts = urlsplit(self.path)
        if not self._authorized(parts.query):
            body = b'{"error":{"code":"unauthorized","message":"invalid or missing token"}}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("WWW-Authenticate", 'Bearer realm="xiaole-mika-gateway"')
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)
            self.close_connection = True
            return

        upgrade = (self.headers.get("Upgrade") or "").lower()
        connection = (self.headers.get("Connection") or "").lower()
        key = self.headers.get("Sec-WebSocket-Key")
        if "websocket" not in upgrade or "upgrade" not in connection or not key:
            self.send_error(400, "WebSocket upgrade required")
            return
        if (self.headers.get("Sec-WebSocket-Version") or "") != "13":
            self.send_error(400, "Unsupported WebSocket version")
            return

        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept_key(key))
        self.end_headers()
        self.wfile.flush()

        log.info("MCP 客户端接入：%s（path=%s）", self.address_string(), parts.path)
        conn = WsConnection(self.rfile, self.wfile, log=lambda *a: log.debug(*a))
        try:
            while True:
                text = conn.read_message()
                if text is None:
                    break
                try:
                    message = json.loads(text)
                except json.JSONDecodeError:
                    conn.send_text(json.dumps({"jsonrpc": "2.0", "id": None,
                                               "error": {"code": -32700, "message": "Parse error"}}))
                    continue
                if not isinstance(message, dict):
                    conn.send_text(json.dumps({"jsonrpc": "2.0", "id": None,
                                               "error": {"code": -32600, "message": "Invalid Request"}}))
                    continue
                response = self.server.service.handle(message)
                if response is not None:
                    conn.send_text(json.dumps(response, ensure_ascii=False))
        except WsError as exc:
            log.info("MCP 连接结束：%s", exc)
        except (ConnectionError, OSError):
            pass
        finally:
            self.close_connection = True

    def _authorized(self, query: str) -> bool:
        expected = self.server.token
        given = (parse_qs(query).get("token") or [None])[0]
        header = self.headers.get("Authorization") or ""
        if not given and header.lower().startswith("bearer "):
            given = header[7:].strip()
        return bool(given) and hmac.compare_digest(given, expected)
