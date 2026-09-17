import 'package:flutter/material.dart';
import '../../app/themes/app_colors.dart';

/// 用户协议 · 功能介绍页（v6.7.0 新增）
/// ------------------------------------------------------------
/// 定位：告诉用户本 App 能做什么（能力面尽量详细），但不暴露任何
/// 实现机制/上游服务/工具名称。无外链、深浅色自适应。
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prim = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final sub = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('用户协议 · 功能介绍')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _section(isDark, '产品定位', [
            _p(prim, '小乐 App 是一款运行在您手机上的 AI 语音助手应用。'
                '它内置了 AI 助手「小智」，能听、会说、能看、能帮您办事——'
                '像一位随身的小管家。'),
          ]),
          _section(isDark, '您可以获得的能力', [
            _p(prim, '一、智能对话', bold: true),
            _p(sub, '文字或语音与小智自由聊天，支持连续多轮对话，记得上下文，越聊越懂你。'),
            _p(prim, '二、语音通话', bold: true),
            _p(sub, '像打电话一样和小智实时语音交流，支持调节说话音量、通话降噪（回声消除），交流更清晰。'),
            _p(prim, '三、拍照识物', bold: true),
            _p(sub, '看到不认识的东西，拍照问小智"这是什么"，它会识别画面内容并为你讲解。'),
            _p(prim, '四、帮您操控手机（AI 代办，需你确认）', bold: true),
            _p(sub, '· 调节音量、屏幕亮度、深浅色主题\n'
                '· 创建倒计时、设置真实系统闹钟（到点会响）\n'
                '· 创建日程并写入系统日历，App 关了也提醒\n'
                '· 查看设备状态：电量、网络、系统信息\n'
                '· 截取当前界面、在聊天里展示图片'),
            _p(prim, '五、通讯与出行', bold: true),
            _p(sub, '帮你打开拨号盘并填好号码（你点拨出才生效）、预填短信内容（你点发送才生效）、'
                '打开地图导航到指定地点、直达系统设置页、用浏览器打开网页。'),
            _p(prim, '六、随身小工具', bold: true),
            _p(sub, '屏幕轻提示、把文字一键分享到微信/钉钉/备忘录等、读写剪贴板、获取当前位置用于导航。'),
            _p(prim, '七、AI 主动关怀', bold: true),
            _p(sub, '开启后，小智可以在你设定的时段内主动来电问候（间隔与时段均可配置，不用时保持零打扰）。'),
            _p(prim, '八、云端同步', bold: true),
            _p(sub, '聊天记录与智能体配置可多端互通，换设备不丢数据；聊天记录可导出为 TXT/JSON 备份分享。'),
            _p(prim, '九、智能体定制', bold: true),
            _p(sub, '创建多个 AI 角色智能体，自定义头像与资料，切换不同"人格"陪伴。'),
            _p(prim, '十、能力扩展', bold: true),
            _p(sub, '可持续接入更多第三方能力服务，小智会越来越多才多艺。'),
          ]),
          _section(isDark, '安全说明', [
            _p(sub, '涉及打电话、发短信、闹钟、日程等真实系统操作时，'
                '都会先展示内容并由你手动确认，安卓系统的安全设计始终生效。'),
          ]),
          _section(isDark, '其他', [
            _p(sub, '本应用持续更新迭代，功能可能随版本升级而增减；'
                '如对功能有疑问，可在开发者中心查看运行日志排查问题。'),
          ]),
        ],
      ),
    );
  }

  Widget _section(bool isDark, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _p(Color color, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: bold ? 15 : 13.5,
          fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
          height: 1.5,
          color: color,
        ),
      ),
    );
  }
}
