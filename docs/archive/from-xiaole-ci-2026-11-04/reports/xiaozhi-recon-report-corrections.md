# 纠正核对报告：token 开关 与 本地 MCP

**结论：本地 MCP 真实存在（App 实现了设备侧 MCP 服务器，27 个 `self.*` 工具，能直接挂 `mika.*`）；但代码里没有"断网自闭环"——工具执行是纯本地，触发仍必须由后端（云端或局域网自建服务器）下发；因此 Mika 可以做成 App 内工具在同一台手机/同一局域网被调用，外连式网关应降级为可选。**

核对对象：`<WORKSPACE>\_recon\xiaole-client-flutter-2027`（用户实际版本，v6.11.5+57）。
（上一轮克隆的 `eiriksgata/xiaozhi-client-flutter` 是阉割参考版，无 MCP，不能作为依据。）

---

## 一、纠正一：`test-token` 是有意设计

### 证据（字段级）
- 默认值：`xiaozhi_websocket_manager.dart:67` `bool enableToken = false`。
- 分支逻辑（同一函数内，共 2 处）：
  - `:142-144` `if (_enableToken && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';`
  - `:145-148` `else headers['Authorization'] = 'Bearer test-token';`
  - `:166` Web 平台回退路径同逻辑：`... ? token : "test-token"`。
  - **没有"完全不发 Authorization"的分支**——头永远存在，只是值可能是 `test-token`。
- 主聊天路径固定走 false + 固定串：
  - `chat_page.dart:920-924` `XiaozhiWebSocketManager(..., enableToken: false)`
  - `chat_page.dart:937` `_connectToWebSocket(_currentAgent?.url ?? '', 'test-token')`
  - 即 **主聊天完全不读 `agent.token`**。
- 真实 token 路径（另一套，语音通话/主动来电）：
  - `xiaozhi_service.dart:137-140 / 182-185 / 316-319` 都是 `enableToken: true`，`:191`/`:321` `connect(websocketUrl, token)` 用调用方传入的真 token；
  - `proactive_poll_service.dart:295,311` 用 `svc.token`（用户/OTA 配置的真 token）。
- token 来源：OTA 响应 `websocket{url,token}`（`xiaozhi_ota_service.dart:252-257`），另有用户在 `agent_config_page.dart:110,571` 手填。
- 服务端为什么接受 `test-token`：自建 `xiaozhi-esp32-server` 默认 `server.auth.enabled: false`（`main/xiaozhi-server/config.yaml:32-38`），auth 关闭时 token 根本不校验；`allowed_devices` 命中的设备也免校验。

### 什么情况必须改 / 绝对不能改
**必须改（唯一条件）**：目标后端开启鉴权——官方云按设备校验，或自建 `server.auth.enabled: true` 且本机 MAC 不在 `allowed_devices`。此时主聊天路径会 401/被拒，需要：
1. `chat_page.dart:923` `enableToken: true`；
2. `chat_page.dart:937` 传入 OTA 下发的真 token（而不是 `'test-token'`）；
3. 补 401 时重新 OTA 取 token 的重试。

**绝对不能改**：
- 社区免费云 / 局域网自建且 auth 关闭时，`test-token` 就是合法占位，任何"修正"都是倒退。
- 不要把 `else` 分支删成"没 token 就不发头"：服务端可能要求该头存在；且 `test-token` 是这套代码在 auth=false 下的既定契约。
- 不要全局把 `enableToken` 置 true 却仍传空串/脏串：空串会落回 `test-token`（`:142` 的 `token.isNotEmpty`），看似无害，但一旦服务端开了 auth，脏串会被拒，且排障成本高。
- 不要未经确认就把 `agent.token` 塞进主聊天：该字段可能为空或过期，而 `XiaozhiService` 已有独立真 token 链路，两者不要混。

---

## 二、纠正二：本地 MCP（设备侧 MCP 服务器）

