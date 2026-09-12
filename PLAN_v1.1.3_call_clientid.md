# 小乐 App v1.1.3 改造方案（审批稿）

> 目标版本：`1.1.3+4`（按"每次功能改动自动升版本"约定，从 `1.1.2+?` 递增）
> 回退点：`v1.1.2`（已验证 CI 构建通过、红线校验通过）
> 改动性质：纯表现层（presentation），**不触碰**通信/音频/网络红线（`lib/core/`、`lib/data/`）

---

## 一、需求拆解（来自张老师 2026-09-06 反馈）

1. **📞 电话按钮没声音（重点）**：要求把 📞 的功能**完全照搬**输入栏右侧那个能正常用的圆形「持续监听」按钮——它本质是实时语音通话且工作正常；抄完它的功能，再套进现在这个好看的 📞 全屏界面即可。结论：界面保留，功能要换成能用的那套。
2. **ClientID 随机生成格式非法**：重写随机生成规则，生成真实的合法格式（参考手机实机 ClientID：`1257d6dc-7b0b-4772-aacc-9b27e33778ac`）。

---

## 二、根因诊断（已查证，确凿）

### 2.1 📞 没声音的根因（一句话）
之前的 v1.1.2 修复里，`_startVoiceCall` **只**做了 `AudioUtil.startRecording()` + 发送 `listen`(realtime) start，**漏掉了把麦克风采集到的音频真正发出去这一步**。

能用的「持续监听」按钮（`voice_record_button.dart` 的 `_startContinuousListening`，行 262–291）实际做了**三件事**：
1. `widget.onContinuousListenStart?.call()` —— 发 `listen`(realtime) start（让服务器开始回 TTS）
2. **`AudioUtil.audioStream.listen((d) => widget.onAudioSend(d))` —— 订阅麦克风音频流并逐帧转发到 WebSocket**（这是关键，缺了它服务器就收不到声音）
3. `AudioUtil.startRecording(enableAEC: true)` —— 启动麦克风采集

我的 📞 只做了 1 和 3，**没做 2**，所以服务器永远收不到你的声音 → 不生成 TTS → 全程静音（界面"已连接"只是写死的状态变量）。

### 2.2 ClientID 格式非法
`agent_config_page.dart` 的 `_randomClientId()`（行 333–337）当前实现：
```dart
String _randomClientId() {
  final r = Random();
  final part = () => r.nextInt(10000).toString().padLeft(4, '0');
  return '${part()}-${part()}-${part()}';   // 形如 1234-5678-9012
}
```
只生成了 **3 段 4 位数字**，不是合法 UUID。而：
- 官方小智设备 `get_client_id()` 生成的是 **UUID 格式**（8-4-4-4-12，带标准短横线）；
- xiaozhi-web-client 的 `CLIENT_ID` 也是自动生成的 **UUID**（如 `6d6ca305-10ac-4349-8609-6ca6330d092c`）；
- 张老师实机 ClientID `1257d6dc-7b0b-4772-aacc-9b27e33778ac` 即标准小写 UUID v4。
- 设备默认身份（`xiaozhi_device_info_util.dart` 的 `getDeviceClientId()`）**本来就用 `Uuid().v4()` 生成合法 UUID**，无需改动。

> 调研来源：XiaoZhi 官方设备激活文档（DeepWiki `78/xiaozhi-sf32` 2.3、3）、xiaozhi-web-client 配置说明（CSDN）。三者一致指向 **UUID（小写，8-4-4-4-12 十六进制）**。

---

## 三、实施方案

### 3.1 修复 📞 通话无声（照搬持续监听功能）

**改动文件**：`lib/presentation/pages/chat/chat_page.dart`

**A. 新增一个音频流订阅字段**（在状态区）
```dart
StreamSubscription<Uint8List>? _callAudioSubscription;
```

**B. `_startVoiceCall()` 补上"转发麦克风音频"这一步**（完整对齐 `_startContinuousListening`）
在现有 `AudioUtil.startRecording(enableAEC: true)` 之后、`_handleContinuousListenStart()` 之前（或之后均可），加入：
```dart
// 关键：订阅麦克风音频流并逐帧转发到 WebSocket（与持续监听同链路）
_callAudioSubscription = AudioUtil.audioStream.listen(
  (audioData) {
    if (!_micMuted) _handleAudioSend(audioData);  // 静音时不发送
  },
  onError: (e) {
    logger.severe('通话音频流错误: $e');
  },
);
```
> 顺序与能用的按钮一致：先 startRecording 打开麦克风 → 订阅转发 → 发 listen(real) start。

