import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xiaozhi_client_flutter/core/storage/storage_service.dart';

/// 智能体头像本地存储层（C 项：头像升级）。
///
/// 设计红线（lead 决策）：
/// - **仅存本地**：配置写入 `SharedPreferences`（key = `xw_avatar_<agentId>`），
///   图片拷贝到 App 私有目录 `agent_avatars/`。**绝不**写入 `AgentModel`、
///   **绝不**触碰 `cloud_sync_service.dart`，因此云端恢复不会带图片、也不会带文字头像配置。
/// - 重装 App → 私有目录与 SharedPreferences 一并清空 → 回落默认文字头像。
/// - 存储不可用时（例如 _prefs 未初始化）优雅降级为纯内存，绝不抛异常。
///
/// 取字模式 `mode`：
/// - `0` 第 1 字（默认）、`1` 第 2 字、`2` 第 3 字、`-2` 末字、`-1` 用户自填（用 `customChar`）。
class AgentAvatarConfig {
  final int mode;
  final String customChar;
  final int paletteIndex;
  final String? imagePath;

  const AgentAvatarConfig({
    this.mode = 0,
    this.customChar = '',
    this.paletteIndex = 0,
    this.imagePath,
  });

  factory AgentAvatarConfig.fromJson(Map<String, dynamic> json) {
    return AgentAvatarConfig(
      mode: json['i'] as int? ?? 0,
      customChar: json['c'] as String? ?? '',
      paletteIndex: json['p'] as int? ?? 0,
      imagePath: json['img'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'i': mode,
        'c': customChar,
        'p': paletteIndex,
        'img': imagePath,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AgentAvatarConfig.fromString(String? s) {
    if (s == null || s.isEmpty) return const AgentAvatarConfig();
    try {
      return AgentAvatarConfig.fromJson(
        jsonDecode(s) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AgentAvatarConfig();
    }
  }
}

/// 预设色板（8~12 套）。每套 `bg` 渐变 + `fg` 字色，要求 `fg` 与 `bg` 最亮处对比度 ≥ 4.5:1。
/// 实现上统一采用「中/深底 + 白字」或「很浅底 + 深灰字」，规避中明度底 + 白字发虚。
class AgentAvatarPalette {
  final List<Color> bg;
  final Color fg;

  const AgentAvatarPalette({required this.bg, required this.fg});
}

const List<AgentAvatarPalette> kAgentAvatarPalette = [
  // 深蓝渐变（最亮 0x1F6FEB 相对亮度 ~0.18）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF1F6FEB), Color(0xFF0B3D91)],
    fg: Color(0xFFFFFFFF),
  ),
  // 深绿渐变（最亮 0x0B8043）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF0B8043), Color(0xFF06623B)],
    fg: Color(0xFFFFFFFF),
  ),
  // 深紫渐变（最亮 0x6A3DE8）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF6A3DE8), Color(0xFF3D1F8F)],
    fg: Color(0xFFFFFFFF),
  ),
  // 玫红渐变（最亮 0xC2255C）→ 白字：深玫红底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFC2255C), Color(0xFF8E1B43)],
    fg: Color(0xFFFFFFFF),
  ),
  // 深青渐变（最亮 0x0E7C86）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF0E7C86), Color(0xFF0A5A62)],
    fg: Color(0xFFFFFFFF),
  ),
  // 橙棕渐变（最亮 0xB54708）→ 白字：深橙棕底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFB54708), Color(0xFF7A2E04)],
    fg: Color(0xFFFFFFFF),
  ),
  // 浅灰渐变（最亮 0xE9ECEF）→ 深灰字 0x2C2C2E：浅底深字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFE9ECEF), Color(0xFFDEE2E6)],
    fg: Color(0xFF2C2C2E),
  ),
  // 浅蓝渐变（最亮 0xD0EBFF）→ 深灰字：浅底深字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFD0EBFF), Color(0xFFA5D8FF)],
    fg: Color(0xFF2C2C2E),
  ),
  // 浅绿渐变（最亮 0xD3F9D8）→ 深灰字：浅底深字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFD3F9D8), Color(0xFFB2F2BB)],
    fg: Color(0xFF2C2C2E),
  ),
  // 浅黄渐变（最亮 0xFFF3BF）→ 深灰字：浅底深字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFFFFF3BF), Color(0xFFFFE066)],
    fg: Color(0xFF2C2C2E),
  ),
  // 深灰渐变（最亮 0x495057）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF495057), Color(0xFF343A40)],
    fg: Color(0xFFFFFFFF),
  ),
  // 靛蓝渐变（最亮 0x364FC7）→ 白字：深底白字，清晰。
  AgentAvatarPalette(
    bg: [Color(0xFF364FC7), Color(0xFF1C2E7A)],
    fg: Color(0xFFFFFFFF),
  ),
];

