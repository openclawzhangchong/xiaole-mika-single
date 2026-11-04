# 结论：**⑤⑥ 已备好待测（默认全关，出包未装机）｜ 说话前预连接已实现（2s 上限 + 断线音频缓存回灌 + 失败提示）**

- 版本：`6.11.10+62`，代码 commit `3d5819f`，文档 commit `2216dd5`
- CI：run **41819784156** ✅ success；APK **40,822,866 B**，sha256 `1a161d2d080df9b50cdecc19015fc3abd530a2a06bb976c4b8d6f2775a360d49`；analyze **0 error**
- **未装机**（设备仍为合并版 6.11.5/57，本轮零写操作）；等你的 12 分钟窗口

---

## 一、候选 ⑤/⑥ 设计

| 候选 | 每 tick 载荷 | 语义假设 | 主要风险 |
|---|---|---|---|
| ⑤ `stop` | `{"type":"listen","state":"stop"}` | "停止监听"，服务端应忽略或回 ACK | 空闲 stop 可能回错误帧 |
| ⑥ `pair` | `{"type":"listen","state":"start","mode":"manual"}` + `{"type":"listen","state":"stop"}` | 成对进入/退出，不产生会话 | `start` 可能瞬时开麦/触发 VAD |
| ⑥' `mcp` | `{"type":"mcp","payload":{"jsonrpc":"2.0","method":"notifications/initialized"}}` | MCP 通知不算会话但算业务活跃 | 未知 method 可能被判非法并关闭 |

- 全部默认 `off`；开发者中心「WS 保活探针」现为 5 项（关闭 / detect / ⑤ / ⑥ / ⑥'），切换即重建连接。
- 发送间隔沿用 45s（可配 10–120s）；会话感知暂停逻辑对所有候选生效（对话中不发，结束 5s 后恢复，60s 无活动兜底解除）。

## 二、判定阈值（两个条件必须同时成立）

1. **存活**：首个 tick 后 **180s 内不出现** `[PROBE] 停止（服务器断开 code=1005）`；
2. **零副作用**：全程 **0 条 `stt`、0 条 `tts`、0 条 `llm`、0 个下行二进制帧、0 次 `AudioTrack(29296) start`**。

任一副作用命中 → 判 **"有效但有副作用"**，与 detect 同罪，不得默认开启；被 1005 提前回收 → **FAIL**。

判定脚本已入库：[ws_probe_judge.ps1](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/tools/ws_probe_judge.ps1)

```powershell
powershell -File tools/ws_probe_judge.ps1 -LogPath probe_stop.log -Mode stop -AudioTrackLog full.log
# 输出示例：候选=stop tick=8 stt=0 tts=0 llm=0 binary=0 AudioTrack.start=0
#          判定=PASS（180s+ 无 1005 且零副作用）
```

窗口内建议命令（每个候选 4 分钟）：

```powershell
adb -s 36c77fb6 logcat -c
adb -s 36c77fb6 logcat -s flutter > probe_<mode>.log   # 另开一路抓完整 log 用于 AudioTrack
```

## 三、说话前预连接（生产改进，无条件生效）

`_ensureConnectedThen(action, label)` 改造：

```
按下麦克风/通话入口
 ├─ 已连接 → 立即执行
 └─ 未连接 → 发起快速重连（上限 2s）
      ├─ 2s 内连上 → 自动重放本次 listen start → 回灌缓存音频 → 继续说话
      └─ 2s 未连上 → 放弃本次操作 + Toast「网络恢复中，请稍候」（不启动 listen start）
```

- **不丢第一句**：断线瞬间的上行 Opus 帧先入缓存（上限 40 帧 ≈ 2.4s），`listen start` 发出后按序回灌（`[PRECONNECT] 回灌缓存音频 N 帧`）；松手/超时即清空，避免残留帧串到下一次。
- **兜底提示**：超时 Toast 文案固定为「网络恢复中，请稍候」，对应日志 `[PRECONNECT] 2s 内未连上（label），丢弃缓存 N 帧并提示稍候`。
- **可观测**：成功时打 `[PRECONNECT] 成功，xxx ms 内连上，自动<label>`，用于统计首字延迟分布。

## 四、重连频率评估

**理论值**（按 70s 回收、纯空闲）：3600 / 69.8 ≈ **51.5 次/小时**，一天约 **1,236 次**；每次 = 1 次 WS 握手 + 1 条 `hello`（服务端视角等价一次新会话）。

**采集方法（日志已内置，无需改码）**

```powershell
adb -s 36c77fb6 logcat -s flutter | findstr "[RECONNECT]"
```

| 日志 | 含义 |
|---|---|
| `[RECONNECT] 计划 #N（连续第M次） delay=…s gap=…s code=… 距断开=…s` | 每次重连的退避与间隔 |
| `[RECONNECT] 成功 #成功/累计 用时=…s` | 成功率与握手耗时 |
| `[RECONNECT] 汇总 累计/成功/失败/间隔(avg/min/max)/近20次closeCode` | 每 10 次自动汇总 |

**判读标准**
- `closeCode` 应清一色 `1005`；出现 `432x` = 身份问题，`-1` = 网络层异常；
- 失败率 > 0 或平均间隔明显 < 60s → 疑似限流/抖动；
- 出现 `429`/`too many`/`432` → 判定"过频"。

**若判过频的备选策略（documented，不默认启用）**：空闲期主动 `disconnect()`，用户按下麦克风时由 2s 预连接即时建连，把"每分钟 1 次"降为"每次使用 1 次"；代价是首字延迟增加约 200–600ms，需用 `[PRECONNECT] 成功，xxx ms` 实测分布确认可接受。

## 五、CI 与产物

| 项 | 值 |
|---|---|
| 代码 commit | `3d5819f`（预连接音频回灌 + 松手清空） |
| CI run | **41819784156** ✅ success |
| artifact | `xiaole-apk-6.11.10+62-3d5819f` |
| APK | `xiaole-6.11.10+62-3d5819f-release.apk`，40,822,866 B |
| SHA-256 | `1a161d2d080df9b50cdecc19015fc3abd530a2a06bb976c4b8d6f2775a360d49` |
| 本机路径 | `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v61110-final\` |
| analyze | 0 error |
| 装机 | **未装机** |

> 期间有一次中间构建（`8450dbf` / run 41818628352）未含音频回灌，已作废；以 `3d5819f` / run 41819784156 为准。

## 六、待你给窗口后执行（约 12 分钟）

顺序建议：⑤ `stop` → ⑥ `pair` → ⑥' `mcp`，每候选 4 分钟、间隔 45s；每个候选前后各记一次 `lastUpdateTime`，全程 `-s 36c77fb6`、只用 `install -r`（禁 `-d`），跑完还原合并版。
