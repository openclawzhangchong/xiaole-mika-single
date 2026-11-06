# 小乐（XiaoLe）单包版 — 聊天 + 实时语音 + 手机操作

一个 APK、一个包名（`com.zcstudy.xiaole`）：Flutter 负责界面与实时语音对话，内嵌的 Kotlin 引擎 **Mika** 以 library 模块编进同一进程，用于让 AI 在手机上执行操作（点按、输入、读屏、任务编排）。

> 本仓库是单包线（小乐 + Mika 合体）的正式源码基线。上游 Flutter 客户端为
> [eiriksgata/xiaozhi-client-flutter](https://github.com/eiriksgata/xiaozhi-client-flutter)（微信风 UI 定制）。

## 当前版本（默认分支）

| 项 | 值 |
|---|---|
| versionName | `6.11.22-mika1` |
| versionCode | `79` |
| 产物 | `xiaole-6.11.22-mika1-arm64.apk` / `xiaole-6.11.22-mika1-universal.apk`（GitHub Actions artifact，不进仓库） |
| 签名 | `C=CN, O=ZCStudy, CN=XiaoLe Release`，cert SHA-256 `9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169` |

79 轮修复三条（在 78 之上）：

1. **P0 息屏 tick 断流**：`_onDisconnected` 不再 `_stopProbe`（只结算统计），tick 定时器跨重连持续跑且 `tick#` 单调递增；原生 `KeepAliveService` 每 30s 打 `[KEEPALIVE] tick#N 来源=native` 并经 MethodChannel 唤醒 Dart，必要时补发 `listen:stop`；回前台僵死判定改为"下行 + 上行双静默 >70s"才重建（不再每次回前台误杀）。
2. **P1 03 录音浮层**：底色改半透明 `rgba(27,27,27,.72)` + `BackdropFilter` blur 14；根因是 `ListView` 默认 `addRepaintBoundaries:true` 把每个气泡放进独立合成层、模糊采不到，已关闭。
3. **P2 版本号**：`AppConfig.appVersion` 改为 `String.fromEnvironment('APP_VERSION')`，CI 从 `pubspec.yaml` 注入，设置页"关于"与 APK `versionName` 单一来源。

78 轮（历史）：

1. **77 前台服务**：连接信号接进 `XiaozhiWebSocketManager`（`_completeHandshake` / 握手超时 / `_onDisconnected` / `forceReconnect` / `disconnect`）；服务仅在“已连接且退到后台”时启动，服务内自持 `PARTIAL_WAKE_LOCK`；Android 13+ 回前台补一次通知权限请求。
2. **78 UI**：录音浮层改到聊天页 `Stack` 同层（`BackdropFilter` 能采到背后内容）、波形 11 根 3pt/3pt、深色导航 `#1A1A1A` 与时间分隔、会话列表品牌头像 + 未读红点、取消态胶囊 `r4` + `#FF8A8A` 圆标。

README 不含截图资产；79 的真机截图在设备验收通过后补入。


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
2. **云端 60–70s 空闲回收**：靠 45s 一次的 `listen{state:"stop"}` 保活续命；语音/文字发送前会把保活置位前置，避免把 `listen stop` 插进本轮识别。
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