### 1. 是否实现设备侧 MCP 服务器 —— 是
文件：`lib/core/network/xiaozhi_mcp_responder.dart`
- 类 `XiaozhiMcpResponder`（v3.0.0），注释明确「对齐真机 mcp_server.cc 协议」。
- `handlePayload()`（:81-89）→ `_dispatch()`（:91-174）实现服务端语义：
  - `case 'initialize'`（:95-104）返回 `protocolVersion 2024-11-05` + `capabilities.tools.listChanged=false` + `serverInfo{name:'xiaole-app', version:'3.0.0'}`；
  - `case 'tools/list'`（:106-119）下发工具（含外部 MCP 合并）；
  - `case 'tools/call'`（:121-165）按 `params.name` 找执行器，返回 `result.content[{type:'text', text: jsonEncode(result)}]`；
  - 错误码：`-32601` 未知/被关工具，`-32603` 执行异常。
- 发送封装 `_sendResult/_sendError`（:181-197）：`{type:'mcp', payload:{jsonrpc:'2.0', id, result|error}}`——与上游文档"云端=客户端、设备=服务器"完全一致。

### 2. 注册了哪些本地工具
数量 27，全部 `self.*` 前缀，定义在 `xiaozhi_mcp_responder.dart:211-539`（`XiaozhiMcpStandardTools`）：
- 设备状态/音量/主题/倒计时/日程/拍照/预览图/亮度/屏幕信息/系统信息/重启；
- `self.phone.dial`（:386）、`self.message.send_sms`（:400）、`self.map.navigate`（:414）；
- `self.system.open_settings`（:427）、**`self.system.open_url`（:448，打开网页）**；
- 闹钟/Toast/分享/剪贴板/定位。
执行器**全部本地实现**（Android intent、系统 API），入口在 `chat_page.dart:966-1433` 的 `_setupMcpResponder()` 内逐个 `register(...)`。
- 相关性：**没有"读通讯录"的工具**；`self.phone.dial` 只是打开拨号盘预填号码（`device_capability_service.dart:153-170`）。

### 3. "不接云端也能本地调用"的机制
代码中存在三层触发源，**全部由后端发起**：
- WS：`chat_page.dart:1473-1477` `type=='mcp'` → `handlePayload`；
- MQTT 常驻下行：`chat_page.dart:1459-1472`（凭据来自 OTA）；
- 主动来电轮询：`proactive_poll_service.dart:453` → `handlePayload`。

反证（不存在本地闭环）：
- 全仓库无 `HttpServer/ServerSocket/shelf/localhost`（无本地 MCP 端口可被外部调）；
- `pubspec.yaml` 无本地 ASR/LLM/意图识别依赖，只有 `record`/`opus_*`/`flutter_pcm_sound`；
- 开发者中心只提供"开关"（`dev_center_page.dart:898-921` 仅 Switch + onTap 切换），**没有手动执行工具的入口**。

→ 结论：**App 自身不能脱离后端触发工具**。用户所说"不连云也能用"合理的两种解释：(a) 不连公网官方云，连的是局域网自建 `xiaozhi-server`（工具照样本地执行）；(b) 强调"能力本身在手机本地、不吃云端算力"。二者代码都支持，但"纯离线自闭环"代码里没有。

### 4. 新增 `mika.*` 工具要改哪几个文件
| 文件 | 位置/符号 | 改动量 |
|---|---|---|
| `lib/core/network/xiaozhi_mcp_responder.dart` | 在 `XiaozhiMcpStandardTools` 里加 `static const XiaozhiMcpTool mikaSubmitGoal`（约 :539 后） | +12 行 |
| `lib/presentation/pages/chat/chat_page.dart` | `_setupMcpResponder()` 内 `register(XiaozhiMcpStandardTools.mikaSubmitGoal, (args) async {...})`（:984 起，参照 :1402 的写法） | +15~20 行 |
| `lib/presentation/pages/chat/chat_page.dart` | 文件头 import 新的 Mika 客户端 | +1 行 |
| `lib/core/mcp/mika_client.dart`（可选新建） | HTTP 调 Mika（带 `Origin` 头，私有地址） | 新建 ~50~80 行 |
| `lib/presentation/services/app_feats.dart` | 若命名 `self.mika.*` → 必须加入 `mcpDefaultOnTools`（:59-65），否则默认**不可见**；若命名 `mika.*`（无 `self.` 前缀）→ `:142` 自动放行，0 行 | +1 或 0 行 |
| `lib/presentation/pages/dev_center_page.dart` | `_McpToolsDetailPage` 的 `groups`（:791-829）加一行，并同步组标题里的"（N 项）"与 :71-72 的"26 项"文案 | +2~3 行 |

