import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';

/// MCP 设备能力服务 —— v6.1.0
///
/// 把「平台能力」封装成纯 Dart 接口，供 MCP 工具执行器调用（见 `chat_page._setupMcpResponder`）。
///
/// ## 设计原则
/// 1. **只做能力封装**：不含任何 MCP 协议逻辑（协议留在 `xiaozhi_mcp_responder` / `chat_page`）；
/// 2. **返回结构化结果**：统一 `{success, message, ...}`，**异常一律在内部消化**，绝不外抛
///    （工具异常绝不能影响通信链路）；
/// 3. **诚实标注 intent 的局限**：闹钟/日历/短信/拨号只是**发起系统请求**，
///    **无法确认用户在系统界面是否点了「确认」** → 返回值含 `requested: true` 与提示语，
///    从根上杜绝"AI 说设好了、实际没设"的假象（v6.1.0 的核心教训）；
/// 4. **非 Android 平台**（Windows 桌面调试）统一返回「不支持」，不崩溃。
class DeviceCapabilityService {
  DeviceCapabilityService._();
  static final DeviceCapabilityService instance = DeviceCapabilityService._();

  static bool get _isAndroid => Platform.isAndroid;

  FlutterTts? _tts;

  Map<String, dynamic> _noAndroid(String what) =>
      {'success': false, 'message': '$what 仅支持 Android（当前平台不支持）'};

  Map<String, dynamic> _fail(String msg) => {'success': false, 'message': msg};

  // ============================================================ A. 系统媒体音量

