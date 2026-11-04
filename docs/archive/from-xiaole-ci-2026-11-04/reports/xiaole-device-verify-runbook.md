# 6.11.6+58 设备验证 Runbook（5 分钟版）+ 并发冲突一页简表

> 适用范围：**只测语音链路稳定性**（3 分钟不断线 / 后台保活 / 断网重连）。
> App 内置工具（`mika.*`）已迁到 `xiaozhi-openclaw-mcp-hub2027`，**不在本次验证范围**，出现 `unknown tool: mika.*` 视为无关噪音。

被测包（固定）：

```
APK   C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6116\xiaole-apk-6.11.6+58-93a1eda\xiaole-6.11.6+58-93a1eda-release.apk
SHA256 7b5fecd7f5df7c04686a8e76aaea43694e3cdaee17f14e44bc92d14cde963930
期望 versionCode=58 / versionName=6.11.6 / minSdk=24
```

---

## A. 5 分钟执行清单（PowerShell，逐块复制；每块都带判定）

### A0. 前置闸门（必须全部为真，否则不要开始）

```powershell
adb devices
adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | Select-String 'versionCode|versionName|lastUpdateTime'
adb -s 36c77fb6 reverse --list
adb -s 36c77fb6 shell "dumpsys activity activities | grep mResumedActivity"
```

判定：

| 检查 | 通过条件 |
|---|---|
| `adb devices` | 只有 1 台 `36c77fb6  device`（出现第 2 个 adb 客户端/其他任务在跑 → **中止**） |
| `reverse --list` | **无** `tcp:8899`、无 `tcp:5005`（有 → 说明对方环境未清干净，中止） |
| 前台 | 没有 `com.wangzan101.mika` 等外部应用反复抢占（后续 A2 里若中途被抢→作废重跑） |
| 智能体 URL | 界面确认 `小乐1793777857804` 的 WebSocket 地址 = `wss://api.tenclass.net/xiaozhi/v1/`（若仍是 `ws://127.0.0.1:8899` → 中止，先修配置） |

### A1. 装机并校验（约 40s）

```powershell
adb -s 36c77fb6 install -r 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6116\xiaole-apk-6.11.6+58-93a1eda\xiaole-6.11.6+58-93a1eda-release.apk'
adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | Select-String 'versionCode|versionName|lastUpdateTime'
$p=(adb -s 36c77fb6 shell "pm path com.zcstudy.xiaole").Trim() -replace 'package:',''
adb -s 36c77fb6 pull $p 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\run_installed.apk'
(Get-FileHash 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\run_installed.apk' -Algorithm SHA256).Hash.ToLower()
adb -s 36c77fb6 shell "dumpsys deviceidle whitelist" | Select-String 'zcstudy'
```

判定（阈值硬性）：

- `install` 输出 `Success`
- `versionCode=58`、`versionName=6.11.6`
- pull 回 hash **等于** `7b5fecd7…cde963930`
- whitelist 含 `user,com.zcstudy.xiaole,10352`
- **记下本次 `lastUpdateTime`**，收尾时再查一次，若变了 → 说明被别的任务覆盖，本轮作废

### A2. 测试 A：连续 3 分钟（180s+）不断线

```powershell
adb -s 36c77fb6 logcat -c
adb -s 36c77fb6 shell am start -n com.zcstudy.xiaole/.MainActivity
Start-Sleep -Seconds 2
adb -s 36c77fb6 shell input tap 700 384        # 列表第一行=云端智能体；随后立刻截图确认进的是它
Start-Sleep -Seconds 4
adb -s 36c77fb6 shell screencap -p /sdcard/A_start.png
adb -s 36c77fb6 pull /sdcard/A_start.png 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_start.png'
```

确认截图标题为 `小乐1793777857804 • 已连接` 后，开始计时采集（**期间不要碰屏幕**）：

```powershell
adb -s 36c77fb6 logcat -v time > 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log'
```

180 秒后在新窗口执行（保留采集窗口）：

