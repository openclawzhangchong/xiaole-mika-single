# 小智生态只读侦察报告（供小乐+Mika 整合用）

**一句话结论：小智生态里 MCP 只有一个业务方向——云端作为 MCP 客户端调用"工具提供方"；因此我们的网关应以「MCP 服务端语义」存在，并主动外连到智能体的 MCP 接入点（wss + token），而不是等前端来调。**

仓库已克隆到（只读、未改动任何仓库）：
- `C:\Users\Administrator\AppData\Local\Temp\recon-xiaozhi\xiaozhi-esp32`
- `C:\Users\Administrator\AppData\Local\Temp\recon-xiaozhi\xiaozhi-client-flutter`
- 另按 docs 指引顺读一层：`xinnan-tech/xiaozhi-esp32-server`、`xinnan-tech/mcp-endpoint-server`（在线文档，未克隆）

---

## 1. MCP 在小智生态里的角色方向

**结论：两个方向都存在，但都是"云端调用工具"，不存在"云端把工具下发给设备"。**
- 设备侧：设备是 MCP **服务器**，云端是 MCP **客户端**，云端发现并调用设备的能力。
- 云端侧：智能体另有"云端 MCP"（MCP 接入点），外部自建 MCP 服务注册进来供**大模型**调用。

依据：
- `xiaozhi-esp32/docs/mcp-protocol_zh.md:5` —「本项目中的 MCP 协议用于后台 API（MCP 客户端）与 ESP32 设备（MCP 服务器）之间的通信，以便后台能够发现和调用设备提供的功能（工具）。」
- 同文件 41–59 行：设备 hello 带 `features:{"mcp": true}`；随后云端发 `initialize` → `tools/list` → `tools/call`，`id` 配对，设备返回 `result.content/isError`。
- `docs/mcp-usage_zh.md` 全文：只讲 `McpServer::AddTool(name, description, properties, callback)` 在**设备端**注册工具（命名风格 `self.xxx`）。
- 官方站文案 xiaozhi.me/home：「设备端 MCP 控制音箱、LED、舵机等外设，云端 MCP 扩展智能家居、知识搜索等能力。」——两种 MCP 均存在。
- `xiaozhi-esp32-server/docs/mcp-endpoint-enable.md` + `mcp-endpoint-integration.md`：智能体可挂"mcp 接入点"，第三方 MCP 服务连上去后工具进入该智能体函数列表。

不确定项：设备工具与云端接入点工具合并后**重名/冲突如何裁决**，文档未写明；官方云与自建云的合并策略是否一致也未写明。

---

## 2. 自建 MCP 服务端给"前端"调用，支持吗？

**结论：小智协议本身不支持"前端/设备调用外部 MCP 服务端"。** websocket/MQTT 上的 `type:"mcp"` 只是承载**云端→设备**的 JSON-RPC，没有反向通道。但**可以自建 MCP 服务端注册到智能体的 MCP 接入点**，由云端（大模型）来调用——这正是"让模型这层 MCP 调到一个我们自建的服务上"。

接入所需：
- **接入点地址**：官方云为 `wss://api.xiaozhi.me/mcp/?token=<token>`（控制台：智能体 → 配置角色 → 复制专属 MCP 接入点）；自建 `xiaozhi-esp32-server` 为 `ws://<ip>:8004/mcp_endpoint/mcp/?token=xxx`（`mcp-endpoint-enable.md`）。**transport 是 websocket，不是 HTTP/SSE**。
- **工具注册**：连上后按标准 JSON-RPC 交互，服务端需实现 `initialize`（`protocolVersion: "2024-11-05"`）、`notifications/initialized`、`tools/list`、`tools/call`、`ping`。调用参数示例 `params: {name, arguments, serialNumber}`（`mcp-endpoint-server/README_dev.md` 测试数据）——`serialNumber` 用于把工具调用路由到某台设备。
- **鉴权**：仅 `?token=` 查询参数。官方 token 是 JWT（载荷含 `userId`/`agentId`/`purpose: mcp-endpoint`，社区实践证据）；自建接入点是随机串。**不用设备码**。设备侧鉴权是另一套：握手头 `Authorization: Bearer <ota返回的token>` + `Device-Id` + `Client-Id`（`websocket_protocol.cc:97-106`，token 无空格时自动补 Bearer）。
- **同步/异步与超时**：JSON-RPC 一请求一响应，语义是**同步**；`mcp_endpoint` 文档与 ESP32 `mcp_server.cc` 均**未写工具调用超时上限**（ESP32 的 120s 是通道超时 `protocol.cc:108-116`，不是工具超时）。→ 契约上应让 `submit_goal` 秒回 task_id。

不确定项：官方 `api.xiaozhi.me/mcp` 与自建 `mcp_endpoint` 报文是否完全一致（官方接口文档页抓取为空，仅控制台与社区项目佐证）；是否支持 HTTP/SSE 形态，未写明。

