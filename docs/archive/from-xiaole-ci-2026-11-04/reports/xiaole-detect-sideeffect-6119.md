# 结论：**detect 有副作用——会触发服务端 ASR、会推 TTS 并真实外放（麦克风是否被打开未证实）** ｜ **6.11.9+61 已出包（未装机）**，但据此把默认值改为 `off`，detect 仅保留为诊断开关 + 会话感知暂停

- 取证来源：上一轮设备窗口（`verify_v2.log`，18:20:26→18:24:26，detect 连接 406 帧完整 logcat）
- 版本：`6.11.9+61`，代码 commit `de7ede8`（文档 commit `b965d52`），CI run **41816712171**（**success**）
- APK：`xiaole-apk-6.11.9+61-de7ede8` / `xiaole-6.11.9+61-de7ede8-release.apk`，40,806,486 B，sha256 `783f5963d742e5b2fbda09ef003abc1f0e29c36d018fd3c535f61b1610acf6ac`
- 设备未被触碰（本轮零 adb 写操作），仍为合并版 6.11.5/57

---

## 一、406 帧到底装了什么

detect 连接存活 240s、8 个 tick，`recv` 从 4 涨到 406：

| 类别 | 数量 | 构成 |
|---|---|---|
| 文本 JSON | **62** | `tts`=43、`stt`=8、`llm`=7、`mcp`=3、`hello`=1 |
| 二进制音频 | **344** | 406 − 62，均为 TTS opus 帧 |
| 合计 | **406** | 平均每个 tick 带来 ≈43 帧（≈ 1 轮完整 TTS） |

**8 个 tick = 8 条 `stt` + 8 条 `llm` + 8 轮 TTS**，不是"确认帧"。原始行示例（逐字）：

```
18:20:56.536 发送消息: {"type":"listen","state":"detect"}
18:20:56.648 收到消息: {"type":"stt","text":"小智","session_id":"99b55fd7"}
18:20:56.656 收到消息: {"type":"tts","state":"start","sample_rate":24000,...}
18:20:58.418 收到消息: {"type":"llm","text":"😊","emotion":"happy",...}
18:20:58.578 收到消息: {"type":"tts","state":"sentence_start","text":"哎，我在呢！",...}
18:20:58.868 D/AudioTrack(29296): set() ... sampleRate 16000 ...   ← 真实外放
18:21:28.110 收到消息: {"type":"tts","state":"sentence_start","text":"我在咧！",...}
18:22:27.453 收到消息: {"type":"tts","state":"sentence_start","text":"我在这儿咧！",...}
```

8 轮 TTS 文本各不相同（"哎，我在呢！/我在咧！/在的在的！/我在这儿咧！…"），窗口内 `AudioTrack(29296)` 共 **10 次 start**。

## 二、三问逐一结论

| 问题 | 结论 | 证据 |
|---|---|---|
| detect 会不会触发服务端 ASR？ | **会** | 每个 tick 后 <200ms 返回 `stt("小智")`，8 tick = 8 条，文本完全一致 |
| 会不会推 TTS 给我们播？ | **会，且真实外放** | `stt → tts start → llm("😊") → tts sentence_start/end → tts stop`；`AudioTrack(29296)` 10 次 start、`sampleRate 16000` |
| 会不会让设备麦克风被打开？ | **未证实（本窗口未见）** | 全程 `AudioRecord*` 命中 0 条（pid 29296），App 未启动录音；但服务端在**没有上行音频**时仍返回 `stt("小智")`——其判定机制未证实 |

**一句话**：detect 能续命，但本质是"每 45s 主动叫醒助手一次"，会自言自语、真实占用 TTS/播放链路。按你的条件（"不能默认开启"），本版**默认 `off`**。

## 三、6.11.9+61 的实现：触发条件与暂停逻辑

### 3.1 探针收敛
- `WsProbeMode` 由 5 值缩为 **`off` / `detect`**（`hello`/`abort`/`ping` 删除，实测无效）。
- 默认 **`off`**；默认间隔 **45s**（`PROBE_DETECT_INTERVAL`，可配 10–120s）。
- 开发者中心「调试」入口改为 2 选项，文案明确写"有 TTS 副作用"。

### 3.2 会话感知（只在空闲时发）
新增 `markConversationActive(why)` / `markConversationIdle(why)`：

| 进入会话（暂停保活） | 会话结束（开始计时恢复） |
|---|---|
| 发送文字 | `tts stop` / `tts end` |
| 上行麦克风音频（说话中） | AI 音频播放结束（500ms 无新帧） |
| 收到 `stt` / `llm` / `tts start` / `tts sentence_start` | 挂断语音通话 |
| 收到下行音频帧（AI 正在播放） | — |

tick 判定顺序：

```
未连接 / 用户主动断开      → 不发
会话进行中                 → skip（日志 "[PROBE] skip（会话进行中）"）
会话结束不足 5s            → skip（PROBE_RESUME_DELAY = 5s）
其余（已连接且空闲 ≥5s）    → 发 {"type":"listen","state":"detect"}
```

兜底：会话标记 **60s 无任何收发活动** 自动解除（`CONVERSATION_STALE`），避免上层漏发"结束"导致保活被永久暂停。
新连接建立时清空会话标记（新 session 不存在旧会话）。

### 3.3 下行取证增强（下一轮实测可直接回答三问）
`[PROBE]` 新增：
- 每条文本消息：`下行#N 文本 type=xxx preview=<脱敏后首 32 字符>`（`token` / `session_id` 一律打码）；
- 二进制帧：`下行#N 二进制 len=L`，前 3 帧附 `head32=<首 32 字节 hex>`；
- 断开汇总：`文本=N 音频=N types={tts=..,stt=..,llm=..}`。

## 四、CI 与产物

| 项 | 值 |
|---|---|
| commit | `de7ede8`（修复 `$(` 插值编译错误后重跑） |
| CI run | **41816712171**（`Build Release APK`，**success**；签名校验步骤通过） |
| artifact | `xiaole-apk-6.11.9+61-de7ede8`（21,280,250 B 压缩包） |
| APK | `xiaole-6.11.9+61-de7ede8-release.apk`，**40,806,486 B**，sha256 `783f5963d742e5b2fbda09ef003abc1f0e29c36d018fd3c535f61b1610acf6ac` |
| analyze | **0 error**（93 条既有 info/warning） |
| 装机 | **未装机**（等你给窗口） |

## 五、已写进文档的硬规矩

`docs/ws-idle-reclaim-evidence.md` 新增 §6：
1. **除"还原上一版"外，任何情况下不许 `adb install -d`**；装机必须 `versionCode` 单调递增。
2. 还原用 `-d` 必须同时满足：目标是恢复被实验覆盖的原包、还原前开关归零、交付报告显式披露时间戳。
3. 多设备一律 `-s 36c77fb6`。

## 六、仍未证实 / 需下一窗口验证

1. **麦克风**：本窗口 App 未开录音（0 条 `AudioRecord`），但服务端仍返回 `stt("小智")`——是否服务端自行回填、是否有隐私影响，**未证实**。
2. **对话并发**：detect tick 恰好落在用户说话中间时会不会打断/被服务端合并，**未实测**（新逻辑已从机制上避免：会话中不发）。
3. **45s 是否足够**：实测只验证了 30s 间隔；45s 仍在 60–70s 回收窗内，理论安全但未真机验证。
4. **是否会触发服务端计费/唤醒统计**：日志无相关字段，**未证实**。
