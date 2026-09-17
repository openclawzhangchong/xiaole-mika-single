import 'package:flutter/material.dart';

/// 设备身份字段编辑对话框（v6.7.0 自 settings_page 迁出公共化）
/// MAC / ClientID / 型号三处共用；行为与原 `_editDeviceField` 完全一致。
///
/// ⚠️ 调用方注意：MAC 的 [onSave] 必须保留 `v.trim().toLowerCase()` 强制小写——
/// 服务器 WS 侧按 device-id 查设备区分大小写，大写 MAC 会 OTA 激活成功但连上
/// 即被静默踢线（close code=1005）。
Future<void> showDeviceEditDialog(
  BuildContext context, {
  required String title,
  required Future<String> Function() getCurrent,
  required Future<void> Function(String) onSave,
}) async {
  final current = await getCurrent();
  if (!context.mounted) return;
  final controller = TextEditingController(text: current);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: '输入新值'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            await onSave(controller.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已保存，重新进入对话后生效'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
}
