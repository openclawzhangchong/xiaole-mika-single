# 可行性报告：小乐 → 网关 → Mika 执行桥

> 打样日期 2026-11-04 · Mika `Z:\github项目\Mika` @ `6661b9e9`（v0.1.35，已从上游快进 28 个提交）· 真机 realme RMX3161 / Android 12

## 1. 结论

**这条链路成立，Mika 源码需要改 0 行。** 主契约是 MCP（WebSocket + query token）：本网关作为 MCP 服务端，把 `mika.submit_goal` 转成手机 Mika 的 `POST /api/v1/tasks`，用 `mika.get_task` 轮询回结果。最小 MCP 客户端实测跑通 `initialize → tools/list → tools/call → get_task`，`submit_goal` 1 ms 返回 task_id，8.0 s 拿到 Mika 的 `answer="2"`。

一个必须说明的边界：**Mika 真实操作手机（读设备信息、执行 shell）依赖它的「手机通道 / 任务屏」**。本次测试中途为了验证失败态强制停止过 Mika，之后该状态没有恢复，realme 又不允许 adb 写无障碍开关（见 §7），所以"经 MCP 触发手机侧 shell 命令"这一条在当前手机上暂时跑不通；同一网关、同一任务层在中断之前已经用真实设备值验证过（§2.2）。

## 2. 实测数据

### 2.1 MCP 链路（`scripts/mcp_client.py`，真实跑）

| 步骤 | 结果 | 观测 |
| --- | --- | --- |
| WebSocket 握手 + query token | 通过 | 错误 token → `HTTP/1.1 401 Unauthorized`，断开 |
| `initialize` | 通过 | 返回 `protocolVersion=2024-11-05`，`capabilities.tools` |
| `notifications/initialized` | 通过 | 无响应（通知） |
| `ping` | 通过 | `result: {}` |
| `tools/list` | 通过 | `mika.submit_goal / mika.get_task / mika.cancel_task / mika.answer_task / mika.list_tasks` |
| `tools/call` `mika.submit_goal` | 通过 | **1 ms** 返回 `task_id=ddcdb865-…`，`status=queued`（不阻塞等执行） |
| `tools/call` `mika.get_task` | 通过 | 8.0 s 时 `status=done`，`answer="2"`，`mika_status=done` |
| `serialNumber` 不匹配 | 通过 | 传 `aa:bb:cc:dd:ee:ff`，网关记 `WARNING` 后照常处理，任务仍然 `done` |

证据：`evidence/mcp_transcript.txt`；网关日志 `logs/gateway.log`（`MCP 客户端接入：127.0.0.1（path=/mcp/）`、`tools/call serialNumber=…`）。

### 2.2 真机执行（同一网关的任务层，经 HTTP 调试口）

| # | 目标 | task_id | 状态 | 耗时 | 真实结果 |
| --- | --- | --- | --- | --- | --- |
| 1 | 型号 / Android 版本 / 电量（只读） | `66a6d44a-…` | done | **64.5 s** | realme RMX3161 / Android 12 / 100%（USB 充电） |
| 2 | `wm size` 屏幕分辨率 | `fd10108e-…` | done | 29.8 s | `1080x2400` |
| 3 | SoC 型号 | `2db72b75-…` | done | 95.2 s | `SM7250`（骁龙 720G） |

以上回答由手机上的 Mika 生成，`conversation` 字段返回了 Mika 的真实会话 id（`mcp-…`），可作为"确实经过 Mika"的旁证。

### 2.3 并发（同时提交 2 个目标，验证不串台）

| 项 | 值 |
| --- | --- |
| 提交延迟 | 44 ms / 48 ms（同一秒内） |
| 结果映射 | `fd10108e` → `1080x2400`；`2db72b75` → `SM7250`，**id 与答案一一对应，无串台** |
| 总耗时 | 97.12 s（两个任务并行，各自独立轮询） |

证据：`evidence/concurrent.json`。

### 2.4 失败态与超时

| 场景 | 期望 | 实测 |
| --- | --- | --- |
| 超时（`timeout_s=30`，任务需 45 s） | 30 s 判超时并取消 | **31.84 s** 置 `status=timeout` `error.code=task_timeout`，手机侧任务随后为 `cancelled` |
| 主动取消（第 8 s 调用 `cancel`） | 立刻受理、最终 cancelled | `accepted=true`，稍后 `status=cancelled` |
| 手机端 Mika 进程被停止后提交 | 明确错误、不挂死 | `HTTP 503` `code=port_forward_broken`，**265 ms** 返回 |
| 设备不在 adb 列表（不存在的序列号） | 明确错误、不挂死 | `HTTP 503` `code=device_offline`，**87 ms** 返回 |
| 错误 MCP token | 401 并断开 | `HTTP/1.1 401 Unauthorized` |

超时判定误差从原来的单次等待窗口（最多晚 20 s）收窄到 1 s 内：`_poll` 把单次 `/wait` 窗口取剩余时间为上限。

## 3. 接口契约

### 3.1 主契约：MCP over WebSocket

