# 更新日志（CHANGELOG）

> **约定（2026-09-13 张老师定）**：**每次版本更新都必须在这里记录**，最新版本在最上方。
> 格式：`版本号 · 日期 · 一句话主题` → 明细（修复 / 新增 / 变更 / 备注）。
> 配套要求见项目铁律：每个版本必须 push GitHub + 打 tag + README 档案行 + 确认 CI。

---

## v6.4.3 · 2026-09-17

**主题：修复「服务器 alert 未被处理」——长文本被拒等关键提示此前在 UI 上完全不可见**

### 背景（一个真实存在的静默 Bug）
App 发出的**所有文字**（含平时打字聊天）都走同一条通道：`listen` + `state:"detect"`
（写死在 `lib/core/network/xiaozhi_websocket_manager.dart:279-299` 的 `sendTextRequest`，
全文无任何长度检查/截断）。官方服务器对 detect 文本有硬性长度上限（实测 **16 字通过 / 18 字被拒**），
超限会回：
```json
{"type":"alert","status":"ERROR","message":"Detect is only for wake words, do not send long texts."}
```
**但客户端此前完全没有处理 `alert` 消息** —— `_handleTextMessage` 的 switch 只有
`tts / stt / hello / llm / mcp` 分支，`alert` 落到 `default` 只记一行日志后丢弃。
⇒ **用户发长句时消息被服务器静默拒绝，界面上毫无提示**，用户以为已经发出去了。

### 修复（最小改动，1 个文件）
`lib/presentation/pages/chat/chat_page.dart` 的 `_handleTextMessage` 新增 `case 'alert':`：
- 记 warning 日志（含 status 与 message 原文）；
- 非空时追加一条**系统气泡**「⚠️ 服务端提示：<原文>」（持久可见、可回溯）；
- `status == ERROR` 时额外弹一次提示条，让问题**立刻可见**。

不改发送逻辑、不加客户端长度限制（避免臆测阈值；阈值以服务端实际返回为准，现在服务端会明说）。

### 自检
- `flutter analyze`：0 error；warning 仍为既有 5 条基线。
- 全量 `flutter test` 回归（见提交说明）。
- 版本 `6.4.2+39` → `6.4.3+40`。

### 真机验收
在聊天框发一条**超过 20 字**的消息 → 现在应能看到「⚠️ 服务端提示：Detect is only for wake words…」
（此前完全无提示）。若不再出现该提示，说明服务端策略已变，另行核对。

---

## v6.4.2 · 2026-09-17

**主题：修复历史遗留 Bug ——「一键云端」恢复到本机后，智能体不立刻出现在首页/聊天列表**

### 现象
从云端恢复（pull）后，**恢复下来的智能体不会立即出现在 App 首页/聊天列表**；
必须**再手动新增一个智能体**，云端恢复的那些才"顺便"一起显示出来。

### 根因（两名诊断员独立复核 + lead 亲自核对代码行，结论一致）
- 列表的状态源是 Riverpod 的 `agentListProvider`（`lib/core/providers/agent_provider.dart:15-18`），
  `ConversationPage` 用 `ref.watch(agentListProvider)` 响应式渲染。
- **新增/修改/删除**三条路径都经由 `AgentListNotifier.addAgent/updateAgent/deleteAgent`，
  它们在写存储后都会 **`await loadAgents()`**（`agent_provider.dart:29-47`）把存储重读进 `state`
  —— 这就是"刷新动作"。
- 而**云端恢复**走 `CloudSyncService.applyPullResult()`（`lib/presentation/services/cloud_sync_service.dart:340-399`），
  它**直接往 SharedPreferences 写 `agent_list` / `chat_history_*` / 身份等**（数据完整、await 无遗漏），
  但**完全不碰 `agentListProvider`**，没有任何通知内存状态的动作。
- 且 `CloudSyncPage` 原本是普通 `StatefulWidget`（**没有 `ref`**），结构上无法调用 provider；
  恢复后仅 `_load()` 刷新了本页的"云端绑定状态"。
- 另：`agentListProvider` **不是 autoDispose**，所以"返回首页/重进页面"**也不会重读磁盘**。
  ⇒ 只有当用户新增智能体触发 `loadAgents()` 时，才会读到已含恢复数据的存储。

### 修复（最小改动，1 个文件）
`lib/presentation/pages/cloud_sync_page.dart`：
1. `CloudSyncPage` 由 `StatefulWidget` → **`ConsumerStatefulWidget`**（`_CloudSyncPageState` → `ConsumerState<CloudSyncPage>`），以获得 `ref`；
2. 在 `_pull()` 中 `await CloudSyncService.applyPullResult(result: r);` 之后补一行
   **`await ref.read(agentListProvider.notifier).loadAgents();`**
   —— 与 `addAgent` 内部的刷新动作完全等价；
3. 新增 `import 'package:flutter_riverpod/flutter_riverpod.dart';` 与 `'../../core/providers/agent_provider.dart'`。

