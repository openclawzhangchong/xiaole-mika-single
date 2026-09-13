# 更新日志（CHANGELOG）

> **约定（2026-09-13 张老师定）**：**每次版本更新都必须在这里记录**，最新版本在最上方。
> 格式：`版本号 · 日期 · 一句话主题` → 明细（修复 / 新增 / 变更 / 备注）。
> 配套要求见项目铁律：每个版本必须 push GitHub + 打 tag + README 档案行 + 确认 CI。

---

## v6.2.1 · 2026-09-13

**主题：聊天页底部「连接错误」红条降噪（屏蔽瞬时网络错误弹窗）**

### 🐛 修复/优化：DNS/连接类瞬时错误不再弹红条

- **现象**：App 底部偶尔弹出红条「连接错误：WebSocketChannelException: SocketException: Failed host lookup: 'api.tenclass.net' (errno=7)」。
  （注：`apitenclass.net` 为截图漏点号，实为小智公共服务器 `api.tenclass.net`；`errno=7`=DNS 解析失败。）
- **根因**：WS 通道 socket 报错 → `xiaozhi_websocket_manager.dart:_onError` 派发 `error` 事件 →
  `chat_page.dart` 原统一弹红条（`_showError('连接错误: …')`）。
  这类错误多为**网络瞬时抖动**（WiFi↔流量切换、信号短暂丢失、DNS 暂不可达），**自动重连会恢复**，红条纯属打扰。
- **修复**（`lib/presentation/pages/chat/chat_page.dart` 仅此一文件）：
  1. 报错分支新增分类：错误串含 `SocketException`/`Failed host lookup`/`Connection refused`/`Network is unreachable`/
     `Connection timed out`/`Connection reset`/`创建WebSocket失败`/`WebSocketChannelException` → 判定为**瞬时网络错误**；
  2. 瞬时网络错误：**不再弹红条**，改为顶部状态栏显示「网络异常，正在自动重连…」+ 记日志（`logger.severe`）；
  3. **需用户处理的错误仍弹红条**：身份拒绝(432x)、自动重连已达上限、OTA 认证失败等（这些错误串不含上述关键词，天然命中 else 分支）。
- **不丢信息**：聊天页顶部本就有常驻「连接状态栏」（`chat_page.dart:300–355`，断线时带「重连」按钮），
  降级后用户仍能看到状态并可手动重连；自动重连成功即恢复正常。
- **冻结文件未动**：`xiaozhi_websocket_manager.dart` 仅消费其事件，未修改协议/编解码参数。

### ✨ 变更

- `pubspec.yaml` 6.2.0+34 → 6.2.1+35；`app_config.dart` appVersion 6.2.0 → 6.2.1；README 徽章与版本表同步。

---

## v6.2.0 · 2026-09-13

**主题：一键云端「设备身份」上传与恢复修复 + 新增「清空云端数据」**

### 🐛 修复：一键云端 MAC / 设备 ID 无法恢复（恢复后连不回原智能体）

- **现象**：新建智能体（随机 MAC，可正常连接）→ 一键上传 → 删除 App → 重装 → 从云端恢复，
  **智能体名称与聊天记录恢复成功，但 MAC 与设备 ID 没有恢复**（被重装后本机新生成的身份顶替）→ 连不回原智能体。
- **根因（已证实，两端都缺）**：
  1. **上传端** `cloud_sync_service.dart` 的 `agentToWeb()` 只序列化 `fOta/fWs/fToken/fModel/fBoard`，
     **不含 `fMac`/`fCid`**（原注释称"fMac/fCid 为网页端本机身份，App 侧不伪造" —— 该认知已过时：
     自 v1.1.5 起设备身份已是**每智能体独立**，且网页版 conf 一直存这两键）；
  2. **恢复端** `applyPullResult()` 只写 `agent_list` / 聊天记录 / 昵称 / 手机号，**完全不写身份**；
  3. 重装 App 后 SharedPreferences 清空 → 本机按 androidId **重新生成**全局身份 →
     进入对话时 `AgentIdentityStore.load(agentId)` 返回 null → 用**新身份**连接。
- **修复**（`lib/presentation/services/cloud_sync_service.dart`）：
  1. `pushAll`：循环内 `AgentIdentityStore.load(agentId)` → 传给 `agentToWeb(a, identity:)`，
     `conf` 补 `fMac` / `fCid`（与网页版 9 键结构对齐）；
  2. `pullAll`：解析时提取 `conf.fMac`/`fCid` 汇总为 `identities`，随结果返回；
  3. `applyPullResult`：**写回** `AgentIdentityStore.save(agentId, mac, clientId, model)`；
     并把**首个智能体**的身份经 `XiaozhiDeviceInfoUtil` 公开 setter 设为**全局身份**（避免恢复后首次连接仍用新身份）。
- **兼容**：云端老数据没有这两个键 → 自动跳过身份写回（行为同旧版，不会更糟）；多智能体按 agentId 分别存取，不串号。
- **云端零改动**：`/push` 的 `agents` 是**整体 JSON 透传**（存 `users.agents_json`），`/pull` 原样返回。

### ✨ 新增：一键云端「🗑 清空云端数据」

- **App**：一键云端页（已绑定状态）新增红色按钮 → **二次确认弹窗**（明示删除范围 + 不可恢复）→ 调用云端。
- **云端**：新增 `POST /clear`（`xiaole-web-2027/cloud/src/worker.js`）：
  手机号 + 用户名**双因子核验** → `DELETE FROM chat_blocks WHERE session_id LIKE 'phone:%'` +
  `DELETE FROM users WHERE phone=?`；返回删除计数。**已部署上线并验证**。
