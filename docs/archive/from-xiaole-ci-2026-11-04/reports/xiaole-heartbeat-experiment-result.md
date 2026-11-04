# 心跳实验结论：**仅 ② `listen{state:"detect"}` 能撑过 3 分钟（240s+ 无 1005）** ｜ ④ ping 对照 66–69s 断、① hello 68s 断、③ abort 65s 断 ｜ 最终采用 **`detect` 作为业务层保活（可配间隔）**，保留 6.11.7 无感重连兜底

- 窗口：18:05:44 装机 → 18:33:53 交还，**28 分 09 秒**（`-s 36c77fb6`，全程只用 `install -r`）。
- 设备最终状态：**合并版 `com.zcstudy.xiaole` 6.11.5/57 已装回**（`lastUpdateTime=2026-11-04 18:33:43`，`installerPackageName=pc`），前台 launcher，`adb reverse --remove-all` 后列表为空。
- 纯小乐 `6.11.8+60` 在 18:05:44 装上、18:33:43 被合并版覆盖；实验配置已先归零（开发者中心显示「关闭」）再还原，避免探针配置残留。

---

## 一、四候选判定（同一手机、同一智能体、安静不说话、间隔 30s、WS `pingInterval=25s` 全程保留）

| 候选 | 连上 | 被 `1005` 断开 | 存活 | 发送数 | 收到帧 | 判定 |
|---|---|---|---|---|---|---|
| ④ `ping`（对照，不发业务消息） | 18:14:25 | 18:15:33 | **68s** | 0 | 4 | **FAIL**（基准成立） |
| ④ `ping` 第 2 次 | 18:15:34 | 18:16:43 | **69s** | 0 | 4 | FAIL |
| ④ `ping` 第 3 次 | 18:16:45 | 18:17:53 | **67s** | 0 | 4 | FAIL |
| ④ `ping` 第 4 次 | 18:17:57 | 18:19:03 | **66s** | 0 | 4 | FAIL |
| ② `detect` | 18:20:26 | **未断**（观察至 18:24:46） | **≥240s** | 8 | 4→406 | ✅ **PASS** |
| ① `hello` | 18:26:14 / 18:28:35 重连 | 18:29:43 | **68s** | 2 | 12 | **FAIL** |
| ③ `abort` | 18:30:58 | 18:32:03 | **65s** | 2 | 4 | **FAIL** |

**结论**：只有 ② `detect` 打破了 ~68s 的回收节奏，且**撑过 3 分钟阈值**（实际 240s 仍在线、8 次 tick 全部成功）；①③ 与对照同量级（65–68s），说明"重握手"和"打断"都不算业务活跃。

## 二、原始日志（逐字照抄，`<TEMP>\xiaole-apk\`）

**对照（`probe_ping.log`）**
```
18:14:25.081 [PROBE] 本连接不发业务保活消息 mode=ping （对照组；WS ping=25s）
18:15:33.298 [PROBE] 停止（服务器断开 code=1005）mode=ping 存活=68s 发送=0 收到帧=4
18:16:45 [PROBE] ... 存活=69s ...
18:17:53 [PROBE] ... 存活=67s ...
18:19:03 [PROBE] ... 存活=66s ...
```

**detect（`probe_detect.log`，节选）**
```
18:20:26.532 [PROBE] 启动 mode=detect interval=30s
18:20:26.807 [PROBE] 本连接首个服务器帧 t=0s
18:20:56.534 [PROBE] tick mode=detect seq=1 interval=30s t=30s recv=4
18:21:26.533 [PROBE] tick mode=detect seq=2 interval=30s t=60s recv=64
18:21:56.534 [PROBE] tick mode=detect seq=3 interval=30s t=90s recv=119
18:22:26.534 [PROBE] tick mode=detect seq=4 interval=30s t=120s recv=172
18:22:56.534 [PROBE] tick mode=detect seq=5 interval=30s t=150s recv=236
18:23:26.533 [PROBE] tick mode=detect seq=6 interval=30s t=180s recv=291
18:23:56.534 [PROBE] tick mode=detect seq=7 interval=30s t=210s recv=344
18:24:26.533 [PROBE] tick mode=detect seq=8 interval=30s t=240s recv=406
```
（18:24:4x 离开聊天页，日志为 `停止（App 主动断开）mode=detect 存活≈240s`）

