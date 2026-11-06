# 小乐（XiaoLe）单包版 — 聊天 + 实时语音 + 手机操作

一个 APK、一个包名（`com.zcstudy.xiaole`）：Flutter 负责界面与实时语音对话，内嵌的 Kotlin 引擎 **Mika** 以 library 模块编进同一进程，用于让 AI 在手机上执行操作（点按、输入、读屏、任务编排）。

> 本仓库是单包线（小乐 + Mika 合体）的正式源码基线。上游 Flutter 客户端为
> [eiriksgata/xiaozhi-client-flutter](https://github.com/eiriksgata/xiaozhi-client-flutter)（微信风 UI 定制）。

## 当前版本（默认分支）

| 项 | 值 |
|---|---|
| versionName | `6.11.25-mika1` |
| versionCode | `82` |
| 产物 | `xiaole-6.11.25-mika1-arm64.apk` / `xiaole-6.11.25-mika1-universal.apk`（GitHub Actions artifact，不进仓库） |
| 签名 | `C=CN, O=ZCStudy, CN=XiaoLe Release`，cert SHA-256 `9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169` |

82 产品定义（收口）：**锁屏可断，亮屏秒回；后台一次都不许重连。**

81 验收暴露了"风暴"的真正根因：不是退避没生效，而是**退避每一步都"成功"**。息屏日志里 `1006` 稳定出现在 16:05:54 / 16:06:58 / 16:08:02，间隔精确 62 秒——正好是服务端 60–70s 空闲回收的节奏。81 去掉后台 `listen{stop}` 后，服务端每 62s 掐一次连接，客户端立刻重连、握手成功、`_completeHandshake` 把退避计数清零，62s 后再被掐：**死循环，退避永远从 2s 重新开始**。因此 81 不是"没压住频率"，而是"后台仍然在主动重连"。

82 改动（在 81 之上）：

1. **后台彻底不重连**：进入 `paused`/`hidden` 时主动断掉后台连接（服务端 62s 空闲回收会留下 1006/1005，判据要求这两个计数为 0），断线后一律不重连、不排重试、不建退避定时器，只置"后台已断开"状态并写 `[KEEPALIVE] 后台断开，等待亮屏（82 口径）`。断就断到底。
2. **亮屏恢复有上限**：`resumed` 时 socket 已死立即补连 1 次；这一轮失败才走 `2s → 5s → 15s`，最多 3 次；仍失败就停手，UI 亮出手动「重新连接」按钮（不再永久后台重连）。
3. **原生闹钟只自愈 wakelock**：`SCHEDULE_EXACT_ALARM` 到点只重取被 ColorOS 强摘的 wakelock + 打 `wakeup#` 日志，**不再 `invokeMethod("wakeup")`**：不唤醒 Dart、不触发任何连接动作。
4. **前台 45s 保活不动**：`listen{stop}` 探针仍只在前台运行，这是绕开服务端 70s 空闲回收的唯一有效手段。
5. **通知文案保留**：「小乐在后台运行」。且 82 起服务/通知的存活只看前后台——后台断线也保留通知，不会因被服务端回收而消失。
6. **mock 任务卡真渲染**：修复 `MessageList` 把 `MessageType.system` 一律当居中纯文本的短路（`metadata['card']=='task'` 优先走 `MessageBubble → XlTaskCard`）。四态卡带卡框、标题、状态标签（queued 灰 / running 蓝 / done 绿 / failed 红）、时间或进度；点击进入 06 详情页（步骤/耗时/结果骨架，queued 也有 4 步演示数据）；注入与清除各一个入口。

82 验收判据（写死）：

- 息屏 3 分钟：`1005 = 0`、`1006 = 0`、`[RECONNECT] = 0`；允许 Dart tick 为 0（设计如此）。
- 亮屏：≤3 秒回连，无错误弹窗、无"连接僵死"；允许一次重连（这次重连是设计）。
- 后台通知仍在、`isForeground=true`。
- 05 拍到四张带状态标签的真卡片，06 拍到点进去的详情页。

05/06 mock 注入步骤（82 起走真任务卡组件）：

1. 「我」页 → 「开发者选项」→ 输入密码 `zc19901111`；
2. 进「UI 演示」→「任务卡演示」，提示"已注入"；
3. 返回聊天页（若聊天页本来就在前台则立即出现；否则下次进入时消费排队指令）；
4. 出现 4 张 mock 任务卡（queued / running / done / failed），每张都有卡框与状态 chip，点任意一张进详情页；日志 `[MOCK] 已注入 4 条 mock 任务卡（82：走 XlTaskCard 真卡片渲染，可点进详情）`；
5. 截图命名 `05-mock-task-cards.png` / `06-mock-task-detail.png`；清除用「UI 演示 → 清除任务卡演示」。

1006 结论：`XiaozhiWebSocketManager.connect()` 的 headers 只有一处构造路径（`device-id`/`client-id` 均来自 `final` 字段），首连与重连完全同值 → **不是重连头不一致**；1006 来自 ColorOS 冻结叠加上服务端 62s 空闲回收。81 的"后台最多 3 次"之所以无效，是因为每次握手成功都会清零计数；82 改为后台一次都不重连，从源头消除该循环。

79 轮修复（历史，其中息屏 tick 方案已被 81 废止）：

1. ~~息屏 tick 保活~~（**81 已废止**：ColorOS 冻结 Dart isolate，该方案不可行）；保留部分：`_onDisconnected` 只结算统计、回前台僵死判定改为"下行 + 上行双静默 >70s"才重建。
2. **P1 03 录音浮层**：底色改半透明 `rgba(27,27,27,.72)` + `BackdropFilter` blur 14；根因是 `ListView` 默认 `addRepaintBoundaries:true` 把每个气泡放进独立合成层、模糊采不到，已关闭。
3. **P2 版本号**：`AppConfig.appVersion` 改为 `String.fromEnvironment('APP_VERSION')`，CI 从 `pubspec.yaml` 注入，设置页"关于"与 APK `versionName` 单一来源。

78 轮（历史）：

1. **77 前台服务**：连接信号接进 `XiaozhiWebSocketManager`（`_completeHandshake` / 握手超时 / `_onDisconnected` / `forceReconnect` / `disconnect`）；**82 起服务/通知的存活只看前后台（退到后台且开关开启即启动，断线不撤通知）**；服务内自持 `PARTIAL_WAKE_LOCK`；Android 13+ 回前台补一次通知权限请求。
2. **78 UI**：录音浮层改到聊天页 `Stack` 同层（`BackdropFilter` 能采到背后内容）、波形 11 根 3pt/3pt、深色导航 `#1A1A1A` 与时间分隔、会话列表品牌头像 + 未读红点、取消态胶囊 `r4` + `#FF8A8A` 圆标。

README 不含截图资产；82 的真机截图在设备验收通过后补入。


## 架构分层

```
┌────────────────────────────────────────────────────────────┐
│ Flutter (lib/)                                             │
│  ├ presentation/ 聊天页 / 语音通话 / 设置 / 开发者中心      │
│  ├ core/network/ WebSocket 会话（保活、预连接、无感重连）    │
│  └ core/mika/    MethodChannel 桥（channel: xiaole/mika）   │
└───────────────┬────────────────────────────────────────────┘
                │ 同进程，同一 Application（MikaApp）
┌───────────────┴────────────────────────────────────────────┐
│ Kotlin 引擎 (:mika-app / :mika-core，源码由脚本拉取)        │
│  ├ MikaBridge    任务提交 / 取消 / 追问 / Provider 配置     │
│  ├ MicGate       进程内麦克风租约（小乐通话 ↔ 引擎录音互斥）│
│  └ 沙箱          rootfs + 无障碍/读屏能力，执行手机操作      │
└────────────────────────────────────────────────────────────┘
```

引擎源码不随本仓库提交，由 `scripts/fetch-mika.sh` 拉取固定提交 `6661b9e9` 再打 `patches/mika-embed.patch`（该 patch 让 Mika 以 library 形式嵌入宿主）。

## 构建

**云端 CI（推荐）**：`.github/workflows/build-merged-apk.yml`，在 `master` 分支手动触发（Actions → Run workflow）。

一次产出两个包（versionCode 相同，仅文件名区分）：

| 产物 | ABI | 用途 |
|---|---|---|
| `xiaole-<ver>-mika1-universal.apk` | arm64-v8a + armeabi-v7a | 兼容老机型 |
| `xiaole-<ver>-mika1-arm64.apk` | arm64-v8a | 主分发（体积小） |

CI 会顺带：剔除 opus 的 Windows/Web 资产、重新对齐并签名、校验权限裁剪、校验签名指纹与发布基线一致。

**本地构建（可选）**：

```bash
bash scripts/fetch-mika.sh
flutter pub get
flutter build apk --release                    # universal
flutter build apk --release --target-platform android-arm64   # arm64
```

## 安装

- 直接安装 `arm64` 包即可（RMX3161 等 arm64 机型）。
- **ColorOS/Funtouch 会拦 adb 安装**：`adb install` 返回 `Failure [-99]`，随后弹安装引导三连窗。
  正确做法是**人工过三连弹**（勾选复选框 → 授权本次安装 → 仍然继续）。
  **不要用 `adb uninstall` 绕过**——卸载会清空 `/data/data/com.zcstudy.xiaole`，开发者授权、已选智能体、本地设置全部丢失。
- **同包名必须同签名**：本 App 与纯小乐客户端包名相同，签名必须逐位一致（`C=CN, O=ZCStudy, CN=XiaoLe Release`，
  `certificate SHA-256 = 9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169`）。
  指纹不同时系统只能"卸载重装"，等价于清数据。比对方法见 `docs/embed-mika.md`。

## 已知限制

1. **云端对文字消息有加权长度预算**：汉字/中英混排约 12 字/段，纯 ASCII 33 字，emoji 10 个。客户端按"码点 + UTF-8 字节"双口径累加切段（先到者为准），超长自动分段发送并在界面提示。
2. **云端 60–70s 空闲回收**：靠 45s 一次的 `listen{state:"stop"}` 保活续命（81 起**仅前台生效**，后台/息屏不再发）；语音/文字发送前会把保活置位前置，避免把 `listen stop` 插进本轮识别。
3. **内部标识与外部品牌分离**：界面一律叫"小乐"，但包名、模块名、类名、MCP 工具名（`mika_submit_goal` 等）、日志 TAG 保留 `mika` 字样。这是设计决定，不是遗留命名。

## 目录

```
android/    宿主 Gradle 工程（settings.gradle.kts 跨仓库 include :mika-core/:mika-app）
lib/        Flutter 源码
patches/    Mika 嵌入补丁（mika-embed.patch）
scripts/    fetch-mika.sh（固定提交拉取 + 打补丁）
docs/       嵌入说明、保活/分段证据、签名基线与 CI 产物说明
test/       Flutter 单测
```

## 下载

安装包不在仓库内，发布在 **Release** 页面。

## 许可证

上游客户端与 Mika 引擎的开源许可证见 `LICENSE` 与 App 内「开源许可」页；两部分的版权归属保留不变。
