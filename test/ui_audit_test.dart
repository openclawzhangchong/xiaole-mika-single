// v1.1.5 UI 截图审计（golden 测试）
// 运行：flutter test --update-goldens test/ui_audit_test.dart
// 产出：test/goldens/*.png（供逐屏对照 v7 原型审计）
//
// 说明：测试环境使用 FlutterTest 内置字体，中文字符可能显示为方块，
// 但颜色/形状/布局/对齐完全真实，可用于视觉审计。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaozhi_client_flutter/app/config/app_config.dart';
import 'package:xiaozhi_client_flutter/app/themes/app_theme.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';
import 'package:xiaozhi_client_flutter/data/models/message_model.dart';
import 'package:xiaozhi_client_flutter/presentation/pages/chat/widgets/chat_input_bar.dart';
import 'package:xiaozhi_client_flutter/presentation/pages/chat/widgets/message_list.dart';
import 'package:xiaozhi_client_flutter/presentation/pages/conversation/conversation_page.dart';
import 'package:xiaozhi_client_flutter/presentation/pages/settings/settings_page.dart';

const _phoneSize = Size(390, 844);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme(),
    home: Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      body: child,
    ),
  );
}

MessageModel _msg(
  String content, {
  required MessageSender sender,
  required MessageType type,
  required int hour,
  required int minute,
}) {
  return MessageModel(
    id: 'm_$content',
    content: content,
    type: type,
    sender: sender,
    timestamp: DateTime(2026, 9, 6, hour, minute),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // mock path_provider（Hive.initFlutter 需要），指向临时目录
    final tmpDir = Directory.systemTemp.createTempSync('xiaole_audit_hive');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmpDir.path,
    );
    // mock 录音插件通道（音频能力检测在测试环境无实现）
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConfig.keyAgentList: jsonEncode([
        {
          'id': 'xiaole',
          'name': 'XiaoLe',
          'url': 'wss://example.com/ws',
          'token': 'token-a',
          'description': 'AI assistant, always on',
          'updatedAt': '2026-09-06T10:24:00.000Z',
        },
        {
          'id': 'zhixin',
          'name': 'ZhiXin',
          'url': 'wss://example.com/ws',
          'token': 'token-b',
          'description': 'Warm companion agent',
          'updatedAt': '2026-09-05T18:30:00.000Z',
        },
        {
          'id': 'geek',
          'name': 'Geek',
          'url': 'wss://example.com/ws',
          'token': 'token-c',
          'description': 'Coding expert agent',
          'updatedAt': '2026-09-01T09:12:00.000Z',
        },
      ]),
    });
    await StorageService.instance.init();
  });

  testWidgets('AUDIT 1: 聊天页消息排版（时间分隔条/系统消息/方形头像/气泡）',
      (tester) async {
    tester.view.physicalSize = _phoneSize * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final messages = [
      _msg('You are connected to agent A', sender: MessageSender.system, type: MessageType.system, hour: 10, minute: 18),
      _msg('Hello! I am your AI assistant.', sender: MessageSender.ai, type: MessageType.text, hour: 10, minute: 18),
      _msg('What is the weather tomorrow?', sender: MessageSender.user, type: MessageType.text, hour: 10, minute: 20),
      _msg('Sure, tomorrow will be sunny, 18-26C.', sender: MessageSender.ai, type: MessageType.text, hour: 10, minute: 20),
      _msg('System maintenance notice', sender: MessageSender.system, type: MessageType.system, hour: 10, minute: 21),
    ];

    await tester.pumpWidget(_wrap(
      MessageList(
        messages: messages,
        scrollController: ScrollController(),
        avatarStyleIndex: 3,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('goldens/audit_chat_messages.png'));
  });

  testWidgets('AUDIT 2: 输入栏（空 = 只有麦克风/输入框/电话）', (tester) async {
    tester.view.physicalSize = _phoneSize * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Spacer(),
        ChatInputBar(
          textController: controller,
          onSendText: () {},
          onStartVoice: () {},
          onStartCall: () {},
        ),
      ],
    )));
    await tester.pump();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/audit_input_empty.png'));
  });

  testWidgets('AUDIT 3: 输入栏（有字 = 绿色发送胶囊出现）', (tester) async {
    tester.view.physicalSize = _phoneSize * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(_wrap(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Spacer(),
        ChatInputBar(
          textController: controller,
          onSendText: () {},
          onStartVoice: () {},
          onStartCall: () {},
        ),
      ],
    )));
    await tester.pump();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/audit_input_typed.png'));
  });

  testWidgets('AUDIT 4: 会话列表（通栏单元格/48px 方形头像/右侧时间/无菜单按钮）',
      (tester) async {
    tester.view.physicalSize = _phoneSize * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        ProviderScope(child: _wrap(const ConversationPage())));
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/audit_conversation_list.png'));
  });

  testWidgets('AUDIT 5: 我页（分组白卡/28px 图标色块/标题「我」）', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(child: _wrap(const SettingsPage())));
    // 音频能力 FutureBuilder 走平台通道，测试环境保持等待态/错误态均可，多次 pump 避免抖动
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/audit_profile_page.png'));
  });
}
