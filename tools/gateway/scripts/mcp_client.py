"""最小 MCP 客户端：按 initialize → tools/list → tools/call 的顺序打自己的服务端。

token 与设备序列号都从环境变量 / .env 读，代码里不出现任何真实值。

用法：
    python scripts/mcp_client.py --url ws://127.0.0.1:8004/mcp/ --goal "查询设备信息"
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import struct
import sys
import time
from urllib.parse import urlsplit

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gateway.ws import accept_key, masked  # noqa: E402
from gateway.__main__ import load_env  # noqa: E402

load_env(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))


class WsClient:
    def __init__(self, url: str, timeout: float = 30):
        parts = urlsplit(url)
        if parts.scheme not in {"ws", "http"}:
            raise SystemExit("只支持 ws:// 或 http://（本地自测，不走 wss）")
        self.host = parts.hostname
        self.port = parts.port or 80
        self.path = (parts.path or "/") + (("?" + parts.query) if parts.query else "")
        self.sock = socket.create_connection((self.host, self.port), timeout=timeout)
        self.sock.settimeout(timeout)

    def handshake(self):
        key = os.urandom(16).hex()
        req = (f"GET {self.path} HTTP/1.1\r\nHost: {self.host}:{self.port}\r\n"
               f"Upgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(req.encode())
        raw = b""
        while b"\r\n\r\n" not in raw:
            chunk = self.sock.recv(4096)
            if not chunk:
                break
            raw += chunk
        head, _, rest = raw.partition(b"\r\n\r\n")
        lines = head.decode("latin-1").split("\r\n")
        if not lines or "101" not in lines[0]:
            raise SystemExit(f"握手失败：{lines[0] if lines else '无响应'}")
        headers = {k.lower(): v for k, v in (line.split(": ", 1) for line in lines[1:] if ": " in line)}
        if headers.get("sec-websocket-accept") != accept_key(key):
            raise SystemExit("Sec-WebSocket-Accept 不匹配")
        self._buf = rest
        return headers

    def send(self, obj: dict):
        self.sock.sendall(masked(json.dumps(obj, ensure_ascii=False).encode("utf-8")))

    def _read_exact(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("连接已关闭")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def recv(self) -> dict:
        while True:
            head = self._read_exact(2)
            opcode = head[0] & 0x0f
            length = head[1] & 0x7f
            if length == 126:
                length = struct.unpack("!H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._read_exact(8))[0]
            payload = self._read_exact(length) if length else b""
            if opcode == 0x9:
                continue  # MCP 服务端不发 WebSocket ping，收到忽略即可
            if opcode == 0x8:
                raise ConnectionError("服务端关闭连接")
            if opcode in (0x1, 0x2):
                return json.loads(payload.decode("utf-8"))

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("MCP_URL", "ws://127.0.0.1:8004/mcp/"))
    ap.add_argument("--token", default=os.environ.get("MCP_TOKEN"))
    ap.add_argument("--serial", default=os.environ.get("XIAOZHI_SERIAL_NUMBER"))
    ap.add_argument("--goal", default="只读查询：这台手机的型号和 Android 版本，不要打开任何应用，直接回答。")
    ap.add_argument("--timeout", type=float, default=420)
    args = ap.parse_args()
    if not args.token:
        raise SystemExit("缺少 token：设置 MCP_TOKEN 或 .env")
    if not args.serial:
        raise SystemExit("缺少设备序列号：设置 XIAOZHI_SERIAL_NUMBER 或 .env")

    url = args.url + ("&" if "?" in args.url else "?") + "token=" + args.token
    client = WsClient(url)
    client.handshake()
    print("[01] WebSocket 握手成功（query token 通过）")

    seq = 0
    def call(method: str, params: dict | None = None, notify: bool = False):
        nonlocal seq
        seq += 1
        msg = {"jsonrpc": "2.0", "method": method}
        if not notify:
            msg["id"] = seq
        if params is not None:
            msg["params"] = params
        started = time.time()
        client.send(msg)
        if notify:
            print(f"[--] {method}（通知，无响应）")
            return None
        reply = client.recv()
        print(f"[{time.time() - started:5.3f}s] {method} → {json.dumps(reply, ensure_ascii=False)[:220]}")
        if "error" in reply:
            raise SystemExit(f"{method} 返回错误：{reply['error']}")
        return reply["result"]

    init = call("initialize", {"protocolVersion": "2024-11-05",
                               "capabilities": {}, "clientInfo": {"name": "xiaole-local-test", "version": "0.1"}})
    if init["protocolVersion"] != "2024-11-05":
        raise SystemExit("协议版本不一致")
    call("notifications/initialized", notify=True)
    call("ping")
    tools = call("tools/list")["tools"]
    print("工具列表：" + ", ".join(t["name"] for t in tools))

    started = time.time()
    submit = call("tools/call", {"name": "mika.submit_goal",
                                 "arguments": {"goal": args.goal, "timeout_s": 300},
                                 "serialNumber": args.serial})
    data = json.loads(submit["content"][0]["text"])
    print(f"[submit] 返回耗时 {time.time() - started:.3f}s → task_id={data['task_id']} status={data['status']}")
    if submit.get("isError"):
        raise SystemExit("提交失败：" + submit["content"][0]["text"])

    task_id = data["task_id"]
    while time.time() - started < args.timeout:
        time.sleep(2)
        snap = json.loads(call("tools/call", {"name": "mika.get_task",
                                             "arguments": {"task_id": task_id},
                                             "serialNumber": args.serial})["content"][0]["text"])
        print(f"[poll {time.time() - started:6.1f}s] status={snap['status']} mika={snap.get('mika_status')} "
              f"progress={(snap.get('progress') or '')[:60]}")
        if snap["finished"]:
            break
    else:
        raise SystemExit("轮询超时")

    print("\n=== MCP 链路结果 ===")
    print(f"task_id : {task_id}")
    print(f"status  : {snap['status']}")
    print(f"answer  : {snap.get('answer')}")
    print(f"error   : {snap.get('error')}")
    print(f"端到端  : {time.time() - started:.1f}s（含模型规划与手机执行）")
    client.close()
    return 0 if snap["status"] == "done" else 1


if __name__ == "__main__":
    raise SystemExit(main())
