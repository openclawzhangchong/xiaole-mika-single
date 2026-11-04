# 小乐 App v4.3.1 + 网页版 v3.4.1 修复方案（V1 · 已审批）

> 审批时间：2026-09-09 23:04 ｜ 审批人：用户（「全部同意！」）
> 需求来源：真机测试反馈两问题（2026-09-09 截图）——①拍照识图显示原始 JSON；②聊天页三点菜单「智能体设置」无响应
> 状态：**已实施并发布 ✅（App v4.3.1 / 网页版 v3.4.1-dev，2026-09-09）**

---

## 一、诊断结论（已勘察确认）

| # | 现象 | 根因 | 定位 |
|---|------|------|------|
| 1 | 拍照识图显示原始 JSON | 服务器 vision 协议已升级**两段式**：上传返回 `{success, uuid, message:"请调用 image_to_text"}`；App 仍按旧协议提取 `text` 字段，落空后把应答原文直显。App 缺「设备→服务器」方向的 MCP 工具调用发起器与应答分支 | `chat_page.dart` `_uploadVision`（仅认 `{success,text}`）+ `case 'mcp'` 无 result 分支 |
| 2 | 三点菜单「智能体设置」无效 | v1.1.4 微信化改造遗留空壳：`onTap` 处只有 `// TODO: 跳转到智能体配置页面`，从未接线 | `chat_page.dart` `_showMoreOptions` |

## 二、决策记录（用户拍板）

1. 识图结果**描述直显**（工具返回描述进 AI 气泡；服务器若另有 LLM 回复照常显示）；
2. **两端同步修**（App + 网页版，同一协议变更两端都中招）；
3. 【AI 建议（可选采纳）】配置页返回后刷新聊天页标题——**已同意一并修**。

## 三、模块一：App 识图两段式协议适配（v4.3.1）

1. **发起器基础设施**（全部在 chat_page 表现层，**红线零触碰**）：自增 id（10000 起步，避开服务器下发请求的 id 空间）+ 待决表 `Map<int, Completer>`；`_callImageToText(uuid)`：经 WS 发 `{"type":"mcp","payload":{"jsonrpc":"2.0","id":<自增>,"method":"tools/call","params":{"name":"image_to_text","arguments":{"uuid":"<uuid>"}}}}`，等待同 id 应答，15 秒超时。
2. **应答分支**：`case 'mcp'` 顶部（**在 🧰 开关判断之前**，防开关关闭时吞掉识图应答）拦截「带 id + result/error」消息 → 匹配待决表，取 `result.content[0].text`；error 分支同理。
3. **`_uploadVision` 返回结构化**：JSON 带 `text` → 旧协议直显（老服务器兼容不变）；带 `uuid` → 交两段式；都无 → 原文兜底（维持现状）。
4. **两个入口适配**：手动 📷 与 MCP `take_photo`（AI 主动拍照）共用链路均改为「uuid → call → 描述直显」；发起调用前若 WS 未连接走想打就打自动连接。
5. **失败友好化**：超时/错误显示中文提示，**任何情况不再把原始 JSON 显示给用户**；HTTP 非 200 不回显响应体（只报状态码，完整 body 进日志）。

## 四、模块二：「智能体设置」接线（v4.3.1）

1. TODO 处替换为 `context.push('/agent-config?agentId=<当前智能体>')`——与会话列表页长按编辑同款（编辑页与路由均已存在）。
2. 已同意：从配置页返回聊天页后刷新标题（改名后 NavBar 同步）。

## 五、模块三：网页版同步修复（v3.4.1-dev）

1. `app.html` `visionCaptureAndAsk` 同款适配：识别 `uuid` → 经 WS 发 `tools/call image_to_text` → 等 result → 描述直显；WS 分发处同样加「发起方向」id 匹配分支（在现有 MCP 处理之前）。
2. 版本号 v3.4.0-dev → **v3.4.1-dev** → CF 部署验证 → GitHub 推送（无 tag 不触发 CI）。

## 六、通用事项

- **版本**：App `4.3.0+17 → 4.3.1+18`；网页版 `3.4.0-dev → 3.4.1-dev`。
- **红线**：App 改动仅 `lib/presentation/`；发版前 `git diff v4.3.0 -- lib/core/ lib/data/` 校验为空。
- **质量门**：App—analyze 0 error → golden 回归（预期 5/5）→ tag `v4.3.1` → CI → APK 交付桌面字节校验；网页版—识图链路冒烟 → CF 线上验证。
- **风险明示**：`image_to_text` 参数名按官方协议取 `uuid`（依据：服务器应答明示调用该工具）；若真机联调报参数错误，从日志抓实际 schema 做一次点状适配（仍按流程走修复版）。

## 实施记录（2026-09-09 回填）

- **App（v4.3.1+18）**：远端 commit `33a1e04673b7a60a3bc645ffba41b2dbc6e76d18`（本地 `f381a61`，7 文件 +216/-39），tag `v4.3.1`，CI run `34369933334` **success**；APK `<DESKTOP>\xiaole-client-v4.3.1.apk`（59,388,666 字节与资产一致，sha1 `7e0a6620c1df05e6`）。改动全在 `lib/presentation/`（chat_page 为主 + settings 顺手清 v4.3.0 遗留 unused_import）；红线校验 `git diff 8a78873 -- lib/core/ lib/data/` 为空 ✅。
- **网页版（v3.4.1-dev）**：commit `118413f550a3d30727d18426957232672451d393`（app.html 188,985 B + 方案 md，字节校验通过）；CF 部署 `xiaole-web` 项目，线上 `https://xiaole-web-1nx.pages.dev/app.html` 已验证 3.4.1-dev 与新函数生效（HTTP 200）。
- **质量门**：analyze 0 error；golden 套件首跑 AUDIT5 出现 0.28%（14706px）假 diff（与 v4.3.0 同数字同位置，固有 flaky：固定 pump 下异步值偶发漂移，非本次改动区域），复跑两轮 5/5 全绿。
- **待真机验收**：①拍照识物——描述文字进 AI 气泡（不再是 JSON 原文）；识图失败只显示中文提示；②三点菜单「智能体设置」→ 打开编辑页，改名返回后聊天页标题同步；③旧协议兼容：若服务器偶发返回 {text} 形态仍直显。
