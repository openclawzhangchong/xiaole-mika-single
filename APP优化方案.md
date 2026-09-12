# 小乐 App 优化方案（基于《xiaoleweb.md》技术全景）

> **依据**：`xiaole-web-2027/xiaoleweb.md`（17 章技术全景，协议知识与 36 条避坑清单均经实测验证）  
> **对象**：`xiaole-client-flutter-2027`（当前 pubspec `1.1.7+8`，真机基线 v1.1.6/v1.1.7）  
> **性质**：审批稿。批准后按批次实施，每批一个版本走 CI 发 APK。



---

## 一、诊断总览：App 现状 vs 网页版能力对照

逐项核对 Flutter 源码后的差距清单（证据 = 文件:行号，可直接定位）：

| #  | 能力              | 网页版                                                | App 现状                                                                              | 证据                                                        | 评级    |
| -- | --------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------- | ----- |
| 1  | MCP 设备工具响应      | 11 项工具，AI 真实操控                                     | **`case 'mcp'` 是空 TODO**——hello 已声明 `features.mcp:true`，服务器发 initialize 后石沉大海       | chat_page.dart:804-807；xiaozhi_websocket_manager.dart:201 | 🔴 P0 |
| 2  | TTS 边界兼容        | stop/end 双兼容                                       | **只处理 `end`**——实测服务器发的是 `stop`，AI 播完后 `_isAiPlaying` 可能永不复位 → 麦克风数据停发 →「第二句听不见」     | chat_page.dart:779-786                                    | 🔴 P0 |
| 3  | 情绪表情            | llm → emoji 前缀                                     | **无 `case 'llm'`**，AI 情绪全丢                                                          | chat_page.dart:758-830（switch 无此分支）                       | 🟡 P1 |
| 4  | MCP 字幕过滤        | stripMcpMarkers                                    | **无过滤**，`% get_weather` 标记直接进气泡                                                     | chat_page.dart:767-777                                    | 🟡 P1 |
| 5  | listen mode 一致性 | 三处必须一致                                             | **混用**：按住说话 start/stop 用 `auto`（851/875），持续监听用 `realtime`（899/923）——若两链路交叉，VAD 语义错乱 | chat_page.dart:851,875,899,923                            | 🔴 P0 |
| 6  | 打断/挂断 abort     | 先 abort 再 stop                                     | **无 abort**——AI 说话中挂断，服务器继续合成下发                                                     | chat_page.dart 全文无 abort                                  | 🟡 P1 |
| 7  | 重连策略            | 指数退避 1s→30s、12 次上限、close code 分类、网络恢复即时重连、手动断开不重连  | **固定 3 秒无限重连**，无退避无上限无分类（1005 idle 回收/432x 身份拒绝会被无脑重连轰炸）                            | xiaozhi_websocket_manager.dart:27,278-303                 | 🔴 P0 |
| 8  | 想打就打（自动连接）      | ensureConnected+pending 回调                         | 未连接时**只弹错误提示**（836/865/889 三处），要用户手动去连                                              | chat_page.dart:836,865,889                                | 🟡 P1 |
| 9  | 设备身份规范          | board=application=`m5stack-core-s3`（解锁 MCP/表情/VAD） | **board 用手机型号**（`deviceModel.toLowerCase()`）——正是 xiaoleweb.md 避坑 #4：自造标识被服务端阉割能力    | xiaozhi_ota_service.dart:421-432                          | 🔴 P0 |
| 10 | 周期性状态上报         | WS 连接即报+每 10 分钟                                    | **只在激活时请求一次**，之后从不上报（后台「最近活跃」不刷新）                                                   | xiaozhi_ota_service.dart（无周期逻辑）                           | 🟡 P1 |
| 11 | MQTT 常驻在线       | 有（经 worker TCP 桥）                                  | **无**——App 原生可直接 TLS 连 8883，比网页还简单                                                  | 全仓无 mqtt 依赖                                               | 🟢 P2 |
| 12 | 视觉识物            | 多帧选亮+富气泡+JSON 解析                                   | **无**（image_picker 已在依赖里，接入成本低）                                                     | —                                                         | 🟢 P2 |
| 13 | 播放音量控制          | masterGain+set_volume 工具联动                         | 无独立 TTS 音量控制                                                                        | audio_util.dart                                           | 🟢 P2 |
| 14 | barge-in 抢话打断   | 能量检测 4 帧                                           | 无（AI 播放期间仅静默丢弃麦克风数据）                                                                | chat_page.dart:816-819                                    | 🟢 P2 |
| 15 | 聊天记录持久化         | IndexedDB 全量                                       | ✅ 已有（v1.1.6）                                                                        | —                                                         | 已达成   |
| 16 | hello 格式        | features.mcp+完整 audio_params                       | ✅ 已正确                                                                               | xiaozhi_websocket_manager.dart:198-211                    | 已达成   |
| 17 | MAC 小写          | 强制小写                                               | ✅ 已修（v1.1.7）                                                                        | —                                                         | 已达成   |

