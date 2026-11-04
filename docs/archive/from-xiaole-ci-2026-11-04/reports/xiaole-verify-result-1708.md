# 6.11.6+58 真机三测结果（2026-11-04 17:08–17:18）

**结论：本轮 3 项测试 1 项 FAIL、2 项作废（VOID），`lastUpdateTime` 已变化 —— 断线未解决。**
- 测试 A（连续 3 分钟）：**FAIL** —— 在 6.11.6+58 上，连接仍被服务端以 `code=1005` 每 ~70s 回收一次，`pingInterval=25s` 未起作用。
- 测试 B（后台 30s）/ 测试 C（断网 10s）：**VOID（不计分）** —— 执行时设备上的包已被外部在 `17:13:41` 覆盖回 `6.11.5/57`，且页面被 dispose，测的不是我们的构建。
- `lastUpdateTime`：**变化** —— 本任务装机 `17:08:40（6.11.6/58）` → 被覆盖 `17:13:41（6.11.5/57）`。

---

## 1. A0 前置基线（通过）

```
adb devices            → 36c77fb6 device（另有 0123456789ABCDEF，非本机，未使用）
adb reverse --list     → 空
装机前 versionCode     → 57 / 6.11.5 / lastUpdateTime 16:44:29
```

## 2. A1 装机与校验（通过）

```
17:08:40  install -r → Success
versionCode=58  minSdk=24  versionName=6.11.6
pull 回 base.apk sha256 = 7b5fecd7f5df7c04686a8e76aaea43694e3cdaee17f14e44bc92d14cde963930  ← 与 artifact 一致
dumpsys deviceidle whitelist → user,com.zcstudy.xiaole,10352   ← 已生效
```

## 3. 测试 A：连续 3 分钟（FAIL）

起点截图 `A_start.png`（17:09，标题「小乐1793777857804 • 已连接」）。日志（`A_3min.log`，PID 18739 = v58）：

```
17:09:xx  已连接到 wss://api.tenclass.net/xiaozhi/v1/
17:10:12.519  连接已断开 code=1005 reason= attempts=0 kind=服务器
17:10:13.527  已连接到 wss://api.tenclass.net/xiaozhi/v1/        ← 1s 内自动恢复
17:11:23.330  连接已断开 code=1005 reason= attempts=1 kind=服务器
17:11:25.336  已连接到 wss://api.tenclass.net/xiaozhi/v1/        ← 2s 内自动恢复
17:12:33.240  连接已断开 code=1005 reason= attempts=2 kind=服务器
17:12:37.247  已连接到 wss://api.tenclass.net/xiaozhi/v1/        ← 4s 内自动恢复
```

判定（阈值：180s 内 0 条 `连接已断开`）：

| 指标 | 实测 | 判定 |
|---|---|---|
| 连续存活时长 | 69.8s / 67.9s / （第三次 17:12:37 起，到被覆盖的 17:13:41 为止 104s 内未再断，但期间进程被换掉） | **< 180s → FAIL** |
| 断线次数 | 180s 窗口内 3 次 | FAIL |
| 关闭码 | 全部 `1005`（无 close frame，服务端静默关闭），reason 空 | 说明不是网络错误、不是 401 |
| 自动重连 | 1s / 2s / 4s 成功 | 重连逻辑正常 |

**关键推论：WS 层 `pingInterval=25s` 没有被服务端当作"活跃"信号。** 服务端是按**业务消息空闲**（约 60–70s）回收，WS ping/pong 不计入。因此"加 pingInterval"这一招单独不成立。

## 4. 测试 B / C（VOID：被测构建在测试中途被替换）

`17:13:41` 外部覆盖安装后，设备上的包变成 `6.11.5 / versionCode 57 / minSdk 30`（校验见第 6 节），后续日志来自 PID 21618（v57）：

```
17:16:24.128  正在连接 wss://api.tenclass.net/xiaozhi/v1/
17:16:24.131  已连接到 wss://api.tenclass.net/xiaozhi/v1/
17:17:24.361  连接已断开 code=1006 reason= attempts=0 kind=服务器   ← 恰好 60.0s
17:17:25.378  已连接到 wss://api.tenclass.net/xiaozhi/v1/          ← 自动恢复
17:17:48.341  连接已断开（App 主动断开 source=dispose）              ← 页面被销毁
```

- B（后台 30s）：`keyevent 3` → 30s → 回前台，回到前台后 26s 才出现 1006；且这是 v57 的数据，**不作判定**。
- C（断网 10s）：`svc wifi/data disable → 10s → enable`，执行时页面已 `source=dispose`，日志中无任何断网相关重连记录，**不作判定**。

## 5. 由 A 得出的下一步（未验证，不作为结论）

1. **先查上游文档确认空闲回收规则**：`xiaozhi-esp32/docs/websocket_zh.md` 是否有心跳/空闲超时要求（ESP32 客户端靠持续音频帧保持会话，App 空会话没有等价物）。
2. 若确认是"业务空闲回收"，需要**业务层心跳**（例如按协议发 `{"type":"listen","state":"detect"}` 或文档中定义的保活消息），而不是 WS ping；实现前需确认该消息不会改变对话状态。
3. 备选方案（不改协议）：接受 60–70s 的服务端回收，但把重连做到"用户无感"——当前 1–4s 恢复，UI 会出现「已断开」横幅；可在重连中隐藏横幅、只显示"重连中"。
4. 1005 应加入"立即重连"白名单（目前走的是普通退避，已 1s 恢复，尚可）。

## 6. 并发冲突证据（本轮新增）

| 时间 | 事件 | 依据 |
|---|---|---|
| 17:08:40 | 本任务装 `6.11.6/58`，hash 校验通过 | `dumpsys package` + sha256 |
| 17:09–17:13 | 测试 A 执行中，前台一直是 `com.zcstudy.xiaole/.MainActivity` | `mResumedActivity` |
| **17:13:41** | 设备上的包被外部覆盖为 `6.11.5/57`（minSdk 30） | `lastUpdateTime` + `versionCode` |
| 17:16:24–17:17:48 | 日志 PID 变为 21618，连接 60.0s 后 1006；17:17:48 `source=dispose` | `BC.log` |
| 17:18:xx | 收尾时前台被置为 `com.android.launcher`（非本任务所为） | `mResumedActivity` |

## 7. 证据文件

| 文件 | 内容 |
|---|---|
| `<TEMP>\xiaole-apk\A_3min.log` | 17:09–17:15:23，含 A 的 3 次 1005 |
| `<TEMP>\xiaole-apk\BC.log` | 17:16–17:18，v57 的 60.0s 1006 与 dispose |
| `...\A_start.png` | 17:09 聊天页「已连接」（v58） |
| `...\A_end.png` / `...\A_open.png` | 列表页（A 结束时已被切走） |
| `...\B1.png` / `...\B2.png` / `...\B3.png` | B 阶段截图（v57） |
| `...\C_end.png` | C 阶段截图（列表页，v57） |
| `...\run_installed.apk` | 从设备 pull 回的 v58 base.apk（sha 已校验） |

## 8. 设备交还状态

```
adb reverse --list                → 空（已 --remove-all）
前台                              → com.android.launcher/.Launcher（已按 HOME 退出 App）
包状态                            → 6.11.5 / versionCode 57 / lastUpdateTime 17:13:41（外部覆盖，未再动）
本任务未执行                        → 未卸载、未再安装、未改任何智能体配置
```