```powershell
Select-String 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log' -Pattern 'XiaozhiWebSocketManager: (正在连接|已连接到|连接已断开|看门狗)' | ForEach-Object { $_.Line }
adb -s 36c77fb6 shell screencap -p /sdcard/A_end.png
adb -s 36c77fb6 pull /sdcard/A_end.png 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_end.png'
```

判定：

| 结果 | 判定 |
|---|---|
| 只有 1 条 `正在连接`，0 条 `连接已断开`，且 A_end 截图仍为「已连接」 | **PASS** |
| 出现任何 `连接已断开 code=1006`（尤其连接后 55–65s 处） | **FAIL**（ping 保活未生效，检查 `pingInterval` 是否真的传入） |
| 中途出现 `source=dispose`（页面被销毁/被抢前台） | **作废**，重跑 A2 |

### A3. 测试 B：后台切出 30s 再回来

```powershell
adb -s 36c77fb6 shell input keyevent 3
Start-Sleep -Seconds 30
adb -s 36c77fb6 shell am start -n com.zcstudy.xiaole/.MainActivity
Start-Sleep -Seconds 25
Select-String 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log' -Pattern 'XiaozhiWebSocketManager: (连接已断开|看门狗|正在连接|已连接到)' | Select-Object -Last 10 | ForEach-Object { $_.Line }
```

判定：

| 结果 | 判定 |
|---|---|
| 后台 30s 内无 `连接已断开`，回前台仍「已连接」 | **PASS（更优）** |
| 后台期间断开，回前台后 25s 内出现 `看门狗：连接不存在，立即补连` → `已连接到 wss://…` | **PASS** |
| 回前台 25s 后仍无任何重连动作、截图「已断开」 | **FAIL**（看门狗未跑或 `_manualClosed` 被误置为 true） |

### A4. 测试 C：断网 10s 再恢复

```powershell
adb -s 36c77fb6 shell svc wifi disable
adb -s 36c77fb6 shell svc data disable
Start-Sleep -Seconds 10
adb -s 36c77fb6 shell svc wifi enable
adb -s 36c77fb6 shell svc data enable
Start-Sleep -Seconds 40
Select-String 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log' -Pattern 'XiaozhiWebSocketManager: (连接已断开|网络中断|正在连接|已连接到)' | Select-Object -Last 12 | ForEach-Object { $_.Line }
adb -s 36c77fb6 shell screencap -p /sdcard/C_end.png
adb -s 36c77fb6 pull /sdcard/C_end.png 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\C_end.png'
```

若 `svc wifi disable` 无权限/无效果，改用：

```powershell
adb -s 36c77fb6 shell cmd connectivity airplane-mode enable
Start-Sleep -Seconds 10
adb -s 36c77fb6 shell cmd connectivity airplane-mode disable
```

判定：

| 结果 | 判定 |
|---|---|
| 断网时出现 1 条 `连接已断开` + `网络中断，1.0s 后第 1 次自动重连…`；恢复后 ≤40s 内 `已连接到 wss://api.tenclass.net/xiaozhi/v1/`，截图「已连接」 | **PASS** |
| 恢复后 60s 内没有任何重连尝试 | **FAIL**（重连定时器或网络恢复监听缺失） |
| 反复 `连接已断开`→`正在连接` 超过 3 轮仍不成功 | **FAIL**（记 backoff 序列，回合结束后单独分析） |

### A5. 收尾取证（一条命令打包）

```powershell
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = "C:\Users\Administrator\Documents\Trae-CN\temp_20261104_03\verify_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log' $out
Copy-Item 'C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\*_start.png','C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_end.png','C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\C_end.png' $out -ErrorAction SilentlyContinue
adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | Select-String 'versionCode|lastUpdateTime' | Out-File "$out\package.txt"
adb -s 36c77fb6 reverse --list | Out-File "$out\reverse.txt"
Get-ChildItem $out | Select-Object Name,Length
```

判定：`package.txt` 的 `lastUpdateTime` 与 A1 记录的**一致**（变了 = 本轮被覆盖，三测作废）。

### A6. 时间预算

