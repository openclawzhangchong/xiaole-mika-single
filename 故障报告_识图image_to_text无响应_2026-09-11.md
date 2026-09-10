# 故障报告：设备端识图（vision）两段式第二步无响应

- **报告日期**：2026-09-11
- **报告人**：张翀（第三方 xiaozhi 协议客户端「小乐 App」开发者）
- **服务器**：`wss://api.tenclass.net/xiaozhi/v1/`（WebSocket）+ `http://api.xiaozhi.me/vision/explain`（视觉上传）
- **客户端**：小乐 App（Flutter，自研协议客户端，遵循 xiaozhi 协议 v1 / MCP 2024-11-05）
- **设备标识**（请贵方用于服务端日志定位）：
  - `Device-Id`：`f4:0d:0a:4c:bc:35`
  - `Client-Id`：`fb129f4e-89d9-4519-85ab-d867b132e40b`
- ⚠️ 本报告含设备标识信息，**仅供服务端排查使用，请勿公开**

---

## 一、问题一句话

`POST http://api.xiaozhi.me/vision/explain` 上传图片**成功返回 `uuid`** 后，
设备按该响应中的提示调用 `image_to_text` 工具，**服务器始终不返回任何应答**
（30 秒内无 `result`、无 `error`、无任何消息），识图功能无法完成。

---

## 二、真机时间线（2026-09-11 06:32，完整原始日志）

**1）连接与会话建立（正常）**
```
06:32:01.807  WS 连接开始 url=wss://api.tenclass.net/xiaozhi/v1/
06:32:02.012  发送 {"type":"hello","version":1,"features":{"mcp":true},"transport":"websocket",
              "audio_params":{"format":"opus","sample_rate":16000,"channels":1,"frame_duration":60}}
06:32:02.073  收到 {"type":"hello",...,"session_id":"0694b9fc"}
06:32:02.075  收到 MCP initialize：
              {"jsonrpc":"2.0","method":"initialize","id":1,"params":{
                "protocolVersion":"2024-11-05",
                "capabilities":{"vision":{"url":"http://api.xiaozhi.me/vision/explain",
                                          "token":"0694b9fc-6e55-47eb-ba40-b5ed5123da19"}},
                "clientInfo":{"name":"xiaozhi-mqtt-client","version":"1.0.0"}}}
06:32:02.076  设备应答 initialize（声明 tools 能力）
06:32:02.110  收到 tools/list（id=2）
06:32:02.111  设备返回 11 项 self.* 工具
```

**2）拍照上传（正常，HTTP 200 + uuid）**
```
06:32:10.615  识图上传开始 url=http://api.xiaozhi.me/vision/explain
              deviceId=f4:0d:0a:4c:bc:35 clientId=fb129f4e-89d9-4519-85ab-d867b132e40b
              （multipart：fields question="这张图里有什么？" + files file=camera.jpg）
06:32:10.972  识图上传完成 HTTP 200 耗时 357ms
              响应体={"success":true,"uuid":"28aed4a8-a198-4fd1-88a5-56158abb49bf",
                      "message":"Please call the tool `image_to_text` to explain the image,
                                 then reply to the user"}
```

**3）按提示调用 image_to_text（★ 服务器零响应）**
```
06:32:10.973  设备发送：
  {"type":"mcp","payload":{"jsonrpc":"2.0","id":10001,"method":"tools/call",
   "params":{"name":"image_to_text","arguments":{"uuid":"28aed4a8-a198-4fd1-88a5-56158abb49bf"}}}}
06:32:10.973 → 06:32:40.975（30 秒）
  服务器**未返回任何消息**（无 result、无 error、无 alert）
06:32:40.975  客户端判定超时：识图三路均无结果 isConnected=true silentSeconds=29
```

**4）另一次对照尝试：把返回的 message 作为文本请求发送（被明确拒绝）**
```
06:32:10.973  设备发送：
  {"type":"listen","state":"detect",
   "text":"Please call the tool `image_to_text` to explain the image, then reply to the user",
   "source":"text"}
06:32:11.001  服务器立即返回：
  {"type":"alert","emotion":"sad","status":"ERROR",
   "message":"Detect is only for wake words, do not send long texts.","session_id":"0694b9fc"}
```

**5）连接本身健康**
```
06:33:11.121  连接已断开 code=1006 attempts=0 kind=服务器   ← 60 秒静默后被回收（正常保护）
06:33:12.128  自动重连成功（新会话 32458318，并重新下发新的 vision url/token）
```

---

## 三、已排除项（均经真机验证）

