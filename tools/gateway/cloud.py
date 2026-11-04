"""主动外连小智云端 MCP 接入点：我们做 WebSocket 客户端，协议上做 MCP 服务端。

报文格式对齐官方示例 `78/mcp-calculator`（`mcp_pipe.py` + MCP Python SDK）：
* 连接：`websockets.connect(url)`；token 在 URL 的 query 里（示例没有额外 header、没有子协议）
* 报文：JSON-RPC 2.0，一条消息一个文本帧，原样转发给 MCP 服务端，不包壳
* 方法：`initialize` / `notifications/initialized` / `tools/list` / `tools/call` / `ping`
* 保活：WebSocket 协议层 ping（示例用 websockets 库默认的 20s ping）
* 重连：指数退避，封顶 30s

连接地址只从环境变量 `XIAOZHI_MCP_URL` 读，代码里不出现真实值。
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import threading
import time
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit

import websockets
from websockets.exceptions import ConnectionClosed

BACKOFFS = (1, 2, 4, 8, 16, 30)
PING_INTERVAL = 20
PING_TIMEOUT = 20

log = logging.getLogger("gateway.cloud")


def split_token(url: str, auth: str) -> tuple[str, dict]:
    """返回 (真正要连的 URL, 额外 header)。

    auth=query：原样连，token 留在 query（官方示例的做法）。
    auth=bearer：把 token 挪到 Authorization: Bearer，URL 里去掉 token。
    """
    parts = urlsplit(url)
    token = (parse_qs(parts.query).get("token") or [None])[0]
    if auth == "bearer" and token:
        keep = {k: v for k, v in parse_qs(parts.query, keep_blank_values=True).items() if k != "token"}
        clean = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(keep, doseq=True), parts.fragment))
        return clean, {"Authorization": f"Bearer {token}"}
    return url, {}


class CloudLink:
    """一条常驻的外连连接：断了就退避重连，连上就等云端下发 MCP 报文。"""

    def __init__(self, service, url: str, auth: str = "query", *, log_fn=None, status_path: str | None = None):
        self.service = service
        self.url = url
        self.auth = auth
        self.auth_url, self.headers = split_token(url, auth)
        self.log = log_fn or log.info
        self.status_path = status_path
        self._stop = threading.Event()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._attempt = 0
        self._started_at = int(time.time() * 1000)
        self._connected_at: int | None = None
        self._last_close: dict | None = None

    # ---- 生命周期 ----

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, name="cloud", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._loop is not None:
            self._loop.call_soon_threadsafe(lambda: None)

    def _run(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._supervise())
        finally:
            self._loop.close()

    async def _supervise(self) -> None:
        while not self._stop.is_set():
            if self._attempt:
                wait = BACKOFFS[min(self._attempt - 1, len(BACKOFFS) - 1)]
                self.log(f"云端 {wait}s 后重连（第 {self._attempt} 次）")
                if await self._sleep(wait):
                    break
            try:
                await self._session()
            except ConnectionClosed as exc:
                self._on_close(exc.code, exc.reason or "", "closed")
            except Exception as exc:  # noqa: BLE001 - 任何异常都按断开处理，交给退避重连
                self._on_close(None, f"{type(exc).__name__}: {exc}", "error")
            else:
                self._on_close(None, "连接正常结束", "closed")
            self._attempt += 1

    async def _sleep(self, seconds: float) -> bool:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self._stop.is_set():
                return True
            await asyncio.sleep(0.2)
        return self._stop.is_set()

    def _on_close(self, code, reason, kind: str) -> None:
        self._connected_at = None
        self._last_close = {"code": code, "reason": str(reason)[:300], "at_ms": int(time.time() * 1000)}
        self.log(f"云端连接断开（{kind}）：close_code={code} reason={str(reason)[:300]!r}")
        self._write_status("disconnected")

    async def _session(self) -> None:
        self.log(f"正在连接云端 MCP 接入点（auth={self.auth}，host={urlsplit(self.auth_url).netloc}）")
        async with websockets.connect(
            self.auth_url,
            additional_headers=self.headers,
            ping_interval=PING_INTERVAL,
            ping_timeout=PING_TIMEOUT,
            max_size=4 * 1024 * 1024,
            open_timeout=15,
        ) as ws:
            self._attempt = 0
            self._connected_at = int(time.time() * 1000)
            self.log("云端握手成功：WebSocket 已建立，等待云端下发 initialize")
            self._write_status("connected")
            await self._serve(ws)

    async def _serve(self, ws) -> None:
        while not self._stop.is_set():
            raw = await ws.recv()
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", "replace")
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                self.log(f"云端报文不是 JSON，已忽略：{raw[:200]!r}")
                continue
            if isinstance(message, list):  # JSON-RPC 批量
                replies = [r for r in await asyncio.to_thread(self._handle_batch, message) if r is not None]
                if replies:
                    await ws.send(json.dumps(replies, ensure_ascii=False))
                continue
            if not isinstance(message, dict):
                self.log(f"云端报文不是 JSON 对象，已忽略：{raw[:200]!r}")
                continue
            reply = await asyncio.to_thread(self._handle, message)
            if reply is not None:
                await ws.send(json.dumps(reply, ensure_ascii=False))

    def _handle_batch(self, messages: list) -> list:
        return [r for r in (self._handle(m) for m in messages if isinstance(m, dict)) if r is not None]

    def _handle(self, message: dict) -> dict | None:
        method = message.get("method") or "(response)"
        msg_id = message.get("id")
        started = time.time()
        # 业务实现会阻塞在 adb/手机上（最长十几秒），放到线程里，别把心跳拖死。
        response = self.service.handle(message)
        self.log(f"云端 << {method} id={msg_id} → 已回包 {time.time() - started:.3f}s"
                 + ("（通知）" if response is None else ""))
        return response

    # ---- 状态落盘，供监控脚本读取 ----

    def _write_status(self, state: str) -> None:
        if not self.status_path:
            return
        payload = {
            "state": state,
            "host": urlsplit(self.auth_url).netloc,
            "auth": self.auth,
            "connected_at_ms": self._connected_at,
            "last_close": self._last_close,
            "reconnect_attempts": self._attempt,
            "started_at_ms": self._started_at,
            "updated_at_ms": int(time.time() * 1000),
        }
        try:
            tmp = self.status_path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False)
            os.replace(tmp, self.status_path)
        except OSError as exc:
            log.debug("写状态文件失败：%s", exc)
