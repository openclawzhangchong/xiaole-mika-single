# 小乐 App v4.4.0 方案（V2 · ✅ 已实施并发布）：AI「自问自答」修复

> ✅ **已实施（本文档为历史方案，冻结存档）**：本方案对应版本 **`v4.4.0`** **已发布**。
> 最新进度以仓库根 `进度与续接.md` 为准。

- 目标版本：**v4.4.0+23**
- 提出日期：2026-09-12
- 状态：**✅ 已实施并发布**（原为"等待审批"）
- 版本说明：V1 提交后张老师提出两点改进 → 本 V2 已写入：
  ① 录音源**不写死常量**，改为**开发者中心可切换开关**（真机可随时 A/B 对比、随时回退，**无需重新发版**）；
  ② 日志分类**默认开启 🔊 音频**（本次是音频问题，复现即可验证）。
- 问题：AI 说话的**最后一个字**被识别成用户说话 → AI 自己接自己的话。早几版无此现象，近期版本出现。
- 已拍板决策：① **关闭抢话打断（barge-in）** ② **录音源改为可切换开关，默认开启 AEC 通路** ③ **尾音保护默认 300ms，开发者中心可调 100–500ms** ④ **日志分类默认打开 🔊 音频**

---

## 一、现象

语音通话/持续对话中，AI 说完后，**它的最后一个字（或尾音）被当成用户说话**上传给服务器，
服务器 ASR 识别后，AI 又接着自己的话往下说（自问自答）。用户并未开口。

---

## 二、根因（三条叠加，均已在代码中定位）

> 网上常见的两种说法——**"加 TTS 延时"**与**"优化 AEC/VAD"**——**都对，但各治一半**。下面把三条根因摊开。

### 根因 ①【主因·症状层】AI 播放"结束"判定早于实际播完，尾音被上行

| 代码位置 | 行为 |
|---|---|
| `chat_page.dart:1577` | 收到音频后 **500ms 没新数据** → 判定"播放结束"（这是**收包侧**判断） |
| `chat_page.dart:1625–1635` | 收到 `tts stop/end` → **立即**置 `_isAiPlaying = false` |
| `chat_page.dart:1789–1794` | `_isAiPlaying` 一变 false，**立刻**把麦克风音频上行给服务器 |

**问题**：前两条是"收包侧"信号，而**扬声器缓冲区里最后几个字还在播**。
于是：AI 最后几个字的尾音 → 被麦克风收录 → 上行 → 服务器 ASR 当成"用户开口" → AI 接自己的话。

**这精确解释了"为什么总是最后一个字"**：前面那些字因为不上行（1791 行 return）根本不会进 ASR，
**只有刚判定结束那一刻、还在缓冲区里的尾音**会被抓到。

### 根因 ②【根因·根本层】AEC 实际未生效，扬声器声音被麦克风收录

| 代码位置 | 现状 |
|---|---|
| `audio_util.dart:117` | **播放**侧已配 `AndroidAudioUsage.voiceCommunication`（通话通路）✅ |
| `audio_util.dart:253–263` | **录音**侧 `RecordConfig` **完全未配 `androidConfig`** ❌（全项目零命中） |

查 `record_platform_interface-1.6.0/lib/src/types/android_record_config.dart`：
```dart
class AndroidRecordConfig { ... final AndroidAudioSource audioSource; ... }
const AndroidRecordConfig({ ..., this.audioSource = AndroidAudioSource.defaultSource, ... });
                                                    // ↑ 当前实际取值就是 defaultSource
enum AndroidAudioSource { ..., voiceCommunication, ... }
```

**即：录音源实际是 `defaultSource`，与播放侧的 `voiceCommunication` 通路不匹配 → 硬件 AEC 走不通。**
（`echoCancel: true` 只是在请求里带了个标志，真正生效依赖 Android 的音频通路。）

### 根因 ③【放大器】v3.2.0 引入的「抢话打断（barge-in）」

| 代码位置 | 行为 |
|---|---|
| `chat_page.dart:1170–1189` | AI 说话期间监听**麦克风振幅**，连续 4 次（约 400ms）> `0.36` → 触发 |
| `chat_page.dart:1179` | 一旦触发：`_isAiPlaying = false` → **立即恢复上行** + 发 `abort` |

**问题**：这个振幅是**未经回声消除的原始信号**（根因②）。AI 说话时麦克风必然收到扬声器声音 →
**振幅必然超标 → 误触发** → 提前恢复上行 → 把 AI 自己的声音送上去。

