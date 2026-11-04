# v6.11.7 交付：覆盖来源已查清（PC 端 adb 降级安装）＋ 心跳方案走「无感重连」（文档未定义 WS 心跳）＋ 已出包、未装机

结论一句话：**17:13:41 把包换回 `6.11.5/57` 的是 PC 端 `adb install`（`installerPackageName=pc`、`installerUid=2000`=shell，不是应用商店、不是手机上的旧 APK 自动装回）；上游文档全文没有 WebSocket 心跳/空闲超时条款，所以走「无感重连」而不是业务层保活；`v6.11.7+59` 已走 GitHub 云端 CI 出包（run `41807490945` ✅），按要求**尚未装机**。**

---

## 一、覆盖安装来源（第 1 步，只读取证）

### 1.1 当前设备真实状态（realme RMX3161，`adb -s 36c77fb6`）

```
versionCode=57 minSdk=30 targetSdk=35
versionName=6.11.5
firstInstallTime=2026-11-04 15:19:29
lastUpdateTime=2026-11-04 17:13:41
installerPackageName=pc
```

- `installerPackageName=pc` = 由 PC 侧 `adb` 安装（`installerUid=2000` 就是 `shell`）。
- `firstInstallTime` 仍是 **15:19:29**（没变）⇒ 对方用的是 **`install -r` 覆盖**（并带 `-d` 允许降级），**不是**卸载重装。

### 1.2 logcat 关键行（原始证据）

来源：`C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log`（同一事件在 `verify_v2.log` 里重复出现）

```
11-04 17:13:41.443 D/OplusInstallAccelerateManager(2356): installerPackageName = pc
11-04 17:13:41.803 D/PackageManager(2356): installStage com.zcstudy.xiaole, dir=/data/app/vmdl528073121.tmp,
                                          installerPackageName=pc, installerUid=2000, full=false
11-04 17:13:41.897 I/ActivityManager(2356): Force stopping com.zcstudy.xiaole appid=10352 user=-1: installPackageLI
11-04 17:13:41.902 I/ActivityManager(2356): Killing 18739:com.zcstudy.xiaole/u0a352 (adj 0): stop com.zcstudy.xiaole due to installPackageLI
11-04 17:13:44.773 D/iopgp(4034): OnPackageChangeEvent: ...{packageName=com.zcstudy.xiaole, version=57, lastUpdateTimeMillis=1793783621900}
11-04 17:13:45.146 D/OplusOsPackageManager(2356): uploadInstallAppInfos:{code=57, ... source=pc, app_pkg=com.zcstudy.xiaole,
                                                     version=6.11.5, md5=026f634ae309cc4cd28d7c67e2df959d, installerPackageName:pc}
```

对照：17:08:40 那一次是我们自己的 `6.11.6/58`（`code=58, version=6.11.6, source=pc`），**同一通道、同一个 `pc` 安装器**。也就是说 17:13 是**另一个会话拿着 6.11.5 的 APK 用同一条 adb 通道做了降级覆盖**。

### 1.3 商店/自动更新侧排除

- `pm list packages` 里确有商店类包（`com.heytap.market` 等），但 **`installerPackageName` 不是它们**，事件日志里也没有它们的安装动作。
- `settings get global package_verifier_enable` / `auto_update_apps` / `ota_disable_automatic_update` 三项均返回 `null`（无有效值、未被改写），realme "应用自动更新"未参与本次安装。
- 本机桌面/下载目录已无残留 `.apk`（旧 6.11.5 包应是另一会话从 CI artifact 临时下载后即装即弃）。

### 1.4 怎么"禁掉它"（可执行）

1. **管理面（根因）**：禁止其它会话/脚本再执行 `adb install` 旧包，尤其是带 `-d` 的降级覆盖。装机只认本会话产出的 `6.11.7+59`，装完立即用 §五 的 preflight 自证。
2. **版本护栏（已生效）**：新包 `versionCode=59` > `57`，正常 `adb install -r` 不会回退；只有显式 `-d` 才能降级 —— 所以"禁止 `-d`"就够。
3. **商店通道**（本次不是它，但若要彻底断开自动更新）：
   - 关商店自动更新：`adb shell pm disable-user --user 0 com.heytap.market`（写操作，需你点头）；或在商店「设置 → 自动更新应用」关闭。
   - 观察名单：`adb shell pm list packages | findstr /i "appstore market updater"`。
4. **不推荐**改包名：会变成另一个 App、丢登录态与设备身份，代价远大于收益（`versionCode=59` 已足够防回退）。