**C. `_endVoiceCall()` 先取消订阅再停麦**（对齐 `_stopContinuousListening`）
在 `AudioUtil.stopRecording()` 之前加入：
```dart
await _callAudioSubscription?.cancel();
_callAudioSubscription = null;
```

**D. 麦克风静音键真正生效**：订阅回调里已用 `if (!_micMuted)` 守卫，挂断/取消静音即时恢复。
**E. 扬声器键**：保持**UI 占位**（当前 `AudioUtil` 无扬声道路由 API，改它要动 `lib/core` 红线）。界面按钮保留可点，但声音路由不变——已在 v1.1.2 说明，本次不变。

**预期行为**：点 📞 → 全屏通话界面 + 真实双向语音（你说话服务器能听到、能回 TTS）；点 挂断 → 停止。功能与红色「持续监听」按钮**逐字节等价**，只是包了一层全屏 UI。

### 3.2 ClientID 随机生成改为合法 UUID

**改动文件**：`lib/presentation/pages/agent_config/agent_config_page.dart`（仅这一处，对应"只修 🎲 生成按钮"的决策）

```dart
String _randomClientId() {
  return const Uuid().v4();   // 形如 1257d6dc-7b0b-4772-aacc-9b27e33778ac
}
```
- `uuid` 包已在文件顶部 import（`import 'package:uuid/uuid.dart';`，行 5），无需新增依赖。
- MAC 生成器 `_randomMac()` 格式本就合法（`XX:XX:XX:XX:XX:XX`），不动。
- 设备默认身份走 `getDeviceClientId()` 的 `Uuid().v4()`，本就合法，不动。

### 3.3 版本号递增
- `pubspec.yaml`：`version: 1.1.3+4`
- `lib/app/config/app_config.dart`：`appVersion = '1.1.3'`
- `lib/presentation/pages/chat/chat_page.dart`：OTA 上报 `appVersion: '1.1.3'`
- `lib/presentation/pages/settings/settings_page.dart`：版本文案改为 `1.1.3`

### 3.4 推送与交付（沿用已验证通道）
1. **强制红线校验**：`git diff 3e067af -- lib/core/ lib/data/` 必须**仅含**既往已批准的设备身份改动（`xiaozhi_device_info_util.dart`），本次不新增任何红线改动 → 否则中止。
2. GitHub API 直推（绕过代理 502 四步法：blob→tree→commit→ref），打 `v1.1.3` 标签触发 CI。
3. CI 通过后用两段式签名 URL 下载 APK 到桌面：`C:\Users\Administrator\Desktop\xiaole-client-v1.1.3.apk`。
4. README 版本档案追加 `v1.1.3` 一行（内容 / 包名 / 验证状态 / 日期）。

---

## 四、红线安全声明
- 本次所有改动仅位于 `lib/presentation/`（chat_page、agent_config_page）与版本号文件，**不动** `lib/core/`、`lib/data/`、路由、配置。
- 实时语音**只调用**已有的 `AudioUtil` / `_handleAudioSend` / `_handleContinuousListenStart/Stop`，**不修改**任何通信/音频实现。
- 扬声器仍为 UI 占位，未引入红线改动。

---

## 五、需张老师确认的假设（如有异议请审批时指出）
1. 📞 = 实时连续语音（与红色按钮同机制），**点 📞 开始、点 挂断 结束**；界面沿用现有全屏通话页。
2. 按你的选择：**保留** 📞 与红色「持续监听」两个按钮（二者本就在不同输入模式，不会同时生效，无重复发送风险）。
3. 扬声器按钮维持 UI 占位（不动红线）；若日后要真切换听筒/扬声器，需单独评估是否开放红线音频路由 API。
4. 本次**只修**「加智能体」弹窗的 🎲 ClientID 生成；设置页设备身份本就合法，不加新按钮。

---

## 六、验证清单（交付前自检 + 真机验收建议）
- [ ] CI 构建通过（run 成功）
- [ ] 红线 diff 干净（仅既往已批准设备身份改动）
- [ ] 桌面 APK 字节级校验存在：`xiaole-client-v1.1.3.apk`
- [ ] 真机：点 📞 进入全屏通话，**双向语音正常**（你说的话对方能听到、能听到回复）
- [ ] 真机：通话中 麦克风静音 键真正静音（对方听不到）
- [ ] 真机：「加智能体」弹窗点 🎲 重新生成，ClientID 形如 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`（合法 UUID，非 1234-5678-9012）

---
*本方案为审批稿，批准后据此执行（不在此稿内直接改代码）。*
