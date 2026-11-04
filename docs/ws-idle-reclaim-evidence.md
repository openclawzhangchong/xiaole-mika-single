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

## 5. 实验结果与副作用评估（v6.11.8+60 真机，2026-11-04 18:05–18:33）

> 同机同智能体、安静不说话、探针间隔 30s、WS `pingInterval=25s` 全程保留。
> 日志：`xiaole-apk\verify_v2.log`（完整 logcat）、`xiaole-apk\probe_*.log`（`[PROBE]` 单线）。

| 候选 | 存活 | 发送 | 收帧 | 判定 |
|---|---|---|---|---|
| ④ ping 对照 ×4 | 66 / 67 / 68 / 69s | 0 | 4 | FAIL（基准成立） |
| ② detect | **≥240s 未断**（8 tick） | 8 | 4→406 | **PASS** |
| ① hello | 68s | 2 | 12 | FAIL |
| ③ abort | 65s | 2 | 4 | FAIL |

### 5.1 406 帧构成（detect 连接 18:20:26→18:24:26）

| 类别 | 数量 | 说明 |
|---|---|---|
| 文本 JSON | 62 | `tts`=43、`stt`=8、`llm`=7、`mcp`=3、`hello`=1 |
| 二进制音频 | **344** | 406 − 62；均为 TTS opus 音频帧 |
| 合计 | 406 | 每个 detect tick 约带来 43 帧（≈1 轮 TTS） |

### 5.2 三问逐一结论

1. **会不会触发服务端 ASR？——会。**
   每个 tick 后 <200ms 必回 `{"type":"stt","text":"小智"}`（8 tick = 8 条，文本完全一致）。
   证据：`18:20:56.536 发送 listen detect` → `18:20:56.648 收到 stt("小智")`。
2. **会不会推 TTS 给我们播？——会，且真实外放。**
   `stt` 后紧接 `tts start` → `llm("😊","happy")` → `tts sentence_start`（"哎，我在呢！""有什么事要我帮忙吗？"等，
   8 tick 各不相同）→ `tts stop`。窗口内 `AudioTrack(29296)` 共 **10 次 start**，
   `18:20:58.868 AudioTrack set() ... sampleRate 16000` 实证外放。43 条 tts 文本 / 344 个音频帧即由此产生。
3. **会不会让设备麦克风被打开？——未证实（本窗口内未见）。**
   全程 `AudioRecord*` 命中 **0 条**（pid 29296），App 未启动录音；但服务端在没有上行音频的情况下仍返回了
   `stt("小智")`，说明"识别"是服务端在 detect 模式下自行判定/回填，其内部机制**未证实**。

### 5.3 风险评估（上线前必读）

- `detect` 保活的本质是"**每 45s 主动叫醒一次助手**"：能续命，但会自言自语，且每次都真实占用 TTS/播放链路。
- 因此 **v6.11.9 起生产默认 `off`**，`detect` 仅保留为开发者诊断项；生产靠"WS ping + 无感重连"兜底。
- 若未来必须用 detect，必须满足：仅在空闲时发（`markConversationActive/Idle` + 5s 恢复）、间隔 ≥45s，
  并接受"每隔一段时间的问候语"这一产品代价。
- 待验证（下一设备窗口）：`detect` 是否会打断用户正在说的话（本次未测并发场景）；服务端 `stt("小智")` 的产生条件。

## 7. 无副作用候选 ⑤/⑥（v6.11.10+62，待设备窗口）

> 目标：找到"能续命"且"零副作用"的业务帧。判定必须**两个条件同时成立**：
> ① 安静 3 分钟无 `1005`；② 全程零 `stt`、零 `tts`、零下行二进制、零 `AudioTrack start`。
> 任一副作用命中 → 判"有效但有副作用"，与 detect 同罪，不得默认开启。

| 候选 | 每个 tick 的载荷 | 语义假设 | 风险点 |
|---|---|---|---|
| ⑤ `stop` | `{"type":"listen","state":"stop"}` | "停止监听"，服务端应忽略/回 ACK | 服务端可能对空闲 stop 回错误帧 |
| ⑥ `pair` | `{"type":"listen","state":"start","mode":"manual"}` + `{"type":"listen","state":"stop"}` | 成对进入/退出监听，不产生会话 | start 可能短暂开麦/触发 VAD |
| ⑥' `mcp` | `{"type":"mcp","payload":{"jsonrpc":"2.0","method":"notifications/initialized"}}` | MCP 通知不算会话，但算"业务活跃" | 未知 method 可能被服务端判非法并关闭 |

**判定流程（每候选 4 分钟，间隔 30s，共约 12 分钟）**
1. 开发者中心 →「WS 保活探针」切到候选（切换即重建连接）；
2. `adb -s 36c77fb6 logcat -s flutter | findstr "[PROBE]"` 存盘；
3. 判 ①：`[PROBE] 停止（服务器断开 code=1005）` 是否在 180s 内出现；
4. 判 ②：`[PROBE] 下行` 中是否出现 `type=stt|tts|llm`、`type=binary`；另查
   `AudioTrack(29296)` start 数（应为 0）；
5. 结论写入本文件 §7 表下方，并回填 README 版本档案。

辅助脚本：`tools/ws_probe_judge.ps1`（传入 logcat 文件与起始时间，输出两条件判定）。

## 8. 重连频率评估（70s 回收下的真实压力）

**理论值（空转 1 小时）**：3600 / 69.8 ≈ **51.5 次**重连/小时；每次重连 = 1 次 WS 握手 + 1 条 `hello`
（服务端侧等价于一次新会话）。一天约 **1,236 次**。这是"无感重连"方案的固有成本。

**评估方法（不需要改代码，日志已内置）**
- 采集：`adb -s 36c77fb6 logcat -s flutter | findstr "[RECONNECT]"`，连续 1 小时；
- 统计：`[RECONNECT] 汇总` 每 10 次自动打印 `累计/成功/失败/间隔(avg/min/max)/近20次 closeCode`；
- 判读：
  - `closeCode` 应全部为 `1005`（正常回收）；出现 `432x` = 身份问题，出现 `-1`（无码）= 网络层异常；
  - `失败` 持续 > 0 或 `间隔` 明显 < 60s → 服务端可能在限流/抖动；
  - 若 1 小时内出现任何 `429`/`too many`/`432`，视为"过频"。

**若判定过频，切换策略（备选，不默认启用）**
- "仅在需要时说前连"：空闲期主动 `disconnect()`，用户按下麦克风/说话时由 v6.11.10 的
  2s 预连接（`_ensureConnectedThen`）即时建连，连上再采音；把"每分钟 1 次"降到"每次使用 1 次"。
- 代价：首字延迟增加约 200–600ms（握手 + hello ACK），需用 `[PRECONNECT] 成功，xxx ms` 实测分布确认。

## 9. 装机硬规矩（2026-11-04 追加）

1. **除"还原上一版"外，任何情况下不许 `adb install -d`。** 装机必须保证 `versionCode` 单调递增。
2. 还原场景使用 `-d` 时，必须满足全部三条：① 目标是恢复被实验覆盖的原包；② 还原前把实验开关归零；
   ③ 在交付报告中显式披露该次 `-d` 的原因与时间戳。
3. 多设备在线时一律带 `-s <serial>`；本机序列号 `36c77fb6`。