**时间线吻合**：barge-in 是 **v3.2.0** 引入的，此前 AI 说话期间不会提前恢复上行 → 所以"早几版没问题" ✓
**张老师判断"是不是语音打断导致的"——方向正确，它是主要诱因之一。**

---

## 三、可行性验证（已全部确认，零新增依赖）

| 项 | 结论 |
|---|---|
| `AndroidRecordConfig` / `AndroidAudioSource.voiceCommunication` | ✅ 存在于 `record_platform_interface` 1.6.0 |
| 是否需要新增依赖 | ✅ **不需要**。`record-6.2.1/lib/record.dart:2` 已 `export 'package:record_platform_interface/record_platform_interface.dart';`，`package:record/record.dart` 可直接用（项目已 import） |
| Android 权限 | ✅ `RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS` 均已在 `AndroidManifest.xml` 声明 |
| 播放侧通路 | ✅ 已是 `voiceCommunication`，只需录音侧对齐 |

---

## 四、修复方案（三个模块）

### 模块 1：关闭抢话打断（barge-in）

1. `chat_page.dart` `_startVoiceCall()`：**不再订阅** `AudioUtil.amplitudeStream`（去掉 `_bargeinSub` 订阅）；
2. `_onAmplitudeForBargeIn` 保留但**停用**（方法头注明"v4.4.0 起停用，原因见本方案根因③"），保留代码便于日后需要时恢复；
3. `app_feats.dart`：`bargein` 默认值改为 `false`；
4. 开发者中心：**移除**「🎤 抢话打断」开关（避免出现一个无效的开关造成困惑；代码保留可回退）。

> 副作用（需知晓）：关闭后**通话中无法用说话打断 AI**；若要停止 AI，只能用挂断或等它说完。

### 模块 2：录音源改为**可切换开关**（默认开启 AEC 通路）

> **V2 改进**：不写死常量，做成开发者中心开关——真机可随时 A/B 对比，不满意直接关掉，
> **无需重新发版**。这比"改回一个常量再发一版"高效得多，也便于在不同机型上试出最优解。

1. `lib/core/utils/audio_util.dart`：
   - 新增静态开关 `useAecSource`（默认 `true`），并用 `StorageService` 持久化（键 `audio_aec_source`）；
   - `RecordConfig`（约 253 行）按开关决定录音源：
     ```dart
     androidConfig: AndroidRecordConfig(
       audioSource: AudioUtil.useAecSource
           ? AndroidAudioSource.voiceCommunication  // 与播放侧(117行)对齐 → 硬件 AEC 通路
           : AndroidAudioSource.defaultSource,      // 原行为（V1 之前的实际取值）
     ),
     ```
   - `echoCancel / noiseSuppress / autoGain` 保持现有 `enableAEC` 控制不变（调用点均已传 `true`）；
2. 开发者中心「能力开关」分组新增开关：
   - 标题：**「🎧 通话降噪通路（AEC）」**
   - 副标题："开启＝走通话音频通路以启用硬件回声消除（消除 AI 尾音误识别；少数机型音色略闷）；关闭＝恢复原录音源"
   - **默认：开启**；副标题注明"下次录音/通话生效"
3. **为何不并入 `AppFeats`**：`AppFeats.allOff()`（"全部关闭"＝普通用户模式）会把所有开关一并关掉，
   而 AEC 属于**基础收音质量**，不是"开发者增强功能"，不应因"全部关闭"而失效 → 使用**独立存储键**。

### 模块 3：尾音保护（Tail Guard）——默认 300ms，可调 100–500ms

1. 新增持久化配置 **「尾音保护时长」**：默认 **300ms**，范围 **100–500ms**
   （键沿用既有风格，如 `tail_guard_ms`，存 `StorageService`）；
2. `chat_page.dart`：AI 播放结束的两个入口（TTS `stop/end` 的 1625 段、500ms 超时的 1577 段）
   在置 `_isAiPlaying = false` 时，记录：
   ```dart
   _resumeGuardUntil = DateTime.now().add(Duration(milliseconds: tailGuardMs));
   ```
3. `_handleAudioSend()` 开头增加：
   ```dart
   if (_resumeGuardUntil != null && DateTime.now().isBefore(_resumeGuardUntil!)) return; // 丢弃尾音
   ```
4. 开发者中心新增**「尾音保护」滑块**（100–500ms，默认 300，带说明文字：
   "AI 说完后，等待多久再恢复采集；调大可减少误识别，调小更灵敏"）。