**一句话诊断**：App 的「连接与音频」底座是好的（hello 正确、realtime 监听已有、录音播放链路完整），但 **MCP 整条链路是空的**、**若干协议细节与实测服务器行为不符（stop 边界/board 身份/重连轰炸）**、**网页版 v3.x 的一批体验能力尚未移植**。

---

## 二、红线政策 v2：三级制（2026-09-09 用户批准，取代原「区域冻结」）

> 原红线的本质是用「区域冻结」替代「理解不足」。现协议知识已沉淀为 xiaoleweb.md（含协议速查表+36 条避坑清单），护栏升级为风险分级：

| 级别 | 范围 | 规则 |
| --- | --- | --- |
| 🔒 **绝对冻结** | `xiaozhi_device_info_util.dart`（MAC/ClientID 生成）、OTA appName `ajb_agent_flutter`、音频编解码/采样率/缓冲参数 | 无必要不动——出错代价最高（身份失效需重新绑定）或对端黑盒不可验证 |
| ⚠️ **条件修改** | `lib/core/network/`（websocket_manager/ota_service 等） | 允许修改，但每次必须：①对照 xiaoleweb.md §16 协议速查表逐字段核对；②真机冒烟清单；③diff 逐行评审登记 |
| ✅ **自由区** | `lib/presentation/`、新增文件、`lib/data/`（加字段必须带默认值，存量数据可读迁移） | 常规开发流程 |

- 保留 `git diff <锚点> -- lib/core/ lib/data/` 作为**评审触发器**（不再要求为空，改为逐行登记）。
- 回滚锚点：**tag `stable-1.1.7`**（= commit 384c5f47e7，真机验证通过的基线）。

## 版本规划（用户指定）：3.0.x 实践期 → 4.0 正式版

| 批次 | 版本 | 内容 |
| --- | --- | --- |
| P0 | **v3.0.0** | 通信正确性四项（本章第三节） |
| P1 | **v3.1.0** | 身份对齐+周期上报 / 想打就打 / 情绪+过滤+abort / 视觉识物 |
| P2 | **v3.2.0 ~ v3.9.9** | MQTT 常驻 / take_photo / 音量 / barge-in / 开发者开关页（可拆多版） |
| 收官 | **v4.0.0** | 全部落成并实测验收后的正式版 |

---

## 三、第一批 P0：通信正确性修复（目标版本 v3.0.0）

> 原则：先让「已经声明的能力」真正工作、把「与实测服务器行为不符」的地方修正。全部是低风险高收益项。

### P0-1 TTS 边界双兼容 + 播放状态全链路核对 🔴

- **改法**：`tts` 分支增加 `state == 'stop'` 与 `'end'` 等价处理（网页版实测服务器发 `stop`）；同时核对 `_isAiPlaying` 的置位点（应在 `tts start`）与复位点全链路。
- **参考**：xiaoleweb.md §2.4 下行分发表；web `onWsMessage` tts 分支。
- **验收**：真机连续对话 10 轮，每轮 AI 说完后无需任何操作即可继续说第二句。

### P0-2 listen mode 统一 🔴

- **改法**：按住说话链路（`_handleAudioStart/Stop`）保持 `auto` 成对；持续监听链路保持 `realtime` 成对；确保两条链路**不交叉发送**（如录音停止时误发另一模式的 stop）。移除 `session_id` 字段（网页版实测不需要，减少变量）。
- **参考**：xiaoleweb.md §2.4 mode 铁律。
- **验收**：两条链路分别连测 5 轮无「第二句听不见/挂断才断句」。

### P0-3 重连策略升级（需红线例外 C）🔴

