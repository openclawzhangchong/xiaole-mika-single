# 小智 AI 终端 · Flutter APP 实现指南

> **文档定位**：以 ESP32-S3 硬件（M5Stack CoreS3）为参照基准，用 **Flutter** 在 Android 上复刻小智 AI 终端的完整能力。
> **适用读者**：Flutter 开发者 / 想在手机上跑小智协议的开发者
> **数据来源**：① ESP32 编译日志（本地）② 小智 v2.2.4 官方发布说明 ③ 乐鑫 AI 玩具硬件设计指南 ④ 小智 WebSocket 协议 v1 规范 ⑤ 小智 OTA API 规范

---

## 📑 目录

- [第一部分 · 参照基准：硬件侧画像](#第一部分--参照基准硬件侧画像)
- [第二部分 · 通信协议：APP 接入核心](#第二部分--通信协议app-接入核心)
- [第三部分 · Flutter 实现方案](#第三部分--flutter-实现方案)
- [第四部分 · 对齐清单与待确认项](#第四部分--对齐清单与待确认项)

---

# 第一部分 · 参照基准：硬件侧画像

## 1.1 目标硬件：M5Stack CoreS3

从编译日志 `build.log.txt` 提取的硬件身份：

| 项目 | 值 |
|------|-----|
| 板卡名 | `m5stack-core-s3` |
| 芯片 | **ESP32-S3**（dual-core Xtensa LX7） |
| 厂商 | M5Stack |
| 固件版本 | **2.4.2**（本地编译，见下方版本说明） |
| 语言 | `zh-CN` |
| 唤醒词模型 | `wn9l_nihaoxiaozhi_tts3`（你好小智） |
| PSRAM | Quad SPIRAM（`CONFIG_SPIRAM_MODE_QUAD=y`） |
| Flash | 16MB（`--flash-size 16MB`） |
| 摄像头 | GC0308（DVP 接口） |

> ⚠️ **版本说明**：本地编译日志显示 `Project Version: 2.4.2`，使用 **ESP-IDF 6.0** 环境（`/opt/esp/python_env/idf6.0_py3.12_env`）；而官方 Release 最新为 **v2.2.4**，要求 **ESP-IDF 5.5.2**。说明本地是较新的 master 分支代码。
> **协议层面两者一致（Protocol-Version: 1）**，APP 按 v1 协议实现即可兼容。

## 1.2 编译配置全量参数（APP 需对齐的功能开关）

### 音频子系统 ⭐

| Kconfig | 值 | APP 对应实现 |
|---------|-----|-------------|
| `CONFIG_USE_AFE_WAKE_WORD` | `y` | 使用 AFE 音频前处理 → Flutter 用 WebRTC AEC/NS/AGC 替代 |
| `CONFIG_USE_ESP_WAKE_WORD` | `n` | 不走乐鑫原生唤醒 |
| `CONFIG_USE_CUSTOM_WAKE_WORD` | `n` | 无自定义唤醒词 |
| `CONFIG_SR_WN_WN9L_NIHAOXIAOZHI_TTS3` | `y` | 唤醒词 **"你好小智"** → APP 侧需自建唤醒方案 |
| `CONFIG_WAKE_WORD_DISABLED` | `n` | 唤醒功能启用 |

### 摄像头（可选模块）

| Kconfig | 值 |
|---------|-----|
| `CONFIG_CAMERA_GC0308` | `y` |
| `CONFIG_CAMERA_GC0308_AUTO_DETECT_DVP_INTERFACE_SENSOR` | `y` |
| `CONFIG_CAMERA_GC0308_DVP_YUV422_320X240_20FPS` | `y` → **320×240 @ 20fps YUV422** |
| `CONFIG_XIAOZHI_CAMERA_HMIRROR` | `y` → 水平镜像 |
| `CONFIG_XIAOZHI_CAMERA_VFLIP` | `y` → 垂直翻转 |

### UI / 配网

| Kconfig | 值 | 含义 |
|---------|-----|------|
| `CONFIG_USE_DEFAULT_MESSAGE_STYLE` | `y` | 默认气泡样式（非微信风） |
| `CONFIG_USE_WECHAT_MESSAGE_STYLE` | `n` | — |
| `CONFIG_USE_MULTILINE_CHAT_MESSAGE` | `n` | 单行聊天气泡 |
| `CONFIG_USE_HOTSPOT_WIFI_PROVISIONING` | `y` | 热点配网 |
| `CONFIG_USE_ESP_BLUFI_WIFI_PROVISIONING` | `n` | — |
| `CONFIG_LANGUAGE_ZH_CN` | `y` | 简体中文 |

## 1.3 分区表与产物（理解固件结构）

| 分区 | 类型 | 偏移 | 大小 | 用途 |
|------|------|------|------|------|
| `otadata` | data/ota | `0xD000` | 8K | OTA 元数据 |
| `ota_0` | app/ota_0 | `0x20000` | 4032K | 主固件 |
| `ota_1` | app/ota_1 | `0x410000` | 4032K | 备份固件（双分区 OTA） |
| `assets` | data/spiffs | `0x800000` | 8M | **模型/字体/音效资源包** |

产物大小：
- `xiaozhi.bin` = `0x2ba9c0` ≈ **2.86 MB**（占用 app 分区 69%，剩余 31%）
- `generated_assets.bin` = **1626.70 KB（1.59 MB）**——内含唤醒词模型 + 提示音（0-9.ogg + activation/welcome/err_pin/success/... 等 17 个音）
- `merged-binary.bin` = `0x996ac8` ≈ **9.59 MB**

> 💡 **对 APP 的启发**：硬件端把提示音（激活音、配网音、低电量音、升级音、错误音）**打包进固件**。Flutter 应在 `assets/audio/` 放同名音效，用 `AudioPlayer` 在对应状态播放，实现体验对齐。硬件端提示音清单（可从日志提取）：
> `0~9.ogg`、`activation.ogg`、`welcome.ogg`、`wificonfig.ogg`、`upgrade.ogg`、`err_pin.ogg`、`err_reg.ogg`、`low_battery.ogg`、`popup.ogg`、`vibration.ogg`、`success.ogg`、`exclamation.ogg`

## 1.4 硬件音频设计参考（乐鑫 AI 玩具指南）—— APP 侧映射

这份乐鑫指南是**硬件**的规范，但它定义了音频链路的质量标准，APP 侧需等价实现：

### 芯片选型逻辑（理解性能边界）
| 场景 | 推荐芯片 | APP 启示 |
|------|---------|---------|
| 纯语音交互 / 早教硬件 | **ESP32-S3** | APP 对标此档，语音为主 |
| H264 视频 / 屏幕 ≥480P / 视觉多模态 | **ESP32-P4** | 若 APP 要加视频通话，需 H264 编码 |
| 成本敏感唤醒 | ESP32-C3 + 外扩 MCU（体验略差） | — |

### MIC 与 AEC 关键指标
| 项目 | 规格要求 | Flutter 侧实现 |
|------|---------|---------------|
| 单 MIC | 灵敏度 ≥ **-38 dB**，SNR ≥ **60 dB** | 手机 MIC 天然满足 |
| 双 MIC（远场/DOA） | 灵敏度 ≥ -38 dBV，公差 ±1~2 dB，SNR ≥ 62 dB（推荐 >64），PSRR > 55 dB | 手机双 MIC 硬件已满足 |
| MIC 间距 | **4 ~ 6.5 cm** | 手机固定，无需处理 |
| 回声参考信号 | 峰值 **-3 ~ -5 dB**，不可饱和失真 | Android 硬件 AEC 自动处理 |
| **AEC 作用** | 全双工交互 + **语音唤醒打断** | ⭐ APP 必须开 AEC，否则唤醒打断失效 |

> 🔑 **最重要的一条**：AEC 算法主要用于 **全双工交互** 以及 **语音唤醒打断**。
> Flutter 录音必须使用 `AudioSource.VOICE_COMMUNICATION`（Android 硬件 AEC 通路），否则播放 TTS 时无法被用户打断。

### 休眠与唤醒策略（APP 可直接复用）
| 硬件策略 | Flutter 等价实现 |
|---------|-----------------|
| 对话结束 5/10 min 无"有效录音" → 退出对话 → DeepSleep/LightSleep | APP 进入后台保活，停止录音，关闭 WebSocket 或降频心跳 |
| 语音待唤醒功耗 > **50 mA**（电池压力大） | Android 端：前台服务 + 部分唤醒锁，注意电量 |
| DeepSleep < **10 µA**，LightSleep DTIM10 < **700 µA** | APP 无对应，改为释放 AudioRecord + 断开 WS |
| 按键唤醒需接 **RTC_IO** | APP：物理音量键 / 悬浮按钮 / 耳机线控 |
| 唤醒 == 系统重启，首播提示音"我来了"掩盖初始化延迟 | APP：冷启动先播 `welcome.ogg` 再连 WS |
| 休眠前播"我要休息了哦" | APP：超时前播 `sleep` 提示音，增强粘性 |

### 音频验证方法（APP 自测可沿用）
- **MIC 一致性**：0.5 m 处播放 90 dB 白噪声，录 10 s，各通道幅度差 ≤ **3 dB**
- **腔体气密性**：封堵拾音孔前后，100 Hz ~ 8 kHz 衰减 ≥ **25 dB**（推荐 30 dB）
- **AEC 效果**：抓取 AEC 前后 4 路音频（2 MIC + 回采 + 消除后），用 Audacity 查 `aec_in` 是否饱和/丢数/左右声道错位

## 1.5 官方固件生态（v2.2.4）

- 官方 Release：**v2.2.4**，含 **129 个** 板卡固件包
- 编译要求：**ESP-IDF 5.5.2**
- 命名规则：`bread-` 开头 = 面包板版；`ml307` / `NT26` 结尾 = **4G 版**；`128x64` 等 = 屏幕分辨率
- 相关板卡：M5Stack 系列有 CoreS3 / Tab5 / Cardputer Adv / AtomS3R+EchoBase 等 8 款
- v2.0.x 起 **Flash 分区表变更**，支持在线自定义字体/表情/背景，**不能从 v1.9.x 自动升级**

### 唤醒词更换（硬件侧）
开源默认唤醒词 **"你好小智"**（`wn9l_nihaoxiaozhi_tts3`）。更换方式：
1. VSCode → ESP-IDF 插件 → `SDK Configuration Editor (menuconfig)` → `ESP Speech Recognition` → `use wakenet` → `Select wake words`
2. 或命令行：`idf.py menuconfig` → 同上路径 → `S` 保存 → `Q` 退出 → `idf.py build` → `idf.py -p COM7 flash monitor`
3. 乐鑫官方提供约 **26 个**免费唤醒词（S3 目标），需先 `idf.py set-target esp32s3`

> 📌 **APP 侧影响**：ESP 的 wakenet 模型是乐鑫私有格式，**无法直接在 Flutter 用**。
> APP 需三选一：
> - **A. Porcupine**（Picovoice）自定义唤醒词，商用需注意授权
> - **B. 服务端 VAD 唤醒**：不发唤醒词，直接 `listen(mode:"realtime")`，由服务端检测（省事但有流量/隐私成本）
> - **C. 按键唤醒**：最简方案，`press_to_talk_mcp_tool` 硬件已支持该模式

---

# 第二部分 · 通信协议：APP 接入核心

> 🎯 **这是 Flutter APP 必须 100% 实现的部分。** 硬件端源码位于 `main/protocols/websocket_protocol.cc`、`main/protocols/mqtt_protocol.cc`、`main/ota.cc`。

## 2.1 协议基本信息

| 项目 | 值 |
|------|-----|
| **协议版本** | `1` |
| **传输方式** | WebSocket（`wss://`） |
| **音频格式** | **OPUS** |
| **上行采样率** | **16000 Hz**，单声道，`frame_duration: 60`（ms） |
| **下行采样率** | **24000 Hz**，单声道，`frame_duration: 60`（ms） |

> ⚠️ **上下行采样率不对称**（16k 上行 / 24k 下行），这是最容易踩的坑。Flutter 端录音用 16 kHz，播放需按 24 kHz 解码 OPUS（或重采样后播放）。

## 2.2 OTA 激活流程（HTTP，先于 WebSocket）

设备**必须先**调用 OTA 接口，拿到 `websocket.url` + `token` + 激活码，才能建连。

### 请求
```
POST /api/ota/          （社区版路径示例：/xiaozhi/ota/）
Host: api.tenclass.net
```

**必需请求头：**

| Header | 示例 | 说明 |
|--------|------|------|
| `Device-Id` | `11:22:33:44:55:66` | 设备 MAC（或硬件 ID 生成的**伪 MAC**） |
| `Client-Id` | `7b94d69a-9808-4c59-...` | **UUID v4**，擦除/重装会变 |
| `User-Agent` | `m5stack-core-s3/2.4.2` | `板卡SKU/版本号` |
| `Accept-Language` | `zh-CN` | 可选 |
| `Content-Type` | `application/json` | — |

**请求体（Android 最小集）：**
```json
{
  "application": {
    "version": "2.4.2",
    "elf_sha256": "<32字节hex>"
  },
  "board": {
    "type": "m5stack-core-s3",
    "name": "m5stack-core-s3",
    "ssid": "卧室",
    "rssi": -55,
    "channel": 1,
    "ip": "192.168.1.11",
    "mac": "11:22:33:44:55:66"
  }
}
```

> 若上报完整信息，还可带：`chip_model_name: "esp32s3"`、`flash_size: 16777216`、`psram_size`、`partition_table[]`、`mac_address`、`uuid`、`application.compile_time`、`application.idf_version`。

### 响应
```json
{
  "activation": { "code": "123456", "message": "请在网站输入激活码" },
  "mqtt": {
    "endpoint": "mqtt.example.com",
    "client_id": "GID_test@@@device-id@@@uuid",
    "username": "device_12345",
    "password": "password",
    "publish_topic": "device-server"
  },
  "websocket": {
    "url": "wss://api.tenclass.net/xiaozhi/v1/",
    "token": "test-token"
  },
  "server_time": {
    "timestamp": 1633024800000,
    "timezone": "Asia/Shanghai",
    "timezone_offset": -480
  },
  "firmware": { "version": "1.0.0", "url": "https://.../1.0.0.bin" }
}
```

**错误码：**
| HTTP | error | 含义 |
|------|-------|------|
| 400 | `Device ID is required` | 缺 `Device-Id` 头 |
| 400 | `Invalid OTA request` | 字段无效 |
| 500 | `Failed to read device auto_update status` | 服务端异常 |

**注意事项：**
- 固件 `0.9.8` 且 `bread-` 开头的版本因音频编码缺陷会被**强制更新**
- 设备禁用自动更新时，服务端不返回新固件
- 板卡类型未知时返回当前版本 + 空下载链接

> 🔐 **激活**：响应含 `activation.code` 时，需在屏幕显示 `activation.message`（如"请在网站输入激活码 123456"），用户到控制台绑定后设备才能正常工作。Flutter 需做**激活码展示页 + 轮询激活状态**。

## 2.3 WebSocket 连接建立

### Step 1 — 握手 Headers
```
Authorization: Bearer <access_token>
Protocol-Version: 1
Device-Id: <设备MAC地址>
Client-Id: <设备UUID>
```

### Step 2 — 客户端发 `hello`
```json
{
  "type": "hello",
  "version": 1,
  "transport": "websocket",
  "features": { "mcp": true },
  "audio_params": {
    "format": "opus",
    "sample_rate": 16000,
    "channels": 1,
    "frame_duration": 60
  }
}
```

### Step 3 — 服务端回 `hello`（注意采样率变为 24000）
```json
{
  "type": "hello",
  "transport": "websocket",
  "audio_params": {
    "format": "opus",
    "sample_rate": 24000,
    "channels": 1,
    "frame_duration": 60
  }
}
```

> 📝 **WebSocket 协议不返回 `session_id`**，所以后续消息中的 `session_id` 可设为**空字符串**。

## 2.4 消息类型全量表

| type | 方向 | 作用 | 关键字段 |
|------|------|------|---------|
| `hello` | ↔ | 握手协商音频参数 | `audio_params` |
| `listen` | → | 开始/停止/唤醒检测 | `state`, `mode`, `text` |
| `tts` | ← | TTS 播放状态 | `state`, `text`(仅 sentence_start) |
| `abort` | → | 中止当前会话 | `reason` |
| `mcp` | ↔ | MCP 能力调用 | `payload` |
| `llm` | ← | **情感/表情** | `emotion`, `text`(emoji) |

### ① 语音识别 `listen`

**开始监听**
```json
{ "session_id": "", "type": "listen", "state": "start", "mode": "<模式>" }
```
| mode | 说明 |
|------|------|
| `auto` | **自动停止**（服务端 VAD 检测说完自动收尾） |
| `manual` | **手动停止**（APP 需显式发 stop） |
| `realtime` | **持续监听**（实时对讲，⚠️ **需 AEC 支持**） |

> `auto` 与 `realtime` 均为服务端 VAD 模式，但 `realtime` **必须有 AEC**，否则会自激。

**停止监听**
```json
{ "session_id": "", "type": "listen", "state": "stop" }
```

**唤醒词检测上报**
```json
{ "session_id": "", "type": "listen", "state": "detect", "text": "你好小智" }
```

### ② 语音合成 `tts`（服务端 → 客户端）
```json
{ "type": "tts", "state": "<状态>", "text": "<文本内容>" }
```
| state | 含义 | 携带 text |
|-------|------|----------|
| `start` | 开始播放 TTS | ❌ |
| `stop` | 停止播放 | ❌ |
| `sentence_start` | **新句子开始** | ✅（用于 UI 逐句显示字幕） |

### ③ 中止 `abort`
```json
{ "session_id": "", "type": "abort", "reason": "wake_word_detected" }
```
`reason` 可选。典型场景：用户说出唤醒词 → 打断当前 TTS 播放。

### ④ MCP 能力调用
```json
{ "session_id": "", "type": "mcp", "payload": { /* MCP Payload */ } }
```
APP 作为 **MCP 客户端**，可暴露本地能力给大模型（如硬件的 `press_to_talk_mcp_tool`）。Flutter 可实现：
`self.screen_brightness`、`self.volume`、`self.take_photo`、`self.get_location`、`self.set_alarm` 等。

### ⑤ 情感状态 `llm`（服务端 → 客户端）
```json
{ "type": "llm", "emotion": "smile" }
{ "type": "llm", "text": "😊", "emotion": "smile" }
```

> 💡 大模型会用 **1 个 token** 输出 emoji 表示当前心情。该 emoji **不会被 TTS 朗读**，但会以独立数据类型返回 → 用于驱动 APP 的表情动画（对标硬件的 `emote_display` / `emoji_collection`）。

## 2.5 Emoji 情感对照表（21 种）

> Flutter 侧建 `Map<String, String>` 做 `emotion → 表情资源` 映射，驱动 Lottie/Rive/静态图。

| # | Emoji | emotion | 中文 |
|---|-------|---------|------|
| 1 | 😶 | `neutral` | 中性 |
| 2 | 🙂 | `happy` | 开心 |
| 3 | 😆 | `laughing` | 大笑 |
| 4 | 😂 | `funny` | 搞笑 |
| 5 | 😔 | `sad` | 伤心 |
| 6 | 😠 | `angry` | 生气 |
| 7 | 😭 | `crying` | 哭泣 |
| 8 | 😍 | `loving` | 喜爱 |
| 9 | 😳 | `embarrassed` | 尴尬 |
| 10 | 😲 | `surprised` | 惊讶 |
| 11 | 😱 | `shocked` | 震惊 |
| 12 | 🤔 | `thinking` | 思考 |
| 13 | 😉 | `winking` | 眨眼 |
| 14 | 😎 | `cool` | 酷 |
| 15 | 😌 | `relaxed` | 放松 |
| 16 | 🤤 | `delicious` | 馋 |
| 17 | 😘 | `kissy` | 亲吻 |
| 18 | 😏 | `confident` | 得意 |
| 19 | 😴 | `sleepy` | 困倦 |
| 20 | 😜 | `silly` | 调皮 |
| 21 | 🙄 | `confused` | 困惑/无奈 |

## 2.6 二进制帧：音频传输

| 方向 | 内容 | 规格 |
|------|------|------|
| 客户端 → 服务端 | OPUS 编码音频 | 16 kHz / 单声道 / **60 ms/帧**（每帧 960 samples） |
| 服务端 → 客户端 | OPUS 编码 TTS 音频 | 24 kHz / 单声道 / **60 ms/帧**（每帧 1440 samples） |

- 使用 WebSocket **二进制帧**（binary frame）传输，非文本帧
- JSON 控制消息走文本帧，音频走二进制帧，**同一连接复用**

## 2.7 会话状态机

### 完整会话流程
```
1. HTTP POST /api/ota/          → 获取 websocket.url / token / 激活码
2. WebSocket 连接（带 4 个 Headers）
3. 发送 hello → 接收 hello（确认 24000 下行）
4. 语音交互循环：
   ├─ 发送 listen(start, mode)
   ├─ 持续发送 OPUS 二进制帧（16 kHz）
   ├─ 接收识别结果（文本）
   ├─ 接收 llm emotion（驱动表情）
   ├─ 接收 tts(sentence_start) → 显示字幕
   └─ 接收 OPUS 二进制帧（24 kHz）→ 解码播放
5. 结束：listen(stop) 或 abort，关闭连接
```

### Manual 模式
```
按键按下 → listen(start, manual) → 录音… → 按键松开 → listen(stop)
                                           → 等待 ASR 结果 → TTS 播放
```

### Auto 模式
```
唤醒/按键 → listen(start, auto) → 录音… → 服务端 VAD 判定说完
                                        → 自动结束 → ASR → TTS
```

### 错误处理
- 网络错误时客户端收到错误消息并**关闭连接**
- **客户端必须实现重连机制**（指数退避，建议 1s→2s→4s→…→30s 上限）

## 2.8 MQTT 协议（可选，作为 WebSocket 备用通道）

从 OTA 响应获取的 MQTT 配置：
```json
{
  "endpoint": "mqtt.example.com",
  "client_id": "GID_test@@@<device-id>@@@<uuid>",
  "username": "device_12345",
  "password": "password",
  "publish_topic": "device-server"
}
```
- `client_id` 格式：`GID_test@@@{device-id}@@@{uuid}`
- 上行 topic：`device-server`
- 硬件端源码：`main/protocols/mqtt_protocol.cc`、`espressif/mqtt (1.1.0)`

> 建议 **MVP 阶段先只做 WebSocket**，MQTT 留作后续（UDP/低延迟场景）。

---

# 第三部分 · Flutter 实现方案

## 3.1 技术栈选型（`pubspec.yaml`）

```yaml
name: xiaozhi_flutter
description: 小智 AI 终端 Flutter 版
environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter

  # ── 网络通信 ──
  web_socket_channel: ^3.0.0      # WebSocket 客户端
  dio: ^5.7.0                     # HTTP（OTA 激活）
  # 或 http: ^1.2.0

  # ── 音频采集 / 播放 ──
  record: ^5.5.0                  # 录音（支持 VOICE_COMMUNICATION = 硬件 AEC）
  just_audio: ^0.9.39             # 低延迟播放（支持 PCM 流式喂入）
  # 如果要最稳的 AEC/NS/AGC：flutter_webrtc: ^0.11.0

  # ── OPUS 编解码 ──
  opus_dart: ^5.0.0               # OPUS FFI 绑定（16k 编码 / 24k 解码）

  # ── 设备身份 ──
  device_info_plus: ^11.1.0       # 取 Android ID / 机型
  uuid: ^4.4.2                    # Client-Id (UUID v4)

  # ── 状态管理 / 存储 ──
  flutter_riverpod: ^2.6.0        # 状态机管理
  shared_preferences: ^2.3.0      # 持久化 Client-Id / token

  # ── 权限 / UI ──
  permission_handler: ^11.3.0     # 麦克风权限
  rive: ^0.13.0                   # 表情动画（21 种 emotion）
  audioplayers: ^6.1.0            # 本地提示音 ogg（激活音/配网音/低电量音）

flutter:
  assets:
    - assets/audio/               # 0~9.ogg, activation.ogg, welcome.ogg ...
    - assets/emotions/            # 21 种表情资源
```

### 关键选型说明

| 需求 | 方案 | 理由 |
|------|------|------|
| **AEC 回声消除** | `record` 包设 `AudioSource.voiceCommunication` | 走 Android 硬件 AEC 通路，**唤醒打断的前提** |
| 备选 AEC | `flutter_webrtc` 的 `setAudioProcessing(true)` | 软件 AEC/NS/AGC，效果最好但包体积大 |
| **OPUS** | `opus_dart` | 纯 Dart FFI，支持 16k/24k 双采样率 |
| 播放 24 kHz | `just_audio` + `StreamAudioSource` 或 `audioplayers` 的 `feedBytes` | 需流式喂 PCM |
| 唤醒词 | `porcupine_flutter` / 按键 / 服务端 VAD | 见 1.5 节三选一 |

## 3.2 项目结构

```
lib/
├── main.dart
├── core/
│   ├── constants.dart              # 协议常量（16k/24k/60ms/Protocol-Version）
│   └── device_identity.dart        # Device-Id / Client-Id 生成与持久化
├── network/
│   ├── ota_client.dart             # POST /api/ota/ 激活
│   ├── ws_protocol.dart            # WebSocket 协议客户端 ⭐
│   └── models/                     # hello/listen/tts/abort/mcp/llm 消息模型
├── audio/
│   ├── opus_codec.dart             # OPUS 编解码封装
│   ├── audio_capture.dart          # 16 kHz 采集 + AEC
│   ├── audio_player.dart           # 24 kHz 流式播放
│   └── sound_effects.dart          # 本地提示音（对齐硬件 17 个 ogg）
├── state/
│   ├── device_state_machine.dart   # idle/connecting/listening/speaking ⭐
│   └── providers.dart
├── features/
│   ├── activation/                 # 激活码展示页
│   ├── chat/                       # 聊天气泡（default 样式，非微信风）
│   ├── emotion/                    # 21 种表情渲染
│   └── settings/                   # 服务器地址、音量、唤醒方式
└── mcp/
    └── mcp_tools.dart              # 暴露给大模型的本地能力
```

## 3.3 设备身份模块

> ⚠️ 对齐硬件：`Device-Id` = MAC 地址（或伪 MAC），`Client-Id` = UUID v4。
> Android 10+ **无法获取真实 WiFi MAC**，需用 `device_info_plus` 的 `androidId` 生成伪 MAC。

```dart
// lib/core/device_identity.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  static const _kClientId = 'xiaozhi_client_id';
  final _uuid = const Uuid();

  /// Device-Id：由 Android ID 生成稳定的伪 MAC（格式 XX:XX:XX:XX:XX:XX）
  Future<String> getDeviceId() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final seed = info.id ?? 'unknown-android';          // Android ID
    final bytes = sha1.convert(utf8.encode(seed)).bytes;
    final mac = bytes.take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    return mac;                                          // 例如 a3:f1:0c:9d:22:7e
  }

  /// Client-Id：UUID v4，首次生成后持久化（擦除/重装才变，对齐硬件语义）
  Future<String> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kClientId);
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString(_kClientId, id);
    }
    return id;
  }

  /// User-Agent：{板卡SKU}/{版本号}，对齐硬件 xingzhi-cube-1.54tft-wifi/1.0.1
  String get userAgent => 'm5stack-core-s3/2.4.2';
}
```

## 3.4 OTA 激活客户端

```dart
// lib/network/ota_client.dart
import 'package:dio/dio.dart';

class OtaConfig {
  final String? activationCode;
  final String? activationMessage;
  final String wsUrl;
  final String wsToken;
  final MqttConfig? mqtt;
  final ServerTime? serverTime;
  final FirmwareInfo? firmware;

  OtaConfig.fromJson(Map<String, dynamic> j)
      : activationCode   = j['activation']?['code'],
        activationMessage= j['activation']?['message'],
        wsUrl            = j['websocket']['url'],
        wsToken          = j['websocket']['token'],
        mqtt             = j['mqtt'] != null ? MqttConfig.fromJson(j['mqtt']) : null,
        serverTime       = j['server_time'] != null ? ServerTime.fromJson(j['server_time']) : null,
        firmware         = j['firmware'] != null ? FirmwareInfo.fromJson(j['firmware']) : null;
}

class OtaClient {
  final Dio _dio;
  final String baseUrl;          // 例如 https://api.tenclass.net
  final String otaPath;          // /api/ota/  或  /xiaozhi/ota/
  OtaClient(this.baseUrl, {this.otaPath = '/api/ota/'})
      : _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  Future<OtaConfig> checkOta({
    required String deviceId,
    required String clientId,
    required String userAgent,
    required String appVersion,
    String language = 'zh-CN',
  }) async {
    final resp = await _dio.post(
      '$baseUrl$otaPath',
      options: Options(headers: {
        'Device-Id': deviceId,
        'Client-Id': clientId,
        'User-Agent': userAgent,
        'Accept-Language': language,
        'Content-Type': 'application/json',
      }),
      data: {
        'application': {'version': appVersion, 'elf_sha256': ''},
        'board': {'type': 'm5stack-core-s3', 'name': 'm5stack-core-s3'},
      },
    );
    return OtaConfig.fromJson(resp.data);
  }
}
```

> 💡 若 `activation.code != null`，跳转**激活码展示页**，显示 `activation.message`（如"请在网站输入激活码 123456"），并轮询激活状态。

## 3.5 WebSocket 协议客户端 ⭐（核心）

```dart
// lib/network/ws_protocol.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 协议常量 —— 严格对齐硬件
class Proto {
  static const int version       = 1;
  static const int inSampleRate  = 16000;  // 上行
  static const int outSampleRate = 24000;  // 下行
  static const int channels      = 1;
  static const int frameDuration = 60;     // ms
  static const String audioFormat = 'opus';
}

enum WsState { disconnected, connecting, handshaking, ready, listening, speaking, error }

class XiaozhiWebSocket {
  WebSocketChannel? _ch;
  final StreamController<Map<String, dynamic>> _json =
      StreamController.broadcast();
  final StreamController<Uint8List> _audio =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get onJson  => _json.stream;
  Stream<Uint8List>            get onAudio => _audio.stream;

  /// 连接：携带 4 个必需 Header
  Future<void> connect({
    required String url,
    required String token,
    required String deviceId,
    required String clientId,
  }) async {
    final uri = Uri.parse(url);
    _ch = WebSocketChannel.connect(uri, protocols: null);
    // web_socket_channel 不支持自定义 header，需在 native 层或用 dart:io
    // 推荐：使用 dart:io WebSocket.connect(url, headers: {...})
    await _handshake();
    _listen();
  }

  /// 使用 dart:io 以携带自定义 Header（正确姿势）
  Future<void> connectWithHeaders({
    required String url,
    required String token,
    required String deviceId,
    required String clientId,
  }) async {
    final ws = await WebSocket.connect(url, headers: {
      'Authorization': 'Bearer $token',
      'Protocol-Version': '${Proto.version}',
      'Device-Id': deviceId,
      'Client-Id': clientId,
    });
    _ch = ws as WebSocketChannel?;   // 实际用 IOWebSocketChannel(ws)
  }

  void _handshake() {
    sendJson({
      'type': 'hello',
      'version': Proto.version,
      'transport': 'websocket',
      'features': {'mcp': true},
      'audio_params': {
        'format': Proto.audioFormat,
        'sample_rate': Proto.inSampleRate,
        'channels': Proto.channels,
        'frame_duration': Proto.frameDuration,
      },
    });
  }

  void _listen() {
    _ch!.stream.listen((data) {
      if (data is String) {
        _json.add(jsonDecode(data) as Map<String, dynamic>);
      } else if (data is Uint8List) {
        _audio.add(data);            // OPUS 二进制帧（24 kHz）
      }
    }, onError: (_) => _reconnect(), onDone: _reconnect);
  }

  // ── 业务方法 ──
  void startListen(String mode) => sendJson({
        'session_id': '', 'type': 'listen',
        'state': 'start', 'mode': mode,      // auto | manual | realtime
      });

  void stopListen() => sendJson({
        'session_id': '', 'type': 'listen', 'state': 'stop',
      });

  void reportWakeWord(String text) => sendJson({
        'session_id': '', 'type': 'listen',
        'state': 'detect', 'text': text,     // "你好小智"
      });

  void abort({String reason = 'wake_word_detected'}) => sendJson({
        'session_id': '', 'type': 'abort', 'reason': reason,
      });

  void sendMcp(Map<String, dynamic> payload) => sendJson({
        'session_id': '', 'type': 'mcp', 'payload': payload,
      });

  /// 发送 OPUS 二进制帧（16 kHz，60ms/帧）
  void sendAudio(Uint8List opusFrame) => _ch?.sink.add(opusFrame);

  void sendJson(Map<String, dynamic> msg) =>
      _ch?.sink.add(jsonEncode(msg));

  /// 断线重连：指数退避
  void _reconnect() { /* 1s → 2s → 4s → … → 30s 上限 */ }

  void dispose() { _ch?.sink.close(); _json.close(); _audio.close(); }
}
```

### 消息解析（对应 2.4 节）

```dart
void handleJson(Map<String, dynamic> m) {
  switch (m['type']) {
    case 'hello':
      // 服务端确认，读取 outSampleRate = 24000，初始化解码器
      break;
    case 'tts':
      switch (m['state']) {
        case 'start':          // 开始播放 → UI 进入 speaking
        case 'stop':           // 播放结束 → UI 回到 idle
        case 'sentence_start': // 逐句字幕：m['text']
      }
      break;
    case 'llm':
      // m['emotion'] → 驱动 21 种表情；m['text'] 可能是 emoji
      break;
    case 'mcp':
      // 处理 MCP payload
      break;
  }
}
```

## 3.6 OPUS 编解码

```dart
// lib/audio/opus_codec.dart
import 'package:opus_dart/opus_dart.dart';

class OpusCodec {
  late final OpusEncoder _enc;   // 16 kHz 上行
  late final OpusDecoder _dec;   // 24 kHz 下行

  Future<void> init() async {
    _enc = OpusEncoder(sampleRate: 16000, channels: 1, application: Application.voip);
    _dec = OpusDecoder(sampleRate: 24000, channels: 1);
  }

  /// PCM16 (16k, 960 samples = 60ms) → OPUS
  Uint8List encode(Int16List pcm16k) => _enc.encode(pcm: pcm16k);

  /// OPUS → PCM16 (24k, 1440 samples = 60ms)
  Int16List decode(Uint8List opus) => _dec.decode(input: opus);
}
```

> **帧长换算**（务必对齐，否则声音会卡顿/变调）：
> - 上行：16000 Hz × 0.060 s = **960 samples/帧**
> - 下行：24000 Hz × 0.060 s = **1440 samples/帧**
> - 若播放器只支持 16 kHz，需对 24 kHz PCM 做重采样（可用 `samplerate` 包或线性插值）

## 3.7 音频采集（必须开 AEC）

```dart
// lib/audio/audio_capture.dart
import 'package:record/record.dart';

class AudioCapture {
  final _rec = AudioRecorder();

  /// ⚠️ 必须用 voiceCommunication —— 这是 Android 硬件 AEC 通路
  /// 否则播放 TTS 时用户无法用唤醒词打断（对应硬件 AEC 的核心作用）
  Future<Stream<Uint8List>> start() async {
    if (!await _rec.hasPermission()) throw Exception('无麦克风权限');
    return await _rec.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      device: null,
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication, // ⭐ AEC
      ),
    ));
  }

  /// 按 60ms 切片 → 每片 960 samples = 1920 bytes (PCM16)
  Stream<Int16List> frames(Stream<Uint8List> raw) async* {
    final buf = BytesBuilder();
    await for (final chunk in raw) {
      buf.add(chunk);
      final bytes = buf.takeBytes();
      // 累积到 1920 字节则吐出一帧
    }
  }

  Future<void> stop() => _rec.stop();
  void dispose() => _rec.dispose();
}
```

## 3.8 状态机（对齐硬件 `device_state_machine.cc`）

```dart
// lib/state/device_state_machine.dart
enum DeviceState {
  idle,        // 待唤醒
  connecting,  // 建连中
  listening,   // 录音中（对应硬件 LED 亮起）
  thinking,    // 等待服务端（ASR → LLM）
  speaking,    // TTS 播放中
  activating,  // 待激活（显示激活码）
  error,
}
```

状态迁移与音效/表情联动：

| 迁移 | 触发 | 动作 |
|------|------|------|
| `idle → connecting` | 启动/重连 | 播 `welcome.ogg` |
| `connecting → activating` | OTA 返回 activation.code | 显示激活码页面 |
| `activating → idle` | 激活完成 | 播 `success.ogg` |
| `idle → listening` | 唤醒词/按键 | 播 `popup.ogg`，上报 `listen(detect)` |
| `listening → thinking` | `listen(stop)` 或 VAD 结束 | 表情 → `thinking 🤔` |
| `thinking → speaking` | `tts(start)` | 表情随 `llm.emotion` 更新 |
| `speaking → idle` | `tts(stop)` | 表情 → `neutral 😶` |
| `speaking → listening` | 唤醒打断 | 发 `abort(wake_word_detected)` |
| `any → error` | WS 错误 | 播 `err_reg.ogg` / `err_pin.ogg`，重连 |
| `idle → (休眠)` | 5/10 min 无有效录音 | 播 `low_battery.ogg` 类提示音，释放录音+断连 |

### 休眠策略（复用乐鑫指南）
```dart
static const idleTimeout = Duration(minutes: 5);  // 或 10 分钟
// 超时 → 播放"我要休息了哦" → 停止录音 → 关闭 WS → 进入 idle 低功耗
```

## 3.9 UI 层：对齐 CoreS3 屏幕

硬件 CoreS3 使用 **LVGL** + `xiaozhi-fonts (2.0.0)` 中文字体，配置：
- `CONFIG_USE_DEFAULT_MESSAGE_STYLE=y` → **默认气泡样式**（非微信风）
- `CONFIG_USE_MULTILINE_CHAT_MESSAGE=n` → **单行聊天气泡**
- 表情：`emote_display.cc` + `emoji_collection.cc`

Flutter 对齐建议：
| 硬件元素 | Flutter 组件 |
|---------|-------------|
| LVGL 状态栏（WiFi/电量/时间） | `AppBar` + 自定义 `StatusBar` |
| 聊天气泡（default 样式，单行） | `ChatBubble`，最大宽度 75%，圆角 12 |
| 表情动画（`emote_display`） | `rive` / Lottie，按 21 种 emotion 切换 |
| 底部状态提示（"聆听中…"/"说话中…"） | `AnimatedContainer` + 波纹动画 |
| 大按钮（按键对话） | `GestureDetector` + 长按录音 |
| 激活码页 | 大号数字 `Text` + 说明文案 |

**状态与表情映射（示例）：**
```dart
const emotionAssets = {
  'neutral': '😶', 'happy': '🙂', 'laughing': '😆', 'funny': '😂',
  'sad': '😔', 'angry': '😠', 'crying': '😭', 'loving': '😍',
  'embarrassed': '😳', 'surprised': '😲', 'shocked': '😱',
  'thinking': '🤔', 'winking': '😉', 'cool': '😎', 'relaxed': '😌',
  'delicious': '🤤', 'kissy': '😘', 'confident': '😏',
  'sleepy': '😴', 'silly': '😜', 'confused': '🙄',
};
```

## 3.10 Android 权限与清单

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>

<!-- 音频 AEC 相关（部分 ROM 需要） -->
<uses-feature android:name="android.hardware.microphone" android:required="true"/>

<application android:usesCleartextTraffic="true">   <!-- 若测试用 ws:// 非加密 -->
  <service android:name="com.ryanheise.audioservice.AudioService"
           android:foregroundServiceType="microphone"/>
</application>
```

> ⚠️ **运行时权限**：`Permission.microphone.request()`（Android 6+）
> ⚠️ **后台录音**：Android 10+ 需 `foregroundServiceType="microphone"`，否则退后台即被掐断

---

# 第四部分 · 对齐清单与待确认项

## 4.1 硬件 ↔ Flutter 参数对照总表

| 维度 | 硬件（M5Stack CoreS3） | Flutter APP |
|------|----------------------|-------------|
| 芯片/算力 | ESP32-S3 dual-core 240 MHz | 手机 SoC（充裕） |
| 内存 | Quad PSRAM + 16 MB Flash | 系统内存 |
| **协议版本** | `Protocol-Version: 1` | `1`（严格一致） |
| **传输** | WebSocket | WebSocket（`wss://`） |
| **音频编码** | OPUS | OPUS |
| **上行采样率** | 16000 Hz / 1ch / 60 ms | 16000 Hz / 1ch / 60 ms |
| **下行采样率** | 24000 Hz / 1ch / 60 ms | 24000 Hz / 1ch / 60 ms |
| 上行每帧采样 | 960 samples | 960 samples（1920 B PCM16） |
| 下行每帧采样 | 1440 samples | 1440 samples（2880 B PCM16） |
| 唤醒词 | wakenet `wn9l_nihaoxiaozhi_tts3` | Porcupine / 按键 / 服务端 VAD |
| AEC | esp_audio_effects + 硬件回采 | `voiceCommunication` 硬件 AEC |
| VAD | 服务端（`auto`/`realtime` 模式） | 服务端 |
| 设备 ID | MAC 地址 | Android ID → 伪 MAC |
| 客户端 ID | UUID v4（Flash 存储） | UUID v4（SharedPreferences） |
| User-Agent | `m5stack-core-s3/2.4.2` | 同左或自定义 |
| 摄像头 | GC0308 320×240@20fps YUV422，H/V 镜像 | `camera` 包，720p+，需手动镜像 |
| 显示 | LCD + Touch，LVGL | Flutter Widget |
| 表情 | `emote_display` / `emoji_collection` | Rive / Lottie |
| 提示音 | 固件内 17 个 ogg | `assets/audio/` 同名 ogg |
| 消息样式 | default（非微信风），单行 | 同左 |
| 配网 | 热点配网 | 无需（手机本来联网） |
| OTA | 双分区（ota_0/ota_1） | 应用商店更新 |
| MCP | `mcp_server` + `press_to_talk_mcp_tool` | MCP 客户端，可暴露手机能力 |
| 休眠 | DeepSleep <10 µA / LightSleep <700 µA | 释放录音 + 断 WS |

## 4.2 开发路线（建议 MVP → 完整）

| 阶段 | 目标 | 关键里程碑 |
|------|------|-----------|
| **P0** | 打通链路 | OTA 激活 → WS 握手 → 按键对话（manual）→ 听到 TTS |
| **P1** | 音频完善 | OPUS 双采样率正确、AEC 生效（播放中可打断）、VAD auto 模式 |
| **P2** | 交互完整 | 21 种表情、字幕逐句、状态机、断线重连、提示音 |
| **P3** | 增强 | 唤醒词（Porcupine）、MCP 工具、摄像头视觉、MQTT 通道 |

## 4.3 ⚠️ 待确认 / 待补充项

| # | 项目 | 说明 | 优先级 |
|---|------|------|--------|
| 1 | **服务器地址** | 示例中 `api.tenclass.net` 为公共/社区服务。自建服务器需确认 `OTA 地址` + `WS 地址` | 🔴 高 |
| 2 | **access_token 来源** | WS 头的 `Bearer <token>` = OTA 响应的 `websocket.token`，需确认是否长期有效/过期刷新 | 🔴 高 |
| 3 | **心跳机制** | 文档未明确 ping/pong 间隔，需抓包或查源码确认（建议 30 s） | 🟡 中 |
| 4 | **ASR 结果消息格式** | 文档未列出"识别结果"的具体 JSON type（可能是 `stt` 或 `asr`），需抓包确认 | 🔴 高 |
| 5 | **MCP Payload 结构** | `payload` 为任意对象，需查 `mcp_server.cc` 确定工具声明格式 | 🟡 中 |
| 6 | **激活轮询接口** | 激活码输入后，APP 如何知道已激活？需确认轮询/回调接口 | 🟡 中 |
| 7 | **24 kHz 播放兼容** | 若 `just_audio` 不支持 24 kHz PCM，需重采样方案 | 🟡 中 |
| 8 | **realtime 模式 AEC** | 需实测 Android 硬件 AEC 是否足以支撑全双工 | 🟡 中 |
| 9 | `elf_sha256` 取值 | APP 无 ELF，可填 APK 签名哈希或留空，需服务端容忍 | 🟢 低 |
| 10 | SSL 证书 | `wss://` 若自建证书需处理信任问题 | 🟢 低 |

## 4.4 源码对照索引（硬件端实现，逆向参考）

```
main/
├── protocols/
│   ├── protocol.cc               # 协议抽象基类
│   ├── websocket_protocol.cc     # ⭐ WebSocket 实现（APP 主要对标）
│   ├── mqtt_protocol.cc          # MQTT 实现
│   └── text_glyph_payload.cc     # 文本/字形
├── ota.cc                        # ⭐ OTA 激活流程（对标 2.2 节）
├── mcp_server.cc                 # ⭐ MCP 服务器（对标 2.4 ④）
├── application.cc                # 主应用逻辑
├── device_state_machine.cc       # ⭐ 状态机（对标 3.8 节）
├── system_info.cc                # 系统信息（对应 OTA 上报字段）
├── settings.cc                   # 设置持久化
├── audio/
│   ├── engines/afe_audio_engine.cc   # AFE 音频引擎（对标 AEC）
│   └── wake_words/
│       ├── wake_word_audio_cache.cc
│       └── custom_wake_word.cc
├── display/
│   ├── emote_display.cc          # 表情显示（对标 21 种 emotion）
│   ├── lcd_display.cc
│   ├── oled_display.cc
│   └── lvgl_display/
│       ├── emoji_collection.cc   # 表情集合
│       ├── lvgl_theme.cc
│       └── lvgl_image.cc
└── boards/
    ├── common/
    │   ├── wifi_board.cc
    │   ├── press_to_talk_mcp_tool.cc  # 按键对话 MCP 工具
    │   ├── power_save_timer.cc        # 省电定时器（对标休眠）
    │   ├── adc_battery_monitor.cc
    │   └── button.cc
    └── m5stack/core-s3/
        ├── m5stack_core_s3.cc
        └── cores3_audio_codec.cc      # CoreS3 音频编解码
```

---

## 📌 一句话总结

**Flutter APP = 设备身份（伪MAC + UUID） + OTA 激活（拿 WS 地址/token） + WebSocket 协议 v1（hello/listen/tts/abort/mcp/llm） + OPUS 双采样率音频（16k↑ / 24k↓ / 60ms） + Android 硬件 AEC（保证打断） + 21 种表情 + 状态机 + 17 个提示音。**

协议层面硬件与 APP **完全一致**，差异仅在：
- 唤醒词实现（wakenet vs Porcupine/按键）
- AEC 载体（esp_audio_effects vs Android voiceCommunication）
- 显示（LVGL vs Flutter）
- 配网/OTA（硬件烧录 vs 应用商店）

---

*文档版本：v2.0（整合编译日志 + v2.2.4 发布说明 + 乐鑫硬件指南 + WS 协议 v1 + OTA API）*
*最后更新：2026-09-09 20:20 GMT+8*
