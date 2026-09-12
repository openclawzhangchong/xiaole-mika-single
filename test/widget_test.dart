// App 启动冒烟测试（v4.0.0：替换建项目残留的 counter 模板——
// 原模板测试的计数器 UI 根本不存在，自创建起就是失败项）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiaozhi_client_flutter/main.dart';

void main() {
  testWidgets('App 启动冒烟：MyApp 可构建出 MaterialApp', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
