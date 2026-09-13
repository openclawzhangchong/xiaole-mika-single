# PLAN v6.1.0 — MCP 设备工具能力扩展（正式版）

> **本方案经张老师审批通过后，即为 v6.1.0 版本更新的依据。**
> 立项时间：2026-09-13 ｜ 基线版本：v6.0.1（commit `dcf7ff3`，tag `v6.0.1`）

---

## 0. 决策依据（张老师审批意见）

| 决策点 | 结论 |
|---|---|
| **改动范围** | **A + B + C + D 全量**（18 项能力，见 §2） |
| **插件版本策略** | **不升级 Flutter**（保持 3.32.2），**锁兼容的降级版插件** |
| **TTS 语音播报** | **做**。已确认：`flutter_tts` **不下载任何模型**，调用系统自带 TTS 引擎，包体极小 —— 无额外负担 |
| **拍照识图** | **本轮不做**，下一轮单独排查（涉及服务端协议，超出工具模块边界） |
| **版本标记** | **必须打 tag**（便于出问题回滚）；按项目铁律：本地+远端双端标注、README 档案行、确认 CI 触发、发布 GitHub Release |
| **改动边界** | **只动 MCP 设备工具模块**；通信/音频编解码/UI 页面/声纹等其他代码零改动 |

---

## 1. 现状诊断（基于源码逐行核对）

### 1.1 现有 11 个工具的真实成色

| 工具 | 实现方式 | 结论 |
|---|---|---|
| `self.get_device_status` | 真读电量/主题/网络 | ✅ 真实 |
| `self.screen.set_theme` | 真切换深浅色 | ✅ 真实 |
| `self.screen.preview_image` | 真渲染图片气泡 | ✅ 真实 |
| `self.audio_speaker.set_volume` | **软件增益**（`AudioUtil.setTtsVolume` → 改 PCM 幅度） | ⚠️ **半真**：软件增益无法突破系统媒体音量上限 |
| `self.timer.*`（3 个） | **内存 `Timer`** | ⚠️ App 被杀即失效 |
| `self.schedule.*`（3 个） | **内存 `Timer`**（同上） | ⚠️ 同上 |
| `self.camera.take_photo` | 相机真开 → 上传识图 | ⚠️ 卡在识图返回（**本轮不处理**） |

### 1.2 三个已确认 bug 的根因

1. **音量"显示 100% 实际只有一半"**：软件增益（`lib/core/utils/audio_util.dart:207-208`）受**系统媒体音量**上限约束 → 系统音量 50% 时，App 调到 100 也只有 50% 响度。
2. **闹钟"说设好了却没设"**：**设备端根本没有闹钟工具**（全项目搜 `alarm` 零结果）。AI 见到工具列表里只有 `timer.create_countdown`，**拿倒计时凑数** → 提醒出现在**聊天窗口**（`_mcpFireReminder`：系统消息+震动+Toast），**系统时钟里没有**。
3. **日程"设了没用"**：工具存在但用内存 `Timer` → App 退出/重启后全部丢失。

### 1.3 与官方固件的对照（重要发现）

逐字核对官方源码 `78/xiaozhi-esp32/main/main/mcp_server.cc`：

- **官方 12 个工具**：`get_device_status` / `audio_speaker.set_volume` / **`screen.set_brightness`** / `screen.set_theme` /
  `camera.take_photo` / `screen.preview_image` / `get_system_info` / `reboot` / `upgrade_firmware` /
  `screen.get_info` / **`screen.snapshot`** / `assets.set_download_url`
- **官方既没有闹钟、也没有日程、倒计时、toast 工具**（源码检索 timer/schedule/alarm/clock/toast 全部 0 匹配）
  → 我们的 `self.timer.*` / `self.schedule.*` 属**本项目自研扩展**；本地文档中"对齐真机 11 项"的表述**不准确**，本方案予以更正。
- 官方工具分两类：**common**（默认 `tools/list` 返回）与 **user-only**（需 `withUserTools: true`）。

---

## 2. 目标能力清单（改后 25 项工具）

### 🅐 修复与已定项（5 项）

