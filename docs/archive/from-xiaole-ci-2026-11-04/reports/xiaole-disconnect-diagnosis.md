# 小乐 APK「一直断线连不上」断线诊断报告

**结论（第一行）：断线真实原因不是 token/401，而是 App 当前停在 `ws://127.0.0.1:8899` 这个本机联调智能体上——该端点由 PC 侧的假小智服务端（`fake_xiaozhi_mcp_server.py`）提供，它每轮发完 `mika.submit_goal` / `mika.get_task` 就主动关闭连接，App 按 1/2/4/8/16/30s 退避无限重连，界面上就是「未连接 / 已断开 / 重连」。云端智能体（`wss://api.tenclass.net/xiaozhi/v1/`）本身连接正常，OTA 下发的就是 `test-token`，服务端接受该 token，全程没有任何 401/403。**

> 附注：手机当前安装的 APK **不是**我们 CI 出的那一个（`lastUpdateTime=16:11:55` 被另一份含 `mika.*` 工具的构建覆盖过，见第 5 节）。即使换回我们的包，只要默认进入的仍是 8899 这个智能体，症状完全一样。

---

## 1. 抓到的证据

完整日志（清空 logcat 后复现，保存于临时目录）：

| 文件 | 时间窗 | 内容 |
|---|---|---|
| `<TEMP>\xiaole-apk\agent1.log` | 16:03:32–16:03:58 | 我们的 CI 包 + 云端智能体，连接全程正常 |
| `...\stability3m.log` | 16:07:53–16:10:57 | 云端智能体，60.26s 后 1006，之后进程被冻结、未再重连 |
| `...\stability3m_b.log` | 16:12:24–16:15:48 | 云端智能体正常 → 切到 8899 智能体后进入无限 1006 循环 |
| `...\diag_clean200s.log` | 16:20:30–16:23:23 | 200s 前台不触碰，8899 智能体，连续 9 次 1006 |

### 1.1 云端智能体：握手正常，无 401

```
16:12:24.306  XiaozhiWebSocketManager: 正在连接 wss://api.tenclass.net/xiaozhi/v1/
16:12:24.306  XiaozhiWebSocketManager: 设备ID: 92:81:7a:fb:a6:fb
16:12:24.306  XiaozhiWebSocketManager: Token启用: false
16:12:24.306  XiaozhiWebSocketManager: 添加默认Authorization头: Bearer test-token
16:12:24.306  XiaozhiWebSocketManager: 使用headers方式连接WebSocket成功      ← 握手成功，无 401/403
16:12:24.309  OTA Response: {... "websocket": {"url":"wss://api.tenclass.net/xiaozhi/v1/","token":"test-token"}}
16:12:24.571  收到服务器 hello: {"type":"hello",...,"session_id":"483aab2b"}
16:12:24.573  收到 mcp initialize → 24.575 回 result 成功
16:12:24.613  收到 mcp tools/list → 24.618 回 31 项工具成功
```

同一模式在 `agent1.log`（16:03:32）与 `stability3m.log`（16:07:53）各完整复现一次：**OTA 200 → WS 握手成功 → hello → MCP initialize/tools/list 全线通过**。

### 1.2 8899 智能体：假服务端每轮主动挂断 → 无限重连（当前用户看到的现象）

```
16:13:27.047  AgentModel(id: 6565c9e0-..., name: 小乐1793779009474, url: ws://127.0.0.1:8899, token: to-test, ...)
16:13:27.576  收到 mcp 帧：{"method":"tools/call","params":{"name":"mika.submit_goal",...}}
16:13:52.585  App 回 result：{"ok":false,"error":{"code":"mika_timeout","message":"Mika 网关 /goal 请求超时（15000ms）"}}
16:13:52.589  XiaozhiWebSocketManager: 连接已断开 code=1006 reason= attempts=0 kind=服务器   ← 服务端挂断
16:13:52.591  网络中断，1.0s 后第 1 次自动重连…
```

200s 干净测试（不触碰屏幕）里这个循环跑了 9 次：`16:20:30 / 16:20:37 / 16:20:48 / 16:21:01 / 16:21:20 / 16:21:47 / 16:22:19 / 16:22:51 / 16:23:23`，全是 `code=1006 reason= attempts=N kind=服务器`。

