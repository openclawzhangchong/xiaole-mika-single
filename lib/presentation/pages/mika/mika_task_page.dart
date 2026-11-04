import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/mika/mika_bridge.dart';

/// Mika 执行页：在同一个 APK、同一个进程里直接调 Mika 引擎。
///
/// 这里不再需要 `adb forward`、PC 网关或 HTTP；提交后状态由引擎经 MethodChannel 回调。
class MikaTaskPage extends StatefulWidget {
  const MikaTaskPage({super.key});

  @override
  State<MikaTaskPage> createState() => _MikaTaskPageState();
}

class _MikaTaskPageState extends State<MikaTaskPage> {
  final TextEditingController _goal = TextEditingController();
  final List<String> _events = [];
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _result;
  String? _taskId;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    MikaBridge.install();
    MikaBridge.onTaskState = (event) {
      if (!mounted) return;
      setState(() {
        final status = event['status']?.toString() ?? '';
        if (status.isNotEmpty && !_events.contains(status)) {
          _events.add(status);
        }
      });
    };
    MikaBridge.engineInfo().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  void dispose() {
    MikaBridge.onTaskState = null;
    _goal.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _goal.text.trim();
    if (text.isEmpty || _running) return;
    setState(() {
      _running = true;
      _events.clear();
      _result = null;
      _taskId = null;
    });
    try {
      final result = await MikaBridge.runTask(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _taskId = result['task_id']?.toString();
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = {'status': 'error', 'reason': '$e'};
        _running = false;
      });
    }
  }

  Future<void> _cancel() async {
    final id = _taskId;
    if (id == null) return;
    await MikaBridge.cancel(id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(' Mika 执行'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _infoCard(scheme),
          const SizedBox(height: 16),
          TextField(
            controller: _goal,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '任务目标',
              hintText: '例如：打开 https://example.com 并告诉我页面标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_running ? '执行中…' : '在进程内执行'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _taskId == null ? null : _cancel,
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_events.isNotEmpty) _statusTimeline(scheme),
          if (_result != null) ...[
            const SizedBox(height: 16),
            _resultCard(scheme),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(ColorScheme scheme) {
    final info = _info;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: info == null
                ? const Text('正在读取引擎信息…')
                : Text(
                    'Mika ${info['version'] ?? '?'} · 进程内直调 · PID ${info['process'] ?? '?'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
          TextButton(
            onPressed: () => MikaBridge.openMikaUi(),
            child: const Text('引擎设置'),
          ),
        ],
      ),
    );
  }

  Widget _statusTimeline(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('状态流转', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < _events.length; i++)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(_events[i]),
                avatar: CircleAvatar(
                  backgroundColor:
                      i == _events.length - 1 ? scheme.primary : scheme.outline,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultCard(ColorScheme scheme) {
    final result = _result!;
    final status = result['status']?.toString() ?? 'unknown';
    final answer = result['answer']?.toString();
    final reason = result['reason']?.toString() ?? result['message']?.toString();
    final ok = status == 'done';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? scheme.primary : scheme.error,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline,
                  color: ok ? scheme.primary : scheme.error),
              const SizedBox(width: 8),
              Text('执行结果 · $status',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          if (answer != null && answer.isNotEmpty)
            SelectableText(answer, style: const TextStyle(fontSize: 15)),
          if (reason != null && reason.isNotEmpty)
            SelectableText(reason, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('原始 JSON（与 HTTP /api/v1/tasks 一致）',
                style: TextStyle(fontSize: 12)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: scheme.surfaceContainerHighest,
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(result),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
