# 小乐单包（`xiaole-mika-single`）

一个 APK、一个包名（`com.zcstudy.xiaole`）、一个安装包。Flutter 负责界面（实时语音对话 + 任务执行），内嵌的 Kotlin 引擎以 **library 模块** 的形式编进同一个进程（内部模块名仍是 `mika-core` / `mika-app`，见文末「内部标识与外部品牌分离」）。

- 基线：小乐 `master` 6.11.14 + 68（commit `61f60ec`；含 listen stop 45s 保活、预连接音频回灌、断线无感重连、「保活置位前置到 listen start 与文字发送之前」，以及「分段上限按内容类别取值」与「会话标记独立 60s 过期 + 解除即补发保活」）
- 单包版本：`6.11.15-mika1+70`（versionCode 70；一次产出两个包：universal `arm64+armv7` 与主分发 `arm64`，两者 versionCode 相同，仅文件名区分；64–69 均为已出过的历史号）
- 引擎源码：`wangzan101/Mika` 固定提交 `6661b9e9`（0.1.35）+ `patches/mika-embed.patch`

## 目录结构

```
xiaole-mika-single/
├── android/                     小乐的 Gradle 工程（宿主 :app）
│   ├── gradlew / gradlew.bat    已入库的 wrapper（Gradle 8.12），clone 即可构建
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
├── patches/mika-embed.patch                   引擎侧 diff（嵌入 3 文件 + 麦克风互斥 2 文件 + 单测 1 文件 + 品牌文案）
├── scripts/fetch-mika.sh                      拉取固定引擎源码 + 打补丁
├── mika/                                      构建时生成，已 gitignore（不复制第三方源码入库）
└── .github/workflows/build-merged-apk.yml     云端出包 + 权限校验 + 麦克风互斥单测
```

## 构建

本机没有 Flutter/JDK/Android SDK，**只走 GitHub Actions**。仓库已固定提交 Gradle wrapper，clone 后不需要本机装 Gradle；CI 里一条命令是：

```bash
gh workflow run build-merged-apk.yml --ref master -R openclawzhangchong/xiaole-mika-single
```

工作流内部依次执行：

```bash
bash scripts/fetch-mika.sh          # 拉固定引擎源码 + 打补丁（生成 mika/，不入库）
flutter pub get
cd android && ./gradlew :mika-core:test --tests "*MicGateTest"   # 麦克风租约单测
flutter build apk --release
```

本地（有 Flutter 3.32.2 / JDK 17 / Android SDK 时）相同：先 `bash scripts/fetch-mika.sh`（Windows 用 Git Bash），再 `flutter pub get && flutter build apk --release`。签名沿用仓库内的 `android/app/xiaole-release.p12`（密码来自 workflow env）。

产物：`build/app/outputs/flutter-apk/app-release.apk`。

## 引擎侧改动（`patches/mika-embed.patch`）

> 用户要求的"必要 3 个文件"指**嵌入本身**的 3 个 Gradle/清单改动（下表前 3 行）；第 4–6 行是合并后才出现的**麦克风互斥**与对应单测；第 7 行是**品牌文案**。全部以 patch 形式维护，不整包复制上游源码。

| # | 文件 | 改动 | 原因 |
|---|---|---|---|
| 1 | `app/build.gradle.kts` | `com.android.application` → `com.android.library`；去掉插件版本（交给宿主）；去掉 `applicationId`/`versionCode`/`versionName`/ABI splits/perf 构建类型；`project(":core")` → `project(":mika-core")` | application 模块不能被另一个 application 依赖 |
| 2 | `core/build.gradle.kts` | 插件改 `id(...)`；`libs.` → `mikaLibs.` | 宿主已有 `libs` 版本目录，避免同名冲突 |
| 3 | `app/src/main/AndroidManifest.xml` | `<application>` 去掉全部应用级属性；`MainActivity` 去掉 LAUNCHER、`exported=false` | 清单合并只能有一个 Application 来源；library 不得自带入口 |
| 4 | `core/.../voice/MicGate.kt`（新增） | 进程内麦克风租约（`tryAcquire/release/holder`，可重入、只能本人释放）；68 起增加日志出口（`logger` 由 `MikaApp` 注入 `Log.i`） | 小乐通话与引擎录音同进程，系统不再互斥；运行层要能直读谁持有/谁被拒 |
| 5 | `voice/PcmRecorder.kt` | `start()` 先拿租约、失败不开流；`release()` 归还 | 拿不到就不录，避免两路 MIC 互相静音 |
| 6 | `core/src/test/.../MicGateTest.kt`（新增） | JVM 单测（互斥/可重入/只能本人释放） | CI 里可复现的验证证据 |
| 7 | 资源 `values`/`values-zh`/`values-b+zh+Hant` + 8 个 Kotlin 文件 | 用户可见的 "Mika" → "小乐"（文案层，见下节） | 品牌统一；不动类名/包名/协议标识 |