数据格式、云端协议、存储 key **均未改动**；不涉及下拉刷新等额外改动（按"最小改动"要求）。

### 自检
- `flutter analyze`：**0 error**；warning 仍为既有 5 条基线（`app_pages.dart` / `xiaozhi_service.dart`，未触碰）。
- **全量 `flutter test` 连跑 3 次：2 次 27/27 全绿，1 次仅在 `AUDIT 5` 报 0.28% / 14,706px** ——
  **与本仓记录的固有 flaky 数值完全一致**（我页/设置页 FutureBuilder 时序漂移），与本次改动无关；
  且 golden 文件**未发生任何变更**。CI 不跑测试，不阻塞。
- 版本 `6.4.1+38` → `6.4.2+39`。

### 真机验收
从云端恢复完成后，**应立刻**在首页/聊天列表看到恢复下来的智能体（无需再新增一个触发）。

---

## v6.4.1 · 2026-09-17

**主题：内置预置「笔记 + 高德」两台外部 MCP（开箱即用，用户可改 key）**

- **首次启动自动写入预置**：`biji-notes`（13 工具，前缀 `notes.`）与 `amap-maps`（15 工具，前缀 `amap.`），
  不必再手动导入配置。用 `xw_external_mcp_seeded` 标记**只写一次**——用户删除后不会被自动塞回。
- **用户可自行改用 key**：进编辑页改 `headers`（笔记的 Bearer token）或 `url` 里的 `key=`（高德）即可；
  **不修改就走预置默认值**。
- **「恢复预置」入口**：管理页右上角菜单「恢复预置（笔记/高德）」，空列表页也有「载入预置」按钮；
  按 id 去重，**不会重复添加**。
- 破坏性工具 `merge_notes` 的"默认关闭"逻辑统一收敛到 `ExternalMcpManager.applyDefaultDisabled()`，
  新增 / JSON 导入 / 预置三条路径共用；仅在用户未做过逐项选择时生效，不覆盖用户显式选择。
- 版本 `6.4.0+37` → `6.4.1+38`。

### ⚠️ 安全提示（张老师已知悉并确认）
预置的 token / key 会**打进 APK**，APK 内字符串可被提取，等同"半公开"。
适用于自有服务；建议在高德开放平台为 key 配置**域名白名单 / 调用配额**并定期轮换。

### 自检
- `flutter analyze`：**0 error**（warning 仍为既有 5 条基线）。
- **全量 `flutter test` 27/27 通过**（外部 MCP 单测 15 + 定位 6 + golden AUDIT 1-5 + 冒烟 1）。
- golden **未发生任何文件变更**（AUDIT 5 的偶发失败属本仓已知冷缓存假象，连跑两次 update-goldens 后即稳）。

---

## v6.4.0 · 2026-09-17

**主题：外部 MCP 接入（App 内增删改 + 加前缀桥接给 AI）**

- **新增「🌐 外部 MCP」管理能力**（开发者中心新增入口 → `lib/presentation/pages/external_mcp_page.dart`）
  - 支持**多条**外部 MCP 服务器配置的增 / 删 / 改 / 停用，配置仅存本机。
  - 支持**粘贴 JSON 导入**：直接贴 `{"mcpServers":{...}}` 片段即可（自动解析 url / headers / 前缀）。
  - 列表显示每台服务器的**连接状态**：在线 · N 个工具 / 连接失败原因。
  - **两级开关**：整台服务器启用开关 + 进入后**逐工具开关**。
  - 安全默认：会写/删数据的工具在 UI 上标注，其中 `merge_notes`（合并会删数据）**首次探测成功后默认关闭**。
- **桥接机制**（`lib/core/mcp/external_mcp_client.dart` / `external_mcp_manager.dart` / `external_mcp_store.dart`）
  - App 兼任 MCP **客户端**，连接外部 streamable-HTTP MCP 服务器；
  - 外部工具按 **前缀** 暴露给 AI：`{prefix}.{原始工具名}`（如 `notes.search_notes`、`amap.maps_geo`），
    与设备工具（`self.*`）合并后在 `tools/list` 一并返回，AI 调用时由 App 转发到对应服务器。
  - 建连时**预拉取**外部工具，确保首轮 `tools/list` 就能看到。
  - `xiaozhi_mcp_responder.dart` **纯加法**：新增两个可选回调 `extraToolsProvider` / `externalCaller`
    （为 null 时行为与改动前完全一致）。
- **`self.location.get_current`（v6.3.0 定位）与高德 MCP 打通**：AI 可取本机 GCJ-02 坐标后调用
  `amap.maps_around_search` / `maps_direction_*` 等。
- 版本 `6.3.0+36` → `6.4.0+37`。

### ⚠️ 本版关键坑（实测，务必保留）
1. **biji-notes 有双重 UA 校验**：Cloudflare + 源站挡非浏览器 UA。
   `Dart/3.x`、`okhttp`、`curl` → **401**（源站伪装成"凭证格式不正确"），空 UA → **403**。
   ⇒ 请求**必须**带浏览器式 `User-Agent`。