| # | 项目 | 结论 |
|---|---|---|
| 1 | 上传 URL 是否正确 | ✅ 正确。服务器 `initialize` 下发的就是该 URL；直接 POST 无文件时返回 `{"error":"没有上传文件"}`（HTTP 400），端点正常 |
| 2 | 上传请求格式 | ✅ 正确。返回 HTTP 200 + `{success, uuid, message}` |
| 3 | WS 连接是否正常 | ✅ 正常。hello 握手、MCP initialize/tools/list 全通，60 秒 idle 回收后能自动重连 |
| 4 | 是否 `session_id` 缺失所致 | ❓ 未确认。设备发送的 mcp 消息未带 `session_id`（服务器下发消息均带），但同一连接上的 `tools/list` 应答无需此字段即可被服务器接受 |
| 5 | 是否设备标识问题 | ✅ OTA 认证通过（`activation=false`，即已激活），设备在服务器端应为已注册状态 |
| 6 | `tools/call` 的 id 是否需延续服务器序列 | ❓ 未确认。设备使用自增 id（10001），如贵方要求特定 id 序列请告知 |

---

## 四、疑点定位（供贵方参考）

1. **服务器只声明了 `vision` 能力，未声明 `tools` 能力**
   `initialize` 中 `params.capabilities` 仅含 `vision{url, token}`。
   按 MCP 2024-11-05 规范，客户端仅应在服务端声明 `tools` 能力后调用 `tools/call`。
   → 设备调用 `tools/call` 是否属于**不被服务端处理**的请求？（实测：确为静默无响应）

2. **服务器对非法请求会明确报错，却对该调用完全静默**
   对照实验中 `listen/detect` + 长文本被立即拒绝并返回 `alert/ERROR`，
   说明服务端**并非**"静默型"实现；而 `tools/call image_to_text` 连错误都不返回，
   更接近"**未匹配到任何处理分支**"。

3. **返回的 `message` 文案疑似"给 LLM 的指令"被当作 HTTP 响应体返回**
   `"Please call the tool \`image_to_text\` to explain the image, then **reply to the user**"`
   —— "reply to the user" 只有具备对话能力的 LLM 才能执行，设备端无法执行该指令。
   推测：服务端可能在生成"要求 LLM 调用 `image_to_text` 工具"的提示后，
   **未继续执行工具调用**，而是把该提示文本直接作为 HTTP 响应返回了设备。

---

## 五、请贵方确认的问题

1. `image_to_text` 是否应由**设备**通过 WS `tools/call` 调用？参数名是否为 `uuid`？
   若是，请给出**正确的消息结构**（是否需 `session_id`、`id` 是否需延续服务端序列、`params` 是否需要额外字段）。
2. 若不是由设备调用，那么上传图片后**设备应执行什么动作**才能获得描述？
   （返回的 `message` 是给设备的指令，还是服务端内部 LLM 的提示？）
3. 官方固件（xiaozhi-esp32）或官方 App 的识图实现，是否有**可参考的协议说明**？
   （官方固件旧版本 `Explain()` 为同步 HTTP 直接返回描述，与当前返回 `uuid` 的行为不一致）
4. 是否存在"服务端 `vision` 能力已升级但**配套流程未完整上线**"的情况？

---

## 六、附：设备端发送的完整请求原文

**A. 上传（multipart/form-data，HTTP）**
```
POST http://api.xiaozhi.me/vision/explain
Device-Id: f4:0d:0a:4c:bc:35
Client-Id: fb129f4e-89d9-4519-85ab-d867b132e40b
Authorization: Bearer 0694b9fc-6e55-47eb-ba40-b5ed5123da19
Content-Type: multipart/form-data
  question = 这张图里有什么？
  file     = camera.jpg (image/jpeg)
```

**B. 索取描述（WebSocket 文本帧）**
```json
{"type":"mcp","payload":{"jsonrpc":"2.0","id":10001,"method":"tools/call",
 "params":{"name":"image_to_text","arguments":{"uuid":"28aed4a8-a198-4fd1-88a5-56158abb49bf"}}}}
```

---

## 七、客户端侧已做的规避措施

- 设备侧已实现**完整日志埋点**（WS/MCP/识图三链路，可按分类开关），
  一次复现即可提供全部往返报文，便于贵方定位；
- 识别到请求无响应时会**优雅降级**并明确提示用户"图片已上传成功，但服务器未返回识别结果"，
  不会出现界面卡死；
- 本轮已排除客户端侧的 5 项可能原因（见第三节），并移除了会触发服务端报错的错误尝试方式。

**期待贵方回复正确调用方式，或确认该功能当前的服务端状态。**
