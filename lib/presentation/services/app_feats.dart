import 'package:flutter/foundation.dart';
import 'package:xiaozhi_client_flutter/core/network/xiaozhi_mcp_responder.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';

/// 开发者功能开关体系（v3.3.0，对齐网页版开发者中心模式，xiaoleweb.md 第十一章）
/// ------------------------------------------------------------------
/// 设计原则（照搬网页版）：每个高风险功能独立开关、可灰度、出问题关掉即回旧行为，
/// 永不回滚整版。开关即时读取（每次用前 get），无状态缓存导致的过期问题。
class AppFeats {
  AppFeats._();

  /// 开发者中心密码（与网页版一致）
  static const String devPassword = 'zc19901111';
  static const String _devAuthedKey = 'xw_dev_authed';

  /// 开关清单与默认值：
  /// - mcptools（🧰 MCP 设备工具）：v3.0 起默认开（用户批准）
  /// - vision（📷 视觉识物）：v3.1 起默认开
  /// - bargein（🎤 抢话打断）：v3.2 起默认开 → **v4.4.0 起默认关**：
  ///   其用未回声消除的麦克风振幅判断，AI 说话时必然误触发，会把 AI 自己的声音上行
  ///   造成「自问自答」。详见 PLAN_v4.4.0_语音自问自答修复.md 根因③
  /// - mqtt（📡 MQTT 常驻在线）：v3.3 新增，**默认关**（EMQX 限流待真机观察，灰度）
  /// - mcpDebug（🧪 MCP 调试）：默认关（开=字幕保留 % 工具名原文）
  /// - emotion（😄 表情动画）：v4.3.0 新增，**默认关**（用户拍板：全屏动画移入
  ///   开发者中心，普通用户默认不见；消息内 emoji 前缀不受此开关影响）
  /// - rawServerAlert（⚠️ 显示服务端原始提示）：v6.4.4 新增，**默认关**。
  ///   开启=开发者模式，聊天页直接显示服务器 alert 技术原文（如 detect 拒绝长文本报错）；
  ///   关闭=普通用户模式，改用友好弹窗（不暴露技术细节）。放进 `keys` 是**有意为之**——
  ///   这样「全部关闭」（`allOff()`）会一并把它关掉，语义正确（一键回到普通用户模式）。
  /// - proactive（🤖 AI 主动来电）：v6.5.0 新增，**默认关**。
  ///   开启=前台定时巡检，由小智判断后主动来电（方案 D：口令存本地 + 设备 MCP 工具取回）。
  ///   放进 `keys` 是**有意为之**——「全部关闭」会一并关掉，一键回到普通用户模式。
  static const List<String> keys = [
    'mcptools',
    'mqtt',
    'vision',
    'bargein',
    'mcpDebug',
    'emotion',
    'rawServerAlert',
    'proactive',
  ];
  static const Map<String, bool> defaults = {
    'mcptools': true,
    'mqtt': false,
    'vision': false, // v6.8.1（E 项）：📷 相机按钮（视觉识物）默认关（原来默认开）
    'bargein': false, // v4.4.0：默认关（误触发导致 AI 自问自答，见方案根因③）
    'mcpDebug': false,
    'emotion': false,
    'rawServerAlert': false, // v6.4.4：默认关 = 普通用户模式（友好弹窗）
    'proactive': false, // v6.5.0：默认关（AI 主动来电属增强功能，需用户主动开启）
  };

  /// v6.8.1（E 项）：27 项 MCP 设备工具中**仅默认开启的 5 项白名单**。
  /// 其余 22 项默认关（仅对新装用户生效；已装用户本地已存的开关不会被覆盖）。
  /// `self.proactive.*`（get_script / trigger_call / skip / get_opening）属来电链路内部工具，
  /// 不在 27 项逐项开关之列，故不在此列。
  /// ⚠️ 集中管理，日后调整默认值只改这一处。
  static const Set<String> mcpDefaultOnTools = {
    'self.location.get_current', // 定位能力
    'self.alarm.set_alarm', // 设置真实闹钟
    'self.map.navigate', // 打开地图导航
    'self.screen.set_brightness', // 调节屏幕亮度
    'self.audio_speaker.set_volume', // 调节系统音量
  };

