# PLAN v6.7.0 —— 「我」页与开发者中心分层重构

> 版本：v6.7.0（build 号顺延）
> 状态：**方案待审批**（未获"可以，照这个执行"前不得动代码）
> 适用仓库：`openclawzhangchong/xiaole-client-flutter-2027`（master）
> 本文档自包含：执行者无需任何会话上下文即可实施。

---

## 0. 已拍板决策记录（用户 2026-09-17 确认，不得更改）

| # | 决策项 | 结论 |
|---|--------|------|
| D1 | 改造基准 | **V2 分层重构**（我的页普通用户化，设备身份编辑整体迁入开发者中心） |
| D2 | 设备身份（MAC/ClientID/型号）编辑 | **全部搬进开发者中心**，新增「设备身份」组 |
| D3 | 「AI 主动联系」 | **留在开发者中心**，整组不动 |
| D4 | 「能力开关」大杂烩组 | **按性质拆分**为「AI 能力」「连接与音频」「调试」三组 |
| D5 | 我的页设备概览 | **完全不留任何设备信息**（连只读一行也不要） |
| D6 | 音频能力检测（AEC/降噪/增益只读 3 行） | **迁入开发者中心「调试」组** |
| D7 | 「关于」组 | 用户协议/隐私政策**不是删除，而是新增两个真实内容页**（详见 §5） |
| D8 | 版本号 | **v6.7.0**；本轮只出方案，不改代码 |
| D9 | 聊天首页（对话页） | **完全不动** |

---

## 1. 背景与目标

### 1.1 问题（现状五个结构缺陷）

1. **受众错位**：「我」页第 2、3 组（设备信息编辑、音频能力只读检测）是开发者内容，占据普通用户页面黄金首位。
2. **同一控制点分裂**：AEC 在两处出现——「我」页音频能力区（只读展示）与开发者中心「通话降噪通路（AEC）」（实际开关）。
3. **高频低频倒挂**：「一键云端 / 导出聊天记录」是普通用户最高频功能，被压在页面中部。
4. **开发者中心「能力开关」组塞 9 条**：总闸、子页入口、开关、说明混杂，浏览负担重。
5. **「关于」组两条 TODO 空壳**（用户协议/隐私政策，点了没反应）。

### 1.2 目标

- 「我」页 = 纯普通用户层（微信风），不出现任何设备身份/诊断内容。
- 开发者中心 = 开发者层，6 个职责单一分组，吸收全部设备身份与诊断内容。
- AEC 收敛为单点（仅开发者中心「连接与音频」组）。
- 协议/隐私页补齐真实内容：功能介绍（不暴露上游与实现机制）+ 权限引导。

---

## 2. 现状基线（实施前必读）

### 2.1 涉及文件

| 文件（相对仓库根） | 现状角色 |
|---|---|
| `lib/presentation/pages/settings/settings_page.dart` | 「我」页（MainPage 底部第 2 个 tab），491 行 |
| `lib/presentation/pages/dev_center_page.dart` | 开发者中心 + MCP 工具详情页 + 密码门 `showDevGateIfNeeded()`，707 行 |
| `lib/presentation/widgets/profile_header.dart` | 资料头组件（**不动**） |
| `lib/presentation/services/app_feats.dart` | 功能开关体系（**不动**） |
| `lib/presentation/pages/main/main_page.dart` | 底部双 tab 导航（**不动**） |

### 2.2 「我」页现状结构（settings_page.dart，ListView 顺序）

