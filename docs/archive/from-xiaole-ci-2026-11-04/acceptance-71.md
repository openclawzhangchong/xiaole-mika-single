# 6.11.15+71 装机验收：全功能逐项点验（16 项实测 + 3 项流程）

> 原则：**每个功能都要真点真用，多次运行多次诊断**。不看代码推断、不以日志替代点击。
> 判定一律"命令 + 正则 + 阈值"，可直接复制执行。
> 设备：`<DEVICE>`（写权限唯一归属本线）。装机基线见 `docs/device-baseline-<DEVICE>-2026-11-04.md`。

## 0. 固定装机顺序（不许改，任何一步都不许卸载）

```powershell
# 0.1 装前记录
adb -s <DEVICE> shell "dumpsys package com.zcstudy.xiaole | grep -E 'versionCode|firstInstallTime'"

# 0.2 装 71（69/70 不装）
# 71 已在设备 36c77fb6 上（versionCode=71，base.apk sha256 = 66d1f307…bb4，59,897,491 B），无需重装
adb -s 36c77fb6 install -r "C:\Users\Administrator\Documents\Trae-CN\temp_20261104_05\dist71\xiaole-6.11.16-mika1-arm64.apk"
# 若返回 Failure [-99]：不要 uninstall。按三连弹点：
#   复选框"已知悉该应用存在风险" → "授权本次安装" → 风险弹窗"仍然继续" → 完成页"打开应用"

# 0.3 装成后确认（versionCode/版本/首次安装时间）
adb -s <DEVICE> shell "dumpsys package com.zcstudy.xiaole | grep -E 'versionCode|versionName|firstInstallTime|installerPackageName'"

# 0.4 恢复数据：App 内 我 → 开发者选项 → 输密码 zc19901111 → 确认 → 选智能体
```

验收期间统一的开日志方式（新开一个终端常驻）：

```powershell
$D="36c77fb6"; $LOG="$env:TEMP\log-71.txt"; $XL="$env:TEMP\log-71-xiaole.txt"
adb -s $D logcat -c
adb -s $D logcat -v time > $LOG                                        # 全量：崩溃/系统告警
adb -s $D logcat -v time -s XiaoLe > $XL                               # 71 固定 tag：KEEPALIVE/TEXTSPLIT/RECONNECT/PRECONNECT/MicGate
function G([string]$p){ Select-String -Path $LOG -Pattern $p -Encoding UTF8 }
function L([string]$p){ Select-String -Path $XL  -Pattern $p -Encoding UTF8 }
# 启动锚点：每次冷启动/杀进程重启后必须出现
L 'BOOT MainActivity onCreate'
```

通用失败信号（每项都要顺带检查）：

```powershell
G 'FATAL EXCEPTION|E/flutter|Exception caught by widgets library|OutOfMemory'
```

---

## 1. 冷启动（跑 2 次）

```powershell
adb -s <DEVICE> shell am force-stop com.zcstudy.xiaole
adb -s <DEVICE> shell "am start -W -n com.zcstudy.xiaole/.MainActivity"
adb -s <DEVICE> exec-out screencap -p > cold$i.png
```

| 判定 | 阈值 |
|---|---|
| 启动耗时 | `TotalTime` ≤ 3000 ms（次次都要打印，2 次取记录） |
| 界面 | 截图会话列表可见、无白屏/黑屏 |
| 崩溃 | 通用失败信号命中数 = **0** |

正则：`TotalTime`、`FATAL EXCEPTION|E/flutter`。

## 2. 文字聊天·短句（跑 2 次：正常 + 边界 9 字）

```powershell
adb -s <DEVICE> shell "am start -n com.zcstudy.xiaole/.MainActivity -e debug_send_text_seg '现在几点了'"
```

| 判定 | 阈值 |
|---|---|
| 不切段 | 不出现 `[TEXTSPLIT]` |
| 回复 | `TTS start` 与 `TTS stop` 各 ≥1，且成对 |
| 丢字 | `stt` 回声与原文完全一致（允许服务端补标点） |
| 拒绝 | `alert` 命中数 = 0 |

正则：`\[TEXTSPLIT\]`、`TTS start|TTS stop`、`alert`。