假服务端源码（`<HOME>\Documents\Trae-CN\temp_20261104_04\fake_xiaozhi_mcp_server.py`，另一个 session 起的，PC 进程 PID 5608 仍在跑）里对 `mika.submit_goal` 结果做判定后 `break` 退出循环，`break` 即关闭 WS —— 与日志中"每次 1006 都紧跟一次 tools/call 返回"完全对齐。`adb reverse --list` 里 `tcp:8899 tcp:8899` 仍在映射。

### 1.3 云端智能体 60 秒后被断（第二类，独立问题）

```
16:07:53.809  已连接到 wss://api.tenclass.net/xiaozhi/v1/
16:08:54.071  连接已断开 code=1006 reason= attempts=0 kind=服务器     ← 距连接恰好 60.26s，reason 为空
16:08:54.072  （无后续 "正在连接"，日志到 16:10:57 也没有重连动作）
16:08:54.646  OplusHansManager: freeze uid: 10352 com.zcstudy.xiaole pids: [27053]
```

- 60.26s 且 `reason=` 为空、无 close frame，符合"服务端/中间层回收空闲长连接"特征；我方 `XiaozhiWebSocketManager` **没有设置 `pingInterval`**（代码里只有 `IOWebSocketChannel.connect(uri, headers:)`），空闲时没有任何保活帧。
- 冻结发生在断开**之后** 0.57s，所以这次不能说是冻结导致的断线；但冻结导致"该重连时 Dart 定时器没跑"，于是用户看到的是**断了之后再也不回来**。
- 该结论只有 1 个样本，需要第 2 次干净实测才能坐实"60s 空闲回收"。

## 2. 当前配置对照（用户猜测的证伪）

| 项 | 实际值（日志实证） |
|---|---|
| 当前智能体 | `6565c9e0-36a6-468f-9527-c1b8bab1184f` / `小乐1793779009474` / `ws://127.0.0.1:8899` |
| 另一个（能连的） | `642093bc-fd5e-4038-aba8-33af988adfa8` / `小乐1793777857804` / `wss://api.tenclass.net/xiaozhi/v1/` |
| token 分支 | `enableToken:false` → 走默认头 `Bearer test-token`（`chat_page.dart:923`、`:937`） |
| OTA 下发 token | `test-token`（官方 OTA 就是这么下发的，不是我们写死绕过校验） |
| HTTP 状态 | OTA 全部 200，WS 握手全部成功；**日志里没有任何 401/403** |
| 设备身份 | `92:81:7a:fb:a6:fb`（App 自生成并绑定到每个 agent），**不是** `7f:f1:b7:5e:ef:aa` |
| MQTT client_id | `GID_test@@@92_81_7a_fb_a6_fb@@@a9cb3bf8-...` |

**对"401 循环"猜测的判定：推翻。** 依据是三条独立证据：(a) OTA 响应把 `test-token` 作为 `websocket.token` 下发，本来就是服务端签发的握手凭证；(b) 握手行 `使用headers方式连接WebSocket成功` 在三次测试中都出现，401 会在握手阶段直接失败并打出 HTTP 状态；(c) 握手后服务端照常下发 `hello` + `mcp initialize` + `tools/list`——鉴权已通过。

## 3. 能连的 vs 默认的，差在哪

| 差异项 | 能连的（1793777857804） | 当前默认的（1793779009474） |
|---|---|---|
| url | `wss://api.tenclass.net/xiaozhi/v1/` | `ws://127.0.0.1:8899`（本机回环，依赖 `adb reverse` + PC 假服务端） |
| token | `to-test`（未启用，实际用 OTA 的 `test-token`） | `to-test`（同左） |
| agent id | `642093bc-…` | `6565c9e0-…` |
| device id | 相同 `92:81:7a:fb:a6:fb` | 相同 `92:81:7a:fb:a6:fb` |
| 谁在服务端说话 | 官方云（会下发 hello/MCP，长连接） | PC 假服务端（每轮测试后主动 close） |
| 结果 | 15s+ 连接正常，MCP 全通过 | 每 7~20s 被挂断一次，无限重连 |

结论：**url 是唯一实质差异**，token/agent id/device id 三者都相同。

## 4. 界面取证（`run-as`/数据目录拿不到，已改截图）

```
run-as: package not debuggable: com.zcstudy.xiaole
ls /data/data/com.zcstudy.xiaole/shared_prefs: Permission denied
```