---

## 3. 绑定与激活

**结论：首次接入靠 OTA 接口下发"激活码 + 连接参数"，用户在 xiaozhi.me 控制台输入 6 位码绑定；换设备/换机器等同于新设备，需要重新绑定。**

依据 `main/ota.cc`：
- 请求：`POST GetCheckVersionUrl()`（NVS `ota_url` 优先，否则 `CONFIG_OTA_URL`），头含 `Activation-Version`、`Device-Id`(MAC)、`Client-Id`(UUID)、`User-Agent`、`Accept-Language`，body 为 `GetSystemInfoJson()`。
- 响应字段（125–254 行）：`activation{code,message,challenge,timeout_ms}`、`mqtt{...}`、`websocket{url,token,version}`、`server_time{timestamp,timezone_offset}`、`firmware{version,url,force}`。
- 未激活时 `activation.code` 被显示并逐位语音播报（`application.cc:753-775` ShowActivationCode）。
- 高安全分支：`Activation-Version: 2` + `Serial-Number` + HMAC-SHA256(challenge) → `POST {ota}/activate`，202 表示继续等待（`ota.cc:467-541`）。
- 换了设备/Client-Id（重刷固件或擦 NVS 会重置 UUID，见 `docs/websocket_zh.md:97`）→ 需重新走激活码绑定；但 `websocket.url/token` 由 OTA 每次下发，**代码无需改地址**。
- 绑定动作本身：控制台"添加设备 → 输入设备播报的 6 位数字验证码"（第三方教程证据，非官方仓库文档）。

不确定项：6 位码的有效期取决于 `activation.timeout_ms`（服务端决定，文档未给具体值）；官方控制台"选择设备接入协议"（开源版/其它）的差异未写明。

---

## 4. 协议消息格式与打断

**结论：文本 JSON 走控制，二进制帧走音频；打断是"客户端发 `abort`"，服务端没有 abort 消息。**

设备 → 云端（`docs/websocket_zh.md` §4.1，代码 `protocol.cc:75-106`）：
- `hello`: `{type, version, features:{mcp,glyph_push}, transport:"websocket", audio_params:{format,sample_rate,channels,frame_duration}, text_font?}`
- `listen`: `{session_id, type:"listen", state:"start"|"stop"|"detect", mode:"auto"|"manual"|"realtime", text?}`（`detect` 用于唤醒词，可带 `text`）
- `abort`: `{session_id, type:"abort", reason:"wake_word_detected"}`
- `mcp`: `{session_id, type:"mcp", payload:{jsonrpc:"2.0", id, method, params|result|error}}`
- （MQTT 才有）`goodbye`

云端 → 设备（`application.cc:604-748` 实际分支）：
- `hello`：`{type:"hello", transport, session_id, audio_params}`
- `stt`：`{type:"stt", text}`
- `llm`：`{type:"llm", emotion, text}`
- `tts`：`{type:"tts", state:"start"|"sentence_start"|"stop", text?}`（`sentence_start` 让设备显示该句）
- `mcp`：`tools/call` 等 JSON-RPC
- `system`：`{command:"reboot"}`
- `alert`：`{status, message, emotion}`
- `notify`：`{audio_url, subtitles:[{start_ms,text}]}`
- `custom`：`{payload}`（需编译开关）

**打断（barge-in）**：设备检测到唤醒词/按键时发 `abort`，服务端随即停止 TTS 并丢弃剩余音频（`websocket_zh.md` §6 状态流转）。`realtime` 模式下设备开 AEC，边播边录不打断。**服务端主动打断（如"停止播放"）无消息类型**，只能靠 `tts.stop`。

不确定项：Flutter 客户端把 TTS 结束判断写成 `state == 'end'`（`chat_page.dart:613`），与文档 `stop` 不一致，实际服务端行为需实测。

---

## 5. 音频参数

**结论：上行为 Opus 16 kHz / 单声道 / 60 ms 帧；下行可能 24 kHz，需重采样；音频走 WebSocket 二进制帧（非 base64）。设备端 VAD/唤醒词可选，VAD 主要由服务端做。**

依据：
- 上行 `audio_params` 由 hello 声明，设备默认 `sample_rate=16000, channels=1, frame_duration=60`（`docs/websocket_zh.md:39-45`）；`OPUS_FRAME_DURATION_MS 60`（`main/audio/audio_service.h:40`），编码采样率固定 16K（`audio_service.h:69`）。
- 下行：服务器 hello 可回 `sample_rate=24000`，设备解码后重采样（`docs/websocket_zh.md:399`、§5.2）。
- 二进制封装三版：v1 裸 Opus；v2 `{version,type,reserved,timestamp,payload_size,payload}`（timestamp 供服务端 AEC）；v3 `{type,reserved,payload_size,payload}`（`websocket_zh.md` §3）。
- VAD/唤醒词：`main/Kconfig.projbuild:979-1041`，`WAKE_WORD_TYPE` **默认 `WAKE_WORD_DISABLED`**；服务端有 VAD 组件（`xiaozhi-esp32-server` 启动日志 `vad成功 SileroVAD`）。`mode:"auto"` 依赖服务端断句，`manual` 由用户停止，`realtime` 需要 AEC。