- **改法**（改 `xiaozhi_websocket_manager.dart` 一处逻辑，接口不变）：
  - 固定 3s → **指数退避 1s×2^n 封顶 30s，最多 12 次**；
  - `onDone` 采集 closeCode 分类：**1005=静默回收（正常，静默重连）**、**4326/4327/4328=身份拒绝（停止重连+明确提示）**、1006=提示切直连/查头；
  - 监听 connectivity 变化，**网络恢复立即重连**（跳过退避）；
  - 增加 `manualClosed` 标志：用户主动断开永不自动重连。
- **参考**：xiaoleweb.md §2.6；web `scheduleReconnect()` 可整体翻译成 Dart。
- **验收**：飞行模式 10s 恢复 → 2s 内重连成功；服务器拒绝身份时只提示不轰炸。

### P0-4 MCP 设备端响应器（红线内新增文件 B）🔴★本批主角

- **改法**：
  - 新增 `lib/core/network/xiaozhi_mcp_responder.dart`：应答服务器 `initialize` / `tools/list` / `tools/call`（协议格式照抄 xiaoleweb.md §5.1：`{type:'mcp',payload:{jsonrpc,id,result:{content:[{type:'text',text:'<JSON>'}]}}}`）；
  - 首批注册 **8 项工具**：`get_device_status` / `set_volume` / `set_theme` / `timer.create_countdown|get_tasks|stop_task` / `schedule.create_event|get_events|delete_event`（take_photo/preview_image 放 P1，依赖拍照与识图链路）；
  - 真实效果映射（移动端比网页更原生）：set_volume→播放器音量、set_theme→themeProvider、定时器/日程到点→**系统通知 + TTS 播报**（App 有真 TTS 播放链路，比网页 speechSynthesis 更正规）；
  - `chat_page.dart` 的空 `case 'mcp'` 挂上响应器（带开关位，默认开？——见审批点 3）。
- **参考**：xiaoleweb.md §5 全章；web `mcpToolList()/mcpExecTool()/handleMcpServerRequest()` 可逐行翻译。
- **验收**：语音说「把音量调到 20」「定个 1 分钟倒计时」，AI 调用工具后**真实生效**并收到正确应答（日志可见 tools/list 上报 8 项）。

### P0 批验收

冒烟：连接→连续对话 10 轮 / 飞行模式重连 / 语音触发 set_volume 与 timer / `git diff` 红线核对。版本 3.0.0+9，tag `v3.0.0`（触发 CI），APK 下载到桌面。

---

## 四、第二批 P1：能力对齐（目标版本 v3.1.0）

### P1-1 设备身份对齐 + 周期状态上报（需红线例外 C）🔴

- **改法**（改 `xiaozhi_ota_service.dart`）：`boardType/boardName` 不再用手机型号，统一 `m5stack-core-s3`（board 名含机型信息移到别处或弃用——**OTA appName `ajb_agent_flutter` 保持不动**，红线不动）；补 `flash_size: 16777216 / psram_size: 8388608 / chip_model_name: esp32-s3`；新增 `reportStatus()`：WS 连接即报 + 每 10 分钟周期报（带真实电量，device_info_plus+battery_plus）。
- **参考**：xiaoleweb.md §2.3 请求体模板、§2.3 周期上报。
- **⚠️ 风险**：已激活设备改 board 后服务器侧认知变化——网页版同款迁移实测无害（存量自动迁移即好）；若极小概率 432x，重新绑定即可。**见审批点 2。**
- **验收**：语音问「你是什么设备」；xiaozhi.me 后台「最近活跃」随 App 打开刷新。

### P1-2 想打就打（不碰红线）

- **改法**：chat_page 三处「未连接」错误 → `ensureConnected(原操作)`：自动连接，hello ACK 后自动发原文字/自动开录音/自动进通话；失败路径（重连超限/432x/手动断开）取消 pending。
- **参考**：xiaoleweb.md §2.6；web `ensureConnected/runPendingAutoAction/cancelPendingAutoAction`。
- **验收**：杀 App 重开，直接发文字 → 自动连上并发出。

### P1-3 情绪表情 + MCP 字幕过滤 + 挂断 abort（不碰红线）

- llm 情绪 → emoji 前缀进 AI 气泡（happy/laughing/cool/sad/angry 五映射）。
- `stripMcpMarkers` 等价实现：正则剥离 `% 工具名`（数字前 % 不误伤），纯标记句不渲染。
- 挂断/断开时若 AI 在播 → 先发 `{type:'abort'}` 再 listen stop。
- **验收**：触发天气类工具，字幕无 `% xxx`；AI 说话中挂断日志见 abort。

