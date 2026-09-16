import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_colors.dart';
import 'package:xiaozhi_client_flutter/core/utils/toast_util.dart';
import '../services/app_feats.dart';
import '../../core/utils/log_buffer.dart';
import 'log_category_page.dart';
import 'external_mcp_page.dart';
import '../../core/utils/audio_util.dart';
import '../../core/storage/storage_service.dart';
import '../../app/config/app_config.dart';

/// 开发者中心（v3.3.0，对齐网页版模式，xiaoleweb.md 第十一章）
/// ------------------------------------------------------------
/// 入口：「我」→ 开发者选项 → 未授权先弹密码门（本机记住授权，页面内可清除）。
/// Cell 列表：左标题+副标题说明、右开关；顶部「N 项开启」；底部全部关闭/清除授权。
class DevCenterPage extends StatefulWidget {
  const DevCenterPage({super.key});

  @override
  State<DevCenterPage> createState() => _DevCenterPageState();
}

class _DevCenterPageState extends State<DevCenterPage> {
  @override
  void initState() {
    super.initState();
    AppFeats.load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('开发者中心')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // N 项开启
          Center(
            child: Text(
              '${AppFeats.onCount} 项开启',
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _section(isDark, '能力开关', [
            _switchTile(
              isDark,
              '🧰 MCP 设备工具',
              '向 AI 注册设备工具：26 项（音量/闹钟/日程/拨号/短信/导航/截屏…）——AI 可真实操控',
              'mcptools',
            ),
            // v6.1.2：点开查看已注册给 AI 的**全部 26 项**工具（分组 + 用途说明）
            ListTile(
              leading: const Icon(Icons.list_alt, color: Color(0xFF576B95)),
              title: const Text('📋 查看已注册的工具清单'),
              subtitle: const Text('26 项能力分组明细（AI 能做什么，一目了然）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showMcpToolsDialog(isDark),
            ),
            // v6.4.0：外部 MCP 服务器管理（可增删改多条，工具带前缀桥接给 AI）
            ListTile(
              leading: const Icon(Icons.hub, color: Color(0xFF576B95)),
              title: const Text('🌐 外部 MCP'),
              subtitle: const Text('接入外部 MCP 服务器（biji 笔记 / 高德地图…），可逐台逐工具开关'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ExternalMcpPage()),
                );
              },
            ),
            _switchTile(
              isDark,
              '📡 MQTT 常驻在线',
              '长连接保后台在线 + 接收远程配置；下次连接生效（限流风险默认关）',
              'mqtt',
            ),
            _switchTile(
              isDark,
              '📷 视觉识物',
              '聊天栏相机按钮：拍照问 AI 这是什么',
              'vision',
            ),
            // v4.4.0：原「🎤 抢话打断」开关已移除——其用未消回声的振幅判断会误触发，
            // 导致 AI 自问自答（方案根因③）。此处改为 AEC 通话通路开关。
            _aecTile(isDark),
            _switchTile(
              isDark,
              '🧪 MCP 调试',
              '开启=字幕保留 % 工具名原文；关闭=自动过滤',
              'mcpDebug',
            ),
            _switchTile(
              isDark,
              '😄 表情动画',
              'AI 对话时的全屏表情动画（v4.3.0 起默认关，可在此开启）',
              'emotion',
            ),
          ]),
          _section(isDark, '诊断', [
            _tailGuardTile(),
            ListTile(
              leading:
                  const Icon(Icons.receipt_long_outlined, color: Color(0xFF576B95)),
              title: const Text('📋 运行日志查看'),
              subtitle: const Text('复制最近 200 条运行日志，供 AI 排查故障'),
              onTap: _copyLogs,
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: Color(0xFF576B95)),
              title: const Text('🗂 日志分类'),
              subtitle: Text(
                  '按功能开关日志记录（已开 ${LogBuffer.enabledCount}/${LogBuffer.categories.length}）'),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogCategoryPage()),
                );
                if (mounted) setState(() {});
              },
            ),
          ]),
          _section(isDark, '安全', [
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF576B95)),
              title: const Text('🔒 清除授权'),
              subtitle: const Text('下次进开发者中心需重新输密码'),
              onTap: () {
                AppFeats.setDevAuthed(false);
                ToastUtil.show('已清除授权');
                Navigator.of(context).pop();
              },
            ),
          ]),
          _section(isDark, '危险操作', [
            ListTile(
              leading: const Icon(Icons.close, color: Color(0xFFE64340)),
              title: const Text('全部关闭'),
              subtitle: const Text('关闭所有开发者功能（等效普通用户模式）'),
              onTap: () {
                AppFeats.allOff();
                setState(() {});
                ToastUtil.show('已全部关闭');
              },
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// v4.4.0：AEC 通话通路开关
  /// **独立于 `AppFeats`**——`AppFeats.allOff()`（"全部关闭"＝普通用户模式）会关掉所有开关，
  /// 而 AEC 属基础收音质量而非"开发者增强功能"，不应被"全部关闭"取消，故用独立存储键。
  Widget _aecTile(bool isDark) {
    return SwitchListTile(
      value: AudioUtil.useAecSource,
      onChanged: (v) {
        AudioUtil.setAecSource(v);
        setState(() {});
        ToastUtil.show(v
            ? '通话降噪通路已开启（下次录音生效）'
            : '通话降噪通路已关闭，恢复原录音源（下次录音生效）');
      },
      title: Text(
        '🎧 通话降噪通路（AEC）',
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '开启＝走通话音频通路以启用硬件回声消除，可消除 AI 尾音被误识别；少数机型音色略闷。下次录音/通话生效',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  int get _tailGuardMs {
    final v = StorageService.instance.getInt(AppConfig.keyTailGuardMs);
    if (v == null) return AppConfig.defaultTailGuardMs;
    return v.clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
  }

  /// v4.4.0：尾音保护时长（100–500ms，默认 300）
  Widget _tailGuardTile() {
    final ms = _tailGuardMs;
    return ListTile(
      leading: const Icon(Icons.timer_outlined, color: Color(0xFF576B95)),
      title: const Text('⏱ 尾音保护'),
      subtitle: Text('AI 说完后等待 $ms 毫秒再恢复采集（减少误识别；调大更保险）'),
      onTap: () => _pickTailGuard(ms),
    );
  }

  Future<void> _pickTailGuard(int current) async {
    double value = current.toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('尾音保护时长'),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()} 毫秒'),
              Slider(
                value: value,
                min: AppConfig.minTailGuardMs.toDouble(),
                max: AppConfig.maxTailGuardMs.toDouble(),
                divisions: 8, // 100~500，步进 50
                label: '${value.round()}ms',
                onChanged: (v) => setS(() => value = v),
              ),
              const Text(
                'AI 说完后等多久再开始听你说话：调大可减少误识别，调小更灵敏',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final v =
        value.round().clamp(AppConfig.minTailGuardMs, AppConfig.maxTailGuardMs);
    await StorageService.instance.setInt(AppConfig.keyTailGuardMs, v);
    setState(() {});
    ToastUtil.show('尾音保护已设为 ${v}ms');
  }

  /// v4.3.2：复制最近 200 条运行日志到剪贴板（供用户粘贴给 AI 排查故障）
  Future<void> _copyLogs() async {
    try {
      final text = LogBuffer.recentText(200);
      if (text.isEmpty) {
        ToastUtil.show('暂无日志，请先复现操作再回来复制');
        return;
      }
      final count = '\n'.allMatches(text).length + 1;
      await Clipboard.setData(ClipboardData(text: text));
      ToastUtil.show('已复制 $count 条日志');
    } catch (e) {
      ToastUtil.show('复制失败：$e');
    }
  }

  /// v6.1.2：展示已注册给 AI 的**全部 MCP 设备工具**。
  /// v6.3.0：由只读弹窗升级为**可操作详情页**——每项行尾带开关，可逐项开关某个工具
  /// （下行层据此在 tools/list 过滤、tools/call 命中禁用工具回 -32601）。
  /// 总闸 `mcptools` 关闭时，逐项开关置灰并提示「先开总闸」。
  void _showMcpToolsDialog(bool isDark) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _McpToolsDetailPage(isDark: isDark),
      ),
    );
  }

  Widget _section(bool isDark, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color:
                    isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(bool isDark, String title, String subtitle, String key) {
    return SwitchListTile(
      value: AppFeats.get(key),
      onChanged: (v) {
        AppFeats.set(key, v);
        setState(() {});
        ToastUtil.show(v ? '$title 已开启' : '$title 已关闭');
      },
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// v6.3.0：MCP 设备工具详情页（逐项开关）。独立 StatefulWidget，
/// 其自身 setState 即可实时刷新开关，不必依赖开发者中心页 rebuild。
class _McpToolsDetailPage extends StatefulWidget {
  final bool isDark;
  const _McpToolsDetailPage({required this.isDark});

  @override
  State<_McpToolsDetailPage> createState() => _McpToolsDetailPageState();
}

class _McpToolsDetailPageState extends State<_McpToolsDetailPage> {
  // 组名 → [ [工具名, 用途], ... ]
  static const List<MapEntry<String, List<List<String>>>> groups = [
    MapEntry('① 基础能力（11 项）', [
      ['self.get_device_status', '设备状态：音量 / 主题 / 电量 / 网络'],
      ['self.audio_speaker.set_volume', '调节音量（真实系统媒体音量）'],
      ['self.screen.set_theme', '切换深色 / 浅色主题'],
      ['self.timer.create_countdown', '创建倒计时（到点提醒+震动+播报）'],
      ['self.timer.get_tasks', '查看进行中的倒计时'],
      ['self.timer.stop_task', '停止指定倒计时'],
      ['self.schedule.create_event', '创建日程（写入系统日历，App 关了也提醒）'],
      ['self.schedule.get_events', '查看已创建的日程记录'],
      ['self.schedule.delete_event', '删除日程记录'],
      ['self.camera.take_photo', '拍照并识别画面内容'],
      ['self.screen.preview_image', '在聊天里显示一张图片'],
    ]),
    MapEntry('② 官方标准补齐（5 项）', [
      ['self.screen.set_brightness', '调节屏幕亮度（应用级，免权限）'],
      ['self.screen.get_info', '屏幕尺寸 / 像素比信息'],
      ['self.get_system_info', '系统与设备信息：品牌 / 型号 / 安卓版本'],
      ['self.screen.snapshot', '截取当前界面（不用系统录屏权限）'],
      ['self.reboot', '重启会话（重新连接 + 清空当前对话）'],
    ]),
    MapEntry('③ 系统能力·免权限（5 项）', [
      ['self.phone.dial', '打开拨号盘并填入号码（需你点拨出）'],
      ['self.message.send_sms', '发短信：预填号码与内容（需你点发送）'],
      ['self.map.navigate', '打开地图导航到指定地点'],
      ['self.system.open_settings', '打开系统设置页：WiFi / 蓝牙 / 声音等'],
      ['self.system.open_url', '用浏览器打开网页'],
    ]),
    MapEntry('④ 提醒与随身工具（5 项）', [
      ['self.alarm.set_alarm', '设置真实系统闹钟（时钟 App 里可见，关机后仍会响）'],
      ['self.show_toast', '屏幕轻提示（不打断对话）'],
      ['self.share.text', '把文字分享到备忘录 / 微信 / 钉钉等'],
      ['self.clipboard.get', '读取剪贴板内容'],
      ['self.clipboard.set', '把文字写入剪贴板'],
    ]),
    MapEntry('⑤ 定位能力（1 项）', [
      ['self.location.get_current', '获取当前 GPS 坐标（GCJ-02，供高德/导航使用）'],
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final masterOn = AppFeats.mcptools;

    return Scaffold(
      appBar: AppBar(title: const Text('MCP 设备工具')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('共 ${_totalCount()} 项能力，逐项开关；关闭后 AI 将看不到该工具',
                style: TextStyle(fontSize: 12, color: sub)),
          ),
          if (!masterOn)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF576B95).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '🧰 总开关「MCP 设备工具」已关闭，下面各项暂不可操作。'
                '请先返回上一页开启总闸。',
                style: TextStyle(fontSize: 12, color: Color(0xFF576B95)),
              ),
            ),
          for (final g in groups)
            _section(g.key, g.value, prim, sub, masterOn),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              '⚠️ 闹钟 / 日程 / 短信 / 拨号 / 分享会打开系统界面，'
              '需要你确认后才真正生效（安卓的安全设计）。',
              style: TextStyle(fontSize: 11, color: sub, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  int _totalCount() => groups.fold(0, (sum, g) => sum + g.value.length);

  Widget _section(String title, List<List<String>> tools, Color prim, Color sub,
      bool masterOn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: prim)),
          ),
          Material(
            color: widget.isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                for (final t in tools)
                  SwitchListTile(
                    // 总闸关 → 置灰不可操作（逐项设置保留，不清除）
                    onChanged: masterOn
                        ? (v) {
                            AppFeats.setMcpToolEnabled(t[0], v);
                            setState(() {});
                          }
                        : null,
                    value: AppFeats.mcpToolEnabled(t[0]),
                    title: Text(t[1],
                        style: TextStyle(
                            fontSize: 14,
                            color: masterOn ? prim : sub)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(t[0],
                          style: TextStyle(fontSize: 11, color: sub)),
                    ),
                    activeColor: const Color(0xFF07C160),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 开发者中心密码门（未授权时弹出；与网页版同密码，错误抖动）
Future<void> showDevGateIfNeeded(BuildContext context) async {
  if (AppFeats.devAuthed) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevCenterPage()),
    );
    return;
  }
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('开发者模式'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
            hintText: '请输入密码', border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.of(ctx).pop(v == AppFeats.devPassword),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text == AppFeats.devPassword),
            child: const Text('确定')),
      ],
    ),
  );
  if (ok == true) {
    AppFeats.setDevAuthed(true);
    ToastUtil.show('授权成功');
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DevCenterPage()),
      );
    }
  } else if (ok == false) {
    ToastUtil.show('密码错误');
  }
}