## 3. 文字聊天·长句分段（跑 2 次：60 字 / 61 字跨段）

60 字样句（已核码点=60）：

```
今天下午三点我要去城东的维修点取修好的笔记本电脑，顺路帮同事带两杯咖啡，回来以后把本周的项目进度整理成一份简短总结发给团队，最后提醒我晚上八点给家里打个电话确认周末的安排
```

```powershell
adb -s <DEVICE> shell "am start -n com.zcstudy.xiaole/.MainActivity -e debug_send_text_seg '今天下午三点我要去城东的维修点取修好的笔记本电脑，顺路帮同事带两杯咖啡，回来以后把本周的项目进度整理成一份简短总结发给团队，最后提醒我晚上八点给家里打个电话确认周末的安排'"
```

| 判定 | 阈值 |
|---|---|
| 分段日志 | 必须出现且仅出现一次 `[TEXTSPLIT] 原文 60码点/180字节 > 上限 12码点/45字节，分 5 段` |
| 每段上限 | `每段码点=` 全部分量 ≤ 12；`字节=` 全部分量 ≤ 45 |
| 逐段回复 | `TTS start`/`TTS stop` 各 **5** 对；`[TEXTSPLIT] 上一段回复结束` 出现 **4** 次 |
| 兜底 | `[TEXTSPLIT] 20s 未见 TTS 结束` 出现 **0** 次（出现即为队列卡顿，记 bug） |
| 丢字 | 5 段 `stt` 依次拼接（去空白/标点）与原文逐字相等，差 1 字即 fail |
| Toast | 截图可见"文字较长，已自动分 5 段发送（每段 ≤12 字）" |

正则：`\[TEXTSPLIT\]`、`每段码点=(\d+(?:/\d+)*)`、`字节=(\d+(?:/\d+)*)`。

## 4. 按住说话（**真人手按**，跑 5 次）

```powershell
# 辅助定位：只在找不到按钮时用，主判定必须是真人按
adb -s <DEVICE> shell uiautomator dump /sdcard/ui.xml
```

| 判定 | 阈值 |
|---|---|
| 链路 | 录音启动 → 波形出现 → 转写 → 回复，四段齐全（截图各 1 张） |
| 置位顺序 | `[KEEPALIVE] 进入会话，保活暂停（开始说话）` 的**行号必须小于** `已发送 listen start 消息` 的行号 |
| 稳定性 | 5 次全部命中上述顺序，**1 次乱序即 fail** |

```powershell
$stale = (G '\[KEEPALIVE\] 进入会话，保活暂停（开始说话）' | Select-Object -First 1).LineNumber
$start = (G '已发送 listen start 消息' | Select-Object -First 1).LineNumber
"置位=$stale  listenStart=$start"
```

## 5. 上滑取消（**真人**按住后上滑，跑 5 次）

| 判定 | 阈值 |
|---|---|
| 取消生效 | 松开后 2s 内无 `listen start` 上行（若已发 start，必须紧随 `abort`，且无 `stt`） |
| 无请求 | 本次文本不出现在 `stt` 回声里；`TTS start` 数增量 = 0 |
| 无残留 | 紧接着发一句短句，回复内容不含被取消的句子片段 |
| 稳定性 | 5 次全部满足；任一次"取消后仍回复"即 fail |

正则：`listen start|abort|stt`。

## 6. 实时语音通话（跑 2 次）

| 判定 | 阈值 |
|---|---|
| 双向音频 | 通话页出现；对方回复有 `TTS start/stop`；本地打断后 `TTS stop` 立即出现 |
| 打断 | 说话后 300ms 内 `TTS stop`（日志时间戳差 ≤ 300ms） |
| 挂断 | 挂断后 2s 内回到聊天页，且无 `[RECONNECT]`、无 alert |

## 7. 任务卡四态（跑 2 次：成功 + 失败）

| 判定 | 阈值 |
|---|---|
| 状态流转 | `排队 → 执行 → 完成` 三个状态各至少出现 1 次（截图各 1 张） |
| 失败态 | 构造失败（断网或非法目标）后卡片显示失败样式，文案正确，不卡在"执行中" |
| 一致性 | 卡片状态与任务详情状态一致（互不矛盾） |