  static final Map<String, bool> _cache = Map.from(defaults);

  /// 是否已通过密码授权（本机记住；开发者中心内可清除重新上锁）
  static bool get devAuthed =>
      StorageService.instance.getBool(_devAuthedKey) ?? false;

  static void setDevAuthed(bool v) =>
      StorageService.instance.setBool(_devAuthedKey, v);

  static bool get(String key) => _cache[key] ?? false;

  /// 「N 项开启」通知（设置页入口实时刷新用）
  static final ValueNotifier<int> onCountNotifier = ValueNotifier<int>(0);

  static void _notify() => onCountNotifier.value = onCount;

  static void set(String key, bool v) {
    _cache[key] = v;
    StorageService.instance.setBool('xw_feat_$key', v);
    _notify();
  }

  /// 启动时从存储恢复（chat_page initState 调用一次）
  static Future<void> load() async {
    for (final k in keys) {
      final v = StorageService.instance.getBool('xw_feat_$k');
      if (v != null) _cache[k] = v;
    }
    // v6.3.0：一并恢复逐项 MCP 工具开关（独立于 keys 列表）
    for (final t in XiaozhiMcpStandardTools.allToolsWithLocation()) {
      final v = StorageService.instance.getBool(_mcpToolKey(t.name));
      if (v != null) _mcpToolCache[t.name] = v;
    }
    _notify();
  }

  static int get onCount => keys.where(get).length;

  static void allOff() {
    for (final k in keys) {
      set(k, false);
    }
    // v6.11.11：WS 保活是生产逻辑（默认 auto），**不受「全部关闭」影响**——
    // 普通用户同样需要 45s listen stop 续命，否则会频繁被云端 1005 回收。
    // 如需彻底关闭保活，只能在开发者中心把「WS 保活」单独切到「关闭」。
    // ⚠️ 不清空逐项 MCP 工具开关（xw_mcp_*）—— 总闸全部关闭＝普通用户模式，
    // 但逐项设置是用户独立偏好，恢复总闸后原逐项配置应仍生效。
  }

  // ---------- 逐项 MCP 工具开关（v6.3.0，独立于 keys 列表） ----------
  /// 存储键：`xw_mcp_<工具名>`（工具名里的 `.` 转义为 `_`，避免 key 冲突）。
  static String _mcpToolKey(String name) => 'xw_mcp_${name.replaceAll('.', '_')}';

  /// 逐项开关的运行时缓存（与 keys 列表完全隔离）。
  static final Map<String, bool> _mcpToolCache = {};

  /// 单个 MCP 工具是否启用。
  ///
  /// **本回调同时服务于「设备工具」与「外部 MCP 工具」**（`chat_page` 只注入这一个
  /// `isToolEnabled`），因此默认值必须**按来源分别判定**：
  /// - **设备工具**（`self.*`）：v6.8.1（E 项）白名单——白名单内 5 项 `?? true`，其余 `?? false`。
  /// - **外部 MCP 工具**（非 `self.` 前缀，如 `notes.*` / `amap.*`）：**默认放行 `?? true`**。
  ///
  /// 🔴 **v6.9.1 修复的真实回归缺陷**：v6.8.1 把默认值统一改成
  /// `mcpDefaultOnTools.contains(name)`，而该白名单只含 5 项设备工具 ⇒ 外部工具**全部**被判为
  /// 禁用 ⇒ `tools/list` 不再下发 ⇒ 小智 AI 完全看不到 biji / 高德 的工具
  /// （症状：v6.4.4 能用、v6.8.1 起"识别不到外部 MCP"）。
  ///
  /// 外部工具**是否启用由「外部 MCP」页负责**：整台启停 `ExternalMcpServer.enabled`
  /// + 逐工具关闭名单 `disabledTools`（两处独立于本回调，互不冲突）。
  ///
  /// 优先级：运行时缓存 > 已持久化存储值 > 默认值（保证"已存值不被默认值回滚"）。
  static bool mcpToolEnabled(String name) {
    final cached = _mcpToolCache[name];
    if (cached != null) return cached;
    final stored = StorageService.instance.getBool(_mcpToolKey(name));
    if (stored != null) return stored;
    // v6.9.1：外部 MCP 工具（非 self. 前缀）默认放行，不受设备工具白名单约束
    if (!name.startsWith('self.')) return true;
    return mcpDefaultOnTools.contains(name);
  }

