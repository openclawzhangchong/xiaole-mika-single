# 6.11.9+61 构建基线（detect 保活收敛版）

> 只描述 **6.11.9+61**。心跳实验版本是 6.11.8+60；无感重连基线是 6.11.7+59。

## 1. 源码基线

| 项 | 值 |
|---|---|
| 仓库 | `openclawzhangchong/xiaole-client-flutter-2027`（public） |
| 分支 | `master` |
| 代码 commit | `de7ede8`（`feat(v6.11.9): detect 保活收敛…` + `fix(v6.11.9): 修正 PROBE 日志字符串插值语法`） |
| 文档 commit | 见后续 `docs:` commit（README / CHANGELOG / 本文件回填，不影响产物） |
| tag | **无**（建议 `v6.11.9`） |
| `version`（pubspec） | `6.11.9+61` |
| `AppConfig.appVersion` | `6.11.9`（OTA 请求头使用） |

改动范围（相对 6.11.8+60 `0450cb8`）：
- `lib/core/network/xiaozhi_websocket_manager.dart`：`WsProbeMode` 缩为 `off`/`detect`；默认间隔 45s；新增
  `markConversationActive/Idle`、`CONVERSATION_STALE` 兜底；`[PROBE]` 下行日志（type + 脱敏预览 + 二进制首 32 字节 hex + 断开汇总）。
- `lib/presentation/pages/chat/chat_page.dart`：配置映射只剩 off/detect；在发文字/上行麦克风/stt/llm/tts start/下行音频处标记会话中，tts stop/播放结束/挂断处标记结束。
- `lib/presentation/services/app_feats.dart`：默认间隔 45s，标签改为二值。
- `lib/presentation/pages/dev_center_page.dart`：入口改「WS 保活探针」，2 选项并提示 TTS 副作用。

## 2. CI 产物

| 项 | 值 |
|---|---|
| workflow | `Build Release APK`（`.github/workflows/build-apk.yml`，push master 触发） |
| run | **41816712171** ✅ success（headSha `de7ede8`） |
| artifact 名 | `xiaole-apk-6.11.9+61-de7ede8` |
| APK 文件名 | `xiaole-6.11.9+61-de7ede8-release.apk` |
| 大小 | **40,806,486 B** |
| SHA-256 | `783f5963d742e5b2fbda09ef003abc1f0e29c36d018fd3c535f61b1610acf6ac` |
| 本机落地路径 | `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v6119\`（含 APK / `SHA256SUMS.txt` / `analyze.log`） |
| analyze | **0 error**（93 条均为既有 info/warning：常量命名、`print`、依赖声明等） |
| GitHub 下载 | `gh run download 41816712171 --repo openclawzhangchong/xiaole-client-flutter-2027 -D <dir>` |

## 3. 签名

CI 步骤 **`Verify APK metadata & signature`** 通过；沿用既有 keystore：
`android/app/xiaole-release.p12`（别名 `xiaole`），证书
`C=CN, O=ZCStudy, CN=XiaoLe Release`，SHA-256 `9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169`。
因此 6.11.5/57 → 6.11.9/61 可**正常覆盖安装**（versionCode 递增，**禁止 `-d`**）。

## 4. 包与兼容性

| 项 | 值 |
|---|---|
| applicationId | `com.zcstudy.xiaole` |
| versionCode / versionName | `61` / `6.11.9` |
| minSdk / targetSdk | `30` / `35` |
| ABI | 通用 APK（含 arm64-v8a） |

## 5. 装机注意

- 当前设备 `36c77fb6` 为合并版 **6.11.5/57**；装本版用 `adb -s 36c77fb6 install -r`，**不许 `-d`**。
- 装前/装后各记一次 `lastUpdateTime`，确认没有被外部会话覆盖。
- 多设备在线时必须带 `-s 36c77fb6`。
- 本版**默认 `off`**：装完不会自动发 detect；要复测需在「开发者中心 → WS 保活探针」显式切到 detect。
