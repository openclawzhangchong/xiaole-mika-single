import 'external_mcp_store.dart';

/// v6.4.1：内置的外部 MCP 预置
/// ------------------------------------------------------------------
/// 目的：App 首次启动就自带「笔记 + 高德」两台外部 MCP，开箱即用，不必每次手导入。
///
/// 规则：
/// 1. **首次启动自动写入**（用 seededKey 标记，只写一次）；
/// 2. 用户可**自行编辑** url / headers（换自己的 key）；不改就用下面的默认值；
/// 3. 用户删除后不会自动恢复；需要时用管理页「恢复预置」重新载入（按 id 去重）。
///
/// ⚠️ 安全提示：以下 token / key 会被打进 APK（字符串可被提取），等同"半公开"。
///    适用于自有服务；建议在高德开放平台为 key 配置域名白名单 / 调用配额并定期轮换。
class ExternalMcpBuiltin {
  ExternalMcpBuiltin._();

  /// 是否已写入过预置（避免用户删除后被重新塞回）
  static const String seededKey = 'xw_external_mcp_seeded';

  static const String _notesToken =
      '4c735c04f3591a4b53ba66f4cb2966886fbc63389075cb61b5ff4c342ab862b7';

  static const String _amapKey = 'd6707a91eab78ba437195acbc28d2dbe';

  /// 预置清单（前缀固定 notes / amap，与确认的命名一致）
  static final List<ExternalMcpServer> presets = <ExternalMcpServer>[
    ExternalMcpServer(
      id: 'builtin_biji_notes',
      name: 'biji-notes',
      prefix: 'notes',
      url: 'https://zhangchong-biji-web.pages.dev/api/mcp/rpc',
      headers: <String, String>{'Authorization': 'Bearer $_notesToken'},
    ),
    ExternalMcpServer(
      id: 'builtin_amap_maps',
      name: 'amap-maps',
      prefix: 'amap',
      url: 'https://mcp.amap.com/mcp?key=$_amapKey',
    ),
  ];
}
