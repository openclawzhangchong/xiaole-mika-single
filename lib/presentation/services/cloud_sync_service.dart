import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/config/app_config.dart';
import '../../data/models/agent_model.dart';
import '../../data/models/message_model.dart';
import 'chat_history_store.dart';
import 'agent_identity_store.dart';
import '../../core/utils/xiaozhi_device_info_util.dart';

/// 一键云端（v4.1.0，纯表现层新增，零红线）
///
/// 复用网页版批次C 的 xiaole-cloud-api + D1，三端（网页/桌面/App）一次同步即互通：
/// - 端点：POST /bind · POST /push · POST /pull（API=xiaole-cloud-api.pages.dev）
/// - 凭证 = 手机号 + 用户名 双因子核验（/bind 起昵称即锁定，重绑须同名）；
/// - 聊天块 ≤250 条/块 × 每会话保留 2 块 ≈ 500 条（服务端裁剪保护）；
/// - 服务端铁律：聊天块纯 INSERT+DELETE（冷热分离），users 元数据覆盖式 upsert。
///
/// 互通映射（与网页版 app.html 批次C 逐字段对齐）：
/// - 消息：web {role:'user'|'ai'|'system', text, ts(毫秒), hm('HH:mm'), img} ↔ MessageModel
///   （App 侧图片仅本地路径，不互通图片本体；pull 到的 img(dataURL) 存 metadata）；
/// - 智能体：web {id, name, avatarIndex, conf{fOta,fWs,fToken,fModel,fBoard,...}, createdAt}
///   ↔ AgentModel（App 头像按 id.hashCode 派生渲染，avatarIndex 不映射显示，仅上传兜底 0）。
class CloudSyncService {
  CloudSyncService();

  static const String cloudApi = 'https://xiaole-cloud-api.pages.dev';
  static const int blockMsgLimit = 250; // 每块消息上限（与服务端 BLOCK_MSG_LIMIT 一致）
  static const int blockKeep = 2; // 每会话保留块数（2 块 ≈ 500 条）
  // v4.3.2：单次 HTTP 超时由 30s 放宽到 60s（真机弱网 + 大包上传容易被 30s 截断）
  static const Duration httpTimeout = Duration(seconds: 60);
  // v4.3.2：日志正文/响应体打印上限（超出截断，避免刷爆缓冲与控制台）
  static const int logClip = 800;

  /// v4.3.2：云同步链路日志（自动进 LogBuffer，见 main.dart 的 onRecord）
  static final Logger _log = Logger('CloudSync');

  /// 响应体截断（保留前 [max] 字符并标注被截长度）
  static String _clip(String s, [int max = logClip]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...[+${s.length - max} chars]';
  }

  /// 手机号脱敏（日志不落明文手机号）
  static String _maskPhone(String phone) => phone.length >= 11
      ? '${phone.substring(0, 3)}****${phone.substring(7)}'
      : phone;

  /// 各会话消息条数概览：`{agentA:12, agentB:300}`
  static String _sessionCounts(Map<String, List<MessageModel>> sessions) =>
      sessions.entries.map((e) => '${e.key}:${e.value.length}').join(', ');

  // 绑定状态持久化键
  static const String _kState = 'cloud_sync_state';
  // 本地资料键（与 profile_header.dart 一致，恢复昵称用）
  static const String _kProfileName = 'profile_name';

  final http.Client _client = http.Client();

  // ================= 绑定状态 =================

