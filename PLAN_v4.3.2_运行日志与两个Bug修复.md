# 小乐 App v4.3.2 修复方案（草案 V1 · ✅ 已实施并发布）

> ✅ **已实施（本文档为历史方案，冻结存档）**：本方案对应版本 **`v4.3.2`** **已发布**。
> 最新进度以仓库根 `进度与续接.md` 为准。

- 目标版本：**v4.3.2+19**
- 提出日期：2026-09-10
- 状态：**已实施并发布 ✅**
- 涉及范围：仅 App（`xiaole-client-flutter-2027`）；网页版本次无改动

---

## 一、需求与问题汇总

| 编号 | 类型 | 内容 | 来源 |
|---|---|---|---|
| A | 新功能 | 开发者中心新增「运行日志查看」，点击复制最近 200 条运行日志 | 张老师提出 |
| B | Bug | v4.3.1 视觉识物"没反应" | 真机反馈 |
| C | Bug | 一键云端上传卡在"打包完成" | 真机反馈 |

---

## 二、诊断结论（含代码证据，已由主理人交叉核对）

### 问题 C：一键云端上传卡死 —— 根因已确定（两条叠加）

**根因 C-1（决定性，几乎必然触发）**
`lib/presentation/services/cloud_sync_service.dart:131`

```dart
'messages': webMsgs.sublist(i * blockMsgLimit, (i + 1) * blockMsgLimit),
```

Dart 的 `sublist(start, end)` 要求 `end <= length`，**超出即抛 `RangeError`**。
只要任一会话的消息数不是 250 或 500 的整数倍（例如 37 条），打包阶段就**立刻崩溃**。
→ 与真机现象"显示打包完成后卡住"完全吻合（崩溃发生在打包之后、网络请求之前）。

**根因 C-2（放大后果）**
`lib/presentation/pages/cloud_sync_page.dart` 的 `_push()`（:133）、`_pull()`（:168）、`_bind()`（:107）
**三个方法均无 try/catch**。任何异常（RangeError / 30 秒超时 / 网络异常）都无人捕获 →
`_busy` 永久为 `true`、状态文字永久停在「打包完成…上传中」、**用户看不到任何失败原因**。

补充：`_post()`（cloud_sync_service.dart:81）超时设置为 30 秒，云端已有数据时服务端
DELETE+INSERT 变慢，30 秒偏紧。

**同步方向**：张老师确认为「上传到云端（本机→云端）」，即 `/push` 方向。

### 问题 B：视觉识物无响应 —— 已排除项 + 待埋点定位项

真机现象（张描述）：相机拉起 → 拍照 → 打勾 → 返回聊天页 → 显示"正在识图" → 之后无任何结果。

**已排除**（依据现象与开关状态）：
- `_visionUrl` 为空的可能性 —— 若为空则根本不会拉起相机（chat_page.dart:1195 会直接 Toast return）
- `🧰 MCP 设备工具` 开关关闭 —— 张老师确认两个开关都开，且开关关时不会走到拍照

**待埋点定位的高概率假设**（按可能性排序）：
1. **拍照期间 App 切到相机 Activity，WS 连接已失效**，`_callImageToText` 发出的调用无应答，
   虽有 15 秒超时兜底，但页面状态可能已重建，导致异步链断裂、提示无法显示
2. `_pendingMcpCalls` 待决表在页面重建后丢失，Completer 永久无人 complete
3. 服务器 `image_to_text` 参数名或应答结构与预期不符（v4.3.1 遗留风险项）
4. `_uploadVision` 上传阶段挂起（30 秒超时兜底，但异常提示链路同样可能断裂）

> 说明：B 的最终根因**必须靠埋点日志一锤定音**。本次先修掉所有确定性缺陷并补齐埋点，
> 若 v4.3.2 仍复现，凭日志做点状修复（走下一版本流程，不无限猜测）。

### 问题 A：运行日志 —— 前置风险（PM 发现，已核实）