| # | 工具 | 实现方式 | 依赖 |
|---|---|---|---|
| 1 | `self.audio_speaker.set_volume`（**同名换实现**） | 改为控制系统**媒体音量**；`get_device_status` 的 `volume` 也改读真实系统音量 | `flutter_volume_controller: 2.0.1`（**锁版**，最新版要求 Flutter≥3.35） |
| 2 | `self.alarm.set_alarm`（**新增**） | `AlarmClock.ACTION_SET_ALARM` intent → 系统时钟预填，用户点确认 | `android_intent_plus: ^6.1.0` |
| 3 | `self.schedule.create_event`（**升级**） | 改为写**系统日历**（`ACTION_INSERT` + CalendarContract），用户点确认 | 同上 |
| 4 | `self.show_toast`（**新增**） | AI 主动轻提示 | 项目已有 `fluttertoast` |
| 5 | `self.share.text`（**新增**） | 分享文本到笔记/微信等（用户点选） | 项目已有 `share_plus` |

> 保留 `self.timer.*`（内存倒计时 + 到点 `_mcpFireReminder`）作为**轻提醒**通道；`self.schedule.get_events` / `delete_event`
> 保留为**App 内已建事件的查看/删除**（系统日历事件由系统日历 App 管理，不在我们能删除的范围）。

### 🅑 补齐官方标准（5 项）

| # | 工具 | 实现方式 | 依赖 |
|---|---|---|---|
| 6 | `self.screen.set_brightness` | 调屏幕亮度（**仅应用级**，避免 `WRITE_SETTINGS` 特殊权限） | `screen_brightness: ^2.1.11` |
| 7 | `self.screen.get_info` | 返回屏幕宽高/像素密度（AI 用于布局适配） | 无（`MediaQuery`/`PlatformDispatcher`） |
| 8 | `self.get_system_info` | 返回系统/设备信息 | 项目已有 `device_info_plus` |
| 9 | `self.screen.snapshot` | **App 内截屏**（`RepaintBoundary` 捕获当前界面 → 存文件 → 返回路径/URL）<br>**不需要 MediaProjection、无系统权限** | 无（Flutter SDK） |
| 10 | `self.reboot` | 语义映射为 **「重新连接 / 清空会话」**（App 无真重启能力，description 明确说明） | 无 |

> **不对齐**官方 `upgrade_firmware` 与 `assets.set_download_url`（真机固件升级/资源下载，高风险且对 App 无意义）。

### 🅒 Android 系统能力（5 项，语音场景高价值）

| # | 工具 | 实现方式 | 权限 |
|---|---|---|---|
| 11 | `self.phone.dial` | `ACTION_DIAL` + `tel:`（**不直接拨出**，仅打开拨号盘预填） | **免权限** |
| 12 | `self.message.send_sms` | `ACTION_SENDTO` + `smsto:`（预填号码与内容，用户点发送） | **免权限** |
| 13 | `self.map.navigate` | `ACTION_VIEW` + `geo:` / `google.navigation:` | **免权限** |
| 14 | `self.system.open_settings` | `Settings.ACTION_*`（WiFi/蓝牙/声音/应用详情等） | **免权限** |
| 15 | `self.system.open_url` / `open_app` | `url_launcher` 打开网页；intent 包名直开 App | 免权限（`launch()` 无需 `<queries>`） |

### 🅓 锦上添花（3 项）

| # | 工具 | 实现方式 | 依赖 |
|---|---|---|---|
| 16 | TTS 播报（**并入 #2/#3 到点行为**，非独立工具） | `flutter_tts.speak(text, language: 'zh-CN')`；到点播报 | `flutter_tts: ^4.2.5`（**无模型下载，用系统引擎**） |
| 17 | `self.clipboard.get/set` | Flutter SDK 自带 `Clipboard` | 无 |
| 18 | `self.torch.set` | 手电筒开关（部分机型不支持则返回失败） | `torch_light: ^2.0.0` |

---

## 3. 依赖与权限变更

### 3.1 pubspec.yaml 新增（全部锁兼容版本）

```yaml
flutter_volume_controller: 2.0.1   # 锁版：最新版需 Flutter≥3.35，本项目 3.32.2
android_intent_plus: ^6.1.0
screen_brightness: ^2.1.11
flutter_tts: ^4.2.5
torch_light: ^2.0.0
```

> `share_plus`、`fluttertoast`、`device_info_plus`、`url_launcher`（如缺需补）复用现有依赖。

### 3.2 权限与 Manifest