## 8. 任务详情 + 中止（跑 2 次）

| 判定 | 阈值 |
|---|---|
| 详情 | 展示步骤列表与每步耗时，数值非 0 且递增 |
| 中止 | 执行中点"中止"≤ 2s 内状态转"已中止"，**后续不再出现该任务的步骤日志** |
| 残留 | 中止后 30s 内无该任务的新步骤（出现即 fail） |

## 9. 屏幕读取（跑 2 次）

| 判定 | 阈值 |
|---|---|
| 授权 | 首次弹权限引导，授权后任务可执行 |
| 只在任务期间 | 任务开始后才出现读屏日志；任务结束（完成/失败/中止）后 **0 条**读屏日志 |
| 泄漏 | 非任务期间截图，无读屏悬浮层/后台截屏记录 |

## 10. 深色模式（9 页全走一遍，跑 1 轮 + 复原 1 轮）

页面清单（逐页截图，命名 `dark-01..09`）：聊天 / 通话 / 我 / 开发者中心 / 权限引导 / 智能体配置 / 外部 MCP 列表 / 工具清单 / 任务详情。

| 判定 | 阈值 |
|---|---|
| 对比度 | 正文与背景对比度 ≥ 4.5:1（截图目测 + 无"深色字压深色底"） |
| 排队卡 | 必须为灰阶（无彩色残留） |
| 错位 | 无颜色错位、无白块、无边框消失 |

## 11. MCP 工具调用（跑 2 次）

| 判定 | 阈值 |
|---|---|
| 端到端 | 云端触发 `mika_submit_goal` → 端上收到 `mcp` 调用 → 回包 → 云端确认，四段日志齐全 |
| 结果 | 任务卡真实创建（不是只回包不落地） |
| 失败可观测 | 断开端上连接再触发，必须有明确失败回包，不静默丢弃 |

## 12. 麦克风互斥（跑 **5 轮 × 每轮 10 次快速交替**）

| 判定 | 阈值 |
|---|---|
| 外放中被拒 | 小乐 TTS 播放期间触发 Mika 录音 → **必须被拒**，日志有 acquire 被拒行 |
| 松手可拿 | TTS 结束后再按 → 能拿到麦克风并正常录音 |
| 三行日志 | 每次交互有 `MicGate` **三行**：acquire 成功 / 被拒 / release（缺一即 fail） |
| 快速交替 | 10 次交替 0 报错、0 崩溃、0 卡死；5 轮全过 |
| 次数匹配 | `MicGate` acquire 成功数 + 被拒数 == release 数（否则存在未释放） |

原文模板（tag `MicGate`，不含 logcat 前缀；持有者取值只有 `xiaole` / `mika`）：

- `acquire holder=<who> 成功 持有者=<who>`
- `acquire holder=<who> 被拒 当前持有者=<cur> 原因=已被其它租约持有`
- `release holder=<who> 归还 剩余=<owner|无>`

```powershell
# 精确计数（跑完一轮后；$XL 见 §0 日志采集）
$ok   = @(L 'acquire holder=xiaole 成功 持有者=xiaole').Count
$deny = @(L 'acquire holder=mika 被拒 当前持有者=xiaole 原因=已被其它租约持有').Count
$rel  = @(L 'release holder=xiaole 归还 剩余=无').Count
"成功=$ok 被拒=$deny 归还=$rel 平衡=$($ok + $deny -eq $rel)"
```

## 13. 杀进程重启（跑 2 次）

```powershell
adb -s <DEVICE> shell am force-stop com.zcstudy.xiaole
adb -s <DEVICE> shell "am start -W -n com.zcstudy.xiaole/.MainActivity"
```

| 判定 | 阈值 |
|---|---|
| 自动重连 | `[RECONNECT] 成功` 出现 ≥1，且无需手点 |
| 保活生效 | 恢复后 120s 内出现 ≥4 条 `[KEEPALIVE] tick#`，序号连续 |
| 崩溃 | 0 次 FATAL/白屏 |

## 14. 息屏 / 后台（各 3 分钟，跑 2 轮）