/// 头像存储服务（单例）。
///
/// - [revision]：保存/异步加载完成时自增，供 `AgentAvatar` 用 `ValueListenableBuilder`
///   跨页刷新（改完头像回列表/聊天页立即生效）。
/// - 惰性加载：首次 `read` 同步返回默认值（首帧即稳定文字头像，不闪烁），并触发一次
///   异步 `load`；加载完成后更新缓存并 `revision++` 触发重建。
class AgentAvatarStore {
  AgentAvatarStore._();

  static final AgentAvatarStore instance = AgentAvatarStore._();

  static const String _prefix = 'xw_avatar_';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final Map<String, AgentAvatarConfig> _cache = {};
  static final Set<String> _loaded = {};

  static String _key(String agentId) => '$_prefix$agentId';

  /// 默认配置：色板索引由 agentId 派生，保证列表色彩多样；其余取默认。
  static AgentAvatarConfig defaultConfig(String agentId) {
    final p = agentId.hashCode.abs() % kAgentAvatarPalette.length;
    return AgentAvatarConfig(paletteIndex: p);
  }

  /// 同步读取（首次会顺带把已落盘配置读进缓存）。永不抛异常。
  ///
  /// ⚠️ 两个必须守住的点（v6.8.3 实测踩过）：
  /// 1. `_lazyLoad` 会**同步**把存储里的真值写进缓存，所以这里读回缓存再返回，
  ///    **不能**在这之后用"默认值"覆盖缓存 —— 否则用户保存过的头像配置会永远失效；
  /// 2. `read()` 可能在 **build 期间**被调用（`AgentAvatar` 内部），所以**绝不能同步
  ///    notify**，否则触发 `setState() or markNeedsBuild() called during build`。
  static AgentAvatarConfig read(String agentId) {
    final cached = _cache[agentId];
    if (cached != null) return cached;
    _lazyLoad(agentId);
    final loaded = _cache[agentId];
    if (loaded != null) return loaded;
    final d = defaultConfig(agentId);
    _cache[agentId] = d;
    return d;
  }

  /// 读取**权威**配置（配置页编辑时使用，确保拿到已落盘的值）。
  ///
  /// ⚠️ 必须**总是**回读存储，而不能只信缓存：`read()` 在首次调用时会先塞入
  /// "默认值"占位并标记已加载，若这里直接返回缓存，配置页会显示成默认值
  /// （而真实的已保存配置要等异步加载完才出现，此时编辑区已不会刷新）。
  /// 存储不可用时回落缓存/默认值，绝不抛异常。
  static Future<AgentAvatarConfig> load(String agentId) async {
    try {
      final raw = StorageService.instance.getString(_key(agentId));
      if (raw != null) {
        final cfg = AgentAvatarConfig.fromString(raw);
        final changed = _cache[agentId]?.toJsonString() != cfg.toJsonString();
        _cache[agentId] = cfg;
        _loaded.add(agentId);
        if (changed) revision.value++;
        return cfg;
      }
    } catch (_) {
      // 存储不可用：降级为缓存/默认值
    }
    final d = _cache[agentId] ?? defaultConfig(agentId);
    _cache[agentId] = d;
    _loaded.add(agentId);
    return d;
  }