`lib/core/utils/logger.dart` 的 `AppLogger` 仅有定义、**全项目几乎零调用**（仅 main.dart 2 处
debugPrint、xiaozhi_ota_service.dart 2 处 print）。若只加按钮不加埋点，**复制出来是空的**。
因此本次主要工作量是"建日志采集管道"，按钮只是出口。

---

## 三、已确认决策（张老师拍板）

| # | 决策项 | 结论 |
|---|---|---|
| 1 | 日志交互 | **A 一键复制打底**（点击即复制到剪贴板 + Toast 提示）；B 预览页作为下一版增强 |
| 2 | 隐私脱敏 | **不脱敏，原样输出**（见第九节风险提示） |
| 3 | 埋点范围 | **补：云端同步 + 视觉识物 + WS/OTA** 三条链路 |
| 4 | 云端修复力度 | **稳：兜底捕获 + 明确提示 + 超时调优** |
| 5 | 识图现象 | 相机拉起→拍照→打勾→显示"正在识图"→无后话 |
| 6 | 开关状态 | `📷视觉识物` 与 `🧰MCP 设备工具` 两个都开 |
| 7 | 同步方向 | 上传到云端（`/push`） |

---

## 四、实施方案

### 模块 1：日志基础设施（P0）

1. **新建** `lib/presentation/services/log_buffer.dart`（✅ 自由区新文件）
   - 内存环形缓冲，容量 **500 条**，超出丢弃最旧
   - 每条记录：`时间戳(yyyy-MM-dd HH:mm:ss.SSS)` + `级别(D/I/W/E)` + `tag` + `正文`
   - 单条正文超过 **500 字符**截断并追加 `...[+N chars]`
   - 提供 `getRecentText(int n)` 输出纯文本（默认取最近 200 条）
   - 提供 `clear()`
2. **改** `lib/core/utils/logger.dart`：在 `d/i/w/e/f` 五个静态方法内**各追加一行** `LogBuffer.add(...)`
   - 属纯增量，不改变既有打印行为；该改动位于 `lib/core/utils/`（非 🔒 冻结区、非 ⚠️ 条件区 `lib/core/network`），
     但仍按最小改动原则登记 diff

### 模块 2：关键路径埋点（P0，本次主要工作量）

| 链路 | 埋点节点 |
|---|---|
| 云端同步 | bind 开始/结果、读取本地记录条数、打包块数与每块消息数、**push 请求发出（含字节数）**、HTTP 状态码、响应体、耗时、异常堆栈 |
| 视觉识物 | 📷 点击、visionUrl 是否为空、WS 连接状态、相机返回（含 `xfile` 是否为 null）、上传开始/HTTP 码/响应原文、`image_to_text` 调用 id 与 uuid、收到 mcp 应答（含 payload 摘要）、超时事件、异常堆栈 |
| WS / OTA | 连接开始、握手结果、hello 发送、收到 `initialize`（含 `capabilities.vision` 是否存在）、断开原因与 close code、OTA 请求与响应码 |

埋点统一走 `AppLogger`，因此自动进入环形缓冲。

### 模块 3：开发者中心「运行日志查看」条目（P0）

1. **改** `lib/presentation/pages/dev_center_page.dart`
2. 新增分组「**诊断**」，插在「能力开关」之后、「安全」之前（诊断是高频使用，不埋在页面底部）
3. 条目样式沿用同文件 `_section()` 卡片 + `ListTile` 风格：
   - `leading`：`Icon(Icons.receipt_long_outlined, color: Color(0xFF576B95))`
   - `title`：`📋 运行日志查看`
   - `subtitle`：`复制最近 200 条运行日志，供 AI 排查故障`
4. 点击行为（方案 A）：
   - 读取 `LogBuffer.getRecentText(200)`
   - 为空 → Toast「暂无日志，请先复现操作再回来复制」
   - 非空 → `Clipboard.setData` 复制 + Toast「已复制 N 条日志」
   - 复制异常 → try/catch，Toast「复制失败：<原因>」
5. 入口仅在已通过开发者密码授权后可见（沿用现有 `_devAuthed` 机制）