1. `ProfileHeader()` 资料头
2. 组「设备信息」：虚拟MAC地址（编辑+点按复制）/ 虚拟Client ID（编辑+点按复制）/ 设备型号（编辑）
3. 组「音频能力」：FutureBuilder 检测 → AEC 回声消除 / 噪声抑制 / 自动增益控制（3 条只读 ListTile）
4. 组「外观」：主题模式（弹窗选择）
5. 组「语音」：说话音量滑杆（联动 MCP set_volume，存 `AppConfig.keyTtsVolume`）
6. 组「账号与云」：一键云端 → CloudSyncPage / 导出聊天记录 → ExportChatPage
7. 组「开发者」：开发者选项 → `showDevGateIfNeeded(context)`（副标题 ValueListenableBuilder 显示"N 项开启"）
8. 组「关于」：版本（`AppConfig.appVersion`）/ 用户协议（TODO 空壳）/ 隐私政策（TODO 空壳）

关键私有方法：`_iconTile(icon, color)`（微信风 28px 色块）、`_buildSection(title, children)`（分组容器）、`_editDeviceField(title, getCurrent, onSave)`（身份编辑对话框）、`_showThemeDialog`（主题弹窗）。

### 2.3 开发者中心现状结构（dev_center_page.dart，ListView 顺序）

- 顶部居中"N 项开启"
- 组「能力开关」（9 条混杂）：🧰 MCP 设备工具（总闸）/ 📋 查看已注册的工具清单（入口→`_McpToolsDetailPage`）/ 🌐 外部 MCP（入口→ExternalMcpPage）/ 📡 MQTT 常驻在线 / 📷 视觉识物 / 🎧 通话降噪通路 AEC（独立存储键，不受 allOff 影响）/ 🧪 MCP 调试 / 😄 表情动画 / ⚠️ 显示服务端原始提示
- 组「AI 主动联系」：总开关（启停 ProactivePollService）/ ⏱ 巡检间隔 / 🌙 允许来电时段 / 📝 巡检口令管理
- 组「诊断」：⏱ 尾音保护（100–500ms）/ 📋 运行日志查看 / 🗂 日志分类
- 组「安全」：🔒 清除授权
- 组「危险操作」：全部关闭（`AppFeats.allOff()`）

### 2.4 ⚠️ 迁移时必须原样保留的行为铁律（不许改语义）

1. **MAC 强制小写**：保存 MAC 时 `v.trim().toLowerCase()`。服务器 WS 按 device-id 区分大小写，大写 MAC = 连上即被踢线（close 1005）。迁移代码时此行**一字不能动**。
2. MAC/ClientID 点按行 = 复制到剪贴板 + SnackBar「已复制到剪贴板」。
3. 编辑保存后 SnackBar 提示「已保存，重新进入对话后生效」。
4. AEC 开关**独立于 AppFeats**（`AudioUtil.useAecSource`），绝不能改成走 `AppFeats`（否则会被 `allOff()` 误关）。
5. 「全部关闭」= `AppFeats.allOff()`，语义不变（含关掉 rawServerAlert/proactive 是有意设计）。
6. 设备型号 FutureBuilder 只允许**单跳**（golden 稳定性约束），迁移时保持原 FutureBuilder 写法。
7. 密码门 `showDevGateIfNeeded` 逻辑不动。
8. 尾音保护存储键 `AppConfig.keyTailGuardMs`、默认值、100–500 滑杆（divisions: 8）不动。

---

## 3. 目标结构

### 3.1 「我」页（settings_page.dart 改后）

```
ProfileHeader 资料头                      ← 不动
组「账号与云」                            ← 提顶（原第 6 组）
  一键云端 → CloudSyncPage
  导出聊天记录 → ExportChatPage
组「通用」                                ← 原外观+语音合并
  主题模式（原样）
  说话音量滑杆（原样）
组「关于」                                ← 补齐真实页面（见 §5）
  版本（AppConfig.appVersion，原样）
  用户协议 → UserAgreementPage（新）
  隐私政策 → PrivacyPolicyPage（新）
组「开发者」                              ← 不动（位置最后，紧贴关于）
  开发者选项（密码门）
```

**删除项**：设备信息组（3 条）、音频能力组（FutureBuilder 整块）、`_editDeviceField` 方法（迁出公共化）。
**清理 import**：`xiaozhi_device_info_util.dart`、`flutter/services.dart` 中不再使用的部分（Clipboard 迁走后）需同步清理；`audio_util`（音量滑杆仍用）、`storage_service` + `app_config`（音量持久化仍用）保留。

