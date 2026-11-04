"""本地模拟小智云端的 MCP 接入点：给网关的 `--mode cloud` 做离线联调，不真的连云。

它的报文完全照官方示例（`78/mcp-calculator` + MCP Python SDK）的顺序发：
initialize → 等回包 → notifications/initialized → tools/list → tools/call → 轮询 get_task。

用法（仓库根目录）：
    python scripts/mock_cloud.py --port 8100 --token mock-token
然后在另一个终端把网关指过来：
    $env:XIAOZHI_MCP_URL="ws://127.0.0.1:8100/mcp/?token=mock-token"; python -m gateway --mode cloud
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import time
from urllib.parse import parse_qs, urlsplit

import websockets
from websockets.exceptions import ConnectionClosed

log = logging.getLogger("mock-cloud")

IDS = iter(range(1, 10_000))


def rpc(method: str, params: dict | None = None) -> dict:
    msg = {"jsonrpc": "2.0", "id": next(IDS), "method": method}
    if params is not None:
        msg["params"] = params
    return msg


class MockCloud:
    def __init__(self, token: str, goal: str, poll: bool, close_after: float, status_path: str):
        self.token = token
        self.goal = goal
        self.poll = poll
        self.close_after = close_after
        self.status_path = status_path
        self.connections = 0
        self.disconnects = 0
        self.tools_registered: list[str] = []
        self._started = int(time.time() * 1000)

    def _write_status(self, state: str, extra: dict | None = None) -> None:
        payload = {
            "state": state,
            "connections": self.connections,
            "disconnects": self.disconnects,
            "tools_registered": self.tools_registered,
            "started_at_ms": self._started,
            "updated_at_ms": int(time.time() * 1000),
            **(extra or {}),
        }
        tmp = self.status_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
        os.replace(tmp, self.status_path)

    async def handler(self, ws) -> None:
        path = ws.request.path
        given = (parse_qs(urlsplit(path).query).get("token") or [None])[0]
        if given != self.token:
            log.warning("拒绝连接：token 不匹配（path=%s）", path)
            await ws.close(1008, "invalid token")
            return

        self.connections += 1
        log.info("云端（模拟）接受连接：path=%s，第 %d 次", path, self.connections)
        self._write_status("connected", {"connection": self.connections})
        try:
            await self._serve(ws)
        except ConnectionClosed as exc:
            self.disconnects += 1
            log.info("连接断开：close_code=%s reason=%r", exc.code, exc.reason)
            self._write_status("disconnected", {"close_code": exc.code, "close_reason": str(exc.reason)})
        except Exception as exc:  # noqa: BLE001
            log.warning("连接异常：%r", exc)
            self._write_status("error", {"error": repr(exc)})

    async def _call(self, ws, message: dict, label: str) -> dict:
        started = time.time()
        await ws.send(json.dumps(message, ensure_ascii=False))
        raw = await asyncio.wait_for(ws.recv(), timeout=360)
        reply = json.loads(raw)
        log.info("云端（模拟）>> %s id=%s → 回包 %d 字节 / %.3fs：%s", label, message.get("id"),
                 len(raw), time.time() - started, json.dumps(reply, ensure_ascii=False)[:300])
        return reply

    async def _serve(self, ws) -> None:
        init = await self._call(ws, rpc("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "xiaozhi-cloud-mock", "version": "0.1"}}), "initialize")
        version = init.get("result", {}).get("protocolVersion")
        log.info("协议版本协商：%s", version)

        await ws.send(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}))
        log.info("已发送 notifications/initialized")

        tools = await self._call(ws, rpc("tools/list"), "tools/list")
        self.tools_registered = [t["name"] for t in tools.get("result", {}).get("tools", [])]
        log.info("云端（模拟）看到 %d 个工具：%s", len(self.tools_registered), ", ".join(self.tools_registered))
        self._write_status("connected", {"tools_registered": self.tools_registered})

        if not self.goal:
            await self._idle(ws)
            return

        submit = await self._call(ws, rpc("tools/call", {
            "name": "mika.submit_goal",
            "arguments": {"goal": self.goal, "timeout_s": 300},
            "serialNumber": os.environ.get("XIAOZHI_SERIAL_NUMBER"),
        }), "tools/call mika.submit_goal")
        text = submit.get("result", {}).get("content", [{}])[0].get("text", "{}")
        data = json.loads(text)
        if "task_id" not in data:
            log.error("提交失败：%s", text)
            await self._idle(ws)
            return
        task_id = data["task_id"]
        log.info("真实 task_id=%s status=%s", task_id, data.get("status"))
        if self.poll:
            await self._poll(ws, task_id)
        await self._idle(ws)

    async def _poll(self, ws, task_id: str) -> None:
        started = time.time()
        for _ in range(150):
            await asyncio.sleep(2)
            snap = await self._call(ws, rpc("tools/call", {
                "name": "mika.get_task", "arguments": {"task_id": task_id},
            }), "tools/call mika.get_task")
            data = json.loads(snap["result"]["content"][0]["text"])
            log.info("[轮询 %6.1fs] status=%s progress=%s", time.time() - started,
                     data.get("status"), (data.get("progress") or "")[:60])
            if data.get("finished"):
                log.info("任务结束：status=%s answer=%r", data.get("status"), data.get("answer"))
                return

    async def _idle(self, ws) -> None:
        if self.close_after:
            log.info("%.0fs 后主动断开连接（模拟云端侧掉线）", self.close_after)
            await asyncio.sleep(self.close_after)
            await ws.close(1001, "mock closing")
            return
        while True:  # 保持连接，等网关断开
            await ws.recv()


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8100)
    ap.add_argument("--token", default="mock-token")
    ap.add_argument("--goal", default="", help="留空则只做 initialize/tools/list，不驱动手机")
    ap.add_argument("--no-poll", action="store_true", help="提交后不轮询 get_task")
    ap.add_argument("--close-after", type=float, default=0, help="若干秒后主动断开，验证网关重连")
    ap.add_argument("--status-file", default="logs/mock-cloud-status.json")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-5s [mock] %(message)s")
    os.makedirs(os.path.dirname(os.path.abspath(args.status_file)), exist_ok=True)
    cloud = MockCloud(args.token, args.goal, not args.no_poll, args.close_after, args.status_file)

    async with websockets.serve(cloud.handler, args.host, args.port, max_size=4 * 1024 * 1024):
        log.info("模拟云端监听 ws://%s:%d/mcp/?token=%s", args.host, args.port, args.token)
        await asyncio.Future()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