```powershell
adb -s <DEVICE> shell input keyevent 26          # 息屏
adb -s <DEVICE> shell input keyevent 3           # 回桌面（后台）
```

| 判定 | 阈值 |
|---|---|
| 心跳不断 | 180s 内 `tick#` ≥ 8 条，相邻间隔 ≤ 25s（允许 1 次抖动到 30s） |
| 序号连续 | `tick#N` 递增无跳号 |
| 重连 | `[RECONNECT]` = 0 |
| 通知 | 息屏期间通知正常展示，点开可回前台 |

```powershell
(G '\[KEEPALIVE\] tick#\d+').Count
```

---

## 15. 离线 / 断网恢复（补漏项，跑 2 轮）

```powershell
# 断网 60s
adb -s <DEVICE> shell svc wifi disable
Start-Sleep -Seconds 60
adb -s <DEVICE> shell svc wifi enable
# 若 svc wifi 无权限，改用飞行模式：
# adb -s <DEVICE> shell "cmd connectivity airplane-mode enable" / disable
```

| 判定 | 阈值 |
|---|---|
| 能重连 | 断网期间出现 `[RECONNECT] 计划`，恢复后出现 `[RECONNECT] 成功`（≥1） |
| 不风暴 | 断网后 **60s 内** `[RECONNECT] 计划` 次数 **≤ 8**（超过即退避失效） |
| 退避可见 | `计划` 行的间隔呈 1/2/4/8/16/30s 递增，至少能观察到 3 个不同档位 |
| 保活重置 | 重连成功后 `tick#` 从 **1** 重新开始且序号连续（不回跳、不重复） |
| 功能恢复 | 恢复后发一句短句，能正常收到 TTS 回复（不是"连着但哑了"） |

```powershell
(G '\[RECONNECT\] 计划').Count          # 60s 窗口内 ≤8
(G '\[RECONNECT\] 成功').Count
(G '\[KEEPALIVE\] tick#\d+') | Select-Object -Last 5
```

## 16. 声学回环：真人语音等价验证（5 次一组，阈值 **4/5**）

**排期决策（不留待定）**：本项排在 **71 装机 + 开发者授权 + 选智能体之后**，作为最后一批，而不是验收开头。实测依据见 §16.4：67 当前数据为空（页面 `暂无会话 / 添加智能体`）且 `RECORD_AUDIO` 为 `ignore`，声学链路在"没绑智能体 + 没麦克风权限"两处同时断，先跑只会得到 0/5 的噪声。

### 16.0 前置通路检查（不依赖云端、不依赖智能体，必须先过）

```powershell
powershell -File mic-path-check.ps1 -Runs 3
```

- 判定：`appops RECORD_AUDIO` 非 `ignore` **且** 本次出现 App 的 `rec start/update` ≥1 次。两条同时成立 ⇒ "麦克风通路 OK"，云端/智能体因素被剥离。
- 触发方式二选一：VAD（放音触发）或长按按钮（`-HoldXY "x,y"`，坐标取自 §4 截图）。
- 不通过 ⇒ 先按归因修，**不要**开始跑 5 次声学；通过 ⇒ 再进 §16.1。
- 基线（2026-11-05，67）：3 轮 **0/3**，原因是权限未授予（见 §16.4），不是音源问题。

**权限怎么给（本机只有 UI 一条路）**

| 通道 | 实测结果 |
|---|---|
| `pm grant` | `SecurityException: Neither user 2000 nor current process has GRANT_RUNTIME_PERMISSIONS` |
| `appops set … allow` | `SecurityException: uid 2000 does not have MANAGE_APP_OPS_MODES` |
| UI（唯一可用） | `grant-mic-ui.ps1 -DryRun` 只定位不确认；去掉开关才真授予。实测路径：应用详情 → `权限管理`(168,1252) → `麦克风` → `使用时允许`(192,1944) |

> `pm grant` / `appops` / `grant-mic-ui.ps1` 都只是**测试手段**，不是产品行为。产品必须自己申请权限，被拒要有明确 UI 提示——已作为缺陷提给单包线。

### 16.1 音源（已生成并入库，可直接复用）

