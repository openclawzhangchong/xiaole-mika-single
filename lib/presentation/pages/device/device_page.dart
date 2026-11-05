import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

import '../../../app/config/app_config.dart';
import '../../../app/themes/xl_tokens.dart';
import '../../../core/utils/xiaozhi_device_info_util.dart';

/// 设备页（会话列表第 3 个 Tab）
/// 设计稿未提供本屏样式，按 01/08 的列表语言延展：50pt 行 / 17 标签 / 14 值 / 脚注 12 #666
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final Battery _battery = Battery();
  late final Future<_DeviceSnapshot> _future = _load();

  Future<_DeviceSnapshot> _load() async {
    final info = XiaozhiDeviceInfoUtil.instance;
    final model = await info.getDeviceModel();
    final os = await info.getOSVersion();
    int? level;
    bool charging = false;
    try {
      level = await _battery.batteryLevel;
      charging = await _battery.batteryState == BatteryState.charging;
    } catch (_) {}
    return _DeviceSnapshot(
      model: model,
      os: os,
      level: level,
      charging: charging,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(title: const Text('设备')),
      body: FutureBuilder<_DeviceSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            padding: const EdgeInsets.only(bottom: XlDims.xxl),
            children: [
              const _GroupHeader('本机'),
              _Group(
                children: [
                  _Row(label: '设备型号', value: data?.model ?? '读取中…'),
                  _Row(label: '系统版本', value: data?.os ?? '读取中…'),
                  _Row(label: '应用版本', value: AppConfig.appVersion),
                ],
              ),
              const _GroupHeader('运行状态'),
              _Group(
                children: [
                  _Row(
                    label: '电量',
                    value: data?.level == null
                        ? '读取中…'
                        : '${data!.level}%${data.charging ? '（充电中）' : ''}',
                  ),
                  const _Row(label: '屏幕读取', value: '任务期间开启'),
                  const _Row(label: '任务结束', value: '立即停止'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  '小乐只在你发起的任务中读取屏幕，任务结束立即停止。',
                  textAlign: TextAlign.center,
                  style: XlType.meta.copyWith(color: p.sectionLabel),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceSnapshot {
  const _DeviceSnapshot({
    required this.model,
    required this.os,
    this.level,
    this.charging = false,
  });

  final String model;
  final String os;
  final int? level;
  final bool charging;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 18 / 13,
          color: p.sectionLabel,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(XlDims.rL),
        ),
        child: Column(
          children: List.generate(children.length, (i) {
            return Column(
              children: [
                children[i],
                if (i != children.length - 1)
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 16,
                    color: p.hairline,
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return SizedBox(
      height: XlDims.settingsRow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              label,
              style: XlType.listTitle.copyWith(color: p.textPrimary),
            ),
            const Spacer(),
            Text(
              value,
              style: XlType.summary.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
