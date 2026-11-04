# 小乐 APK 断线修复与验证报告（6.11.6+58 / 2026-11-04）

**结论：断线根因已确认并在代码层修好（`pingInterval` 25s 保活 + 独立看门狗），master 已出包 `6.11.6+58`、装机 hash 校验通过；但"连续 3 分钟不掉线 / 后台切出再回 / 断网 10s 恢复"三测**没有**跑完，所以这条**不能**标记为"已验证解决"。阻断原因是同一台手机上另一个 session 在持续抢占设备：它在 `16:44:29` 用 `6.11.5(57)` 覆盖了我们刚装的包，在 `16:52` 把控的云端智能体 WebSocket 地址改成 `ws://127.0.0.1:8899`，并重新打开 `adb reverse tcp:8899` 与假小智服务端，构成新一轮"一直断线"循环。**

---

## 1. 代码修复（已提交、已出包）

仓库 `openclawzhangchong/xiaole-client-flutter-2027`，commit `93a1eda`，`pubspec.yaml` 版本从 `6.11.5+57` → `6.11.6+58`。

改动文件：[xiaozhi_websocket_manager.dart](file:///C:/Users/Administrator/AppData/Local/Temp/xiaole-ci/lib/core/network/xiaozhi_websocket_manager.dart)（42 增 / 3 删）

| 改动 | 内容 | 作用 |
|---|---|---|
| 常量 | `PING_INTERVAL = 25s`、`WATCHDOG_INTERVAL = 20s` | 保活 + 看门狗节奏 |
| 连接 | `IOWebSocketChannel.connect(uri, headers: headers, pingInterval: PING_INTERVAL)` | 修 `16:07:53.809 → 16:08:54.071`（恰 60.26s，code=1006、reason 空）的空闲回收 |
| 看门狗 | `_startWatchdog()`，连接建立即启动，每 20s 检查 `isConnected` | 进程被 OplusHans 冻结后 Dart 定时器停摆、回前台时"订阅还在但连接没了"，立即补连；达上限则清零重试 |
| 重连 | 原 `_onDisconnected` 内联退避逻辑抽成 `_scheduleReconnect()`，看门狗复用同一条路径 | 纯 `Timer` 调度，**不依赖** `didChangeAppLifecycleState` |
| 主动断开 | `disconnect()` 里取消 `_watchdogTimer` | 用户手动断开不会被看门狗连回去 |

> 依赖确认：`pubspec.lock` 中 `web_socket_channel: 3.0.3`，`IOWebSocketChannel.connect` 支持 `pingInterval`（pong 超时也会触发 `_onDisconnected`，所以没有再额外做"静默判僵死"，避免云端空闲不下发消息时误杀）。
> CI：run `41800363754` success，`analyze` 无 error（`analyze.log`）。

## 2. 出包与装机校验

| 项 | 值 |
|---|---|
| artifact | `xiaole-apk-6.11.6+58-93a1eda` |
| APK 大小 | 40,806,378 B |
| artifact sha256 | `7b5fecd7f5df7c04686a8e76aaea43694e3cdaee17f14e44bc92d14cde963930` |
| 装机时间 | `lastUpdateTime=2026-11-04 16:43:10` |
| 装机后 versionCode / versionName | `58` / `6.11.6`（minSdk 24, targetSdk 35） |
| 从设备 pull 回的 base.apk sha256 | `7b5fecd7…cde963930` —— **与 artifact 完全一致** |
| firstInstallTime | `15:19:29`（未卸载重装，保留了智能体数据） |

冻结防护：

```
$ adb shell dumpsys deviceidle whitelist +com.zcstudy.xiaole
Added: com.zcstudy.xiaole
$ adb shell dumpsys deviceidle whitelist | grep zcstudy
user,com.zcstudy.xiaole,10352          ← 已生效（17:03 复查仍在）
```

## 3. 三测结果

| 测试 | 结果 | 证据 |
|---|---|---|
| 连续 ≥3 分钟不掉线 | **未完成**（只跑到约 20s 就被覆盖安装打断） | 见下 |
| 后台切出再回，保持或自动恢复 | **未执行**（设备被另一任务占用） | —— |
| 断网 10s 再恢复，自动重连 | **未执行** | —— |

新包连云端（16:44）实证：

```
16:44:09.624 ChatScreen: WS 初始化开始 agentId=642093bc-fd5e-4038-aba8-33af988adfa8
              url=wss://api.tenclass.net/xiaozhi/v1/
16:44:09.906 XiaozhiWebSocketManager: 使用headers方式连接WebSocket成功
16:44:09.907 XiaozhiWebSocketManager: 已连接到 wss://api.tenclass.net/xiaozhi/v1/
16:44:10.110 发送 hello: {"type":"hello","version":1,"features":{"mcp":true},...}
16:44:10.176 收到服务器 hello 响应，会话ID: cbd0dcd3
16:44:10.215 回 tools/list（31 个 self.* 工具）
```

同刻截图：标题「小乐1793777857804 • 已连接」（绿点，无红色横幅）。

但 **16:44:29** 设备上的包被换回 `6.11.5 / versionCode 57`：

```
lastUpdateTime=2026-11-04 16:44:29
versionCode=57  minSdk=30  versionName=6.11.5
```

即我们的包只在设备上存活 `16:43:10 → 16:44:29`（89 秒）。

## 4. 阻断证据：另一个 session 在改写设备状态

| 时间 | 事件 | 证据 |
|---|---|---|
| 16:39:37 | 前一次被覆盖（`6.11.5`） | `lastUpdateTime` |
| 16:43:10 | 我们装 `6.11.6+58`，sha 校验通过 | 第 2 节 |
| 16:44:29 | 又被 `6.11.5/57` 覆盖 | `dumpsys package` |
| 16:52 | 云端智能体被改：`WebSocket 地址 = ws://127.0.0.1:8899` 并保存 | 编辑页截图（16:52 保存后列表时间戳变 16:52） |
| 16:52:39 | App OTA 仍返回官方地址，但随后连 127.0.0.1 | 见下日志 |
| 16:52:41 | 连不上（无服务端）：`HttpException ... uri = http://127.0.0.1:8899` → `1006` 循环 | 见下日志 |
| 16:54:19 | 假服务端重启，下发 `mcp initialize`，`clientInfo={"name":"fake-xiaozhi"}` | 见下日志 |
| 16:55 / 17:03 | `adb reverse` 被重新加回：`tcp:8899`、`tcp:5005` | `adb reverse --list` |
| 16:53–17:02 | 前台被 `com.wangzan101.mika` 反复抢占（`mResumedActivity` 多次为 Mika，截图多次落在 Mika 首页/设置页） | 逐次截图 |

关键日志：

```
16:52:39.591 OTA Response: {..., websocket: {url: wss://api.tenclass.net/xiaozhi/v1/, token: test-token}}
16:52:39.547 正在连接 ws://127.0.0.1:8899            ← 用的是智能体里被改过的 url，不是 OTA 的
16:52:41.595 SEVERE: WebSocketChannelException: HttpException: Connection closed before full header
             was received, uri = http://127.0.0.1:8899
16:52:41.595 连接已断开 code=null reason=null attempts=0 kind=服务器
16:54:19.961 收到 mcp initialize ... clientInfo: {"name": "fake-xiaozhi", "version": "0.0.1"}
16:54:19.995 回 error: -32601 "unknown tool: mika.submit_goal"   ← 我们这版没有 mika.*，对方联调因此失败
```

也就是说：现在的"一直断线"已经不是代码缺陷，而是**设备上的智能体指向了一个本地假服务端**（该服务端在 `mika.submit_goal` 失败后主动断链）。这与诊断报告第一版结论完全一致。

## 5. 智能体配置留档（清理前导出）

| 字段 | 能连的云端智能体 | 本机联调智能体（已不在列表） |
|---|---|---|
| id | `642093bc-fd5e-4038-aba8-33af988adfa8` | `6565c9e0-36a6-468f-9527-c1b8bab1184f` |
| name | `小乐1793777857804` | `小乐1793779009474` |
| url（原始） | `wss://api.tenclass.net/xiaozhi/v1/` | `ws://127.0.0.1:8899` |
| url（16:52 被改成） | `ws://127.0.0.1:8899` ← **需恢复** | — |
| token | `to-test`（`enableToken:false`，实际用 OTA 下发的 `test-token`） | `to-test` |
| otaUrl | `https://api.tenclass.net/xiaozhi/ota/` | 同左 |
| MAC / device-id | `92:81:7a:fb:a6:fb` | 同左 |
| Client ID | `a9cb3bf8-6c8a-41c5-aa2b-8c8d4fe9882a` | 同左 |
| 设备型号 | `m5stack-core-s3` | 同左 |
| createdAt | 2026-11-04 15:37:39 | 2026-11-04 15:57:39 |

> 设备身份是 App 自生成的 `92:81:7a:fb:a6:fb`，**不是**你给的 M5Stack CoreS3 `7f:f1:b7:5e:ef:aa`；OTA 对该身份返回 `activation=false`（已激活），本次全程没有新建绑定、没有触发重新激活。

## 6. 需要立刻做的收尾（3 步，不改绑定）

1. 长按 `小乐1793777857804` → 编辑智能体 → 展开"高级设置" → 把 **WebSocket 地址** 从 `ws://127.0.0.1:8899` 改回 `wss://api.tenclass.net/xiaozhi/v1/` → 右上角"提交激活"（该动作只 `updateAgent` + 只读轮询 OTA，不会新建绑定）。
2. 停掉 PC 侧假服务端进程，`adb reverse --remove-all`（当前还挂着 `tcp:8899`、`tcp:5005`）。
3. 重新安装 `6.11.6+58` 包（sha `7b5fecd7…`），并保证 3 分钟内没有第二个任务覆盖安装/抢占前台，然后按下面三条跑完。

## 7. 剩余验证清单（设备让出来后按序执行）

```
# A. 3 分钟不倒线
adb logcat -c && adb logcat -v time > verify3m.log   # 另开窗口，进入云端智能体后计时 180s+
grep 'XiaozhiWebSocketManager: (正在连接|连接已断开)' verify3m.log   # 期望：只有 1 条"正在连接"，0 条"连接已断开"

# B. 后台切出 30s 再回
adb shell input keyevent 3 ; sleep 30 ; am start -n com.zcstudy.xiaole/.MainActivity
# 期望：回来 20s 内出现"看门狗：连接不存在，立即补连"，或原本就没断

# C. 断网 10s
adb shell svc wifi disable ; adb shell svc data disable ; sleep 10
adb shell svc wifi enable  ; adb shell svc data enable
# 期望：恢复后按 1/2/4/8s 退避重连，最终"已连接到 wss://..."
```

三测都过才可对外说"断线已解决"。

## 8. 当前设备真实状态（截至 17:03）

- 已装：`6.11.5 / versionCode 57`（不是我们的包，**不含**本次 ping/看门狗修复）。
- 智能体：`小乐1793777857804`，URL = `ws://127.0.0.1:8899`（坏），列表可见 1 项。
- `adb reverse`：`tcp:8899`、`tcp:5005` 仍存在；PC 侧假服务端已被对方重启。
- 冻结白名单：`user,com.zcstudy.xiaole,10352` 已生效（保留）。
- 编辑页的临时输入（已用返回键丢弃，未保存），持久化配置未被本次操作改坏。