```powershell
# 目录：docs/archive/from-xiaole-ci-2026-11-04/acoustic/
powershell -File tts-gen.ps1
# 产出：speech-zh.wav（12.56s）+ g50/g70/g90 三个增益档
# 文本：小乐，帮我查一下今天北京的天气怎么样，出门要不要带伞？顺便看看明天上午有没有雨，我要去城东一趟。
# 引擎：SAPI Microsoft Huihui（中文），22kHz/16bit/单声道；不是"测试测试"这类短促合成音，避免 VAD 误判
```

### 16.2 播放与采集（一条命令跑完 5 次）

```powershell
powershell -File acoustic-loop.ps1 -Wav speech-zh-g90.wav -Runs 5 -IntervalSec 7 -Tag g90 -GrantMic
```

脚本固定行为：`-s <DEVICE>`（另一台设备绝不碰）→ 确认 App 在前台（不在则拉起）→ 清 logcat 并起采集 → 每次播放前打 `ACOUSTIC_MARK RUN n START`、播放（`SoundPlayer.PlaySync`，实测耗时 12.6s）→ 间隔 7s → 打 `END` 标记 → 抓 `dumpsys audio` 与截图 → 差分统计。

### 16.3 判定口径（**三源交叉**，日志恢复后切回日志主判）

| 源 | 证据 | 阈值 | 缺失时 |
|---|---|---|---|
| ① 音频通路 | `dumpsys audio` 新增行含 `pack:com.zcstudy.xiaole` 的 `rec start/update`（已触发）+ `callingPack=com.zcstudy.xiaole` 的 `requestAudioFocus`（已发声） | 每次两条都要有 | 直接 FAIL |
| ② 界面 | 截图裁掉状态栏/底栏（y 30%–85%）后的指纹，与本轮基线不同（气泡出现） | 每次都要变 | 直接 FAIL |
| ③ 权限 | `dumpsys appops RECORD_AUDIO` 不是 `ignore` | 全程成立 | 直接 FAIL |
| ④ 日志（71 起**必检**） | `-s XiaoLe`：`[KEEPALIVE]` 置位 + `listen start` +（`stt` 或 `tts`）；启动另有 `BOOT MainActivity onCreate` 锚点 | 每次都要命中 | 未命中 ⇒ **直接 FAIL** |

- **四源全齐 = PASS**（①+②+③+④）。④ 不再是"恢复后可选"，71 已把四类日志走原生通道，**不存在"没日志也能过"的口子**。
- "判定降级" 只在**采集层面异常**时使用（logcat 断了 / 文件 0 行 / 系统限制），且必须写明缺哪一源、用什么替代证据；正常情况不该出现这个词。
- 完整链路阈值不变：**5 次里 ≥4 次**。

```powershell
$d="docs/archive/from-xiaole-ci-2026-11-04/acoustic/runs/<最新>-g70"
Import-Csv "$d\summary.csv" | Format-Table Run,AppRec,AppPlay,UiChanged,Result,Notes
$pass=(Import-Csv "$d\summary.csv" | Where-Object Result -eq PASS).Count; "PASS=$pass/5"
```

**日志口径（71 起）**：`adb logcat -s XiaoLe` 直读 `[KEEPALIVE]` / `[TEXTSPLIT]` / `[RECONNECT]` / `[PRECONNECT]` / `MicGate`，`BOOT MainActivity onCreate` 作启动锚点。67 时代 release 无任何 Dart 日志，才退到 `dumpsys` 判定；71 修好后 ④ 恢复必检，① 退为辅助证据。

### 16.4 基线实测（67，5 次/组；2026-11-04 ~ 11-05）

| 轮次 | 配置 | 结果 | 归因 |
|---|---|---|---|
| 23:52 | g90，5 次 | 0/5 | 无 Dart 日志；音频通路无 App 录音/发声记录 |
| 23:55 | g90，5 次（v2 音频判定） | 0/5 | `appops get … RECORD_AUDIO` = **`Uid mode: RECORD_AUDIO: ignore`**；页面 `暂无会话/添加智能体` |
| 00:03 | 前置通路检查，VAD 3 次 | **0/3** | 权限仍 `ignore`；`pm grant` 被 ColorOS 拒绝（`GRANT_RUNTIME_PERMISSIONS`），`appops set` 同样被拒（`MANAGE_APP_OPS_MODES`） |
| 00:10 | `grant-mic-ui.ps1 -DryRun` | 定位成功 | 应用详情 → `权限管理`(168,1252) → `麦克风` → `使用时允许`(192,1944)，**未点确认**（不提前授予以免掩盖"App 自己申请"的产品行为） |