## 品牌：内部标识与外部品牌分离

**外部品牌一律叫"小乐"**（launcher label、界面文案、通知标题、关于页、权限说明）。**内部标识保持不动**，否则会破坏已有集成：

- `applicationId` / 包名 / namespace：`com.zcstudy.xiaole`、`com.wangzan101.mika.*`
- 模块/目录/类/变量：`mika-core`、`mika-app`、`MikaApp`、`MikaBridge`、`MicGate`、`mika/`
- MCP 工具名与网关命名空间：`mika_submit_goal` / `mika_get_task` / `mika_cancel_task`
- 上游仓库 URL、Release 资源名、CLI 名（`Mika CLI`）、User-Agent、日志 TAG
- 开源许可证页的版权/作品名（法律归属，必须保留）

以后改名只动文案层（资源 XML 的 string 值 + Flutter 可见字符串），不要再碰标识符。

## 铁律：同包名必须同签名

**只要 `applicationId` 是 `com.zcstudy.xiaole`，无论出自哪个仓库（纯小乐、单包、任一分支），签名证书必须逐位相同。**

- 唯一合法基线（`C=CN, O=ZCStudy, CN=XiaoLe Release`）：
  `9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169`
  （来源：`docs/ci-artifact-6.11.7.md`、`docs/ci-artifact-6.11.9.md`，两份是同一把）
- 违反后果**不是**"装不上"这么轻：同包名不同签名时，系统只允许**卸载再装**，卸载即删除 `/data/data/com.zcstudy.xiaole`，用户会一次性丢掉：开发者授权状态、已选智能体/角色、本地会话与设置、权限授予记录。远程云端智能体不受影响，但本地入口全空。
- 在 ColorOS 上的表现：`adb install` 返回 `Failure [-99]`，安装引导弹三连窗；**此时正确做法是人工过三连弹（勾选复选框 → 允许本次安装 → 仍然继续），绝不能先 `adb uninstall` 再装**——卸载才是清数据的直接原因。
- 验证方法（两个包逐位比对，必须完全相同）：

```bash
apksigner verify --print-certs 包A.apk | grep "certificate SHA-256"
apksigner verify --print-certs 包B.apk | grep "certificate SHA-256"
```

- 防回归：`.github/workflows/build-merged-apk.yml` 的 `Verify both APKs` 步骤已把上述指纹写死为 `XIAOLE_CERT_SHA256`，任一包不匹配直接失败；签名材料只描述方法（仓库内 `android/app/xiaole-release.p12` + alias `xiaole`），**不把 p12 本体与口令写进文档**。

### 改名盘点（用户可见层）

| 位置 | 改前 | 改后 |
|---|---|---|
| 引擎 `strings.xml` `app_name` | `Mika` | `小乐` |
| 引擎无障碍服务说明 | `...lets Mika read...` | `...lets 小乐 read...` |
| 通知标题（任务进度/结果/空闲） | `Mika` / `Mika: %1$s` | `小乐` / `小乐: %1$s` |
| 通知渠道名 | `Mika ...` | `任务进度` / `任务结果` / `需要你处理`（原本无品牌） |
| 对话页标题 / 侧栏 / 关于页 | `Mika` / `关于 Mika` | `小乐` / `关于小乐` |
| 悬浮胶囊空闲标题 | `Mika` | `小乐` |
| 关于页更新通知 | `Mika <版本>` | `小乐 <版本>` |
| 诊断信息抬头 | `Mika 诊断信息 / Mika diagnostics` | `小乐 诊断信息 / Xiaole diagnostics` |
| MCP 登录回调页 | `Mika: 登录成功/失败` | `小乐: 登录成功/失败` |
| 合并版执行页 | ` Mika 执行` / `Mika <版本> · 进程内直调` | `小乐 · 执行` / `小乐 · 你的手机助手 · 引擎 <版本>` |

