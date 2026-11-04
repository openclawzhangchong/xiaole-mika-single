"""手机端 Mika 的传输层：adb forward + /api/v1 任务接口。

Mika 的 HTTP 服务跑在 APK 里（RemoteHost），只监听手机回环 127.0.0.1；电脑经
`adb forward tcp:0 tcp:<手机端口>` 进来，在手机看来就是回环连接，因此可以用 USB 令牌。
这里只读引用 Mika 源码里的约定，不改它一行：

* 连接信息文件 `/sdcard/Android/data/com.wangzan101.mika/files/mcp-usb.json`
  （由 APK 的 `McpRuntime.writeUsbScript` / `McpUsb.info` 写出，含 token、port、boot）
* `POST /api/v1/tasks` 的 `request_id` 会成为 Mika 任务 id，可用来做幂等与对账
* 任务状态取值见 Mika `RemoteStatus`
"""

from __future__ import annotations

import http.client
import json
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request

API = "/api/v1"
MAX_RESPONSE = 4 * 1024 * 1024
TERMINAL = {"done", "failed", "cancelled"}


class PhoneError(Exception):
    """网关对外错误。code 直接进响应体；ambiguous 表示写操作可能已经生效。"""

    def __init__(self, code: str, message: str, http_status: int = 503, *, ambiguous: bool = False, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.ambiguous = ambiguous
        self.details = details or {}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _now_ms() -> int:
    return int(time.time() * 1000)


class MikaPhone:
    """一台手机 + 一条 adb forward。所有调用都在调用方线程里同步执行。"""

    def __init__(self, adb: str = "adb", device: str | None = None,
                 info_path: str = "/sdcard/Android/data/com.wangzan101.mika/files/mcp-usb.json",
                 connect_script: str = "/sdcard/Android/data/com.wangzan101.mika/files/connect-computer.sh",
                 request_timeout: float = 15.0, read_retries: int = 3, log=None):
        self.adb = adb
        self.device = device
        self.info_path = info_path
        self.connect_script = connect_script
        self.request_timeout = request_timeout
        self.read_retries = read_retries
        self.log = log or (lambda level, msg: None)
        self.token: str | None = None
        self.phone_port: int | None = None
        self.local_port: int | None = None
        self.boot: str | None = None
        self.forward_key: str | None = None
        self._lock = threading.Lock()
        self._opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        self._client_version = "xiaole-gateway/0.1.0"

    # ---------- adb ----------

    def _run_adb(self, *args, timeout: float = 20) -> str:
        prefix = [self.adb] + (["-s", self.device] if self.device else [])
        try:
            result = subprocess.run(prefix + list(args), stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, encoding="utf-8", timeout=timeout)
        except FileNotFoundError:
            raise PhoneError("adb_unavailable", "找不到 adb，请安装 Android platform-tools 或指定 --adb 路径。") from None
        except subprocess.TimeoutExpired:
            raise PhoneError("adb_timeout", "adb 命令超时，手机可能已断开。") from None
        if result.returncode != 0:
            detail = (result.stderr or result.stdout or "").strip().splitlines()
            raise PhoneError("adb_error", "adb 执行失败：" + (detail[-1] if detail else "未知错误"))
        return result.stdout.strip()

    def _devices(self) -> list[dict]:
        out = self._run_adb("devices")
        found = []
        for line in out.splitlines():
            parts = line.split("\t", 1) if "\t" in line else line.split(maxsplit=1)
            if len(parts) == 2 and parts[0] != "List" and parts[1].strip():
                found.append({"device": parts[0], "state": parts[1].split()[0]})
        return found

    def select_device(self) -> None:
        devices = self._devices()
        if self.device:
            state = next((d["state"] for d in devices if d["device"] == self.device), None)
            if state != "device":
                raise PhoneError("device_offline" if state in (None, "offline") else "device_unauthorized",
                                 f"手机 {self.device} 当前状态：{state or '未连接'}。请接好 USB 线并确认已授权调试。")
            return
        online = [d["device"] for d in devices if d["state"] == "device"]
        if len(online) == 1:
            self.device = online[0]
            return
        if not online:
            states = ", ".join(f"{d['device']}={d['state']}" for d in devices) or "无"
            raise PhoneError("device_offline", f"没有在线设备（{states}）。请连接手机或重新授权 USB 调试。")
        raise PhoneError("device_selection", "检测到多台在线设备，请用 --device 指定手机序列号。",
                         details={"devices": devices})

    def bootstrap(self) -> str:
        """跑 Mika 自带的 connect-computer.sh：打开手机侧「USB 电脑连接」并写出连接信息。"""
        self.log("info", "运行手机端 bootstrap：" + self.connect_script)
        try:
            out = self._run_adb("shell", "sh", self.connect_script, timeout=60)
        except PhoneError as exc:
            raise PhoneError("phone_bootstrap_failed",
                             "手机端没打开电脑连接：" + exc.message +
                             " 请解锁手机、打开 Mika 一次后重试。") from None
        return out

    # ---------- 连接信息 ----------

    def _read_info(self) -> dict:
        try:
            raw = self._run_adb("shell", "cat", self.info_path)
            info = json.loads(raw)
        except json.JSONDecodeError:
            raise PhoneError("connection_info_invalid",
                             "手机里的 mcp-usb.json 不可解析。先运行 mika connect（或本网关 --bootstrap）。") from None
        except PhoneError:
            raise PhoneError("connection_info_missing",
                             "读不到 mcp-usb.json，说明手机上「USB 电脑连接」没开。先 --bootstrap 或 mika connect。") from None
        token = info.get("token")
        port = info.get("port")
        if not isinstance(token, str) or not token or not isinstance(port, int) or not 1 <= port <= 65535:
            raise PhoneError("connection_info_invalid", "连接信息里 token/port 不合法。")
        return info

    def _check_boot(self, info: dict) -> None:
        boot = self._run_adb("shell", "settings", "get", "global", "boot_count")
        if not boot.isdigit() or str(info.get("boot")) != boot:
            raise PhoneError("stale_connection", "手机重启过（boot 编号不一致），连接信息已过期。先 --bootstrap 或 mika connect。")

    def _forward(self, port: int) -> None:
        out = self._run_adb("forward", "tcp:0", f"tcp:{port}")
        if not out.isdigit() or not 1 <= int(out) <= 65535:
            raise PhoneError("adb_error", "adb 没有返回可用的转发端口（端口转发失败）。")
        self.phone_port = port
        self.local_port = int(out)

    def _drop_forward(self) -> None:
        if self.local_port is not None:
            try:
                self._run_adb("forward", "--remove", f"tcp:{self.local_port}", timeout=5)
            except PhoneError:
                pass
        self.local_port = None

    def connect(self, do_bootstrap: bool = False) -> None:
        with self._lock:
            self._close_locked()
            self.select_device()
            if do_bootstrap:
                self.bootstrap()
            info = self._read_info()
            self._check_boot(info)
            self.token = info["token"]
            self.boot = str(info.get("boot"))
            self._forward(info["port"])
            self.log("info", f"adb forward tcp:{self.local_port} -> tcp:{info['port']}（设备 {self.device}）")

    def close(self) -> None:
        with self._lock:
            self._close_locked()

    def _close_locked(self) -> None:
        self._drop_forward()

    def reconnect(self, do_bootstrap: bool = False) -> None:
        """连接坏了重来一遍：重新选设备、重读连接信息（手机可能换了令牌或重启）、重建转发。"""
        self.connect(do_bootstrap)

    # ---------- HTTP ----------

    def _http(self, method: str, path: str, body: dict | None = None, timeout: float | None = None) -> dict:
        if self.local_port is None:
            raise PhoneError("port_forward_missing", "adb 端口转发不存在，请重连。")
        url = f"http://127.0.0.1:{self.local_port}{API}{path}"
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": "Bearer " + (self.token or ""),
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Mika-Client": self._client_version,
        })
        try:
            with self._opener.open(req, timeout=timeout or self.request_timeout) as response:
                raw = response.read(MAX_RESPONSE + 1)
                if len(raw) > MAX_RESPONSE:
                    raise PhoneError("upstream_protocol", "手机返回内容过大。", 502)
                payload = json.loads(raw) if raw else {}
                if not isinstance(payload, dict):
                    raise PhoneError("upstream_protocol", "手机返回的不是 JSON 对象。", 502)
                if "error" in payload:
                    err = payload["error"] if isinstance(payload["error"], dict) else {}
                    code = err.get("code") if isinstance(err.get("code"), str) else "upstream_error"
                    msg = err.get("message") if isinstance(err.get("message"), str) else "手机拒绝了这个请求。"
                    raise PhoneError(code, msg, 502)
                return payload
        except urllib.error.HTTPError as exc:
            exc.close()
            if exc.code == 401:
                raise PhoneError("upstream_auth", "手机拒绝了访问令牌。（令牌可能已更换，重新 --bootstrap）", 502) from None
            if exc.code == 404:
                raise PhoneError("upstream_not_found", "手机没有这个接口/任务。", 404) from None
            raise PhoneError("upstream_error", f"手机返回 HTTP {exc.code}。", 502) from None
        except (urllib.error.URLError, OSError, http.client.HTTPException, ValueError) as exc:
            raise PhoneError("port_forward_broken", "连不上手机的转发端口：" + str(getattr(exc, "reason", exc)), 503) from None

    def _read(self, method: str, path: str, body: dict | None = None, timeout: float | None = None) -> dict:
        """只读调用：失败时重连一次再按次数重试。"""
        last: PhoneError | None = None
        for attempt in range(self.read_retries):
            try:
                return self._http(method, path, body, timeout)
            except PhoneError as exc:
                if exc.code in {"upstream_auth", "upstream_not_found", "upstream_protocol"}:
                    raise
                last = exc
                self.log("warn", f"只读调用失败（{exc.code}），第 {attempt + 1}/{self.read_retries} 次：{exc.message}")
                time.sleep(min(0.3 * (2 ** attempt), 2.0))
                try:
                    self.reconnect()
                except PhoneError as rexc:
                    last = rexc
                    self.log("warn", f"重连失败：{rexc.code} {rexc.message}")
                    if rexc.code in {"device_offline", "device_unauthorized"}:
                        raise rexc
        raise last or PhoneError("upstream_error", "只读调用失败。", 502)

    # ---------- Mika 任务接口 ----------

    def probe(self) -> dict:
        info = self._read("GET", "")
        if info.get("api_version") != 1 or "tasks" not in (info.get("capabilities") or []):
            raise PhoneError("incompatible_api", "手机上的 Mika 没有任务 API v1，装新版 APK 后再试。", 502)
        return info

    def probe_fast(self) -> dict:
        """不做多次重试的探活；转发断了先重连一次，仍不行就直接报错（给提交前的快速失败用）。"""
        try:
            return self._http("GET", "", timeout=5)
        except PhoneError as exc:
            if exc.code in {"upstream_auth", "upstream_not_found", "upstream_protocol"}:
                raise
            self.reconnect()
            return self._http("GET", "", timeout=5)

    def device_state(self) -> dict:
        return self._read("GET", "/device")

    def start_task(self, goal: str, request_id: str, conversation: str | None) -> dict:
        body = {"goal": goal, "request_id": request_id}
        if conversation:
            body["conversation"] = conversation
        started = _now_ms()
        try:
            return self._http("POST", "/tasks", body)
        except PhoneError as exc:
            if exc.code in {"upstream_auth", "upstream_not_found", "upstream_protocol"}:
                raise
            # 写操作不盲目重发：先按 request_id 对账（Mika 用 request_id 作任务 id）。
            self.log("warn", f"提交结果不确定（{exc.code}），按 request_id 对账")
            for attempt in range(self.read_retries):
                try:
                    snapshot = self._http("GET", f"/tasks/{request_id}")
                    self.log("info", f"对账命中：任务 {request_id} 已在手机上（{snapshot.get('status')}）")
                    return snapshot
                except PhoneError as rexc:
                    if rexc.code == "upstream_not_found":
                        break
                    try:
                        self.reconnect()
                    except PhoneError as cexc:
                        if cexc.code in {"device_offline", "device_unauthorized"}:
                            raise PhoneError(cexc.code, cexc.message, 503, ambiguous=True) from None
                    time.sleep(min(0.3 * (2 ** attempt), 2.0))
            raise PhoneError("outcome_unknown",
                            "提交可能已到达手机但没有收到结果，未自动重发。恢复连接后按 task_id 查询。",
                            504, ambiguous=True) from None
        finally:
            self.log("debug", f"提交耗时 {_now_ms() - started} ms")

    def get_task(self, task_id: str) -> dict:
        return self._read("GET", f"/tasks/{task_id}")

    def wait_task(self, task_id: str, timeout_s: int) -> dict:
        return self._read("POST", f"/tasks/{task_id}/wait", {"timeout_s": timeout_s}, timeout=timeout_s + 5)

    def cancel_task(self, task_id: str) -> dict:
        # 写操作：不重试，交给调用方决定怎么报告。
        return self._http("POST", f"/tasks/{task_id}/cancel", {})

    def answer_task(self, task_id: str, text: str) -> dict:
        return self._http("POST", f"/tasks/{task_id}/answer", {"text": text})