两条根因都必须在 71 装机时消除：**① 权限（走 App 自身弹窗点"允许"；本机无 adb 授权通道）；② 开发者授权 + 选智能体**。任一未做，本项必挂。顺手记一条：`-GrantMic` 在本机**不可用**，已被 `grant-mic-ui.ps1` 取代。

### 16.5 参数扫描（三档各 5 次，成功组合回填）

物理摆位无法在无人值守下改变，故**距离用声压等价替代**：自由场每 20cm 约 −6 dB，即振幅 0.5 倍 ≈ 距离翻倍。音量档位同样用 wav 增益实现（**不自动改电脑系统音量**，避免污染桌面设置）。

| 档位 | wav | 等价条件 | 结果 | 结论 |
|---|---|---|---|---|
| 高 | `speech-zh-g90.wav` | 90% 音量 ≈ 20cm | 待 71 回填 | — |
| 中 | `speech-zh-g70.wav` | 70% 音量 ≈ 28cm | 待 71 回填 | — |
| 低 | `speech-zh-g50.wav` | 50% 音量 ≈ 40cm（−6 dB） | 待 71 回填 | — |

**稳定组合**（验收后填入，后续复测直接照抄）：`____________`

### 16.6 失败归因表（逐条排查，不许只报"没触发"）

| 假设 | 一条命令验伪 | 判定 |
|---|---|---|
| 麦克风权限未授予 | `adb -s <DEVICE> shell appops get com.zcstudy.xiaole RECORD_AUDIO` | `ignore` ⇒ 先 `pm grant`，VAD 物理上不可能工作 |
| 未绑智能体 | 截图是否停在 `暂无会话/添加智能体` | 是 ⇒ 先恢复授权与智能体 |
| 设备静音/勿扰 | `settings get global zen_mode` | ≠0 ⇒ 记录（不影响录音，但影响提示音核对） |
| App 在手动模式 | App 内语音模式开关 = 自动 | 手动 ⇒ 切换后重跑 |
| 麦克风被 Mika 占用 | `dumpsys audio` 是否有 `pack:com.wangzan101.mika` 的 `rec start` 未释放 | 有 ⇒ 先结束 Mika 录音，再验 MicGate |
| 音量不足 / 距离过远 | 换 g70→g90 各跑 5 次 | 只有 g90 过 ⇒ 记录稳定组合为 g90 |
| 电脑未发声 | 播放耗时 < 12s 或 0 | 检查 wav 路径与 `SoundPlayer` |
| 网络不可达 | 恢复后短句无 TTS，且 `[RECONNECT]` 持续 | 先修网络项（§15）再重跑 |

每条都写"验伪命令 + 结论"，不接受"可能/大概"。

## 17. 运行次数矩阵（"多次运行"的落地口径）

| 项 | 次数 | 说明 |
|---|---|---|
| 4 按住说话 | **≥5** | 竞态高发，逐次核对置位顺序 |
| 5 上滑取消 | **≥5** | 竞态高发，逐次核对无残留 |
| 12 麦克风互斥 | **5 轮 ×10 次** | 竞态高发，逐轮核对三行日志 |
| 15 离线/断网恢复 | **≥2** | 一次 60s、一次 120s（长时间断网也须收敛到 30s 封顶） |
| 16 声学回环 | **3 档 ×5 次** | g90/g70/g50 各 5 次；单档 ≥4/5 即通过，并把稳定档位写回 §16.5 |
| 其余 11 项 | **≥2** | 一次正常 + 一次异常/边界 |

## 18. Bug 处理（当场闭环）

