# 6.11.15+69 装机验收：全功能逐项点验（15 项）

> 原则：**每个功能都要真点真用，多次运行多次诊断**。不看代码推断、不以日志替代点击。
> 判定一律"命令 + 正则 + 阈值"，可直接复制执行。
> 设备：`36c77fb6`（写权限唯一归属本线）。装机基线见 `docs/device-baseline-36c77fb6-2026-11-04.md`。

## 0. 固定装机顺序（不许改，任何一步都不许卸载）

```powershell
# 0.1 装前记录
adb -s 36c77fb6 shell "dumpsys package com.zcstudy.xiaole | grep -E 'versionCode|firstInstallTime'"

# 0.2 装 69（APK 由单包线产出后放到本地目录）
adb -s 36c77fb6 install -r "<TEMP>\xiaole-apk\v61115\<69.apk>"
# 若返回 Failure [-99]：不要 uninstall。按三连弹点：
#   复选框"已知悉该应用存在风险" → "授权本次安装" → 风险弹窗"仍然继续" → 完成页"打开应用"

# 0.3 装成后确认（versionCode/版本/首次安装时间）
adb -s 36c77fb6 shell "dumpsys package com.zcstudy.xiaole | grep -E 'versionCode|versionName|firstInstallTime|installerPackageName'"

# 0.4 恢复数据：App 内 我 → 开发者选项 → 输密码 zc19901111 → 确认 → 选智能体
```

验收期间统一的开日志方式（新开一个终端常驻）：

```powershell
$D="36c77fb6"; $LOG="$env:TEMP\log-69.txt"
adb -s $D logcat -c
adb -s $D logcat -v time > $LOG
function G([string]$p){ Select-String -Path $LOG -Pattern $p -Encoding UTF8 }
```

通用失败信号（每项都要顺带检查）：

```powershell
G 'FATAL EXCEPTION|E/flutter|Exception caught by widgets library|OutOfMemory'
```

---

## 1. 冷启动（跑 2 次）

```powershell
adb -s 36c77fb6 shell am force-stop com.zcstudy.xiaole
adb -s 36c77fb6 shell "am start -W -n com.zcstudy.xiaole/.MainActivity"
adb -s 36c77fb6 exec-out screencap -p > cold$i.png
```

| 判定 | 阈值 |
|---|---|
| 启动耗时 | `TotalTime` ≤ 3000 ms（次次都要打印，2 次取记录） |
| 界面 | 截图会话列表可见、无白屏/黑屏 |
| 崩溃 | 通用失败信号命中数 = **0** |

正则：`TotalTime`、`FATAL EXCEPTION|E/flutter`。

## 2. 文字聊天·短句（跑 2 次：正常 + 边界 9 字）

```powershell
adb -s 36c77fb6 shell "am start -n com.zcstudy.xiaole/.MainActivity -e debug_send_text_seg '现在几点了'"
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
adb -s 36c77fb6 shell "am start -n com.zcstudy.xiaole/.MainActivity -e debug_send_text_seg '今天下午三点我要去城东的维修点取修好的笔记本电脑，顺路帮同事带两杯咖啡，回来以后把本周的项目进度整理成一份简短总结发给团队，最后提醒我晚上八点给家里打个电话确认周末的安排'"
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
adb -s 36c77fb6 shell uiautomator dump /sdcard/ui.xml
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

正则：`MicGate`、`acquire|release|denied|reject`（具体文案以 69 实际日志为准，首次运行先抄一行原文回填本文档）。
> 临时占位：等单包线交出三行日志的确切格式后，这里必须换成硬正则，不保留"靠人抄"的口子。

## 13. 杀进程重启（跑 2 次）

```powershell
adb -s 36c77fb6 shell am force-stop com.zcstudy.xiaole
adb -s 36c77fb6 shell "am start -W -n com.zcstudy.xiaole/.MainActivity"
```

| 判定 | 阈值 |
|---|---|
| 自动重连 | `[RECONNECT] 成功` 出现 ≥1，且无需手点 |
| 保活生效 | 恢复后 120s 内出现 ≥4 条 `[KEEPALIVE] tick#`，序号连续 |
| 崩溃 | 0 次 FATAL/白屏 |

## 14. 息屏 / 后台（各 3 分钟，跑 2 轮）

```powershell
adb -s 36c77fb6 shell input keyevent 26          # 息屏
adb -s 36c77fb6 shell input keyevent 3           # 回桌面（后台）
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
adb -s 36c77fb6 shell svc wifi disable
Start-Sleep -Seconds 60
adb -s 36c77fb6 shell svc wifi enable
# 若 svc wifi 无权限，改用飞行模式：
# adb -s 36c77fb6 shell "cmd connectivity airplane-mode enable" / disable
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

## 16. 运行次数矩阵（"多次运行"的落地口径）

| 项 | 次数 | 说明 |
|---|---|---|
| 4 按住说话 | **≥5** | 竞态高发，逐次核对置位顺序 |
| 5 上滑取消 | **≥5** | 竞态高发，逐次核对无残留 |
| 12 麦克风互斥 | **5 轮 ×10 次** | 竞态高发，逐轮核对三行日志 |
| 15 离线/断网恢复 | **≥2** | 一次 60s、一次 120s（长时间断网也须收敛到 30s 封顶） |
| 其余 11 项 | **≥2** | 一次正常 + 一次异常/边界 |

## 17. Bug 处理（当场闭环）

发现 bug 时：**同一会话内定位 → 改 → 重出包（69.x）→ 重新安装 → 只重验该项 + 通用失败信号**，
不许攒到最后。重装仍走 §0.2 三连弹，**禁止 `adb uninstall`**。

## 18. 收尾

```powershell
# 关闭保活探针 → 还原 57 → 清 reverse → 回桌面
adb -s 36c77fb6 install -r -d "<TEMP>\xiaole-apk\xiaole-apk-6.11.5+57-c315bc4\xiaole-6.11.5+57-c315bc4-release.apk"
adb -s 36c77fb6 reverse --remove-all
adb -s 36c77fb6 shell input keyevent KEYCODE_HOME
```

还原后用 `docs/device-baseline-36c77fb6-2026-11-04.md` §2 的字段复核，并追加本次 69 的 `firstInstallTime`。