### 模块 4：一键云端卡死修复（P0）

1. **改** `cloud_sync_service.dart:131`：切块边界收口
   ```dart
   final end = (i + 1) * blockMsgLimit;
   webMsgs.sublist(i * blockMsgLimit, end > webMsgs.length ? webMsgs.length : end)
   ```
   （或等价的 `skip/take` 写法），彻底消除 `RangeError`
2. **改** `cloud_sync_page.dart`：`_push()` / `_pull()` / `_bind()` **全部包 try/catch**
   - 捕获后统一调用 `_fail('上传失败：<具体原因>')`，确保 `_busy` 复位、按钮恢复可用
   - `TimeoutException` → 「上传超时，请检查网络后重试」
   - `SocketException` / `HandshakeException` → 「网络连接失败」
   - 其他 → 「上传失败：<error>」
3. **改** `cloud_sync_service.dart:81`：HTTP 超时由 30 秒调整为 **60 秒**（云端已有数据时服务端耗时更长）
4. 上传请求体字节数写入日志（便于判断是否为大数据量导致）

### 模块 5：视觉识物无响应修复（P0）

1. **改** `chat_page.dart` `_doTakePhotoAndAsk()`：拍照返回后**先重新校验 WS 连接状态**
   - 若已断开（拍照期间极可能被回收），先走现有重连逻辑再发起 `image_to_text` 调用
   - 避免"连接已死但仍按在线发送"导致永久等待
2. 全流程**结果兜底**：无论成功、失败、超时，都必须更新或移除「📷 拍照识物中…」系统气泡，
   确保用户**一定能看到终态**（成功描述 / 中文错误提示），杜绝"没有后话"
3. `image_to_text` 超时由 15 秒调整为 **20 秒**，超时文案明确为「识图超时，请稍后重试」
4. 补齐模块 2 所列识图链路埋点（这是 B 最终定位的关键手段）

---

## 五、改动文件清单与红线评估

| 文件 | 区域 | 红线 | 改动性质 |
|---|---|---|---|
| `lib/presentation/services/log_buffer.dart` | 新文件 | ✅ 自由 | 新增 |
| `lib/core/utils/logger.dart` | 非冻结/非条件区 | 边界追加 | 5 行增量（登记 diff） |
| `lib/presentation/pages/dev_center_page.dart` | presentation | ✅ 自由 | 新增分组与条目 |
| `lib/presentation/services/cloud_sync_service.dart` | presentation | ✅ 自由 | 切块修复 + 超时调整 |
| `lib/presentation/pages/cloud_sync_page.dart` | presentation | ✅ 自由 | try/catch 兜底 |
| `lib/presentation/pages/chat/chat_page.dart` | presentation | ✅ 自由 | 连接校验 + 终态兜底 + 埋点 |
| `pubspec.yaml` / `app_config.dart` / `README.md` | — | ✅ | 版本号 4.3.2+19 |

**红线承诺**：🔒 冻结区（`xiaozhi_device_info_util.dart`、OTA `appName`、音频编解码参数）**零触碰**；
⚠️ 条件区 `lib/core/network` **零改动**。

---

## 六、质量门（实施后必须通过）

1. `flutter analyze` → 0 error（warning 不新增）
2. golden 回归 `flutter test test/ui_audit_test.dart` → 5/5（已知 AUDIT5 固有 flaky，复跑即绿）
3. `git diff <锚点> -- lib/core/ lib/data/` 为空（红线零触碰复核）
4. 真机冒烟：开发者中心日志条目可见可用

---

## 七、真机验收清单

1. 开发者中心 →「📋 运行日志查看」点击后 Toast 显示已复制条数，粘贴出来是有内容的中文日志
2. 复现识图（拍照→打勾）→ 无论成功或失败，**一定出现终态气泡**（描述或中文错误提示），不再"没有后话"
3. 复现识图后立刻去复制日志 → 日志中能看到完整的识图链路（上传 HTTP 码、uuid、调用 id、应答或超时）
4. 一键云端上传 → 不再卡死；即使失败也显示明确原因，按钮可再次点击
5. 上传成功后另一部手机/网页版能拉到记录

