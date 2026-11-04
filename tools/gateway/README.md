# 早期 MCP 网关方案（保留供参考）

**状态：已被 hub 承载方案取代，本目录不再演进。** 云端接入点现由 `xiaozhi-openclaw-mcp-hub2027` 负责连接，
本网关只作为"本地执行桥"的历史实现留档（原始代码从 `xiaole-mika-lianhe` 迁入，未做行为改动）。

## 它当时做什么

一段文字目标 → 网关 → 手机上的 Mika 执行 → 结果回传。主契约是 MCP：

```
mika.submit_goal / mika.get_task / mika.cancel_task / mika.answer_task / mika.list_tasks
```

HTTP + SSE 只是本地自测与排障用，不是对外契约；音频不走这里。

## 运行（本地自测）

```bash
python -m tools.gateway --bootstrap
# MCP: ws://127.0.0.1:8004  /  HTTP 调试口: http://127.0.0.1:8790
```

配置走环境变量（**不要把真实值提交进仓库**，模板见 `scripts` 同级说明）：

```
MCP_TOKEN=<自己生成>
MIKA_DEVICE=<adb devices 里的序列号>
CLOUD_ENABLED=false          # 默认 false，不主动外连
```

## 目录

| 文件 | 作用 |
|---|---|
| `__main__.py` / `app.py` | 入口与 HTTP/SSE 调试口 |
| `mcp.py` | MCP 服务端（工具定义与分发） |
| `tasks.py` | 任务状态机（submit/get/cancel/answer/list） |
| `phone.py` | 与设备侧 Mika 的桥 |
| `ws.py` / `cloud.py` | 连接管理与外连模式（默认关闭） |
| `scripts/e2e.py` | 端到端自测（submit → sse → task → timeout） |
| `scripts/mcp_client.py` | 最小 MCP 客户端（initialize → tools/list → tools/call → get_task） |
| `scripts/mock_cloud.py` | 模拟云，离线验证协议 |

> 注：迁入时仅移动文件，未接入本项目 CI；不参与 APK 构建。