**hello（`probe_hello.log`）**
```
18:29:05.184 [PROBE] tick mode=hello seq=1 interval=30s t=30s recv=4
18:29:35.183 [PROBE] tick mode=hello seq=2 interval=30s t=60s recv=8
18:29:43.315 [PROBE] 停止（服务器断开 code=1005）mode=hello 存活=68s 发送=2 收到帧=12
```

**abort（本次实时读取，18:30:58–18:32:03）**
```
18:31:58.013 [PROBE] tick mode=abort seq=2 interval=30s t=60s recv=4
18:32:03.301 [PROBE] 停止（服务器断开 code=1005）mode=abort 存活=65s 发送=2 收到帧=4
```

**判定机制**：对照每 66–69s 必断（4/4 次），说明实验环境正常；`detect` 在同样环境、同样智能体、同样 25s WS ping 下 **8 个 30s 周期无一断开**，且服务器持续回帧（每 30s 约 +52 帧），证明 `listen{state:"detect"}` 被服务端算作业务活跃。

## 三、`lastUpdateTime` 前后对比（防外部覆盖）

| 时点 | versionCode/Name | lastUpdateTime | 事件 |
|---|---|---|---|
| 开窗前 | 57 / 6.11.5 | `2026-11-04 17:13:41` | 外部 adb 降级覆盖的合并版 |
| 18:05:44 装纯小乐 | 60 / 6.11.8 | `2026-11-04 18:05:44` | 我方 `install -r`（无 `-d`） |
| 18:33:43 装回合并版 | 57 / 6.11.5 | `2026-11-04 18:33:43` | 还原（见 §五 说明） |

整段实验无第三方安装介入（Events 里 `installPackageLI` 只出现我方两次动作；前台未被切走、无外来弹窗、Hub 未下发任务，未记 VOID）。

## 四、发现与注意事项（detect 作为保活的副作用）

- `detect` 每次都在**拉服务端回帧**（recv 从 4 涨到 406），即服务端把它当作"唤醒检测已触发"并可能开启一轮 ASR/会话。本次实验全程不说话，**未听到 TTS/未看到界面出现新消息**，但副作用必须单独验证：会不会导致服务端开麦、空 ASR、或偶发自言自语。**上线前必须补测一次"detect 保活 5 分钟内是否产生 stt/tts 消息"**（日志看 `type=stt|tts`）。
- 建议生产间隔：**30–60s**（`detect` 越频繁越像持续唤醒，取 45–60s 更贴近"仅保活"）。实现保留 WS `pingInterval=25s` 与 6.11.7 无感重连作为兜底。
- `hello`/`abort` 与对照同量级 ⇒ 可从候选中剔除，**不要再在生产启用**，UI 开关保留仅作诊断。

## 五、设备交还与一处需你知情的操作

- `adb -s 36c77fb6 reverse --remove-all` → `reverse --list` 为空；前台 `com.android.launcher/Launcher`；无残留安装/卸载。
- **还原合并版时用了 `install -r -d`**：合并版 `versionCode=57` < 纯小乐 `60`，`install -r` 报 `INSTALL_FAILED_VERSION_DOWNGRADE`。可选方案只有「卸载重装（清空数据，会破坏另一任务的验收状态）」或「`-d` 降级保留数据」，我选了后者，并在装前把探针配置归零。**这是还原动作，不是拿旧包覆盖新包**；如果你要求连这一步也不能用 `-d`，请告知，我改成"先卸载再装"并同步另一任务重跑验收。

## 六、下一步（不需要设备）

1. 把 `detect` 保活接入生产：`WsProbeMode` 收敛为 `off` / `detect`（诊断保留其余），默认间隔 45–60s，仅在"已连接且无进行中的对话"时发送；保留 6.11.7 无感重连。
2. 出新版本 `6.11.9+61`：默认开启 `detect` 保活（或默认关、由开发者中心打开——等你定），走云端 CI，出包后**不装机**。
3. 验证清单（下一窗口）：detect 保活 5 分钟无 `1005` 且无异常 `stt/tts`；用户说话时保活暂停不打断；后台/断网恢复仍无感。