合计约 **80~100 行、4 个既有文件（+1 个可选新文件）**。注意 `mcpToolEnabled` 的优先级（`app_feats.dart:136-144`）：运行时缓存 > 持久化 > 默认值，所以用 `self.` 前缀时必须进白名单，否则老用户本地已存 `false` 也会继续不可见。

### 5. 走本地 MCP 时还需要外连网关吗
- Mika 工具由 **App 进程在手机本地执行**（executor 直接 HTTP 调 Mika），不是"PC 网关被云端调用"。
- 手机与 Mika 同一局域网（私有地址可达）时，整条链路可做到"不连公网云"：局域网自建 xiaozhi-server（ASR/LLM/TTS）+ App 本地工具。
- 需要网关的场景只剩：手机不在同一局域网（4G/公网）、多用户/多设备统一入口、服务端统一审计/重试。
- → **网关方案降级为可选增强，不再是主路径**。

---

## 三、两种路径对比

| 维度 | 本地设备 MCP（`mika.*`） | 云端 MCP 接入点（外连网关） |
|---|---|---|
| 是否要联网 | 仅需能连后端；局域网自建即可，无需公网 | 必须公网可达 xiaozhi 云 + 网关外连 wss |
| 是否要绑设备码 | 与现有 App 一致（沿用已有激活/绑定） | 与设备绑定无关；需控制台复制 token，且 JWT 会过期 |
| 延迟 | 少一跳（云端→手机→局域网 Mika） | 多两跳（云端→网关→Mika），且受公网波动 |
| 能调用哪些能力 | 27 项本地能力 + 任意新增本地工具 + 外部 MCP | 仅网关暴露的工具，拿不到手机本地能力 |
| 改造成本 | ~80-100 行，4 个文件 | 新服务 + 部署 + token 生命周期 + 运维 |
| 失败面 | 手机与 Mika 不同网段即不可用 | 网关/公网/JWT 任一环节故障即不可用 |

---

## 四、推荐路线

1. **主路径：设备侧 MCP**，新增 `mika.submit_goal / mika.get_task / mika.cancel`（用 `mika.` 前缀，自动默认可见，且与 `self.*` 隔离）。
2. 执行器在 App 内直连 Mika 私有地址，显式带 `Origin` 头；长任务立即返回 `task_id`，`get_task` 轮询。
3. 保留现有 `enableToken:false + test-token`（auth 关闭场景），只在接官方/开启鉴权的后端时按第一节的三步切换。
4. 网关仅在"跨公网/多设备/统一审计"时启用，且复用同一套 `mika.*` 工具契约，避免两套语义。
5. 工具可见性走 `AppFeats.mcpToolEnabled`；开发调试用 `mcpDebug` 开关看原文工具名。

---

## 五、不确定项
- "不连云"的实际验证环境未确认（是局域网自建服务端，还是用户记的其他 App 版本）；代码层面无纯离线的触发器。
- 无"读通讯录"工具；若需求是读联系人而非拨号，需要新增（Android 需 `READ_CONTACTS` 权限），文档/代码均未提供。
- `tools/call` 无明确超时上限（上游文档未写明），Mika 长任务必须异步化。
- 官方云是否对 `test-token` 放行未实测；按 OTA token 校验的可能性存在，接入前需真机验证一次 401 行为。
- `main/xiaozhi-server/config.yaml` 的 `auth.enabled:false` 是自建服务端默认；智控台部署下该配置可能被覆盖（文件头注释已说明）。