### 3.2 开发者中心（dev_center_page.dart 改后）

```
顶部"N 项开启"                           ← 不动
组①「设备身份」                           ← 新增，自「我」页迁入
  虚拟MAC地址（编辑 + 小写强制 + 点按复制）  ⚠️ 铁律 §2.4-1
  虚拟Client ID（编辑 + 点按复制）
  设备型号（编辑，FutureBuilder 单跳）
组②「AI 能力」                            ← 原「能力开关」拆分
  🧰 MCP 设备工具（总闸，原样）
  📋 查看已注册的工具清单（入口，原样）
  🌐 外部 MCP（入口，原样）
  📷 视觉识物（原样）
  😄 表情动画（原样）
组③「AI 主动联系」                        ← 整组原样（决策 D3）
组④「连接与音频」                         ← 原「能力开关」拆分
  📡 MQTT 常驻在线（原样）
  🎧 通话降噪通路（AEC）（原样，独立键 ⚠️ §2.4-4）
  ⏱ 尾音保护（自「诊断」迁入）
组⑤「调试」                               ← 原「能力开关」拆分 + 迁入
  🧪 MCP 调试（原样）
  ⚠️ 显示服务端原始提示（原样）
  音频能力检测（自「我」页迁入：FutureBuilder → AEC/降噪/增益 3 条只读，原样）
  📋 运行日志查看（原样）
  🗂 日志分类（原样）
组⑥「管理」                               ← 原「安全」+「危险操作」合并
  🔒 清除授权（原样）
  全部关闭（红色图标，原样）
```

其余（`_McpToolsDetailPage`、密码门、`_switchTile`、`_section` 等工具方法）全部不动。

### 3.3 新增公共组件（编辑对话框）

`_editDeviceField` 目前是 settings_page.dart 的私有方法。迁移方案：

- 新建 `lib/presentation/widgets/device_edit_dialog.dart`，导出顶层函数：

```dart
/// 设备身份字段编辑对话框（MAC/ClientID/型号共用）
/// [title] 对话框标题；[getCurrent] 取当前值；[onSave] 写入回调
Future<void> showDeviceEditDialog(
  BuildContext context, {
  required String title,
  required Future<String> Function() getCurrent,
  required Future<void> Function(String) onSave,
})
```

- 内容 = 原 `_editDeviceField` 逐行搬移（AlertDialog + TextField + 保存后 SnackBar「已保存，重新进入对话后生效」），**不改任何行为**。
- dev_center_page.dart 调用它；settings_page.dart 删除该方法与相关 import。
- MAC 的 `onSave` 回调里保留 `setDeviceMacAddress(v.trim().toLowerCase())`，并保留原注释（⚠️ MAC 强制小写的说明）。

---

## 4. 实施步骤（建议顺序）

1. **打回滚锚点 tag**：`stable-pre-v6.7.0`（不以 v 开头，不触发 CI），确认 push 到远端。
2. 新建 `device_edit_dialog.dart`（§3.3）。
3. 新建两个内容页（§5）。
4. 改 `settings_page.dart`：删两组 + 删方法 + 调组顺序 + 关于组两条 onTap 接新页 + 清 import。
5. 改 `dev_center_page.dart`：新增「设备身份」组（三条 ListTile 代码从 settings_page 迁入，`_iconTile` 色块样式同样迁入或复制为本地方法）+ 「能力开关」拆三组 + 尾音保护/音频检测迁位 + 「安全」「危险操作」合并「管理」。
6. `flutter analyze` 清零。
7. **golden 基线更新**：me 页在 golden 基线内（chat/session/input/me 四页，基线在 `test/goldens/`，回归脚本 `flutter test test/ui_audit_test.dart`；开发者中心不在基线内）。me 页结构变了，需执行：

