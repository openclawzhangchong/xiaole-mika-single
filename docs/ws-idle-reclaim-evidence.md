# 证据：云端按「业务消息空闲」回收 WS（1005 / ~60–70s）与 pingInterval 无效

> 入库证据说明。原始日志均来自真机（realme RMX3161，`7f:f1:b7:5e:ef:aa`，M5Stack CoreS3 身份），
> 日志文件：`C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log`（下称 A 日志）。

## 1. 结论（可入库一句话）

**服务端对 WebSocket 的回收依据是"业务消息空闲"，不是 TCP/WS 层的 ping。**
6.11.6 已把 WS 层 `pingInterval` 设为 25s，真机仍每 **70s 左右**被 `code=1005` 静默关闭；
未加 ping 的 6.11.5 则是 **60.26s** 被 `code=1006` 回收——两者同量级，说明 ping 没有续命作用。
上游文档（`websocket_zh.md` / `mcp-protocol_zh.md`）没有定义任何 WS 心跳或空闲超时条款，
所以只能靠实验确认"哪条业务消息算活跃"（见 §4）。

## 2. 时间序列（6.11.6+58，`pingInterval=25s`，全程安静不说话）

| # | 连上 | 被断开 | 存活 | close code | 重连时刻 / 延迟 |
|---|---|---|---|---|---|
| 1 | 17:10:13.527 | 17:11:23.330 | **69.8s** | `1005` | 17:11:25.336 / +2s |
| 2 | 17:11:25.336 | 17:12:33.240 | **67.9s** | `1005` | 17:12:37.247 / +4s |
| 3 | 17:12:37.247 | —（17:13:41 被外部降级覆盖安装打断） | — | — | — |

对照（6.11.5+57，无 pingInterval）：`16:07:53.809` 连上 → `16:08:54.071` 断开 = **60.26s**，`code=1006`。

**关键点**：加 ping 前 60.26s、加 ping 后 67.9–69.8s，同一量级；`1006`→`1005` 只说明这次是"无 close frame 的静默关闭"，并没有变长。

## 3. 原始日志行（逐字照抄，A 日志行号）

```
1126:11-04 17:10:12.519 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 连接已断开 code=1005 reason= attempts=0 kind=服务器
1127:11-04 17:10:12.520 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 1005=服务器回收连接（多为静默超时，属正常），自动重连
1128:11-04 17:10:12.520 I/flutter (18739): WARNING: ...: ChatScreen: WebSocket 已断开 closeCode=1005
1145:11-04 17:10:13.527 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 已连接到 wss://api.tenclass.net/xiaozhi/v1/

1954:11-04 17:11:23.330 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 连接已断开 code=1005 reason= attempts=1 kind=服务器
1955:11-04 17:11:23.330 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 1005=服务器回收连接（多为静默超时，属正常），自动重连
1956:11-04 17:11:23.330 I/flutter (18739): WARNING: ...: ChatScreen: WebSocket 已断开 closeCode=1005
1991:11-04 17:11:25.336 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 已连接到 wss://api.tenclass.net/xiaozhi/v1/

2875:11-04 17:12:33.240 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 连接已断开 code=1005 reason= attempts=2 kind=服务器
2876:11-04 17:12:33.241 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 1005=服务器回收连接（多为静默超时，属正常），自动重连
2877:11-04 17:12:33.241 I/flutter (18739): WARNING: ...: ChatScreen: WebSocket 已断开 closeCode=1005
2946:11-04 17:12:37.247 I/flutter (18739): INFO: ...: XiaozhiWebSocketManager: 已连接到 wss://api.tenclass.net/xiaozhi/v1/
```

推断依据：`code=1005`（无 close frame）+ 固定 60–70s 区间 + ping 无效 ⇒ 服务端在应用层按"最后一条业务消息"计时回收。

## 4. 心跳实验设计（v6.11.8，默认关）

实现位置：`lib/core/network/xiaozhi_websocket_manager.dart`（`WsProbeMode` + `[PROBE]` 日志）；
开关入口：开发者中心「调试 → WS 心跳实验」（`AppFeats.wsProbeMode`，默认 `off`，间隔 30s，可 10–120s）。

| 候选 | 定时消息 | 目的 |
|---|---|---|
| ① `hello` | 完整 hello（version/device-id/features/audio_params） | 重握手是否算活跃 |
| ② `detect` | `{"type":"listen","state":"detect"}` | 文档里的唤醒态是否算活跃 |
| ③ `abort` | `{"type":"abort","reason":"heartbeat"}` | 控制类消息是否算活跃 |
| ④ `ping` | 不发业务消息（仅 WS `pingInterval=25s`） | 对照组，应仍在 ~70s 被 1005 |

记录点（全部走 `[PROBE]` 前缀，真机用 `adb -s 36c77fb6 logcat | findstr PROBE` 抓）：
启动候选与间隔、每次 tick 的 `seq/t/recv`、本连接首个服务器帧时刻、断开时 `存活秒数 + 发送数 + 收到帧数 + closeCode`。

**判定阈值**：同一手机、同一智能体、安静不说话，**连接撑过 3 分钟且无 `code=1005`** → 该消息算"业务活跃"；仍在 ~70s 被 1005 回收 → 排除。每候选跑 4–5 分钟。

**设备窗口估算**：4 个候选各 5 分钟 = 20 分钟；加切换/核对/回退 ≈ **25 分钟**（不含装机时间）。
切换候选后聊天页会立即重建连接（`wsProbeRevision` 监听），不必等 70s 自然回收，避免"候选有效→永远切不到下一个"的死锁。

## 5. 边界说明

实验只回答"哪条消息能续命"，不改变生产默认：`off` 为默认，`allOff()` 会把探针归零。
即使找到有效心跳，也只按"可配置间隔"接入；若 4 个候选全部无效，则生产继续用 6.11.7 的"无感重连"（不消除回收，只让用户无感）。