- **边界**：只清云端；本机数据不受影响。

---

## v6.1.3 · 2026-09-13

**主题：开发者中心可查看已注册的全部 MCP 工具**

- **新增**：开发者中心「🧰 MCP 设备工具」下方新增 **「📋 查看已注册的工具清单」** →
  弹窗**分组列出全部 26 项**（工具名 + 中文用途），底部附「闹钟/日程/短信/拨号/分享需你确认才生效」提示。
- 开关副标题更新为「26 项（音量/闹钟/日程/拨号/短信/导航/截屏…）」。
- **改动范围：仅 `dev_center_page.dart`**（已验证 `git status` 只有该业务文件变更）。

---

## v6.1.2 · 2026-09-13

**主题：修复截屏的 GPU 资源泄漏**

- **修复**：`self.screen.snapshot` 中 `ro.toImage()` 得到的 `ui.Image` **用完未 `dispose()`** →
  每次截屏泄漏一张图的显存（多次截屏可能 OOM）。改为 `try { ... } finally { img.dispose(); }`。
- 来源：独立验证员发现的第二个实锤问题。

---

## v6.1.1 · 2026-09-13

**主题：修复截屏工具失效**

- **修复**：`self.screen.snapshot` 恒返回"当前界面不支持截屏" ——
  v6.1.0 方案里要求"用 `RepaintBoundary` 包住聊天页根视图"**实施时漏做**，
  导致 `findRenderObject()` 永远拿不到 boundary。
  修复：`chat_page.dart` 加 `GlobalKey _snapshotKey` + `build()` 根视图包 `RepaintBoundary(key: _snapshotKey)`
  + 执行器改从该 key 取 boundary。
- 来源：独立验证员发现的实锤缺陷（静态分析查不出）。
- 遗留：本次引入显存泄漏（见 v6.1.2）。

---

## v6.1.0 · 2026-09-13

**主题：MCP 设备工具能力扩展（11 → 26 项）**

- **修复 3 个真机 bug**：
  1. `set_volume` 由「软件增益」改为**控制系统媒体音量**（根治"显示 100% 实际只有一半响度"）；
  2. **新增 `self.alarm.set_alarm`** —— 经 `AlarmClock.ACTION_SET_ALARM` 调用**真·系统时钟闹钟**
     （App 关闭 / 手机重启仍会响）。原先无此工具，AI 只能拿倒计时凑数 → "说设好了实际只设了 App 内提醒"；
  3. `schedule.create_event` 由内存 Timer 改为**写系统日历**（根治"日程设了没用"）。
- **补齐官方标准 5 项**：`screen.set_brightness`（应用级，免 WRITE_SETTINGS）/`screen.get_info`/
  `get_system_info`/`screen.snapshot`/`reboot`（映射为"重连+清空会话"，description 明确不重启手机）。
- **免权限系统能力 5 项**：`phone.dial`（只预填不直拨）/`message.send_sms`/`map.navigate`/
  `system.open_settings`/`system.open_url`。
- **其他 5 项**：`show_toast`/`share.text`/`clipboard.get`·`clipboard.set`/到点 **TTS 语音播报**（系统自带引擎，不下载模型）。
- **诚实性设计**：intent 类工具只能"发起请求"，返回值统一含 `requested: true` + 明确提示，杜绝"AI 说设好了实际没设"。
- **顺手修复**：通话全屏收起按钮未走 `_collapseVoiceCallOverlay` → 收起后系统 UI 不恢复（沉浸式残留）。
- **依赖**：+4（`flutter_volume_controller 2.0.1` / `android_intent_plus` / `screen_brightness` / `flutter_tts`）；
  `torch_light` 因要求 Dart SDK ^3.12（本项目 3.8.1）**未采用**，手电筒不做。
  **全部新能力免危险权限，AndroidManifest 零改动**。

---

## v6.0.1 · 2026-09-13

**主题：修复 v6.0.0 的 CI 失败并发布正式版**

- **修复**：`Free disk space` 步骤误删 `$AGENT_TOOLSDIRECTORY`（= `/opt/hostedtoolcache`，**Flutter/Java 工具链所在**）
  → `flutter: command not found`。清理范围收窄为仅 `.NET`/`Boost`，并注释禁止删工具链与 NDK。
- **同时**：补齐 `abiFilters`（ARM 限定）修复 CI 磁盘耗尽；将工作流迁移为 `build-apk-v2.yml`（新增 `workflow_dispatch` 兜底）；
  把**完整项目树（~200 文件）**纳入版本管理（修复"重建仓库历史不完整导致回滚丢文件"）。
- **发布**：GitHub Release「小乐 v6.0.1 ⭐ 正式版（通话全屏）」，APK 约 37MB。

---

## v6.0.0 · 2026-09-12

**主题：正式版——基于 v4.4.0 原版，唯一新增「通话界面全屏」**

- **新增**：通话中隐藏顶端工具栏（`appBar: _showVoiceCallOverlay ? null : AppBar(...)`）+ 系统沉浸式
  （`immersiveSticky`/`edgeToEdge` 进出配对）；展开/收起封装为 `_expandVoiceCallOverlay()` /
  `_collapseVoiceCallOverlay()` 成对方法；`dispose` 亦恢复系统 UI。
- **封存**：v4.5.x–v4.6.2 的语音扩展能力（麦克风灵敏度 / 端侧声纹 / 本地唤醒 KWS / 46 唤醒词配置）
  **全部封存未删除** —— 本地 tag `archive-voice-wip-20260912` 与远端 tag `v4.5.0`~`v4.6.2`（含 Release APK）可随时找回。
- **范围**：通信协议零改动、音频编解码参数零改动。