统计：资源文案替换 619 处（默认/简体/繁体三套）、Kotlin 可见字符串 20 处、Flutter 可见文案 2 处（另 1 处录音日志）；另做了 341 处中文"小乐 "→"小乐"的空格规整。

**故意没改**：日语/韩语/阿拉伯语等 9 套语言资源里的品牌词（本次面向中文用户，避免误译）；以及上节列出的所有内部标识。

### 踩坑记录：批量改名的两个坑（接手必看）

1. **大小写**：PowerShell 的 `-replace` **默认不区分大小写**。第一版脚本把 `name="card_back_to_mika"` 也换成了 `name="card_back_to_小乐"`，`R.string` 全部未解析，`:mika-app:compileReleaseKotlin` 直接失败（run `41821665408`）。正确做法：用区分大小写的替换，或 Python `str.replace`。
2. **只改文本节点**：XML 里 `<string name="...">值</string>` 的 name 是标识符，值才是文案。批量脚本必须只处理 `>` 与 `<` 之间的文本，并跳过含 `http`/仓库 URL 的行（否则会把 `github.com/wangzan101/Mika` 的链接改坏）。

改完自检：`grep -P 'name="[^"]*小乐'` 必须为空；再用 `git apply --check` 在固定提交的干净工作树上验证补丁。

## 麦克风互斥（实现）

同一进程、同一 UID 下，Android 的 AudioFocus 只看到一个 client，不会替两路 `AudioRecord` 互斥。所以用应用层锁：

1. `MicGate`（`core` 纯 JVM）持有唯一 owner：`xiaole` / `mika`（owner 值是内部标识，不对外展示）。
2. 小乐：`AudioUtil.startRecording()` 在 `startStream` 之前 `acquireMic()`，拿不到就跳过本次录音并打日志；`stopRecording()`/流错误/流结束/启动失败四条路径都 `releaseMic()`。
3. 引擎：`PcmRecorder.start()` 拿不到租约直接返回 false（按住说话会有"录音失败"的反馈，而不是录进一段静音）；正常停止、录满自动停、cancel 都归还。
4. 同一 owner 重复获取是幂等的（避免重复 start 把自己锁死）。

验证：
- 逻辑层：CI 执行 `:mika-core:test --tests MicGateTest`，覆盖互斥/可重入/越权释放。
- 运行层：见下节「麦克风互斥运行层验证清单」。

### 麦克风互斥运行层验证清单（装机窗口执行）

> **68 起可直读日志**：`MicGate` 是纯 JVM 模块，不能直接引 `android.util.Log`；`MikaApp.onCreate`
> 注入日志出口，三行普通调用（不在 `assert` 里，release + R8 不会 strip），单测不注入即静默：
>
> ```text
> MicGate: acquire holder=xiaole 成功 持有者=无
> MicGate: acquire holder=mika 被拒 当前持有者=xiaole 原因=已被其它租约持有
> MicGate: release holder=xiaole 归还 剩余=无
> ```
>
> `release` 不打引用计数：`MicGate` 语义是"同一 owner 可重入、只有本人能还"，没有嵌套计数可吐；
> `剩余` 打的是归还后的实际持有者（`无` 或仍占着的 owner）。

**前置**

```bash
adb -s 36c77fb6 install -r dist/xiaole-6.11.12-mika1-arm64.apk   # 主分发 arm64；禁止 -d
adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | grep -E 'versionCode|versionName'
adb -s 36c77fb6 logcat -c
adb -s 36c77fb6 logcat -v time | grep -E 'MicGate|AudioUtil' > micgate.log &
```

**用例（每项记录时间点 + 对应日志行）**