### P1-4 视觉识物（不碰红线，新增页面/组件）

- 复用 `image_picker` 拍照/相册 → **多帧选亮在移动端可简化**（原生相机已就绪，无网页黑帧问题）→ multipart POST vision 接口（vision url/token 从 MCP initialize `params.capabilities.vision` 提取，依赖 P0-4）→ 结果 JSON 提取 `.text` 进 AI 气泡，缩略图+问题进用户气泡。
- **参考**：xiaoleweb.md §7。
- **验收**：拍桌物 → AI 正确描述；存本地聊天可回看。

### P1 批验收

同 P0 流程。版本 3.1.0+10，tag `v3.1.0`。

---

## 五、第三批 P2：体验增强（目标版本 v3.2.0 起，可拆多版，按需裁剪）

| 项    | 内容                                                                                                                                                                   | 参考   |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| P2-1 | **MQTT 常驻在线**：App 原生 TLS 直连 8883（无需 worker 桥！`mqtt_client` 包），240s 心跳+自动重连，收后台下发的 MCP/配置消息转响应器——**后台显示在线+远程主题/音色自定义解锁**。注意 EMQX 同 clientId 高频重连限流（xiaoleweb.md §6.2） | §六   |
| P2-2 | **take_photo / preview_image 补齐**：AI 主动调相机（前台弹拍照页）+ AI 发图进气泡，凑齐 11 项工具                                                                                               | §五   |
| P2-3 | **TTS 音量独立控制**：flutter_pcm_sound 音量接口（待核验 API 名）+ 设置页滑杆，与 set_volume 工具联动                                                                                            | §4.2 |
| P2-4 | **barge-in 抢话打断**：AI 播放期间持续 RMS 监测（record 静默流），连续 4 帧>0.025 → abort；feature flag 可关                                                                                  | §4.3 |
| P2-5 | **开发者开关页**：MCP/上报/识物/barge-in/MQTT 各自独立开关（照搬网页版 7 开关模式，默认关可灰度）                                                                                                       | §十一  |

---

## 六、测试与交付流程（每批相同）

1. 实施前 `git diff <上✅tag> -- lib/core/ lib/data/` 基线确认为空（例外项登记）。
2. 静态：`flutter analyze` 零新增 error；单元：MCP 应答 JSON 格式对拍测试（与 xiaoleweb.md §16 速查表逐字段比对）。
3. UI 回归：golden 截图审计（既有 `test/goldens/` 基线，涉及 UI 改动时更新）。
4. 真机验证清单随批给出（见各批验收）。
5. 版本号自动递增、CI tag 触发、失败新建 tag 不复用、APK 下载到桌面字节校验。
6. 归档：README 版本档案 + PLAN + 记忆。

---

## 七、审批点汇总（请逐项拍板）

| # | 决策                                                                                                               | 建议                                                             |
| - | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| 1 | ~~红线例外~~ → 已升级为**三级红线制**（第二节），通信/OTA 层条件修改 | **已批准** | `xiaozhi_websocket_manager.dart`（仅重连逻辑段）与 `xiaozhi_ota_service.dart`（仅身份参数+新增上报方法），其余全部走「新增文件不改既有文件」 | **批准**（v1.1.6 已有先例，且这是修正确性问题）                                  |
| 2 | ✅ **board 身份对齐** `m5stack-core-s3`（放弃手机型号标识）                                                                       | **批准**——这是解锁 MCP/表情/VAD 的钥匙；OTA appName `ajb_agent_flutter` 不动 |
| 3 | ✅ **MCP 工具开关默认态**                                                                                                  | 建议**默认开**（App 是你个人设备，无多用户灰度诉求）；若求稳可选默认关+设置页开                   |
| 4 | ✅ **MQTT 常驻做不做**（P2-1）                                                                                             | **做**——App 原生直连比网页还简单，且解锁后台自定义主题                               |
| 5 | ✅ **批次节奏**：P0→v3.0.0、P1→v3.1.0、P2→v3.2.0~3.9.9，每批实测验收后再下一批；全部落成后发正式版 **v4.0.0**                                                               | **同意**                                                         |

**回复「同意」= 五项全批，我从 P0 开始；对任何一项有不同意见，单独说明即可，其余照常开工。**
