"""入口：python -m gateway"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import threading

from .app import make_server
from .cloud import CloudLink
from .mcp import McpService, McpWsServer
from .phone import MikaPhone, PhoneError
from .tasks import TaskManager


def load_env(path: str | None) -> None:
    """读本地 .env（不入库），只补全还没设置的环境变量。"""
    if not path or not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def build_logger(path: str | None, verbose: bool) -> logging.Logger:
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if path:
        handlers.append(logging.FileHandler(path, encoding="utf-8"))
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)-5s [%(threadName)s] %(name)s: %(message)s",
        handlers=handlers,
        force=True,
    )
    return logging.getLogger("gateway")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m gateway",
                                 description="小乐 ↔ Mika 执行桥：MCP 主契约 + 本地 HTTP 调试口")
    ap.add_argument("--env-file", default=".env", help="本地配置（token、设备身份），不入库")
    ap.add_argument("--host", default=None, help="HTTP 调试口地址")
    ap.add_argument("--port", type=int, default=None, help="HTTP 调试口端口")
    ap.add_argument("--mcp-host", default=None, help="MCP websocket 地址")
    ap.add_argument("--mcp-port", type=int, default=None, help="MCP websocket 端口（默认 8004）")
    ap.add_argument("--mcp-token", default=None, help="MCP 鉴权 token；优先用环境变量 MCP_TOKEN")
    ap.add_argument("--mode", choices=("local", "cloud", "both"), default=None,
                    help="local=本地监听（默认）；cloud=主动外连小智云端；both=两者都开")
    ap.add_argument("--adb", default=os.environ.get("MIKA_ADB", "adb"), help="adb 可执行文件")
    ap.add_argument("--device", default=os.environ.get("MIKA_DEVICE"), help="手机序列号（多台设备时必填）")
    ap.add_argument("--bootstrap", action="store_true",
                    help="启动时运行手机上的 connect-computer.sh，打开 Mika 的 USB 电脑连接")
    ap.add_argument("--timeout", type=int, default=None,
                    help="任务默认时限（秒）")
    ap.add_argument("--max-concurrent", type=int, default=4)
    ap.add_argument("--wait-window", type=int, default=20, help="单次向手机等待的秒数（Mika 上限 50）")
    ap.add_argument("--log-file", default=None, help="把网关日志同时写到文件")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    load_env(args.env_file)
    log = build_logger(args.log_file, args.verbose)

    # .env 是在解析参数后才加载的，这里再补一次环境变量兜底。
    if args.device is None:
        args.device = os.environ.get("MIKA_DEVICE")
    if args.timeout is None:
        args.timeout = int(os.environ.get("GATEWAY_TASK_TIMEOUT", "300"))

    host = args.host or os.environ.get("GATEWAY_HOST", "127.0.0.1")
    port = args.port or int(os.environ.get("GATEWAY_PORT", "8790"))
    mcp_host = args.mcp_host or os.environ.get("MCP_HOST", "127.0.0.1")
    mcp_port = args.mcp_port or int(os.environ.get("MCP_PORT", "8004"))

    phone = MikaPhone(adb=args.adb, device=args.device, log=lambda level, msg: getattr(log, level)(msg))
    try:
        phone.connect(do_bootstrap=args.bootstrap)
        info = phone.probe()
        log.info("手机就绪：%s，Mika %s，端口 %s → 本机 %s", phone.device, info.get("server_version"),
                 phone.phone_port, phone.local_port)
    except PhoneError as exc:
        log.warning("手机暂时不可用（%s）：%s  网关仍会启动，提交时会返回该错误码。", exc.code, exc.message)

    manager = TaskManager(phone, timeout_default=args.timeout, max_concurrent=args.max_concurrent,
                          wait_window=args.wait_window, log=lambda level, msg: getattr(log, level)(msg))

    mcp_server = None
    cloud_link = None
    cloud_enabled = os.environ.get("CLOUD_ENABLED", os.environ.get("cloud.enabled", "false")).strip().lower() in {
        "1", "true", "yes", "on"}
    mode = args.mode or os.environ.get("GATEWAY_MODE") or ("both" if cloud_enabled else "local")
    token = args.mcp_token or os.environ.get("MCP_TOKEN")
    service = McpService(manager, expected_serial=os.environ.get("XIAOZHI_SERIAL_NUMBER"),
                         log_fn=lambda msg: log.info(msg))

    if mode in ("local", "both"):
        if token:
            mcp_server = McpWsServer((mcp_host, mcp_port), service, token)
            threading.Thread(target=mcp_server.serve_forever, name="mcp", daemon=True).start()
            log.info("MCP 服务监听 ws://%s:%d/mcp/?token=<已配置>", mcp_host, mcp_server.server_address[1])
        else:
            log.error("没有配置 MCP token（环境变量 MCP_TOKEN 或 .env），本地 MCP 服务未启动；HTTP 调试口仍可用。")

    if mode in ("cloud", "both"):
        cloud_url = os.environ.get("XIAOZHI_MCP_URL") if cloud_enabled else None
        if cloud_url:
            status_path = os.environ.get("CLOUD_STATUS_FILE") or os.path.join(
                os.path.dirname(os.path.abspath(args.log_file)) if args.log_file else os.getcwd(),
                "logs", "cloud-link-status.json")
            os.makedirs(os.path.dirname(status_path), exist_ok=True)
            cloud_link = CloudLink(service, cloud_url, os.environ.get("XIAOZHI_MCP_AUTH", "query"),
                                   log_fn=lambda msg: log.info("[云端] %s", msg), status_path=status_path)
            cloud_link.start()
            log.info("外连模式已启动（地址来自 XIAOZHI_MCP_URL，host=%s）",
                     cloud_link.auth_url.split("/mcp/")[0].replace("wss://", ""))
        elif cloud_enabled:
            log.error("mode=%s 且 cloud.enabled=true，但没有配置 XIAOZHI_MCP_URL，外连未启动。", mode)
        else:
            log.warning("mode=%s 但 cloud.enabled=false，外连未启动（默认只本地监听）。", mode)

    server = make_server(host, port, manager, phone)
    log.info("HTTP 调试口监听 http://%s:%d", host, server.server_address[1])
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("收到中断，正在退出")
    finally:
        server.shutdown()
        server.server_close()
        if mcp_server is not None:
            mcp_server.shutdown()
            mcp_server.server_close()
        if cloud_link is not None:
            cloud_link.stop()
        phone.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