| # | 操作 | 期望 | 证据 |
|---|---|---|---|
| 1 | 小乐实时通话中（麦克风活跃），切到「小乐 · 执行」→ 引擎对话页按住说话 | 引擎不录音，提示「麦克风用不了，可能正被别的 App 占着」 | `MicGate: acquire holder=mika 被拒 当前持有者=xiaole`；UI 截图 |
| 2 | 小乐这轮录音结束（松手/通话结束）后，引擎再按住说话 | 正常录音并转出文字 | `MicGate: acquire holder=mika 成功 持有者=无` |
| 3 | 反方向：引擎按住说话不放，小乐点麦克风开始录音 | 小乐跳过本次录音，不崩、不静音对方 | `MicGate: acquire holder=xiaole 被拒 当前持有者=mika` + `AudioUtil: 麦克风被引擎占用，跳过本次录音` |
| 4 | 引擎松手后 5s 内，小乐再录一次 | 能正常进 `流式录音启动成功` | `MicGate: release holder=mika 归还 剩余=无` 后紧跟 `acquire holder=xiaole 成功` |
| 5 | 快速交替 10 次（间隔 <1s，两侧轮流按住） | 每次只有一方在录；无崩溃、无 ANR | 10 组 acquire 里"成功/被拒"成对，`logcat -b crash` 为空 |
| 6 | 异常归还：录音中切后台 / 通话被结束 / 引擎任务取消，然后另一侧立刻开麦 | 另一侧能拿到麦，不出现永久占用 | `release ... 剩余=无` 后另一侧 `acquire ... 成功` |
| 7 | **TTS 外放期间抢麦**：见下方构造方法 | Mika 必须被拒，不允许在 AI 外放时开录（回声/串音最重） | `MicGate: acquire holder=mika 被拒 当前持有者=xiaole` |
| 8 | 全程 `dumpsys media.audio_flinger` 抽查 3 次 | 输入线程 `ACTIVE` 轨道恒 ≤1 | 每次抓 `ACTIVE` 段前后 10 行（辅助证据，不单独作为验收依据） |

**用例 7 的构造方法（TTS 期间抢麦）**

1. 进**实时通话**（连续对话，麦克风在通话期间一直持有，不是按住说话那种一松手就归还）。
2. 说一句会引出较长回答的话，例如「给我讲一段 30 秒左右的睡前故事」。
3. 听到第一句回复（TTS 已开始外放）后 **1–2 秒内**，在「小乐 · 执行」页触发 Mika 的语音输入（按住说话，或提一个需要录音的任务）。
4. 期望：Mika 侧立即被拒（UI 提示 + `MicGate: acquire holder=mika 被拒 当前持有者=xiaole`），TTS 不中断、不重连。
5. 反向补充：**按住说话**模式下发送后小乐会归还麦克风，TTS 期间 `当前持有者=无`，此时 Mika 能拿到麦。
   这是已知缺口（要"外放期间一律禁麦"得把小乐租约持有延长到 `tts state=stop`），本轮未改，先记录。

**logcat 关键字速查**

```bash
adb -s 36c77fb6 logcat -v time -s MicGate:I          # 只留互斥租约三行
adb -s 36c77fb6 logcat -v time | grep -E 'AudioUtil: (流式录音启动成功|停止录音|麦克风被引擎占用|启动录音失败)'
adb -s 36c77fb6 logcat -b crash -v time              # 必须为空
adb -s 36c77fb6 shell dumpsys media.audio_flinger | grep -n -A12 -i 'Input'
```

判读原则：以 `MicGate` 三行日志为准（谁持有、谁被拒、谁归还）；`dumpsys` 只作旁证。只凭"听起来正常"不算通过。



## 权限裁剪（合并清单前后）

引擎的清单会被并入小乐，下面三条只服务独立 App 的场景，用 `tools:node="remove"` 从合并清单剔除：

| 权限 | 原来给谁用 | 合并后 |
|---|---|---|
| `REQUEST_INSTALL_PACKAGES` | 引擎自更新（下载 APK 覆盖安装） | 删除（合并版不提供自更新） |
| `WRITE_SECURE_SETTINGS` | adb 授权后自动打开无障碍服务 | 删除（改为用户手动开启无障碍） |
| `READ_MEDIA_VISUAL_USER_SELECTED` | 相册面板（Android 14 部分授权） | 删除（面板不暴露；小乐自己的 `READ_MEDIA_IMAGES` 保留） |

保留并说明：
- `RECORD_AUDIO` / `FOREGROUND_SERVICE(+SPECIAL_USE/DATA_SYNC)` / `POST_NOTIFICATIONS` / `WAKE_LOCK`：实时语音 + 任务前台服务。
- `SCHEDULE_EXACT_ALARM` / `SET_ALARM`：定时/闹钟能力（任务可能用到），属特殊访问权限，用户可在系统设置关闭。
- `RECEIVE_BOOT_COMPLETED`：小乐本来就有（AI 主动来电的 WorkManager 跨重启）。
- 无障碍服务与悬浮窗：引擎的 UI 自动化能力需要，保留；建议默认关闭悬浮球（会挡 Flutter 全屏点击）。
- `INTERACT_ACROSS_USERS_FULL` 仅作为组件的 `android:permission` 守卫出现，不是 `uses-permission` 申请。

