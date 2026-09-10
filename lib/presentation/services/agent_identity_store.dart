import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaozhi_client_flutter/core/utils/xiaozhi_device_info_util.dart';

/// v4.3.0：统一虚拟设备型号（用户批准：弃用手机型号 fallback 与 xiaole-voice-v1，
/// 全面对齐 m5stack-core-s3 硬件画像——《小智硬件 Android 迁移指南》：
/// 板卡 m5stack-core-s3 / 芯片 esp32-s3 / Flash 16MB / PSRAM 8MB）。
/// OTA 识别层 v3.1.0/v4.0.1 起已统一，本常量与矫正只清展示/存储层残留。
const String kUnifiedDeviceModel = 'm5stack-core-s3';

/// 每智能体独立设备身份存储（v1.1.5）
///
/// 背景：设备身份（MAC/ClientID/型号）在 lib/core 的 XiaozhiDeviceInfoUtil 中
/// 是全局单例（全部智能体共用一份），新增智能体提交时会覆盖旧值导致串号。
///
/// 本存储按 agentId 把三元组分开保存（表现层自己的 SharedPreferences 键），
/// 进入某智能体对话、连接初始化之前，由 chat_page 把该智能体的身份
/// 通过 XiaozhiDeviceInfoUtil 的公开 setter 应用到全局（只调用不改 lib/core）。
class AgentIdentityStore {
  AgentIdentityStore._();

  static const String _prefix = 'agent_identity_';

  /// v4.3.0：型号归一——入参已是统一型号则原样返回，否则返回统一型号
  ///（手机型号 fallback / xiaole-voice-v1 等旧值一律归一）。
  static String normalizeModel(String model) =>
      model == kUnifiedDeviceModel ? model : kUnifiedDeviceModel;

  /// v4.3.0：全局型号矫正——全局覆盖值不是统一型号时写入统一型号（幂等）。
  /// 调用入口：聊天页 initState / 智能体配置页加载设备字段 / 设置页设备型号展示。
  static Future<void> normalizeGlobalModel() async {
    final cur = await XiaozhiDeviceInfoUtil.instance.getDeviceModel();
    if (cur != kUnifiedDeviceModel) {
      await XiaozhiDeviceInfoUtil.instance.setDeviceModel(kUnifiedDeviceModel);
    }
  }

  /// 保存某智能体的设备身份三元组
  static Future<void> save(
    String agentId, {
    required String mac,
    required String clientId,
    required String model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefix}mac_$agentId', mac);
    await prefs.setString('${_prefix}clientid_$agentId', clientId);
    await prefs.setString('${_prefix}model_$agentId', model);
  }

  /// 读取某智能体的设备身份；任一缺失返回 null（视为未配置，不切换全局）
  static Future<Map<String, String>?> load(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString('${_prefix}mac_$agentId');
    final clientId = prefs.getString('${_prefix}clientid_$agentId');
    final model = prefs.getString('${_prefix}model_$agentId');
    if (mac == null || clientId == null || model == null) return null;
    return {'mac': mac, 'clientId': clientId, 'model': model};
  }
}