  /// 读取本机绑定状态（null = 未绑定）
  static Future<CloudSyncState?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kState);
    if (raw == null || raw.isEmpty) return null;
    try {
      return CloudSyncState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveState(CloudSyncState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kState, jsonEncode(s.toJson()));
  }

  /// 仅解除本机绑定（云端数据不受影响）
  static Future<void> clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kState);
  }

  // ================= API =================

  Map<String, dynamic> _err(String body, int code) {
    String msg = 'HTTP $code';
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['error'] is String && (j['error'] as String).isNotEmpty) {
        msg = j['error'] as String;
      }
    } catch (_) {}
    return {'ok': false, 'error': msg};
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final sw = Stopwatch()..start();
    final payload = jsonEncode(body);
    _log.info('→ POST $path 请求体 ${payload.length} 字节');
    try {
      final resp = await _client
          .post(
            Uri.parse('$cloudApi$path'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(httpTimeout);
      sw.stop();
      _log.info('← POST $path HTTP ${resp.statusCode}'
          ' 耗时 ${sw.elapsedMilliseconds}ms 响应体=${_clip(resp.body)}');
      if (resp.statusCode != 200) return _err(resp.body, resp.statusCode);
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        _log.warning('POST $path 响应非 JSON：${_clip(resp.body)}');
        return {'ok': false, 'error': '响应格式错误'};
      }
    } on TimeoutException catch (e) {
      sw.stop();
      _log.severe('✗ POST $path 超时（${sw.elapsedMilliseconds}ms）：$e');
      rethrow;
    } catch (e) {
      sw.stop();
      _log.severe('✗ POST $path 异常（${sw.elapsedMilliseconds}ms）：$e');
      rethrow;
    }
  }

  /// 绑定（幂等；同手机号重绑必须同名）
  /// 成功返回 {'ok':true,'boundAt':int,'existed':bool}，失败 {'ok':false,'error':..}
  Future<Map<String, dynamic>> bind(String phone, String userName,
      {Map<String, dynamic>? profile, List<Map<String, dynamic>>? agents}) async {
    _log.info('绑定开始 phone=${_maskPhone(phone)} userName=$userName');
    final r = await _post('/bind', {
      'phone': phone,
      'userName': userName,
      if (profile != null) 'profile': profile,
      if (agents != null) 'agents': agents,
    });
    _log.info(r['ok'] == true
        ? '绑定成功 phone=${_maskPhone(phone)}'
        : '绑定失败：${r['error']}');
    if (r['ok'] == true) {
      await _saveState(CloudSyncState(
        phone: phone,
        userName: userName,
        boundAt: (r['boundAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        lastSync: 0,
      ));
    }
    return r;
  }

  /// 上传（全部智能体聊天记录 + 智能体配置 + 昵称档案）
  /// [sessions] = agentId → 该会话消息（内部取最近 500 条打包成 ≤250/块 × 2 块）
  Future<Map<String, dynamic>> pushAll({
    required CloudSyncState state,
    required String nickname,
    required List<AgentModel> agents,
    required Map<String, List<MessageModel>> sessions,
  }) async {
    _log.info('pushAll 开始：${agents.length} 个智能体，'
        '本地会话 ${sessions.length} 个（${_sessionCounts(sessions)}）');
    final blocks = <Map<String, dynamic>>[];
    // v6.2.0：先读取每个智能体的**设备身份**（MAC/ClientID）并随配置一并上传。
    // 背景：原先只传 fOta/fWs/fToken 等（注释称 fMac/fCid"App 侧不伪造"），
    // 但自 v1.1.5 起身份已是**每智能体独立**（AgentIdentityStore），网页版 conf 也一直存这两键。
    // 不上传的后果：重装 App 后云端没有身份副本 → 恢复时用本机新生成的身份 → 连不回原智能体。
    final identities = <String, Map<String, String>>{};
    for (final a in agents) {
      final ident = await AgentIdentityStore.load(a.id);
      if (ident != null) {
        identities[a.id] = ident;
        _log.info('已读取智能体 ${a.id} 的设备身份（mac=${ident['mac']}）');
      } else {
        _log.info('智能体 ${a.id} 无本地身份记录（将不上传 fMac/fCid）');
      }
    }
    for (final a in agents) {
      final msgs = sessions[a.id];
      if (msgs == null || msgs.isEmpty) {
        _log.info('会话 ${a.id} 无本地消息，跳过');
        continue;
      }
      final recent = msgs.length > blockMsgLimit * blockKeep
          ? msgs.sublist(msgs.length - blockMsgLimit * blockKeep)
          : msgs;
      final webMsgs = recent.map(messageToWeb).toList();
      final blockCount = (webMsgs.length / blockMsgLimit).ceil();
      for (int i = 0; i < blockCount; i++) {
        final start = i * blockMsgLimit;
        final rawEnd = (i + 1) * blockMsgLimit;
        // v4.3.2 修复：sublist 的 end 超过 length 会抛 RangeError，
        // 导致 pushAll 直接崩溃、UI 永远停在「打包完成」（真机卡死主因）。
        final end = rawEnd > webMsgs.length ? webMsgs.length : rawEnd;
        final chunk = webMsgs.sublist(start, end);
        _log.info('打包 ${a.id} 第 ${i + 1}/$blockCount 块：${chunk.length} 条'
            '（下标 $start..$end）');
        blocks.add({
          'agentId': a.id,
          'seq': i + 1,
          'messages': chunk,
        });
      }
      _log.info('智能体 ${a.id}：本地 ${msgs.length} 条 → 取最近 '
          '${webMsgs.length} 条 → $blockCount 块');
    }
    _log.info('打包完成：共 ${blocks.length} 块，开始 POST /push');
    final r = await _post('/push', {
      'phone': state.phone,
      'userName': state.userName,
      'agentId': '*', // 全部智能体模式
      'blocks': blocks,
      'profile': {'userName': nickname},
      'agents': agents
          .map((a) => agentToWeb(a, identity: identities[a.id]))
          .toList(),
    });
    _log.info('pushAll 结果：${r['ok'] == true ? '成功' : '失败 ${r['error']}'}'
        '（blocks=${r['blocks']} messages=${r['messages']}）');
    if (r['ok'] == true) {
      await _saveState(CloudSyncState(
        phone: state.phone,
        userName: state.userName,
        boundAt: state.boundAt,
        lastSync: (r['syncedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ));
    }
    return r;
  }

  /// 拉取云端数据（结构化返回；不写本地，写盘由 UI 层主导以便展示进度/确认）
  Future<Map<String, dynamic>> pullAll(CloudSyncState state) async {
    _log.info('pullAll 开始 phone=${_maskPhone(state.phone)} '
        'userName=${state.userName}');
    final r = await _post(
        '/pull', {'phone': state.phone, 'userName': state.userName});
    if (r['ok'] != true) {
      _log.warning('pullAll 失败：${r['error']}');
      return r;
    }
    final agents = <AgentModel>[];
    // v6.2.0：同时收集每智能体的**设备身份**（conf.fMac/fCid），供恢复时写回本地。
    // 云端老数据可能没有这两键 → 自动跳过（行为与旧版一致，不会更糟）。
    final identities = <String, Map<String, String>>{};
    final rawAgents = r['agents'];
    if (rawAgents is List) {
      for (final a in rawAgents) {
        if (a is Map<String, dynamic>) {
          final m = agentFromWeb(a);
          if (m != null) agents.add(m);
          final id = a['id'];
          final conf = a['conf'];
          if (id is String && conf is Map) {
            final mac = conf['fMac'];
            final cid = conf['fCid'];
            if (mac is String &&
                mac.isNotEmpty &&
                cid is String &&
                cid.isNotEmpty) {
              identities[id] = {'mac': mac, 'clientId': cid};
            }
          }
        }
      }
    }
    if (identities.isNotEmpty) {
      _log.info('pullAll：云端含设备身份 ${identities.length} 个（可恢复）');
    } else {
      _log.info('pullAll：云端无设备身份字段（老数据），恢复时跳过身份写回');
    }
    final sessions = <String, List<MessageModel>>{};
    int msgCount = 0;
    final rawSessions = r['sessions'];
    if (rawSessions is Map) {
      rawSessions.forEach((aid, list) {
        if (list is! List) return;
        final msgs = <MessageModel>[];
        for (final m in list) {
          if (m is Map<String, dynamic>) {
            final msg = messageFromWeb(m);
            if (msg != null) msgs.add(msg);
          }
        }
        if (msgs.isNotEmpty) {
          sessions[aid.toString()] = msgs;
          msgCount += msgs.length;
        }
      });
    }
    final profile = r['profile'];
    final nickname = (profile is Map<String, dynamic>)
        ? (profile['userName'] as String? ?? '')
        : '';
    _log.info('pullAll 成功：${agents.length} 个智能体 / $msgCount 条消息');
    return {
      'ok': true,
      'agents': agents,
      'sessions': sessions,
      'messages': msgCount,
      'nickname': nickname,
      'identities': identities, // v6.2.0：设备身份（供 applyPullResult 写回）
      'cloudAgentCount': rawAgents is List ? rawAgents.length : 0,
    };
  }

  /// v6.2.0：**清空该账号在云端的全部数据**（`users` 行 + 名下所有 `chat_blocks`）。
  ///
  /// ⚠️ 危险操作 —— 调用方（UI）**必须先做二次确认**。
  /// 清空后本地绑定状态保留（仍处于已绑定），仅重置 lastSync。
  Future<Map<String, dynamic>> clearAll(CloudSyncState state) async {
    _log.warning('clearAll 开始（清空云端数据）phone=${_maskPhone(state.phone)}');
    final r = await _post('/clear', {
      'phone': state.phone,
      'userName': state.userName,
    });
    if (r['ok'] == true) {
      await _saveState(CloudSyncState(
        phone: state.phone,
        userName: state.userName,
        boundAt: state.boundAt,
        lastSync: 0,
      ));
      _log.warning('clearAll 成功：云端数据已清空'
          '（agents=${r['deletedAgents']} blocks=${r['deletedBlocks']}）');
    } else {
      _log.warning('clearAll 失败：${r['error']}');
    }
    return r;
  }

  /// 恢复写盘：覆盖本机智能体列表 + 聊天记录 + 昵称（UI 层先 confirm 再调用）
  static Future<void> applyPullResult({
    required Map<String, dynamic> result,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final agents = result['agents'] as List<AgentModel>;
    final sessions = result['sessions'] as Map<String, List<MessageModel>>;

    // 1) 覆盖智能体列表（与 AgentLocalStorage 同键同格式）
    await prefs.setString(AppConfig.keyAgentList,
        jsonEncode(agents.map((a) => a.toJson()).toList()));

    // 2) 清空全部本地聊天记录（chat_history_ 前缀），再写入云端会话
    final kill = prefs.getKeys()
        .where((k) => k.startsWith(ChatHistoryStore.keyPrefix))
        .toList();
    for (final k in kill) {
      await prefs.remove(k);
    }
    for (final entry in sessions.entries) {
      // ChatHistoryStore 整表覆盖语义：直接写同键 JSON
      await prefs.setString('${ChatHistoryStore.keyPrefix}${entry.key}',
          jsonEncode(entry.value.map((m) => m.toJson()).toList()));
    }

    // 3) 恢复昵称（存在才覆盖；ID 锁定手机号）
    final nickname = result['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) {
      await prefs.setString(_kProfileName, nickname);
    }
    final state = await loadState();
    if (state != null) {
      await prefs.setString(_kProfileId, state.phone);
    }

    // 4) v6.2.0：恢复**每智能体的设备身份**（MAC / ClientID）
    //    —— 原先完全不写这一步，导致重装 App 后本机重新生成身份、连不回原智能体。
    //    同时把【首个智能体】的身份应用为**全局设备身份**，避免"恢复完成后第一次连接"
    //    仍使用新生成的身份（进入该智能体对话时 chat_page 也会再对齐一次，双重保险）。
    final identities =
        (result['identities'] as Map<String, Map<String, String>>?) ?? const {};
    for (final a in agents) {
      final id = identities[a.id];
      if (id != null) {
        await AgentIdentityStore.save(a.id,
            mac: id['mac']!,
            clientId: id['clientId']!,
            model: kUnifiedDeviceModel);
      }
    }
    if (agents.isNotEmpty) {
      final first = identities[agents.first.id];
      if (first != null) {
        await XiaozhiDeviceInfoUtil.instance.setDeviceMacAddress(first['mac']!);
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceClientId(first['clientId']!);
        await XiaozhiDeviceInfoUtil.instance
            .setDeviceModel(kUnifiedDeviceModel);
      }
    }
  }

  static const String _kProfileId = 'profile_id';
}

// ================= 绑定状态模型 =================

class CloudSyncState {
  final String phone;
  final String userName;
  final int boundAt;
  final int lastSync;

  const CloudSyncState({
    required this.phone,
    required this.userName,
    required this.boundAt,
    required this.lastSync,
  });

  factory CloudSyncState.fromJson(Map<String, dynamic> j) => CloudSyncState(
        phone: j['phone'] as String? ?? '',
        userName: j['userName'] as String? ?? '',
        boundAt: (j['boundAt'] as num?)?.toInt() ?? 0,
        lastSync: (j['lastSync'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'userName': userName,
        'boundAt': boundAt,
        'lastSync': lastSync,
      };

  /// 脱敏显示：138****5678
  String get maskedPhone =>
      phone.length >= 11 ? '${phone.substring(0, 3)}****${phone.substring(7)}' : phone;
}

// ================= 互通映射（与网页版批次C 逐字段对齐） =================

/// MessageModel → web 消息 {role, text, ts, hm}
Map<String, dynamic> messageToWeb(MessageModel m) {
  String hm;
  final h = m.timestamp.hour.toString().padLeft(2, '0');
  final min = m.timestamp.minute.toString().padLeft(2, '0');
  hm = '$h:$min';
  final role = m.sender == MessageSender.user
      ? 'user'
      : m.sender == MessageSender.ai
          ? 'ai'
          : 'system';
  return {
    'role': role,
    'text': m.content,
    'ts': m.timestamp.millisecondsSinceEpoch,
    'hm': role == 'system' ? '' : hm,
  };
}

/// web 消息 → MessageModel（解析失败返回 null 跳过）
MessageModel? messageFromWeb(Map<String, dynamic> m) {
  final text = m['text'];
  if (text == null) return null;
  final role = m['role'] as String? ?? 'ai';
  final ts = (m['ts'] as num?)?.toInt() ?? 0;
  final tsMs = ts <= 0 ? DateTime.now().millisecondsSinceEpoch : ts;
  final img = (m['img'] as String? ?? '');
  return MessageModel(
    id: 'cloud_${tsMs}_${text.hashCode}',
    content: text.toString(),
    type: img.isNotEmpty ? MessageType.image : MessageType.text,
    sender: role == 'user'
        ? MessageSender.user
        : role == 'ai'
            ? MessageSender.ai
            : MessageSender.system,
    timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
    status: MessageStatus.received,
    metadata: img.isNotEmpty ? {'img': img} : null,
  );
}

/// AgentModel → web agent {id, name, avatarIndex, conf, createdAt}
///
/// [identity] 为 `AgentIdentityStore.load()` 的结果（{mac, clientId, model}）——
/// v6.2.0 起随上传携带，使云端 `conf` 与**网页版 9 键结构**（fMac/fCid/fModel/fBoard/fOta/fWs/
/// fMode/fWorker/fToken）对齐，恢复时才能把设备身份装回本地。
Map<String, dynamic> agentToWeb(AgentModel a, {Map<String, String>? identity}) {
  return {
    'id': a.id,
    'name': a.name,
    'avatarIndex': 0, // App 头像按 id.hashCode 派生渲染，无独立索引
    'conf': {
      'fOta': a.otaUrl,
      'fWs': a.url,
      'fToken': a.token,
      'fModel': 'm5stack-core-s3',
      'fBoard': 'm5stack-core-s3',
      // v6.2.0：补上每智能体的真实设备身份（网页版一直存这两键，App 此前遗漏）
      if (identity != null) 'fMac': identity['mac'] ?? '',
      if (identity != null) 'fCid': identity['clientId'] ?? '',
    },
    'createdAt': a.createdAt?.millisecondsSinceEpoch ?? 0,
  };
}

/// web agent → AgentModel（缺 url 时用 otaUrl 兜底占位；解析失败返回 null）
AgentModel? agentFromWeb(Map<String, dynamic> a) {
  final id = a['id'] as String?;
  final name = a['name'] as String?;
  if (id == null || id.isEmpty || name == null) return null;
  final conf = (a['conf'] is Map<String, dynamic>)
      ? a['conf'] as Map<String, dynamic>
      : <String, dynamic>{};
  final ws = conf['fWs'] as String? ?? '';
  final ota = conf['fOta'] as String? ?? '';
  final createdAtMs = (a['createdAt'] as num?)?.toInt() ?? 0;
  return AgentModel(
    id: id,
    name: name,
    url: ws,
    token: conf['fToken'] as String? ?? '',
    otaUrl: ota,
    description: '',
    isActive: true,
    createdAt: createdAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
        : null,
  );
}