  /// 测试辅助：清空逐项 MCP 工具运行时缓存（不影响持久化存储）。
  static void resetMcpToolCache() => _mcpToolCache.clear();

  /// 写回单个 MCP 工具的开关状态（持久化）。
  static void setMcpToolEnabled(String name, bool v) {
    _mcpToolCache[name] = v;
    StorageService.instance.setBool(_mcpToolKey(name), v);
  }

  // ---------- 语义化快捷读取（避免散落魔法字符串） ----------
  static bool get mcptools => get('mcptools');
  static bool get mqtt => get('mqtt');
  static bool get vision => get('vision');
  static bool get bargein => get('bargein');
  static bool get mcpDebug => get('mcpDebug');
  static bool get emotion => get('emotion');
  // v6.4.4：开发者模式=直接显示服务器 alert 原始技术文本；默认 false=普通用户友好模式
  static bool get rawServerAlert => get('rawServerAlert');
  // v6.5.0：AI 主动来电总开关；默认 false=普通用户模式（不巡检、零流量）
  static bool get proactive => get('proactive');

  // ---------- v6.11.11：WS 保活（生产逻辑，默认 auto） ----------
  /// 2026-11-04 真机定案：`listen{state:"stop"}` 每 45s 一次 =
  /// 8 tick / 6 分钟零副作用（零 stt/tts/llm/下行音频/AudioTrack start）、零重连。
  /// 因此它不再是"诊断开关"，而是生产默认行为：
  /// - `auto`（默认）：已连接且无会话时每 45s 发一次 listen stop；
  /// - `off`：不发任何保活消息（仅 WS ping + 无感重连兜底）。
  /// `detect` 只保留在底层枚举做诊断，**不进入可选集**（会触发 TTS 外放）。
  static const String wsKeepaliveDefault = 'auto';
  static const String _wsKeepaliveKey = 'xw_ws_keepalive';
  static const String _wsProbeSecKey = 'xw_ws_probe_interval_sec';

  /// 配置变更通知：聊天页监听后立即重建连接，让新配置即时生效。
  static final ValueNotifier<int> wsProbeRevision = ValueNotifier<int>(0);

  static String get wsKeepaliveMode {
    final v = StorageService.instance.getString(_wsKeepaliveKey);
    if (v != null && (v == 'auto' || v == 'off')) return v;
    // 兼容 v6.11.10 实验键：旧值 detect/pair/mcp/stop 一律回落生产默认 auto
    return wsKeepaliveDefault;
  }

  /// 保活间隔（秒），默认 45s；限制 10–120s，避免把保活变成压测。
  static int get wsKeepaliveIntervalSec =>
      (StorageService.instance.getInt(_wsProbeSecKey) ?? 45).clamp(10, 120);

  static void setWsKeepalive(String mode) {
    StorageService.instance
        .setString(_wsKeepaliveKey, mode == 'off' ? 'off' : 'auto');
    wsProbeRevision.value++;
  }

  /// 开发者中心展示用中文名
  static String get wsKeepaliveLabel => wsKeepaliveMode == 'off'
      ? '关闭（仅 ping + 无感重连）'
      : '自动（${wsKeepaliveIntervalSec}s · listen stop）';
}
