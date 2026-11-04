"""最小 RFC6455 WebSocket 实现（服务端 + 客户端各一半），只为本项目自测服务。

MCP 的 websocket 传输就是「一条 JSON-RPC = 一个文本帧」，所以这里不引入第三方库。
"""

from __future__ import annotations

import base64
import hashlib
import struct

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_FRAME = 1 << 20


class WsError(Exception):
    pass


def accept_key(key: str) -> str:
    return base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()


def masked(payload: bytes) -> bytes:
    """客户端发出的帧必须带掩码（这里给自测客户端用）。"""
    mask = bytes([7, 17, 33, 65])
    body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    length = len(payload)
    if length < 126:
        head = bytes([0x81, 0x80 | length])
    elif length < 65536:
        head = bytes([0x81, 0x80 | 126]) + struct.pack("!H", length)
    else:
        head = bytes([0x81, 0x80 | 127]) + struct.pack("!Q", length)
    return head + mask + body


def text_frame(payload: bytes) -> bytes:
    length = len(payload)
    if length < 126:
        head = bytes([0x81, length])
    elif length < 65536:
        head = bytes([0x81, 126]) + struct.pack("!H", length)
    else:
        head = bytes([0x81, 127]) + struct.pack("!Q", length)
    return head + payload


class WsConnection:
    """服务端一侧：从一个已升级的 socket 读写。"""

    def __init__(self, rfile, wfile, log=None):
        self.rfile = rfile
        self.wfile = wfile
        self.log = log or (lambda *a: None)

    def _recv(self, n: int) -> bytes:
        data = self.rfile.read(n)
        if len(data) < n:
            raise WsError("connection closed")
        return data

    def read_message(self) -> str | None:
        """返回一条文本消息；连接正常关闭返回 None。"""
        collected = b""
        while True:
            first = self._recv(2)
            fin = first[0] & 0x80
            opcode = first[0] & 0x0f
            is_masked = bool(first[1] & 0x80)
            length = first[1] & 0x7f
            if length == 126:
                length = struct.unpack("!H", self._recv(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv(8))[0]
            if length > MAX_FRAME:
                raise WsError("frame too large")
            mask = self._recv(4) if is_masked else None
            payload = self._recv(length) if length else b""
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x8:  # close
                self.close(1000)
                return None
            if opcode == 0x9:  # ping → pong
                self._send(payload, opcode=0xA)
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode in (0x1, 0x2):
                collected = payload
                if fin:
                    return collected.decode("utf-8", "replace")
                continue
            if opcode == 0x0:  # 续帧
                collected += payload
                if fin:
                    return collected.decode("utf-8", "replace")
                continue
            raise WsError(f"unsupported opcode {opcode}")

    def _send(self, payload: bytes, opcode: int = 0x1):
        length = len(payload)
        if length < 126:
            head = bytes([0x80 | opcode, length])
        elif length < 65536:
            head = bytes([0x80 | opcode, 126]) + struct.pack("!H", length)
        else:
            head = bytes([0x80 | opcode, 127]) + struct.pack("!Q", length)
        self.wfile.write(head + payload)
        self.wfile.flush()

    def send_text(self, text: str):
        self._send(text.encode("utf-8"))

    def close(self, code: int = 1000):
        try:
            self._send(struct.pack("!H", code), opcode=0x8)
        except Exception:  # noqa: BLE001 - 关窗时的写失败不用再报
            pass