发现 bug 时：**同一会话内定位 → 改 → 重出包（71.x）→ 重新安装 → 只重验该项 + 通用失败信号**，
不许攒到最后。重装仍走 §0.2 三连弹，**禁止 `adb uninstall`**。

## 19. 收尾

```powershell
# 关闭保活探针 → 还原 57 → 清 reverse → 回桌面
adb -s <DEVICE> install -r -d "<TEMP>\xiaole-apk\xiaole-apk-6.11.5+57-c315bc4\xiaole-6.11.5+57-c315bc4-release.apk"
adb -s <DEVICE> reverse --remove-all
adb -s <DEVICE> shell input keyevent KEYCODE_HOME
```

还原后用 `docs/device-baseline-<DEVICE>-2026-11-04.md` §2 的字段复核，并追加本次 71 的 `firstInstallTime`。

## 20. 执行时序（连跑批 / 独占批）与最短时间表

> 全文 19 个章节里，§1–§16 是 **16 个实测项**，§17–§19 是流程（次数矩阵 / Bug 闭环 / 收尾）。按"能否连续执行"分三批，目标是把必须独占设备的项压到最后，减少窗口切换。

### 20.1 分类

| 批 | 项 | 依据 |
|---|---|---|
| **P1 连跑**（App 前台即可，项间无需等待） | §1 冷启动、§2 短句、§3 长句分段、§13 杀进程、§7 任务卡、§8 任务详情、§9 屏幕读取、§11 MCP、§10 深色 9 页、§4 按住说话、§5 上滑取消、§6 实时通话 | 只依赖 App 前台，不抢外部资源；顺序按"改动量小 → 大"排，减少来回切页 |
| **P2 连跑但需 Mika 配合** | §12 MicGate 5 轮 ×10 次 | 需要 Mika 在线并反复抢麦，仍可连续跑，但中途不能杀进程 |
| **P3 独占·系统态** | §15 断网恢复（改系统网络）、§14 息屏/后台（3 分钟零输入） | §15 期间网络不可用，不能和任何联网项交叉；§14 期间不能有 adb 注入或点击 |
| **P4 独占·物理态** | §16 声学回环（电脑外放 + 手机静置） | 播放期间只允许截图/抓 dump；必须先过 §16.0 通路检查 |
| **P0 前置（串行）** | 装 71（三连弹）→ `zc19901111` → 选智能体 → 首次按住说话触发 **App 自身权限弹窗**并点"允许" | 没有可测对象之前，其它项都无意义；权限必须由 App 弹出，脚本授权不算产品行为 |

### 20.2 最短顺序

```
P0 装机+配置+首个权限弹窗
 → P1 连跑 12 项（§1→§2→§3→§13→§7→§8→§9→§11→§10→§4→§5→§6）
 → P2 §12 MicGate
 → P3 §15 断网 → §16.0 通路检查 → P4 §16 声学三档 → P3 §14 息屏/后台
 → §19 收尾
```

### 20.3 时间表（单项耗时按次数矩阵实算）

| 阶段 | 内容 | 估算 | 累计 |
|---|---|---|---|
| P0 | 装机 + 三连弹 + 密码 + 选智能体 + 首次权限弹窗 | 11 min | 11 |
| P1 | 12 项连跑（含 §10 九页 ×2、§4/§5 各 5 次） | 62 min | 73 |
| P2 | §12 MicGate 5 轮 ×10 次 | 12 min | 85 |
| P3 | §15 断网 60s + 120s（含恢复观察） | 6 min | 91 |
| P4 | §16.0（3 次）+ §16 声学（3 档 ×5 次） | 8 min | 99 |
| P5 | §14 息屏/后台（3 min ×2） | 8 min | 107 |
| P6 | §19 收尾（装回 57、清 reverse、回桌面） | 4 min | 111 |

**窗口建议 ≥2 小时**（111 min + 约 10% 余量）。依据：声学单次 12.6s 播放 + 7s 间隔 ≈ 98s/次；断网 = 60/120s + 30s 观察；息屏 = 3 min ×2；其余按"每次 1.5–3 min × 矩阵次数"。
发现 bug 触发重出包时另计：每项重验 8–15 min，且要重走 §0.2 三连弹（**禁止 uninstall**）。

