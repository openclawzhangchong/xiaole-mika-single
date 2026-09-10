import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/themes/app_colors.dart';
import 'agent_avatar.dart';

/// 「我」页资料头（对齐原型 v6 的 .profile-header）
/// 头像 + 昵称 + ID + 箭头，点击可编辑昵称/ID（存 SharedPreferences）。
class ProfileHeader extends StatefulWidget {
  const ProfileHeader({super.key});

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  static const String _kName = 'profile_name';
  static const String _kId = 'profile_id';

  String _name = '小乐';
  String _id = 'xiaole_user_001';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString(_kName) ?? '小乐';
      _id = prefs.getString(_kId) ?? 'xiaole_user_001';
      _loading = false;
    });
  }

  Future<void> _save(String name, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name.trim().isEmpty ? '小乐' : name.trim());
    await prefs.setString(_kId, id.trim().isEmpty ? 'xiaole_user_001' : id.trim());
    if (!mounted) return;
    setState(() {
      _name = prefs.getString(_kName) ?? '小乐';
      _id = prefs.getString(_kId) ?? 'xiaole_user_001';
    });
  }

  void _edit() {
    final nameCtl = TextEditingController(text: _name);
    final idCtl = TextEditingController(text: _id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtl,
              decoration: const InputDecoration(labelText: 'ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _save(nameCtl.text, idCtl.text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      child: InkWell(
        onTap: _edit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Row(
            children: [
              AgentAvatar(
                styleIndex: 0,
                size: 64,
                radius: 8,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _loading
                        ? const SizedBox(
                            height: 20,
                            width: 80,
                            child: LinearProgressIndicator(),
                          )
                        : Text(
                            _name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                    const SizedBox(height: 4),
                    _loading
                        ? const SizedBox(
                            height: 14,
                            width: 120,
                            child: LinearProgressIndicator(),
                          )
                        : Text(
                            'ID: $_id',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