- 地址：`ws://127.0.0.1:8004/mcp/?token=<token>`（`MCP_HOST` / `MCP_PORT` 可配；路径不校验，自建示例里的 `/mcp_endpoint/mcp/` 也能直接接）
- 鉴权：query `token` 或 `Authorization: Bearer`，常量时间比较；不匹配立即 `401` 并断开。token 只从 `MCP_TOKEN`（环境变量 / 本地 `.env`）读，不入库。
- 协议版本：`2024-11-05`；报文：一条 JSON-RPC 2.0 = 一个 WebSocket 文本帧。
- 必须实现的方法：`initialize`、`notifications/initialized`、`tools/list`、`tools/call`、`ping`。
- `tools/call` 的 `params` 允许携带 `serialNumber`（小智传的设备序列号）：仅记录与比对，**不一致也继续处理**，不报错。

工具：

| 工具 | 入参 | 出参（`content[0].text` 里的 JSON） |
| --- | --- | --- |
| `mika.submit_goal` | `goal`（必填，≤4000 字）、`session_id`、`conversation`、`timeout_s`(30..1800) | `{task_id, status, created, poll_with, hint}`，**立即返回** |
| `mika.get_task` | `task_id` | 任务快照（见 §3.3） |
| `mika.cancel_task` | `task_id` | `{task_id, accepted, status}` |
| `mika.answer_task` | `task_id` + `text` | 任务快照；用于 `waiting_for_answer`（Mika 在手机上反问） |
| `mika.list_tasks` | `limit`(1..100) | `{tasks:[快照…]}` |

`initialize` 响应示例：

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05",
 "capabilities":{"tools":{"listChanged":false}},
 "serverInfo":{"name":"xiaole-mika-gateway","version":"0.1.0"}}}
```

`tools/call` 响应示例（工具内部错误用 `isError:true`，不打断连接）：

```json
{"jsonrpc":"2.0","id":8,"result":{"content":[{"type":"text","text":"{\"task_id\":\"ddcdb865-…\",\"status\":\"queued\"}"}],"isError":false}}
```

### 3.2 本地调试口（HTTP + SSE，非主契约）

监听 `http://127.0.0.1:8790`，仅用于自测/排障。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/goal` | `{"goal","session_id","conversation","timeout_s","request_id"}` → `202` 任务快照；`request_id` 即 task_id，重复提交返回 `200` 且 `idempotent_replay=true` |
| GET | `/task/{id}` | 任务快照 |
| GET | `/task/{id}/events?since=N` | SSE：`snapshot`/`status`/`progress`/`result`/`error`/`cancel_requested`，带 `id:` 可断线续传 |
| POST | `/task/{id}/cancel` | 取消 |
| POST | `/task/{id}/answer` | `{"text"}` 回答手机侧反问 |
| GET | `/tasks?limit=` | 最近任务 |
| GET | `/health` | 手机连通性、Mika 版本、端口映射 |

### 3.3 任务快照字段

`task_id, session_id, goal, conversation, status, mika_status, created_at_ms, updated_at_ms, deadline_at_ms, progress, step, question, waiting_for, note, answer, error{code,message}, cancel_requested, attempts, finished, duration_ms`。

`status` 取值 = Mika 的 `starting/queued/running/paused/waiting_for_answer/waiting_on_phone/done/failed/cancelled`，网关另加 `timeout`（网关时限）与 `unknown`（断连后未能确认，可恢复）。

### 3.4 错误码

| HTTP | code | 含义 |
| --- | --- | --- |
| 400 | `invalid_request` | 参数不合法（goal 空/过长、timeout 越界、request_id 非 canonical UUID…） |
| 404 | `task_not_found` | 网关没有该任务 |
| 409 | `task_finished` | 任务已结束还回答 |
| 429 | `too_many_tasks` | 未完成任务 ≥ 32 |
| 502 | `upstream_auth` / `upstream_protocol` / `upstream_error` | 手机拒绝令牌 / 返回异常 |
| 503 | `device_offline` / `device_unauthorized` / `device_selection` | 设备不在、未授权、多台设备未指定 |
| 503 | `connection_info_missing` / `stale_connection` | 手机没开 USB 电脑连接 / 重启后信息过期 |
| 503 | `port_forward_broken` / `adb_error` / `adb_unavailable` | 转发断了 / adb 出错 / 找不到 adb |
| 504 | `outcome_unknown` | 提交结果不确定，未自动重发 |

重试策略：只对只读调用重试（默认 3 次，指数退避，每次先重建转发）；写操作不盲重发，`submit` 失败时按 `request_id` 去手机对账，对不上才返回 `outcome_unknown`。

## 4. Mika 的真实接口面（源码确认，不靠 README）