- **全部新增能力均不需要危险权限**（拨号用 `ACTION_DIAL` 而非 `ACTION_CALL`；截图为 App 内截图；TTS 无权限）。
- **`AndroidManifest.xml` 预期零改动**（`android_intent_plus.launch()` 不需要 `<queries>`）。
- ⚠️ 若实测发现某机型必须 `<queries>`，另行单独申报，不擅自扩大改动范围。

---

## 4. 文件改动清单（严格限定 MCP 工具模块）

| 文件 | 改动 |
|---|---|
| `pubspec.yaml` | +5 依赖（锁版） |
| `lib/core/network/xiaozhi_mcp_responder.dart` | 新增/调整工具**定义**（含英文 description 与 JSON Schema） |
| `lib/presentation/pages/chat/chat_page.dart` | `_setupMcpResponder()` 区域内：调整 3 个执行器、新增 12 个执行器 |
| **新增** `lib/core/mcp/device_capability_service.dart` | 把音量/intent/TTS/剪贴板/截图/手电筒等**平台能力**封装成独立服务 |

**明确不动**：通信（WS/OTA/MCP 握手流程）、音频编解码与参数、UI 页面结构与样式、声纹/唤醒等封存能力、`main.dart`。

---

## 5. 关键实现要点

1. **音量**：`setAndroidAudioStream(AndroidAudioStream.music)` 后读写媒体音量；`set_volume` 的 0–100 直接映射系统音量；`get_device_status` 返回真实值。
2. **闹钟/日历**：intent **launch 只代表"已请求"**，无法确认用户是否点确认 → **工具返回值必须诚实**（如 `{'success': true, 'requested': true, 'note': '已在系统时钟预填，请用户确认保存'}`），
   并在工具 description 里写明"系统时钟会弹出，请用户点保存"。**绝不再出现"AI 说设好了但实际没设"的假象**。
3. **TTS 播报**：到点触发顺序 = 系统消息 → 震动 → Toast → **语音播报**（播报失败静默降级，不影响前三条）。
4. **截图**：`RepaintBoundary` 包住聊天页根视图 → `toImage()` → 存 App 私有目录 → 返回路径；失败返回 `success:false`。
5. **所有新执行器**统一 `try/catch`，异常一律返回 `{'success': false, 'message': ...}`（**绝不让工具异常影响通信链路**）。

---

## 6. 验证与交付

1. **静态**：`flutter analyze --no-pub` **0 error**、无新增 warning。
2. **回归**：golden 基线（版本号变更按既有经验连跑两次）。
3. **独立验证员**：逐项核对 18 项能力的实现真实性（**不许只复述代码**）。
4. **真机冒烟清单**（交张老师）：
   - 说"把音量调到 100"→ **听感真的变最大**，`get_device_status` 读数一致
   - 说"7 点叫我起床"→ **系统时钟弹出并预填** → 保存后**时钟 App 里能看到**，**杀掉 App 仍会响**
   - 说"明天 9 点开会"→ **系统日历弹出并预填**
   - 说"提示我一下"→ 出现轻提示 Toast
   - 说"把这段话记到备忘录"→ 拉起分享面板
   - 说"打电话给妈妈"→ 打开拨号盘并预填号码
   - 说"导航到泉州华侨职校"→ 打开地图导航
   - 倒计时到点 → **设备开口念出来**
5. **发布**：版本 **v6.1.0**；commit → push → **tag v6.1.0** → 确认 CI 触发 → **GitHub Release（标注正式版）** → README 档案行。**APK 交付**。
6. **回滚锚点**：`v6.0.1`（`dcf7ff3`）—— 本版出任何问题，`git checkout v6.0.1` 即可回到当前可用状态。

---

## 7. 风险与止损

| 风险 | 应对 |
|---|---|
| 新插件与 Flutter 3.32.2 不兼容 | 已锁降级版；若某包仍报错 → **该能力降级为"返回不支持"**，不阻塞整体发版 |
| `flutter_tts` 在部分机型无中文引擎 | 播报失败静默降级（不影响消息/震动/Toast） |
| `torch_light` 机型不支持 | 返回 `success:false` + 说明 |
| 系统时钟/日历 intent 被某些 ROM 阉割 | `launch()` 失败时返回明确错误信息，并**在聊天里提示"该机型不支持"** |
| 改动意外影响通信 | 所有新代码收在 MCP 模块与新服务文件内；**发版前跑完整回归 + 独立验证** |

---

*方案结束 — 待张老师审批。审批通过后按 §4 清单实施。*