| 阶段 | 预计 |
|---|---|
| A0 前置 | 20s |
| A1 装机 | 40s |
| A2 3 分钟 | 200s |
| A3 后台 | 60s |
| A4 断网 | 60s |
| A5 取证 | 15s |
| **合计** | **≈ 5 分 40 秒**（A0 出现异常则不计入） |

---

## B. 设备并发冲突一页简表（证据）

| 时间 (2026-11-04) | 事件 | 判定依据 | 影响 |
|---|---|---|---|
| 15:19:29 | 本任务首次装 CI 包，`firstInstallTime` 固定 | `dumpsys package` | 基线 |
| 16:07:53 → 16:08:54 | 旧包连云端后 **60.26s** 被断（1006，reason 空） | `stability3m.log` | 定位"空闲回收"根因 |
| 16:08:54.646 | `OplusHansManager freeze uid 10352 com.zcstudy.xiaole` | logcat | 冻结使重连定时器停摆 |
| 16:39:37 | 设备上的包首次被外部构建覆盖（`6.11.5`） | `lastUpdateTime` | 本任务包被替换 |
| 16:43:10 | 本任务装 `6.11.6+58`，pull 回 hash 与 artifact 一致 | `dumpsys` + sha256 | 修复版上台 |
| 16:44:09 | 新包连 `wss://api.tenclass.net/xiaozhi/v1/`，hello + 31 个 `self.*` 工具全通 | `verify` 日志 | 证明 token/401 无关 |
| **16:44:29** | 又被 `6.11.5 / versionCode 57 / minSdk 30` 覆盖 | `lastUpdateTime` + `versionCode` | **修复版仅存活 89 秒**，3 分钟测试中断 |
| 16:52 | 云端智能体 WS 地址被改成 `ws://127.0.0.1:8899` 并保存 | 编辑页截图 + 列表时间戳 16:52 | 用户"能连的智能体"被破坏 |
| 16:52:39 | OTA 仍返回官方地址，但 App 连的是智能体里的 127.0.0.1 | 日志 `正在连接 ws://127.0.0.1:8899` | 说明"配置项优先于 OTA"，是复现关键 |
| 16:52:41 | `HttpException uri=http://127.0.0.1:8899` → `1006` 循环 | 日志 | 复现"一直断线" |
| 16:54:19 | 假服务端重启，`mcp initialize` 的 `clientInfo.name = fake-xiaozhi` | 日志 | 确认对端是测试桩，非官方云 |
| 16:54:19 | 本任务包回 `unknown tool: mika.submit_goal`（master 无 `mika.*`） | 日志 | 对端联调因此失败 |
| 16:53 → 17:02 | 前台被 `com.wangzan101.mika` 反复抢占（≥6 次采样命中，截图多次落到 Mika 页） | `mResumedActivity` + 截图 | 无法保持 3 分钟前台 |
| 16:55 / 17:03 | `adb reverse` 被重新加回 `tcp:8899`、`tcp:5005` | `reverse --list` | 本机回环端点复活 |
| 17:02 | 本任务 5 次尝试改回官方 URL 均被抢占打断，中途输入法污染字段（已用返回键丢弃、未保存） | 逐次截图 | 未污染持久化配置，但确认并发不可控 |

### B1. 由该表推出的规矩（建议纳入流程）

1. **设备互斥**：同一时段只允许一个任务持有 `36c77fb6`；持有方在开始时 `adb reverse --list` 打基线，交还时再打一次，差异清零。
2. **安装即登记**：每次 `install` 后必须记录 `versionCode + lastUpdateTime`；下一轮开始前比对，不一致即视为"被覆盖"，不沿用旧结论。
3. **配置只读原则**：非本任务的智能体（尤其用户说"能连的"那一个）不得改 url/token/MAC；需要改先报备。
4. **adb reverse 生命周期**：调试用的 `tcp:8899/5005` 用完立即 `--remove-all`，不许跨任务残留。
5. **前台占用登记**：验证窗口内不得启动其他 App 到前台；违者该轮作废重跑。
6. **结论口径**：只有 A2/A3/A4 三项全 PASS 且 `lastUpdateTime` 未变，才允许对外写"断线已解决"。