---

## 八、【AI 建议（可选采纳）】

以下为自主补充建议，**不属于硬性要求**，可逐条采纳或忽略：

1. **【AI 建议】日志头部加元信息块**：在复制内容开头附一行版本、build、机型、系统版本、
   三个开关（vision/mcptools/mqtt）当前状态。对我排查价值很大，成本约 10 行代码。
2. **【AI 建议】加一个「分享为 txt 文件」次要入口**：复用已有的 `share_plus ^10.1.4`。
   200 条日志可能数十 KB，剪贴板在部分机型有长度限制，分享是保底通道。
3. **【AI 建议】加「清空日志」按钮**：便于干净复现（先清空→复现→再复制），减少噪音。
4. **【AI 建议】缓冲容量 500 但只取 200**：留有余量，避免刚复现完的现场被后续日志冲掉。
5. **【AI 建议】顺带核对网页版切块逻辑**：网页版 JS 的 `slice` 语义不越界，
   初步判断不受 C-1 影响，实施时会确认一次，如有同类问题另行上报。

---

## 九、风险与回滚

| 风险 | 说明 | 应对 |
|---|---|---|
| **日志含敏感信息** | 按决策不脱敏，日志中将包含**真实手机号、设备 MAC、云端 token、聊天内容** | 请仅将日志发给我用于排查，**不要公开分享或发到群里**；如后续改变主意，脱敏可在下一版补上 |
| B 根因未完全确定 | 需靠埋点定位 | v4.3.2 先修确定性缺陷 + 埋点；仍复现则凭日志点状修复 |
| 改动面偏大 | 涉及 6 个文件 + 埋点 | 全部位于 ✅ 自由区，可整版回滚 |
| 回滚锚点 | 发布前打本地 tag 锚点 | 沿用 `stable-1.1.7`（=384c5f47e7）作为兜底回滚点 |

---

## 十、实施记录

| 项 | 内容 |
|---|---|
| 本地 commit | `7798b12`（5 模块主体，12 文件 +742/-120）+ `f9937e9`（log_buffer 迁 core/utils 收尾） |
| 推送 commit | `03d45dd11fd030f62011d6ce2372df34e7ad1978`（远端 master），tree sha `db82a46ec8` 完全匹配 |
| tag | v4.3.2 |
| CI run | **34491173343 → success**（Build Android APK，约 12 分钟） |
| APK | `xiaole-client-v4.3.2.apk` · **59,487,082 字节** · sha1 `dc955d63c458cc7e36ed94663748707a2b15371b`（已交付桌面） |
| 质量门 | analyze 83 issues 全为存量 info / **0 error**；golden 5/5 全绿一次通过；红线 `lib/core/network`+`lib/data` 零改动 |
| 验收结果 | 待张老师真机验收（见第七节清单） |

### 实施中的两处技术修正（记录备查）

1. **日志接入点修正**：设计时写入的是"在 `AppLogger`（`lib/core/utils/logger.dart`）各方法追加写缓冲"，
   但诊断发现 `AppLogger` 是 **package:logger 的全项目零调用死代码**，实际在用的是 `package:logging`。
   故主接入点改为 `lib/main.dart` 的 `Logger.root.onRecord`（全项目日志汇聚点），`AppLogger` 侧保留
   双接入作冗余。**若不改此点，按钮会复制出空内容。**
2. **分层修正**：`log_buffer.dart` 初版置于 `lib/presentation/services/`，被 `lib/core/utils/logger.dart`
   引用即形成 **core → presentation 反向依赖**。已迁至 `lib/core/utils/log_buffer.dart`（commit `f9937e9`）。

### 附带修复（诊断中发现的同源缺陷，已一并处理）

- `_pull()` 中 `r['messages'] as int` → `(r['messages'] as num?)?.toInt() ?? 0`：
  服务端不返回 `messages` 字段时会抛 cast 异常，同样导致卡在「从云端读取…」。
