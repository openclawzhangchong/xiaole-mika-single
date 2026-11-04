# 小乐 + Mika 单包（`xiaole-mika-single`）

一个 APK、一个包名（`com.zcstudy.xiaole`）、一个安装包。Flutter 负责界面（实时语音对话 + 任务执行），Mika 的 Kotlin 引擎以 **library 模块** 的形式编进同一个进程。

- 基线：小乐 `master` 6.11.7 + 59（run `41807490945`，含"断线无感重连"）
- 单包版本：`6.11.7-mika1+60`（versionCode 60 ≥ 纯小乐 59，避免装包时把别人的包顶回去）
- Mika：`wangzan101/Mika` 固定提交 `6661b9e9`（0.1.35）+ `patches/mika-embed.patch`

## 目录结构

```
xiaole-mika-single/
├── android/                     小乐的 Gradle 工程（宿主 :app）
│   ├── settings.gradle.kts      跨模块 include + mikaLibs 版本目录
│   └── app/
│       ├── build.gradle.kts     依赖 :mika-app / :mika-core
│       └── src/main/
│           ├── AndroidManifest.xml             Application=MikaApp，权限裁剪(remove)
│           └── kotlin/com/zcstudy/xiaole/
│               ├── MainActivity.kt            注册 MethodChannel "xiaole/mika"
│               └── MikaBridge.kt              进程内 RemoteTaskHub / ProviderStore / MicGate
├── lib/
│   ├── core/mika/mika_bridge.dart             Dart 侧通道封装(任务 + 麦克风租约)
│   ├── core/utils/audio_util.dart             录音前后申请/归还麦克风租约
│   └── presentation/pages/mika/mika_task_page.dart  执行页(引擎信息/模型/任务/结果)
├── patches/mika-embed.patch                   Mika 的 6 个文件改动
├── scripts/fetch-mika.sh                      拉取固定 Mika + 打补丁
├── mika/                                      构建时生成，已 gitignore（不复制第三方源码入库）
└── .github/workflows/build-merged-apk.yml     云端出包 + 权限校验 + 麦克斯互斥单测
```

## 构建

本机没有 Flutter/JDK/Android SDK，**只走 GitHub Actions**；CI 里一条命令是：

```bash
bash scripts/fetch-mika.sh && flutter pub get && flutter build apk --release
```

本地（有 Flutter 3.32.2 / JDK 17 / Android SDK 时）相同：先 `bash scripts/fetch-mika.sh`（Windows 用 Git Bash），再 `flutter build apk --release`。签名沿用仓库内的 `android/app/xiaole-release.p12`（密码来自 workflow env）。

产物：`build/app/outputs/flutter-apk/app-release.apk`。

## Mika 侧改动（`patches/mika-embed.patch`，6 个文件）

| 文件 | 改动 | 原因 |
|---|---|---|
| `app/build.gradle.kts` | `com.android.application` → `com.android.library`；去掉插件版本（交给宿主）；去掉 `applicationId`/`versionCode`/`versionName`/ABI splits/perf 构建类型；`project(":core")` → `project(":mika-core")` | application 模块不能被另一个 application 依赖 |
| `core/build.gradle.kts` | 插件改 `id(...)`；`libs.` → `mikaLibs.` | 宿主已有 `libs` 版本目录，避免同名冲突 |
| `app/src/main/AndroidManifest.xml` | `<application>` 去掉全部应用级属性；`MainActivity` 去掉 LAUNCHER、`exported=false` | 清单合并只能有一个 Application 来源；library 不得自带入口 |
| `core/.../voice/MicGate.kt`（新增） | 进程内麦克风租约（`tryAcquire/release/holder`，可重入、只能本人释放） | 小乐通话与 Mika 录音同进程，系统不再互斥 |
| `voice/PcmRecorder.kt` | `start()` 先拿租约、失败不开流；`release()` 归还 | 拿不到就不录，避免两路 MIC 互相静音 |
| `core/src/test/.../MicGateTest.kt`（新增） | JVM 单测（互斥/可重入/只能本人释放） | CI 里可复现的验证证据 |

## 麦克风互斥（实现）

同一进程、同一 UID 下，Android 的 AudioFocus 只看到一个 client，不会替两路 `AudioRecord` 互斥。所以用应用层锁：

1. `MicGate`（`core` 纯 JVM）持有唯一 owner：`xiaole` / `mika`。
2. 小乐：`AudioUtil.startRecording()` 在 `startStream` 之前 `acquireMic()`，拿不到就跳过本次录音并打日志；`stopRecording()`/流错误/流结束/启动失败四条路径都 `releaseMic()`。
3. Mika：`PcmRecorder.start()` 拿不到租约直接返回 false（按住说话会有"录音失败"的反馈，而不是录进一段静音）；正常停止、录满自动停、cancel 都归还。
4. 同一 owner 重复获取是幂等的（避免重复 start 把自己锁死）。

验证：
- 逻辑层：CI 执行 `:mika-core:test --tests MicGateTest`，覆盖互斥/可重入/越权释放。
- 运行层（待装机窗口）：小乐通话录音时 `adb logcat | grep MicGate` 应看到 `xiaole` 持有；此窗口 Mika 按住说话应被拒绝。

## 权限裁剪（合并清单前后）

Mika 的清单会被并入小乐，下面三条只服务 Mika 独立 App 的场景，用 `tools:node="remove"` 从合并清单剔除：

| 权限 | 原来给谁用 | 合并后 |
|---|---|---|
| `REQUEST_INSTALL_PACKAGES` | Mika 自更新（下载 APK 覆盖安装） | 删除（合并版不提供自更新） |
| `WRITE_SECURE_SETTINGS` | adb 授权后自动打开无障碍服务 | 删除（改为用户手动开启无障碍） |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Mika 相册面板（Android 14 部分授权） | 删除（面板不暴露；小乐自己的 `READ_MEDIA_IMAGES` 保留） |

保留并说明：
- `RECORD_AUDIO` / `FOREGROUND_SERVICE(+SPECIAL_USE/DATA_SYNC)` / `POST_NOTIFICATIONS` / `WAKE_LOCK`：实时语音 + 任务前台服务。
- `SCHEDULE_EXACT_ALARM` / `SET_ALARM`：Mika 的定时/闹钟能力（任务可能用到），属特殊访问权限，用户可在系统设置关闭。
- `RECEIVE_BOOT_COMPLETED`：小乐本来就有（AI 主动来电的 WorkManager 跨重启）。
- 无障碍服务与悬浮窗：Mika 的 UI 自动化能力需要，保留；合并版建议默认关闭悬浮球（会挡 Flutter 全屏点击）。
- `INTERACT_ACROSS_USERS_FULL` 仅作为 Mika 组件的 `android:permission` 守卫出现，不是 `uses-permission` 申请。

CI 会 `aapt2 dump permissions` 并在发现上述三条仍在时直接失败。

## 尚未解决

- rootfs 30 MB（`assets/runtime/rootfs.tar.xz`）未优化，包体约 74 MB。
- 无障碍设备操作（点击/滑动/截屏）在合并包内未实测（真机上 Mika 无障碍服务原本是关闭状态）。
- 麦克风互斥的**运行层**验证要等装机窗口；设备当前由另一条线做 MCP 端到端。
- `mika/` 每次 CI 重新拉取（未做 Gradle 构建缓存优化）。