  /// 读取当前**媒体音量**（0–100）；失败返回 null
  Future<int?> getVolume() async {
    try {
      final v = await FlutterVolumeController.getVolume(stream: AudioStream.music);
      if (v == null) return null;
      return (v * 100).round().clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// 设置系统**媒体音量**（0–100）。这是 set_volume 工具的真实现：
  /// 直接改系统媒体音量，所以"说 100 就真的最大声"。
  Future<Map<String, dynamic>> setVolume(int percent) async {
    final v = percent.clamp(0, 100);
    try {
      // 不弹系统音量条（避免干扰通话/聊天界面）—— 该选项是类级开关，用官方推荐方法设置
      await FlutterVolumeController.updateShowSystemUI(false);
      await FlutterVolumeController.setVolume(
        v / 100.0,
        stream: AudioStream.music,
      );
      final now = await getVolume();
      return {'success': true, 'volume': now ?? v};
    } catch (e) {
      return _fail('设置系统音量失败：$e');
    }
  }

  // ============================================================ B. 系统闹钟 / 日历

  /// 设置**系统时钟闹钟**（`AlarmClock.ACTION_SET_ALARM`）。
  ///
  /// [weekdays] 传 Calendar 的星期常量（周日=1 … 周六=7）表示重复；
  /// 传 null 表示**只响一次**。
  ///
  /// ⚠️ 系统时钟会弹出并预填，**需要用户点「保存」才会真正生效**。
  Future<Map<String, dynamic>> setAlarm({
    required int hour,
    required int minute,
    String? label,
    List<int>? weekdays,
  }) async {
    if (!_isAndroid) return _noAndroid('系统闹钟');
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return _fail('时间不合法（hour 0-23，minute 0-59）');
    }
    try {
      final args = <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': (label ?? '小乐提醒').trim(),
        // 保留系统界面 → 让用户在时钟里确认（Android 的安全设计，无法静默写入）
        'android.intent.extra.alarm.SKIP_UI': false,
      };
      if (weekdays != null && weekdays.isNotEmpty) {
        args['android.intent.extra.alarm.DAYS'] = weekdays;
      }
      await AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: args,
      ).launch();
      final hh = hour.toString().padLeft(2, '0');
      final mm = minute.toString().padLeft(2, '0');
      return {
        'success': true,
        'requested': true, // ⚠️ 只是"已请求"，非"已生效"
        'time': '$hh:$mm',
        'label': label ?? '小乐提醒',
        'repeat': weekdays == null || weekdays.isEmpty ? 'once' : weekdays,
        'message': '已打开系统时钟并预填 $hh:$mm 的闹钟，'
            '请在时钟界面点「保存」完成设置（保存后即使 App 关闭也会响）',
      };
    } catch (e) {
      return _fail('无法打开系统时钟（该机型可能不支持）：$e');
    }
  }

  /// 写入**系统日历**（`ACTION_INSERT` + CalendarContract）。
  /// ⚠️ 同样需要用户在日历界面点保存。
  Future<Map<String, dynamic>> createCalendarEvent({
    required String title,
    required DateTime start,
    DateTime? end,
    String? description,
  }) async {
    if (!_isAndroid) return _noAndroid('系统日历');
    try {
      final e = end ?? start.add(const Duration(hours: 1));
      await AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: <String, dynamic>{
          'title': title,
          'beginTime': start.millisecondsSinceEpoch,
          'endTime': e.millisecondsSinceEpoch,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
      ).launch();
      return {
        'success': true,
        'requested': true,
        'title': title,
        'begin': start.toIso8601String(),
        'message': '已打开系统日历并预填「$title」，'
            '请在日历界面点「保存」完成（保存后即使 App 关闭也会提醒）',
      };
    } catch (e) {
      return _fail('无法打开系统日历（该机型可能不支持）：$e');
    }
  }

  // ============================================================ C. 系统能力（intent）

  /// 打开拨号盘并预填号码（**不直接拨出**，免权限）
  Future<Map<String, dynamic>> dial(String number) async {
    if (!_isAndroid) return _noAndroid('拨号');
    final n = number.replaceAll(RegExp(r'[^\d+#*]'), '');
    if (n.isEmpty) return _fail('号码为空');
    try {
      await AndroidIntent(
        action: 'android.intent.action.DIAL',
        data: 'tel:$n',
      ).launch();
      return {
        'success': true,
        'requested': true,
        'number': n,
        'message': '已打开拨号盘并填入 $n，请点绿色按钮拨出',
      };
    } catch (e) {
      return _fail('无法打开拨号盘：$e');
    }
  }

  /// 打开短信界面并预填号码与内容（免权限）
  Future<Map<String, dynamic>> sendSms({
    required String number,
    required String body,
  }) async {
    if (!_isAndroid) return _noAndroid('短信');
    final n = number.replaceAll(RegExp(r'[^\d+#*]'), '');
    if (n.isEmpty) return _fail('号码为空');
    try {
      await AndroidIntent(
        action: 'android.intent.action.SENDTO',
        data: 'smsto:$n',
        arguments: <String, dynamic>{'sms_body': body},
      ).launch();
      return {
        'success': true,
        'requested': true,
        'number': n,
        'message': '已打开短信界面并填好内容，请点发送',
      };
    } catch (e) {
      return _fail('无法打开短信界面：$e');
    }
  }

  /// 打开地图导航到目的地（免权限）
  Future<Map<String, dynamic>> navigate(String destination) async {
    if (!_isAndroid) return _noAndroid('地图导航');
    final d = destination.trim();
    if (d.isEmpty) return _fail('目的地为空');
    try {
      await AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'geo:0,0?q=${Uri.encodeComponent(d)}',
      ).launch();
      return {
        'success': true,
        'requested': true,
        'destination': d,
        'message': '已打开地图并定位到「$d」，请选择路线开始导航',
      };
    } catch (e) {
      return _fail('无法打开地图：$e');
    }
  }

  /// 打开系统设置页。[page] 取值见 [settingsActions]（wifi/bluetooth/sound/app…）
  static const Map<String, String> settingsActions = {
    'wifi': 'android.settings.WIFI_SETTINGS',
    'bluetooth': 'android.settings.BLUETOOTH_SETTINGS',
    'sound': 'android.settings.SOUND_SETTINGS',
    'display': 'android.settings.DISPLAY_SETTINGS',
    'battery': 'android.settings.BATTERY_SAVER_SETTINGS',
    'location': 'android.settings.LOCATION_SOURCE_SETTINGS',
    'apps': 'android.settings.APPLICATION_SETTINGS',
    'airplane': 'android.settings.AIRPLANE_MODE_SETTINGS',
    'data': 'android.settings.DATA_ROAMING_SETTINGS',
    'home': 'android.settings.SETTINGS',
  };

  Future<Map<String, dynamic>> openSettings(String page) async {
    if (!_isAndroid) return _noAndroid('系统设置');
    final key = page.trim().toLowerCase();
    final action = settingsActions[key];
    if (action == null) {
      return _fail('不支持的设置页「$page」，可选：${settingsActions.keys.join("/")}');
    }
    try {
      await AndroidIntent(action: action).launch();
      return {'success': true, 'requested': true, 'page': key,
        'message': '已打开系统设置（$key）'};
    } catch (e) {
      return _fail('无法打开系统设置：$e');
    }
  }

  /// 用系统浏览器打开网页（`url_launcher` 已在项目依赖中，此处用 intent 保持一致）
  Future<Map<String, dynamic>> openUrl(String url) async {
    if (!_isAndroid) return _noAndroid('打开网页');
    final u = url.trim();
    if (u.isEmpty) return _fail('链接为空');
    final fixed = (u.startsWith('http://') || u.startsWith('https://')) ? u : 'https://$u';
    try {
      await AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: fixed,
      ).launch();
      return {'success': true, 'requested': true, 'url': fixed,
        'message': '已用浏览器打开 $fixed'};
    } catch (e) {
      return _fail('无法打开链接：$e');
    }
  }

  // ============================================================ D. 轻提示 / 分享 / 剪贴板 / TTS / 亮度

  /// AI 主动轻提示（不打断对话）
  void showToast(String text) {
    try {
      Fluttertoast.showToast(
        msg: text,
        toastLength: text.length > 20 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    } catch (_) {}
  }

  /// 分享文本到其他 App（备忘录/笔记/微信…，用户点选目标）
  Future<Map<String, dynamic>> shareText(String text, {String? subject}) async {
    if (text.trim().isEmpty) return _fail('内容为空');
    try {
      await Share.share(text, subject: subject);
      return {'success': true, 'requested': true,
        'message': '已拉起系统分享面板，请选择要保存到的 App（如备忘录）'};
    } catch (e) {
      return _fail('分享失败：$e');
    }
  }

  Future<String?> getClipboard() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      return d?.text;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> setClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return {'success': true, 'length': text.length};
    } catch (e) {
      return _fail('写入剪贴板失败：$e');
    }
  }

  /// 设备**语音播报**（到点提醒时用）。
  /// ⚠️ 使用**系统自带 TTS 引擎**，**不下载任何模型**；若系统缺中文引擎则静默失败。
  Future<bool> speak(String text) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage('zh-CN');
      await tts.setSpeechRate(0.5);
      await tts.awaitSpeakCompletion(false); // 不阻塞，允许后续播报打断
      await tts.speak(text);
      return true;
    } catch (_) {
      return false; // 播报失败静默降级（消息/震动/Toast 照常）
    }
  }

  Future<void> stopSpeak() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /// 读取**应用级**屏幕亮度（0–100）
  Future<int?> getBrightness() async {
    try {
      final v = await ScreenBrightness().application;
      return (v * 100).round().clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// 设置**应用级**屏幕亮度（0–100）。
  /// 用应用级而非系统级：**不需要 `WRITE_SETTINGS` 特殊权限**（系统级需用户去设置里手动授权）。
  Future<Map<String, dynamic>> setBrightness(int percent) async {
    final v = percent.clamp(1, 100); // 0 会黑屏，下限取 1
    try {
      await ScreenBrightness().setApplicationScreenBrightness(v / 100.0);
      return {'success': true, 'brightness': v};
    } catch (e) {
      return _fail('设置亮度失败：$e');
    }
  }
}