```bash
export PATH="/c/Users/Administrator/.workbuddy/binaries/flutter/flutter/bin:$PATH"
flutter test --update-goldens test/ui_audit_test.dart   # 仅接受 me 页基线变化
flutter test test/ui_audit_test.dart                     # 复跑确认全绿
```

⚠️ 若 chat/session/input 三页基线出现 diff，属异常，必须排查而不是盲目接受。
8. 真机冒烟：改 MAC → 保存 → 重进对话生效；开关各项；「全部关闭」；清除授权后密码门重现。
9. commit（规范 message，见 §6）→ tag `v6.7.0` → 确认 CI 触发（查 actions/runs）→ APK 下载桌面 → PLAN md 回填仓库 → push。

**红线自查**（改动前对照）：本方案只动 `lib/presentation/`（✅ 自由区）+ 新文件。不触碰：`xiaozhi_device_info_util.dart`（🔒 冻结）、OTA appName `ajb_agent_flutter`、音频编解码参数、`lib/core/network` 行为。若实施中发现任何一步需要改 core 层，立即停下上报，不得自行扩权。

---

## 5. 新增内容页（全文草稿，可直接使用）

> 共同规范：微信风静态页（Scaffold + AppBar + ListView/富文本卡片），**无任何外链 URL**，深浅色主题自适应，文案遵循"只讲能力、不讲机制"——不出现 MCP / WebSocket / tenclass / xiaozhi-esp32 / 服务器地址等技术上游词。

### 5.1 `lib/presentation/pages/user_agreement_page.dart`（用户协议）

标题「用户协议 · 功能介绍」。正文分节卡片（每节一张圆角卡片，参照开发者中心 `_section` 风格）：

**第一节 产品定位**
小乐 App 是一款运行在您手机上的 AI 语音助手应用。它内置了 AI 助手「小智」，能听、会说、能看、能帮您办事——像一位随身的小管家。

**第二节 您可以获得的能力**（尽量详细，条目化）

1. **智能对话**：文字或语音与小智自由聊天，支持连续多轮对话，记得上下文，越聊越懂你。
2. **语音通话**：像打电话一样和小智实时语音交流，支持调节说话音量、通话降噪（回声消除），交流更清晰。
3. **拍照识物**：看到不认识的东西，拍照问小智"这是什么"，它会识别画面内容并为你讲解。
4. **帮您操控手机**（AI 代办，需你确认）：
   - 调节音量、屏幕亮度、深浅色主题
   - 创建倒计时、设置真实系统闹钟（到点会响）
   - 创建日程并写入系统日历，App 关了也提醒
   - 查看设备状态：电量、网络、系统信息
   - 截取当前界面、在聊天里展示图片
5. **通讯与出行**：帮你打开拨号盘并填好号码（你点拨出才生效）、预填短信内容（你点发送才生效）、打开地图导航到指定地点、直达系统设置页、用浏览器打开网页。
6. **随身小工具**：屏幕轻提示、把文字一键分享到微信/钉钉/备忘录等、读写剪贴板、获取当前位置用于导航。
7. **AI 主动关怀**：开启后，小智可以在你设定的时段内主动来电问候（间隔与时段均可配置，不用时保持零打扰）。
8. **云端同步**：聊天记录与智能体配置可多端互通，换设备不丢数据；聊天记录可导出为 TXT/JSON 备份分享。
9. **智能体定制**：创建多个 AI 角色智能体，自定义头像与资料，切换不同"人格"陪伴。
10. **能力扩展**：可持续接入更多第三方能力服务，小智会越来越多才多艺。

**第三节 安全说明**
涉及打电话、发短信、闹钟、日程等真实系统操作时，都会先展示内容并由你手动确认，安卓系统的安全设计始终生效。

**第四节 其他**
本应用持续更新迭代，功能可能随版本升级而增减；如对功能有疑问，可在开发者中心查看运行日志排查问题。