- HTTP 服务跑在 **APK 进程内**（`MiniHttpServer`），不是 PC 侧进程；USB 模式下只绑定 `127.0.0.1`（`RemoteHost.kt:12,54-58`），电脑侧靠 `adb forward` 进来（转发后的连接在手机看来就是回环）。
- 鉴权：`Bearer <token>`。**任何带 `Origin` 的请求一律 403**（`RemoteAccess.kt:34-35`），只接受私有地址；普通 token 全局有效，`loopbackToken`（USB 电脑连接用的那个）只认回环来源（`RemoteAccess.kt:48-50`）。
- 端口/令牌来源：手机端脚本 `connect-computer.sh` 启动前台服务并把 `{token, port, boot}` 写进 `/sdcard/Android/data/com.wangzan101.mika/files/mcp-usb.json`（`McpRuntime.kt:177-201`）。默认端口 8765。
- REST 路由（`RemoteTaskApi.kt:43-104`）：`GET /api/v1`、`GET /device`、`GET /tasks`、`POST /tasks`、`GET /tasks/{id}`、`POST /tasks/{id}/wait`、`/answer`、`/steer`、`/cancel`。
- 「提交目标→拿结果」已有现成入口：`POST /tasks {goal, conversation?, request_id?}`；**`request_id` 直接成为任务 id**（canonical 小写 UUID，`RemoteTaskService.kt:39`），所以网关用它做幂等与并发隔离。`/wait` 支持长轮询（上限 50 s）。
- 状态机见 `RemoteTasks.kt:45-54`；`waiting_on_phone` 表示"必须人在手机上操作，远程回答不了"，网关照实透出并不自动回答。
- 命令下发不是在 PC 侧跑 adb，也不是终端子进程：由 Mika 的手机通道在**任务虚拟屏**上执行；`phone_system_command` 在拿不到屏时直接 `no_app_open`（`PhoneAdvancedTools.kt:331`）。多任务隔离靠各自的任务/会话 id + 独立虚拟屏，网关这一侧只按 task_id 隔离。

## 5. Mika 需要的最小改动：0 行

依据：`POST /tasks` 已接受 `goal` + `request_id` + `conversation`，已有 `GET /tasks/{id}`、`/wait`（长轮询）、`/cancel`、`/answer`，状态字段齐全，USB 令牌与 `adb forward` 是官方支持的接入方式（`connect-computer.sh` + `mcp-usb.json`）。网关只做转发、状态映射和错误码，不需要任何 Mika 代码改动。本次测试对 Mika 仓库只做了 `git pull --ff-only`，没有修改。

## 6. 本次未通过 / 未确认

1. **经 MCP 触发"手机侧真实命令执行"未在终态复现。** 网关、MCP、任务层都正常（`done` + 真实回答），失败点在手机：Mika 的无障碍/手机通道未开启，`phone_system_command` 拿不到任务屏。Mika 自己给出的原因是"无障碍服务未开启 / 手机助手未运行"，随后又说明当前任务里没有 `phone_system_command` 这个工具。图表中的真实设备值（§2.2）是在该状态丢失之前用同一网关跑出来的，可作为链路能力的证据，但不能算"当前状态下也通过"。
2. **物理拔 adb 未做。** 本机没有管理员权限，禁用 USB PnP 设备需要 UAC 弹窗（用户明确不接受弹窗）；改用两种等价真实故障：① 停掉手机端 Mika 进程 → `port_forward_broken` 265 ms；② 用不存在的序列号 → `device_offline` 87 ms。都返回明确错误、不挂死，但没有覆盖"USB 线被拔掉"这一物理事件本身。
3. **未连云。** 按要求没有向 `api.xiaozhi.me` 发起 OTA 或 MCP 握手：PC 脚本模拟设备连云端可能影响后台已绑定记录（OTA 请求会带设备身份，存在触发重新激活/覆盖的风险），风险不可控，因此只做本地 `ws://` 验证。真要接云端，需要先在测试账号上确认 OTA 对已绑定设备是否幂等。
4. **已装 APK 是 0.1.34，源码是 0.1.35。** 本次验证用的接口在 0.1.34 上就已存在，未重装；升级后需回归一次。

## 7. 设备身份与本地配置

- 使用用户已绑定的设备身份作为 `serialNumber` 原样透传，**未做任何格式转换**（保持小写、带冒号）。值只放在本地 `.env`（已被 `.gitignore` 挡住），仓库内的 `.env.example` 只有空字段，文档与代码里都不出现具体值。
- 网关对该值只做"记日志 + 不一致告警后继续"，不参与鉴权，不影响任何任务。

## 8. 复现步骤

```powershell
# 1) 手机连好 USB，打开一次 Mika；.env 里配好 MCP_TOKEN / MIKA_DEVICE / XIAOZHI_SERIAL_NUMBER
cd Z:\github项目\xiaole-mika-lianhe
python -m gateway --bootstrap --log-file logs\gateway.log

# 2) 另开一个终端跑最小 MCP 客户端
python scripts\mcp_client.py --goal "查询这台手机的型号和 Android 版本"

# 3) 本地 HTTP 调试（并发/失败态）
python scripts\e2e.py --base http://127.0.0.1:8790
```

若 `mika.get_task` 的 `answer` 里出现"无障碍服务没有开启"，请在手机上手动开启 Mika 的无障碍服务后再跑第 2 步；这是手机权限问题，不是网关问题。