（release 包非 debuggable，`shared_prefs`/本地 db 均不可读，故此节以截图为准）

- `diag_app.png`：智能体列表只有两项——`小乐1793777857804`（15:37）、`小乐1793779009474`（15:57），两项均显示「点击开始对话」，无状态标签、无 url 展示。
- `now2.png`：App 回到前台时直接停在 `小乐1793779009474` 的聊天页，标题「小乐1793779009474 • 未连接」，红色横幅「已断开」，右侧「重连」。**这就是用户所述的"一直断线连不上"的界面状态。**
- 该聊天页属于 App 任务栈顶（`am start` 提示 "current task has been brought to the front"），即**冷启动/回前台直接落在这个连不上的智能体上**，用户一开 App 就是"已断开"。

## 5. 附带发现（必须一起处理，否则复测无意义）

1. **装的不是我们的包。**
   - `firstInstallTime=2026-11-04 15:19:29`（我们装 CI 包的时刻），但 `lastUpdateTime=2026-11-04 16:11:55` —— 16:11:55 被另一份包覆盖。
   - 运行日志里有 `mika.submit_goal` / `mika.get_task` 及其 `mika_timeout` 业务错误；CI 仓库 master（`c315bc4`）`lib/` 下 grep 不到 `mika.submit_goal|mika_timeout`，说明当前跑的是另一分支（`feat/mika-mcp-tools`）的构建。
   - 已装包 sha 与我们 artifact（`3f59ea41…`）不同，`libapp.so` 同尺寸不同 hash。
2. **另一个 session 的设备占用。** PC 侧假服务端 PID 5608 仍在跑、`adb reverse tcp:8899` 仍在、前台 App 是 `com.wangzan101.mika`（`mResumedActivity`），我们 App 被挤到后台并触发 `OplusHansManager freeze uid:10352 com.zcstudy.xiaole`。
3. **一处真实崩溃（待复核）。**
   ```
   16:08:00.293 E/flutter: Unhandled Exception: Null check operator used on a null value
     #0 _ChatPageState._setupMcpResponder.<anonymous closure> (chat_page.dart:971)
     #1 XiaozhiMcpResponder._sendError (xiaozhi_mcp_responder.dart:204)
   ```
   服务器下发不认识的 MCP 请求时，错误回包路径里有 `!` 空断言；这会让该次 MCP 调用直接抛异常（不断线，但设备端 MCP 静默失败）。

## 6. 修复动作（按根因，等你确认后执行）

按证据，用户设想的"token 三步走"（`enableToken:true` + 真 token + 401 重拉 OTA）**不成立**，不需要改，`test-token` 默认分支也不动。真正要做的是：

**A. 立刻让用户可用（不改代码，环境侧）**
1. 在 App 里把「上次进入的智能体」切回 `小乐1793777857804`（云端），或删掉 `小乐1793779009474`（8899 联调项）。
2. 停掉 PC 侧假服务端 + 撤销 `adb reverse tcp:8899`，否则该智能体永远连不上。

**B. 代码侧（需你拍板是否做）**
3. 加 WS 保活：`XiaozhiWebSocketManager` 里给 `IOWebSocketChannel` 设 `pingInterval`（建议 20–30s），避免云端长连接在 ~60s 空闲被回收（第 1.3 节）。改动点：`lib/core/network/xiaozhi_websocket_manager.dart:151`。
4. （可选）重连时不再重复打 OTA / 断线后重连失败要能看出来：目前每次重连都新打一次 OTA（日志每轮 `OTA Response` 一次），且 `_onDisconnected` 打印的 `attempts` 用的是旧值。
5. 第 5.3 节的空断言修掉（`chat_page.dart:971` 一带）。

**C. 出包与验收**
6. 用我们自己的 CI 包重新装机（覆盖另一份构建），设备身份仍用 App 现有的 `92:81:7a:fb:a6:fb`；**不新建绑定、不触发激活**（OTA 已返回 `activation=false`）。
7. 验收：云端智能体前台不动手，连续 ≥3 分钟无 `code=` 断线行，贴首尾时间戳。

> 待你确认两点：(1) 是否允许我删/切换手机上的 8899 联调智能体、停掉另一 session 的假服务端与 `adb reverse`；(2) 保活（A/B 中的第 3 项）是否纳入本次修复并重出包。