---

## 二、心跳规则：文档怎么说（第 2 步，只读原文）

仓库：`C:\Users\Administrator\AppData\Local\Temp\recon-xiaozhi\xiaozhi-esp32\docs\`

### 2.1 `websocket_zh.md`（全文 503 行已通读）

**没有**任何"心跳 / keepalive / ping / 空闲超时 / 保活"条款。相关原文只有握手超时与断开处理：

- `websocket_zh.md:69`
  > 如果在超时时间（默认 10 秒）内未收到正确回复，认为连接失败并触发网络错误回调。
  （这是 **hello 握手** 10s 超时，不是会话空闲超时）
- `websocket_zh.md:81-82`
  > 当服务器或网络出现断连，回调 `OnDisconnected()` 被触发：设备会调用 `on_audio_channel_closed_()`，并最终回到空闲状态。
- `websocket_zh.md:392-393`
  > 设备通过设置 `Authorization: Bearer <token>` 提供鉴权，服务器端需验证是否有效。
  > 如果令牌过期或无效，服务器可拒绝握手或在后续断开。
  （只说明"可能断开"，**没有给出任何时间阈值，也没有说哪种消息能续命**）
- `websocket_zh.md:162-168` 里 `listen` 的 `state` 只有语义定义：
  > `"state"`：`"start"`, `"stop"`, `"detect"`（唤醒检测已触发）
  ⇒ `detect` 是"唤醒词已触发"的业务事件，**文档未定义为心跳**。

### 2.2 `websocket.md`（英文同源）

- `:70` 只有 hello 10s 超时；`:83` `OnDisconnected`；`:413` 连接失败提示。同样**无心跳/空闲超时**。

### 2.3 `mcp-protocol_zh.md`

全文只有 1 处 `idle`（`:207` 的 `"newState": "idle"` 状态机示例），**无心跳、无保活、无超时**。

### 2.4 唯一有"心跳"字样的地方是 MQTT/UDP，不适用

- `mqtt-udp_zh.md:69`
  > `Keep Alive`：心跳间隔（默认240秒）
- `mqtt-udp_zh.md:306-309`
  > 基类 `Protocol` 提供超时检测：默认超时时间：120 秒；基于最后接收时间计算；超时时自动标记为不可用

这是 **MQTT 控制通道 / UDP 会话**的机制，不是 WebSocket 传输；本 App 走的是 `websocket`。

### 2.5 文档结论

**文档未写明 WebSocket 的服务端空闲超时，也未说明哪条消息算"活跃"，更无官方保活写法。** 真机唯一硬证据是我们自己的实测：`pingInterval=25s` 仍被 ~70s 一次的 `1005` 静默关闭 ⇒ **WS 控制帧 ping 不算业务活跃**，服务端按**业务消息**空闲回收。因此按你的指令走**次优解「无感重连」**，并在下文明确写清：**没能消除服务端回收，只是让用户无感**。

---

## 三、改动清单与版本号（第 3 步）

版本：`6.11.6+58` → **`6.11.7+59`**（`pubspec.yaml:19`；`lib/app/config/app_config.dart:7` 同步 `appVersion=6.11.7`，OTA 请求使用）。

| 文件 | 改动 |
|---|---|
| `lib/presentation/pages/chat/chat_page.dart` | 断线 UI 改为"无感"（见下）；新增 `RECONNECT_UI_GRACE=4s`、`_reconnectUiTimer`、`_showReconnectBar`、`_isAutoReconnecting` getter、`_armReconnectUiTimer()` |
| `lib/core/network/xiaozhi_websocket_manager.dart` | **未改**：保留 `pingInterval=25s`、`WATCHDOG_INTERVAL=20s`、`_scheduleReconnect()`（1s→2s→4s→…封顶 30s，12 次） |
| `pubspec.yaml` / `app_config.dart` | 版本号 |
| `CHANGELOG.md` / `README.md` / `进度与续接.md` | 版本档案与 CI 结论回填 |

行为矩阵（`chat_page.dart`）：

| 场景 | 旧（6.11.6） | 新（6.11.7） |
|---|---|---|
| 1005/1006 空闲回收 | 红条 `已断开 (1005)` + 「重连」按钮，每 ~70s 闪一次 | 状态改 `重连中…`（与"已连接"等宽），**4s 内不显示状态条**；顶部圆点琥珀色 +「重连中」，回连成功即恢复绿色 |
| 4s 仍未恢复 | 同旧 | 亮琥珀色状态条 + 「重连」按钮（可手动） |
| 432x 身份校验失败 | `已断开 (432x)` | **保持** `已断开 (432x)`（重连无效，必须让用户看到真实原因） |
| 重连达上限 | 弹错误、状态停留在旧值 | 弹错误 + 状态条交还手动「重连」，不再伪装"重连中" |

关键代码位置：[chat_page.dart](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/lib/presentation/pages/chat/chat_page.dart#L76-L81)（字段）、[L786-L804](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/lib/presentation/pages/chat/chat_page.dart#L786-L804)（getter/定时器）、[L1854-L1891](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/lib/presentation/pages/chat/chat_page.dart#L1854-L1891)（连接/断开事件）、[L1913-L1923](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/lib/presentation/pages/chat/chat_page.dart#L1913-L1923)（不可自愈错误）。

> 明确边界：本版**没有消除**服务端按业务空闲 ~60–70s 的回收，只是让它对用户不可见（断线不报、1–4s 静默补连、UI 不跳字）。

---

## 四、CI 结果

| 项 | 值 |
|---|---|
| commit | `0a713ef`（`fix(v6.11.7): 断线改为无感重连…`），随后 `569daaa` 仅改文档 |
| run | **41807490945** ✅ success（`Build Release APK`，push master，耗时 **9m17s**） |
| artifact | `xiaole-apk-6.11.7+59-0a713ef`（已下载到 `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6117\`） |
| APK | `xiaole-6.11.7+59-0a713ef-release.apk`，**40,806,378 B** |
| sha256 | `2f695d3b711230bc3004b8cd066805a875170ccbfd9dcc9a5711957d759f5990` |
| analyze | `87 issues`，**0 error**（全部既有 `info`/`warning`；本次仅新增 1 条 `constant_identifier_names` info，与仓库既有常量命名风格一致）；`flutter build apk --release` 通过即为编译自证 |
| 签名 | `apksigner verify` 通过（workflow 内置复核，证书与 6.11.5/6.11.6 同一稳定 keystore，可覆盖安装） |
| 装机 | **未装**（按指令等你通知） |

---

## 五、待设备验证清单（拿到你通知后执行）

**Preflight（必须先过，不过就作废）**
1. `adb devices -l`：确认目标真机是 `-s 36c77fb6`（当前还挂了另一台 `XXB/b906`，命令**必须带 `-s`**，否则报 `more than one device`）。
2. `adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | findstr /i "versionCode versionName firstInstallTime lastUpdateTime installerPackageName"` → 装完应为 `versionCode=59 / 6.11.7`、`lastUpdateTime` 更新、`installerPackageName=pc`。
3. `adb reverse --list` 应为**空**（不得残留 8899/5005 联调）。
4. 确认无第三方会话在抢前台/改智能体配置（一旦出现即按作废处理）。

**A. 前台连续 ≥3 分钟**
- 进入聊天页，语音对话一次后静置 3 分钟；全程 `adb logcat` 抓 `XiaozhiWebSocketManager|WebSocket 已断开|1005`。
- 判据：出现 `closeCode=1005` 属预期（服务端回收），但**UI 不得出现"已断开"**；日志应呈现 `已断开 → 1s 后 已连接到 …` 的循环；3 分钟内随时说话都能得到回应。

**B. 后台切出再回来**
- Home 键切后台 60s → 回前台；判据：顶部显示"已连接"（或 1–4s 内由"重连中"转为"已连接"），发一句话有回应，**页面无红色错误条**。

**C. 断网 10 秒再恢复**
- 飞行模式 10s → 关闭；判据：10s 内显示琥珀"重连中"（不显示红色"已断开"），恢复后 1–4s 内回到"已连接"且能正常对话；若 >4s 才恢复，允许出现琥珀色状态条（此时"重连"按钮可点）。

三项全过才算这条修好。

---

## 六、证据文件索引

- `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\A_3min.log`（17:13:41 覆盖安装原始行）
- `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\verify_v2.log`（17:08:40 我方 6.11.6 安装 + 17:13:41 降级覆盖）
- `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6117\xiaole-apk-6.11.7+59-0a713ef\`（APK + SHA256SUMS + analyze.log）
- 文档原文：`...\recon-xiaozhi\xiaozhi-esp32\docs\websocket_zh.md`、`websocket.md`、`mcp-protocol_zh.md`、`mqtt-udp_zh.md`