  /// 惰性加载：把已落盘配置**同步**读进缓存（SharedPreferences 的读是同步的）。
  ///
  /// 为什么要同步读进缓存：`read()` 首次调用发生在 `AgentAvatar.build()` 里，
  /// 若此处只做异步加载，首帧会先用默认色板/默认取字渲染，之后才纠正（闪烁）。
  /// 同步读进缓存 ⇒ **首帧就是正确的文字头像**（需求要求"不闪烁"）。
  ///
  /// ⚠️ 但**刷新通知必须推迟到微任务**：build 期间同步 `revision.value++` 会让
  /// 正在构建的 `ValueListenableBuilder` 被 `markNeedsBuild`，触发
  /// `setState() or markNeedsBuild() called during build` 断言。
  /// 又因为缓存已同步更新、当前这帧读到的就是新值，首次填充时**根本不需要通知**。
  static void _lazyLoad(String agentId) {
    if (_loaded.contains(agentId)) return;
    _loaded.add(agentId);
    try {
      final raw = StorageService.instance.getString(_key(agentId));
      if (raw == null) return;
      final cfg = AgentAvatarConfig.fromString(raw);
      final prev = _cache[agentId];
      if (prev != null && prev.toJsonString() == cfg.toJsonString()) return;
      _cache[agentId] = cfg;
      if (prev == null) return; // 首次填充：当前这帧已读新值，无需额外通知
      Future<void>.microtask(() => revision.value++);
    } catch (_) {
      // 存储不可用：保持默认，不抛异常
    }
  }

  /// 保存配置并触发刷新。存储失败时仅更新内存缓存，不抛异常。
  static Future<void> save(String agentId, AgentAvatarConfig cfg) async {
    _cache[agentId] = cfg;
    _loaded.add(agentId);
    try {
      await StorageService.instance.setString(_key(agentId), cfg.toJsonString());
    } catch (_) {
      // 存储不可用：内存缓存已更新，降级
    }
    revision.value++;
  }

  /// 取字纯逻辑：按 mode 从 name 取字，越界/空 → 回落第 1 字；name 空 → '乐'。
  static String pickDisplayChar(String name, int mode, String customChar) {
    if (mode == -1) {
      final c = customChar.trim();
      if (c.isNotEmpty) return c.characters.first;
      return '乐';
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '乐';
    final chars = trimmed.characters;
    switch (mode) {
      case 1:
        return chars.length >= 2 ? chars.elementAt(1) : chars.first;
      case 2:
        return chars.length >= 3 ? chars.elementAt(2) : chars.first;
      case -2:
        return chars.last;
      default:
        return chars.first;
    }
  }

  // ---- 本地图片 ----

  static Future<Directory> _avatarDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/agent_avatars');
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (_) {
      // 目录创建失败：后续 copy 会抛，由调用方 catch
    }
    return dir;
  }

  /// 拷贝选中图片到 App 私有目录，返回新路径。会先删除旧图片（oldPath）。
  static Future<String> saveImage(String agentId, File source,
      {String? oldPath}) async {
    if (oldPath != null) {
      try {
        final old = File(oldPath);
        if (await old.exists()) await old.delete();
      } catch (_) {
        // 旧文件删除失败：忽略，继续写新文件
      }
    }
    final dir = await _avatarDir();
    final name = '${agentId}_${DateTime.now().millisecondsSinceEpoch}.png';
    final dest = File('${dir.path}/$name');
    await source.copy(dest.path);
    return dest.path;
  }

  /// 删除本地图片（清除图片 / 替换时由 saveImage 调用，这里供显式清除）。
  static Future<void> deleteImage(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 忽略
    }
  }

  /// 测试辅助：清空内存缓存与加载标记（**不影响**持久化存储）。
  /// 用于验证"存 → 清内存 → 再读"能否正确回读已落盘配置。
  static void resetForTest() {
    _cache.clear();
    _loaded.clear();
  }
}