2. **amap 的 `Accept` 必须同时含 `application/json` 和 `text/event-stream`**，否则 **406**。
3. **鉴权失败形态不同**：biji → HTTP **401**；**amap 错误 key 是 HTTP 200 + body `{"status":"0","info":"INVALID_USER_KEY"}`**
   ⇒ 绝不能只看状态码，必须解析 body。
4. 响应三态：顶层 `error` / `result.isError` / 正常 `result.content[0].text`；
   amap 的 text 是 JSON 字符串、biji 是纯文本 —— 一律原样透传。
5. 两服务器均无状态（无 `Mcp-Session-Id`、无需 `notifications/initialized`）。
6. Dart **没有 `?[]` 空安全下标运算符**（本版踩到过，须逐层判空）。

### 自检
- `flutter analyze`：**0 error**；warning 5 条均为既有基线（`app_pages.dart` / `xiaozhi_service.dart`，本次未触碰）。
- **全量 `flutter test` 25/25 通过**（外部 MCP 单测 13 + 定位 6 + golden AUDIT 1-5 + 冒烟 1；单测用 stub 客户端，不发真实网络）。

---

## v6.3.0 · 2026-09-16

**主题：设备 MCP 详情页（逐项开关）+ 定位能力（self.location.get_current）**

### ✨ 新增：设备 MCP 工具「逐项开关」

- 开发者中心「📋 查看已注册的工具清单」由**只读弹窗**升级为**可操作详情页**（`dev_center_page.dart`）：26+1 项 MCP 设备工具每项行尾带 `Switch`，可独立开启/关闭。
- `AppFeats` 新增 `mcpToolEnabled(name)` / `setMcpToolEnabled(name, bool)`；持久化键 `xw_mcp_<name>`（工具名中的 `.` 转义为 `_`）。`load()` 一并恢复逐项设置；**逐项键独立于 `keys` 列表，`allOff()` 不清空**（总闸「全部关闭」= 普通用户模式，逐项偏好保留）。
- `xiaozhi_mcp_responder.dart`（**纯加法**）：新增可选字段 `bool Function(String name)? isToolEnabled`
  - `tools/list` 用 `.where((t) => isToolEnabled?.call(t.name) ?? true)` 过滤；
  - `tools/call` 命中被禁用工具 → 回 `-32601 unknown tool`（与"不存在"一致，不暴露被关工具）；
  - `initialize` 的 `listChanged:false` 等协议字段**保持不变**。
- `chat_page.dart`：`_setupMcpResponder()` 注入 `isToolEnabled: AppFeats.mcpToolEnabled`（26 处 `register` 全部保留，过滤在下发层做）。

### ✨ 新增：定位能力（self.location.get_current，第 27 项工具）

- 新增 `lib/core/mcp/location_service.dart`（单例）：`getCurrent()` 流程——
  ① 权限检查/申请（复用 `permission_handler`，拒绝 / 永久拒绝均返回结构化原因）；
  ② 检查定位服务是否开启（未开返回「请打开定位」）；
  ③ `geolocator` 高精取位（**超时 8s** 降级到最近已知位置）；
  ④ **WGS-84 → GCJ-02 转换**（内置纯函数 `wgs84ToGcj02`，已写单测校验已知点）；
  ⑤ 返回 `{latitude, longitude, accuracy, coordType:'gcj02', provider}`。**所有异常内部消化，绝不抛出或阻塞 UI**。
- `xiaozhi_mcp_responder.dart` 新增工具定义 `self.location.get_current`（无参 inputSchema）。
- `chat_page.dart` 注册第 27 项 → 调用 `LocationService.instance.getCurrent()`（取位结果在聊天回显一条系统消息）。
- `pubspec.yaml` 新增 `geolocator ^13.0.0`（锁定 Flutter 3.32.2 / Dart 3.8.1 兼容版，实测 13.0.4 解析通过）；`AndroidManifest.xml` 新增 `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`。

### 🔒 红线遵守

- `xiaozhi_mcp_responder.dart` 改动为**纯加法**（新增字段 + 两处过滤/拦截分支 + 1 个工具定义）；hello/initialize 既有协议字段、音频编解码参数、既有冻结文件均未触碰。
- 除 `geolocator` 外**未引入任何新依赖**（`permission_handler` 为既有）。

### ✨ 变更

- `pubspec.yaml` 6.2.1+35 → **6.3.0+36**；`app_config.dart` appVersion 6.2.1 → **6.3.0**；README 徽章与版本表同步。
- 定位隐私：仅 AI 调用时按需取位，绝不后台采集；纳入逐项开关（可在详情页关闭 `self.location.get_current`）。

### ⚠️ 跨版本依赖（已知）

- IP 粗定位兜底（走高德 `maps.ip_location`）需 v6.4.0 桥接后才生效；本版先实现「提示 + 网络/低精度定位尝试」，IP 兜底占位。

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
