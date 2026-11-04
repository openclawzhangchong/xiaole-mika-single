# 6.11.7+59 构建基线（供「合并版单 APK」任务读取）

> 本文件为只读基线说明，不修改 `docs/` 下其它任务的目录与文件。
> 只描述 **6.11.7+59**（无感重连版）。心跳实验在 **6.11.8+60**，不要把它当作合并基线。

## 1. 源码基线

| 项 | 值 |
|---|---|
| 仓库 | `openclawzhangchong/xiaole-client-flutter-2027`（public） |
| 分支 | `master` |
| 代码 commit | `0a713ef`（`fix(v6.11.7): 断线改为无感重连…`） |
| 文档 commit | `569daaa`（README / CHANGELOG / 进度与续接 回填，不影响产物） |
| tag | **无**（该版未打 tag；若要打，建议 `v6.11.7`） |
| `version`（pubspec） | `6.11.7+59` |
| `AppConfig.appVersion` | `6.11.7`（OTA 请求头使用） |

改动范围（相对 6.11.6+58 `93a1eda`）：仅 `lib/presentation/pages/chat/chat_page.dart`
（断线 UI 无感化：1005/1006 → `重连中…`，4s 内不亮状态条）+ 版本号 + CHANGELOG/README。
`lib/core/network/xiaozhi_websocket_manager.dart` 未改（保留 `pingInterval=25s`、看门狗、`_scheduleReconnect`）。

## 2. CI 产物

| 项 | 值 |
|---|---|
| workflow | `Build Release APK`（`.github/workflows/build-apk.yml`，push master 触发） |
| run | **41807490945** ✅ success（9m17s） |
| artifact 名 | `xiaole-apk-6.11.7+59-0a713ef` |
| APK 文件名 | `xiaole-6.11.7+59-0a713ef-release.apk` |
| 大小 | **40,806,378 B** |
| SHA-256 | `2f695d3b711230bc3004b8cd066805a875170ccbfd9dcc9a5711957d759f5990` |
| 本机落地路径 | `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6117\xiaole-apk-6.11.7+59-0a713ef\`（含 APK / `SHA256SUMS.txt` / `analyze.log`） |
| GitHub 下载 | `gh run download 41807490945 --repo openclawzhangchong/xiaole-client-flutter-2027 -D <dir>` |

## 3. 签名（合并版必须沿用，否则无法覆盖安装）

```
Verifies
Number of signers: 1
V2 Signer: certificate DN: C=CN, O=ZCStudy, CN=XiaoLe Release
V2 Signer: certificate SHA-256 digest: 9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169
V2 Signer: certificate SHA-1 digest:   6a81d05a40349ca21cc1ae10ab640b66c5a5e372
V2 Signer: key algorithm: RSA / 2048 bits
```

keystore：`android/app/xiaole-release.p12`（别名 `xiaole`），密码取自 `XIAOLE_KEYSTORE_PASSWORD`。
同一套证书从 6.11.5 起未变，因此 6.11.5/6.11.6/6.11.7 可互相覆盖安装。

## 4. 包与兼容性

| 项 | 值 |
|---|---|
| applicationId | `com.zcstudy.xiaole` |
| versionCode / versionName | `59` / `6.11.7` |
| minSdk / targetSdk | `30` / `35` |
| ABI | 通用 APK（含 arm64-v8a，M5Stack CoreS3 / realme RMX3161 可装） |

## 5. 装机注意（踩过的坑）

- 真机当前被外部会话用 `adb install -d` 降级覆盖成 **6.11.5/57**；合并版装机时**禁止 `-d`**（`versionCode=59` 正常覆盖即可），并确认 `installerPackageName=pc`。
- 多设备（现在同时挂着 realme `36c77fb6` 与 `XXB/b906`）时所有 `adb` 命令必须带 **`-s 36c77fb6`**。
- 装完自检：`adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | findstr /i "versionCode versionName lastUpdateTime installerPackageName"`。