> 说明：这样实现是"**丢弃恢复上行后前 N 毫秒的音频**"，比"延后恢复上行"更简单可靠，
> 也不影响录音流的连续性（不会因重启录音产生爆音/丢字）。

---

### 模块 4：日志分类默认开启 🔊 音频（V2 新增，张老师拍板）

`lib/core/utils/log_buffer.dart` 的 `defaultCategoryEnabled` 中 `'audio': false` → **`true`**。
- 默认开启项变为：`vision` / `ws` / `mcp` / **`audio`**（`cloud` / `ota` / `ui` 仍默认关）
- 目的：本次是音频问题，复现后即可看到"恢复采集 / 尾音保护 / 播放结束"相关记录，便于验证参数是否生效

---

## 五、【AI 建议（可选采纳）】——不属于硬性要求，可逐条取舍

1. ~~建议把 `audio` 日志分类临时打开~~ → **已由张老师拍板，列入模块 4（默认开启）**，不再作为建议。
2. **建议给尾音保护加一条日志**：每次进入/退出保护期打一行（含时长），便于确认参数生效。
3. **500ms 播放超时是否调整**：若服务器下发音頻包间隔偶发 >500ms，会误判"播放结束"，
   这既可能造成"第二句听不见"，也会让尾音保护提前开始。**建议保持 500ms 不变**，
   因为尾音保护（模块 3）已经覆盖了这段风险；若真机仍有问题再单独调。
4. **暂不建议动 VAD**：服务器端 VAD 我们无法改；端侧 VAD 目前没有引入，新增成本高风险大。

---

## 六、改动文件清单与红线

| 文件 | 区域 | 改动 |
|---|---|---|
| `lib/presentation/pages/chat/chat_page.dart` | ✅ 自由 | 停用 barge-in 订阅、尾音保护逻辑、日志 |
| `lib/presentation/services/app_feats.dart` | ✅ 自由 | `bargein` 默认 false（如保留开关键） |
| `lib/presentation/pages/dev_center_page.dart` | ✅ 自由 | 移除抢话打断开关、新增尾音保护滑块 |
| `lib/core/utils/audio_util.dart` | `lib/core/utils/` | 录音源 `androidConfig`（**已获张老师授权**） |
| `pubspec.yaml` / `app_config.dart` / `README.md` | — | 版本号 4.4.0+23、说明 |

**红线核对**：
- 🔒 冻结区（`xiaozhi_device_info_util.dart`、OTA `appName`、**音频编解码参数**）**零触碰**
  —— 注意：`audioSource` 是**音频通路**选择，**不是编解码参数**（`sampleRate`/`encoder`/OPUS 帧长才是），故不在冻结范围；
- ⚠️ 条件区 `lib/core/network/` **零改动**（audio_util 属于 `lib/core/utils/`）；
- 若张老师对"改 `lib/core/`"仍有顾虑，可在审批时把模块 2 单独去掉，只做 1+3。

---

## 七、验收清单（真机）

1. 连续对话 **5 轮以上**，AI 说完后**不再自己接话**（核心指标）；
2. 把尾音保护分别调到 **100 / 300 / 500** 各试一轮：
   - 100 若仍偶尔自问自答 → 说明需要更大值；
   - 500 若明显感觉"我说完后 AI 反应迟钝" → 说明过大；
   - 记录最适合的值（后续可设为默认）；
3. 关闭 barge-in 后，AI 说话期间**不会**再出现「🎤 已打断 AI」提示；
4. 通话音质主观评估：与修改前对比有无明显变闷/变小声；
5. 打开 🔊 音频日志分类，复现一次，日志中应能看到"恢复采集/尾音保护"相关记录；
6. **AEC 开关 A/B 对比**（V2 新增）：开发者中心「🎧 通话降噪通路（AEC）」开/关各试一轮——
   - 开启：是否不再自问自答？音色是否可接受？
   - 关闭：是否复现自问自答（用于反向确认根因②成立）？
   - 记录结论；若关闭也不复现，说明模块 3 的尾音保护已足够，AEC 开关可保持默认开作为保险。

---

## 八、实施记录（审批通过后回填）

| 项 | 内容 |
|---|---|
| 本地 commit | 待填 |
| 推送 commit | 待填 |
| tag | v4.4.0 |
| CI run | 待填 |
| APK | 待填 |
| 质量门 | 待填 |
| 验收结果 | 待填 |
