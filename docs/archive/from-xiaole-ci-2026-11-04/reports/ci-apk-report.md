# 云端打包与真机验证报告（阶段一）

**结论：GitHub Actions 云端打包成功（release + 稳定签名），产物已装到 realme RMX3161 并正常启动、无崩溃；签名证书 SHA-256 固定为 `9D:2D:A8:80:5E:78:48:01:E1:3C:54:A6:35:E8:BF:52:8D:B3:03:A2:35:AD:B5:63:37:45:CA:DC:EB:12:A1:69`。**

---

## 1. 仓库可见性与 workflow

- 仓库：`openclawzhangchong/xiaole-client-flutter-2027`
- 可见性：原为 **private**，按授权已执行 `gh repo edit --visibility public`，现为 **public**（源码已公开）。
- 新增 workflow：[`.github/workflows/build-apk.yml`](https://github.com/openclawzhangchong/xiaole-client-flutter-2027/blob/master/.github/workflows/build-apk.yml)
  - 触发：`workflow_dispatch` + push `master` 且路径命中 `lib/**`、`android/**`、`assets/**`、`pubspec.yaml|lock`、workflow 自身。
  - 无 Secrets：签名密码写在 job `env`（`XIAOLE_KEYSTORE_PASSWORD` / `XIAOLE_KEY_PASSWORD` = `REDACTED-KEYSTORE-PASSWORD`），keystore 随仓库提交，公开仓库即可跑。
  - `flutter analyze` 为 `continue-on-error`，结果写 Job Summary，不阻塞出包。
  - 产物：`xiaole-<version>-<sha7>-release.apk` + `SHA256SUMS.txt` + `analyze.log`，artifact 名 `xiaole-apk-<version>-<sha7>`，保留 14 天。
- 既有 `build-apk-v2.yml`（tag 触发、GitHub Release）未改动。
- 代码改动仅两处：workflow 新建、`android/app/build.gradle.kts` 的 `signingConfigs`（release 改用 `android/app/xiaole-release.p12`）；未触碰 `test-token` 任何逻辑，未新增 `mika.*`。

签名材料生成方式：本机无 JDK/keytool，使用 Git 自带 `openssl` 生成 PKCS12（RSA2048，10 年，CN=XiaoLe Release），keystore 已提交至仓库，密码与 workflow 一致。

## 2. Job 运行记录

| run id | 事件 | 结果 | 耗时 |
|---|---|---|---|
| 41788793007 | push（debug 首版） | **cancelled**（为切 release 主动取消，非失败） | ~1 min |
| 41789229257 | push（`c315bc4`，release+签名） | **success** | 10 分 03 秒（07:00:09Z → 07:10:12Z） |
| 41791206221 | workflow_dispatch | 进行中（07:17:14Z，**非本会话触发**） | — |

- 失败次数：**0**（首版为主动取消；release 一次通过）。
- 首版之所以取消：先验证 workflow 骨架成功触发后，按新授权改 release，避免重复烧额度。

## 3. APK 元数据与签名

| 项 | 值 |
|---|---|
| 本地路径 | `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\xiaole-apk-6.11.5+57-c315bc4\xiaole-6.11.5+57-c315bc4-release.apk` |
| 大小 | 40,806,374 B（约 38.9 MB） |
| SHA-256 | `3f59ea41b9ca13dbc11e249a040449f3f745862c5a0605cb1f9a4421e97ece23` |
| 包名 | `com.zcstudy.xiaole` |
| 版本 | versionName `6.11.5` / versionCode `57` |
| minSdk / targetSdk | 24 / 35 |
| ABI | arm64-v8a（设备） |
| 签名方案 | v1 **false**、v2 **true**、v3 **false**（`apksigner verify` 通过） |
| 证书 SHA-256 | `9D:2D:A8:80:5E:78:48:01:E1:3C:54:A6:35:E8:BF:52:8D:B3:03:A2:35:AD:B5:63:37:45:CA:DC:EB:12:A1:69` |

说明：`aapt2 dump badging` 在 CI 内执行，但输出写入了 Job Summary 未落日志；上表 package/version/minSdk/targetSdk 以设备 `dumpsys package` 复核为准，两者一致。

## 4. 真机安装与启动验证

- 设备：realme RMX3161，序列号 `36c77fb6`，Android 12（API 31），arm64-v8a。
- 安装前检查：`pm list packages` 仅有 `com.zcstudy.micbridge.a16`，**不存在同包名 `com.zcstudy.xiaole`** → 无旧版、无签名冲突，**未执行任何卸载**（无数据丢失）。
- 安装：`adb install -r` → realme 安全安装器两次确认（"已知悉该应用存在风险"+"仍然继续"）后 `Success`；`firstInstallTime=2026-11-04 15:19:29`。
- 启动：`monkey -p com.zcstudy.xiaole` → `mResumedActivity = com.zcstudy.xiaole/.MainActivity`。
- 稳定性：清空 logcat 后 force-stop 重启，**crash buffer 无 FATAL**；截图显示首页正常（"小乐"、对话/我 两 Tab、"添加智能体"），仅有首次通知权限弹窗（非异常）。

## 5. 未确认项 / 需用户决定

1. **覆盖安装未复测**：本次仅首次安装。后续同签名 APK 覆盖安装应成功，但未实跑一次验证（下一次构建可顺带做）。
2. **v3 签名未启用**：当前仅 v2；如需 v3，要在 Gradle 显式开启（不影响 Android 12 安装）。
3. **Kestore 公开**：keystore 与密码均在公开仓库中，任何人都能用该证书签名同样包名的 APK；这是用户接受的现状，但意味着后续分发不可视为可信来源。
4. **额外的 dispatch run 41791206221** 正在跑（非本会话触发），会消耗额度，是否取消需用户确认。
5. **aapt2 badging 原文未落日志**，如需留档可在 workflow 加 `tee` 到 stdout（会再触发一次构建）。
6. 本机仍无 Flutter/JDK/Android SDK，本地 `apksigner` 不可用；本地仅核对了文件哈希与设备侧安装签名（`version:2`）。
7. 阶段二（加 `mika.*` 工具）尚未开始，等这条链路确认后再做。