不确定项：服务端下行到底固定 24k 还是按设备能力协商，文档只说"可能"；v2/v3 是否被官方云强制启用，未写明。

---

## 6. 第三方 Flutter 客户端

**结论：可配置自建服务端（每个智能体独立配 OTA 地址 / WS 地址 / Token），默认打官方 `api.tenclass.net`；没有工具调用入口；改造成本中等。**

依据（`xiaozhi-client-flutter`）：
- 配置项：`data/models/agent_model.dart` 的 `url/token/otaUrl`；`chat_page.dart:359-526` 依次做 OTA 认证 → 取设备 MAC → `connect(agent.url, token)`；默认 OTA `https://api.tenclass.net/xiaozhi/ota/`（`chat_page.dart:372`）。
- 鉴权缺陷：`enableToken: false` 且 token 传死值 `'test-token'`（`chat_page.dart:494-501`、`xiaozhi_websocket_manager.dart:107-113`）——接官方或带鉴权的自建服务会失败。
- 工具调用：`chat_page.dart:646-650` `case 'mcp'` 是 `// todo:处理 MCP 消息`；仅在 hello 里声明 `features:{"mcp": true}`，**不做 initialize/tools/list 响应**。
- 音频：编解码写死 16 kHz（`core/utils/audio_util.dart:33-41`），下行 24k 会变调；无 AEC/VAD/唤醒词，靠"播放时静音上行 + 500ms 静默判定"（`chat_page.dart:566-592`）。
- 文本输入走 `{"type":"listen","state":"detect","text":...,"source":"text"}`（`xiaozhi_websocket_manager.dart:230-251`，`source` 字段文档未写）。

关键改造文件（按重要性）：`lib/core/network/xiaozhi_websocket_manager.dart`、`lib/presentation/pages/chat/chat_page.dart`、`lib/core/utils/audio_util.dart`、`lib/core/network/xiaozhi_ota_service.dart`、`lib/data/models/agent_model.dart`。

不确定项：该仓库是否仍维护、是否已在真机跑通官方云，未验证（`api_constants.dart` 仍是 `api.example.com` 占位）。

---

## 7. 对整合方案的直接影响

**结论：网关必须同时扮演两个角色——对云端是「MCP 服务端语义」，对 Mika 是「MCP 客户端/HTTP 客户端」；前端小乐不承担工具执行。**

- 对云端：进程主动 `wss` 外连智能体 MCP 接入点（token 在 query），实现 `initialize / tools/list / tools/call`，暴露 `submit_goal / get_task / cancel`（建议统一前缀，如 `mika.submit_goal`，避开设备的 `self.*`）。
- 对 Mika：网关跑在用户机器/局域网内，调 Mika 的 HTTP/MCP，天然绕开"仅私有地址 + Origin 403"。
- 对前端：小乐只说协议（hello/listen/abort/音频），不实现工具；只有"设备本地能力"（音量、灯、表情）才需要在设备侧做 device MCP server。
- 时序：`submit_goal` 立即返回 `task_id`（不让云端等长任务），`get_task` 轮询；单次工具调用控制在秒级（超时无官方定义）。
- 风险：接入点 token 是 JWT，会过期/可在控制台吊销，网关需重连与 401 处理；官方接口文档页未读到，`api.xiaozhi.me/mcp` 报文需实测对齐。

---

## 对方案的修正建议（≤10 行）

1. 网关定位改为「外连式 MCP 服务端」：不是被前端调，而是主动连 `wss://api.xiaozhi.me/mcp/?token=...`（或自建 `mcp_endpoint`）。
2. 工具契约按 JSON-RPC 同步语义设计，`submit_goal` 秒回 task_id，长任务一律走 `get_task` 轮询。
3. 工具名加命名空间前缀，避免与设备 `self.*` 工具冲突。
4. 保留设备侧 MCP server 能力给本地硬件控制，不把 Mika 的执行逻辑塞进前端。
5. 前端若基于 Flutter 仓库改造，先修三处：token 传递（当前写死 test-token）、24k 下行解码、`tts.state=="stop"` 判断。
6. 若必须零控制台配置，退路是让前端实现 device MCP server（云端本来就会发 `initialize/tools/list`），但执行逻辑会落在 App 内。
7. 上线前用 `mcp-endpoint-server` 自建环境做协议对齐测试，再接官方云。