### 5.2 `lib/presentation/pages/privacy_policy_page.dart`（隐私政策 / 权限引导）

标题「隐私政策 · 权限引导」。基调：**引导用户放心授权全部权限**，说明每项权限的用途与不授权的后果，并给出保活设置引导。

**开头导语**
为了让小乐 App 的每一项功能都能完整使用，我们真诚建议您授予以下全部权限。放心授权后，App 会越来越好用、越来越稳定。

**第一节 权限清单**（每条：权限名 + 用途 + 不授权的影响）

| 权限 | 为什么需要 | 不授权会怎样 |
|---|---|---|
| 🎤 麦克风 | 与小智语音对话的核心通道 | 只能打字交流，无法语音通话 |
| 📷 相机 | 拍照识物 | 无法拍照让小智识别 |
| 🔔 通知 | 接收 AI 回复与主动来电提醒 | 收不到提醒、可能错过主动来电 |
| 📅 日历 | 写入日程提醒 | 日程功能不可用 |
| 📍 位置 | 导航与位置相关能力 | 无法使用导航/定位功能 |
| 📞 电话 | 打开拨号盘并填号（由你拨出） | 无法使用"帮我打电话" |
| 💬 短信 | 预填短信内容（由你发送） | 无法使用"帮我发短信" |
| 🖼 存储/相册 | 导出聊天记录、选择图片识图 | 无法导出与选图 |

**第二节 让 App 常驻不杀（重要）**
请按以下步骤设置，避免小乐被系统后台杀掉，保证语音通话不断线、AI 主动来电不漏接：
1. 系统设置 → 应用 → 小乐 → 电池 → 选择「不限制/允许后台运行」；
2. 在电池优化列表中将小乐设为「不优化/白名单」；
3. 若有「自启动」开关，请开启；
4. 最近任务里不要上滑清理小乐。
（不同品牌手机路径略有差异，关键词：电池优化、自启动、后台运行。）

**第三节 我们的承诺**
- 权限仅用于实现对应功能，不会在后台滥用；
- 涉及电话、短信等敏感系统操作，均需你手动确认后才真正生效；
- 你的聊天记录保存在本机，云端同步仅在你主动开启后进行；
- 随时可在系统设置中收回任何权限，App 会优雅降级为不依赖该权限的模式。

---

## 6. 版本与交付（CI 序列）

1. commit message 规范：`v6.7.0: 我的页与开发者中心分层重构（V2）——设备身份迁入开发者中心、能力开关拆组、新增用户协议/隐私政策页`
2. README 版本档案追加 v6.7.0 行（简述改动）。
3. tag `v6.7.0` → 触发 `build-apk.yml`（Flutter 3.32.2）→ 确认 CI 成功。
4. APK 下载到桌面；PLAN md 本文档回填仓库；push 远端。
5. 回滚通道：实施前锚点 tag `stable-pre-v6.7.0`。

## 7. 验收清单（全过才算完成）

- [ ] 我的页顺序：资料头 → 账号与云 → 通用 → 关于 → 开发者；**无**任何 MAC/ClientID/型号/音频能力字样
- [ ] 「用户协议」「隐私政策」可打开、内容完整、无外链、深浅色均正常
- [ ] 开发者中心 6 组顺序正确：设备身份 / AI 能力 / AI 主动联系 / 连接与音频 / 调试 / 管理
- [ ] MAC 编辑保存后仍强制小写；点按复制仍生效；保存提示语不变
- [ ] AEC 开关仍走独立存储键，`全部关闭` 不影响它
- [ ] 「全部关闭」后 rawServerAlert/proactive 一并关闭（原语义）
- [ ] 清除授权 → 退出 → 再进弹密码门
- [ ] `flutter analyze` 零错误；golden 复跑全绿（me 基线已更新）
- [ ] 真机冒烟通过（改身份→重进对话生效；语音功能正常）
- [ ] CI v6.7.0 成功出包