CI 会 `aapt2 dump permissions` 并在发现上述三条仍在时直接失败。

## 体积构成（6.11.12-mika1+67 实测 74,142,884 B；68 起双包）

按 APK 内条目压缩后字节归组（占 74.0 MB 有效载荷）：

| 组 | 字节 | 占比 | 明细 |
|---|---:|---:|---|
| 引擎运行环境 | 31,466,196 | 42.5% | `assets/runtime/rootfs.tar.xz`（已是 xz，无法再靠 zip 压缩） |
| DEX / Kotlin | ~9,150,000 | 12.4% | `classes.dex` 9,021,764（未压缩存储）+ kotlin 元数据 |
| Flutter 引擎 | 9,644,197 | 13.0% | `libflutter.so`：arm64 5,184,998 + armv7 4,459,199 |
| Flutter 业务 AOT | 6,771,745 | 9.1% | `libapp.so`：arm64 3,218,893 + armv7 3,552,852 |
| MLKit OCR | 9,849,115 | 13.3% | `libmlkit_google_ocr_pipeline.so` 双 ABI 7,918,785 + `assets/mlkit-google-ocr-models` 1,930,330 |
| Flutter 资源 | ~3,220,000 | 4.3% | `flutter_assets` 2,722,499（其中 `opus_flutter_windows`/`opus_flutter_web` 的 dll/wasm 约 2.6 MB 是桌面/Web 平台的库，Android 用不到） |
| Android 资源 | 3,605,316 | 4.9% | `resources.arsc` 2,634,508 + `res/` 970,808（单文件 `res/iw.png` 740,892） |
| 其他原生库 | ~90,000 | 0.1% | `libproot.so` 76,068 + `libmikarun.so` 7,010 + `libproot_loader.so` 987 |

按 ABI 汇总：`arm64-v8a` 13,136,711 + `armeabi-v7a` 11,730,680，**双 ABI 并打包占 15.8%**。

可瘦点（按收益排序）：

1. **只出 arm64**（真机 RMX3161 是 arm64）：**68 已实施**，CI 额外产出 `xiaole-6.11.12-mika1-arm64.apk`
   作为主分发包（`xiaole.abi=arm64-v8a` + `--target-platform android-arm64`），预期 ~62 MB；
   universal 包保留给 32 位机器，两者 versionCode 同为 68。
2. **删掉 `opus_flutter_windows` / `opus_flutter_web` 资源**：**68 已实施**，两个包构建后统一
   `zip -d` 掉这四个 dll/wasm（约 2.6 MB）→ `zipalign` → 用同一把正式签名 `apksigner sign`，CI 断言条目不存在。
3. **`res/iw.png` 740 KB**：已用 `aapt2 dump resources` 反查到它是 `drawable/mika_launcher_art`
   （`nodpi`，被引擎的桌面图标/关于页引用），**确认在用，保留**，不删。
4. **rootfs 31 MB**：可尝试裁剪无用的 busybox 软链/文档、或在 CI 里重打 xz 最高压缩；风险最高（运行环境随时可能缺工具），建议二次开发稳定后再动。
5. **DEX 9 MB**：可评估 R8 full mode + `shrinkResources`，收益需实测（Compose/MLKit/OkHttp 反射较多，别一次开太狠）。
6. MLKit OCR 9.8 MB 属功能刚需（屏幕文字识别），暂不动；若后续换端侧小模型可回收 4–5 MB。

## 尚未解决

- rootfs 31 MB（`assets/runtime/rootfs.tar.xz`）未优化；体积拆解与可瘦点见上节「体积构成」。
- 无障碍设备操作（点击/滑动/截屏）在合并包内未实测（真机上该服务原本是关闭状态）。
- 麦克风互斥的**运行层**验证要等装机窗口（清单见「麦克风互斥运行层验证清单」）；两台设备当前都不许装。
- **TTS 外放期间禁麦只在实时通话（持续持有麦克风）时成立**；按住说话模式松手即归还，TTS 期间引擎仍能开麦，
  属已知缺口（需把小乐租约延长到 `tts state=stop`，本轮未改）。
- `mika/` 每次 CI 重新拉取（未做 Gradle 构建缓存优化）。CI 一次约 40 分钟（双包会更久），不为小改频繁出包。
- 日语/韩语等 9 套语言资源未改名。
- 6.11.13 / 6.11.14 尚未合入；最终版排期 `6.11.14-mika1+69`。
