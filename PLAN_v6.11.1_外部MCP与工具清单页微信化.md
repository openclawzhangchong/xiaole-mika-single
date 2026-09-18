# 方案：v6.11.1 · 外部 MCP 与工具清单页微信化

> **状态：✅ 已实施**，对应发布版本 **v6.11.1**（基线 `6.11.0+52` → `6.11.1+53`；CI run 35342901807 success，APK 40,773,270 B sha1 `0f942cee` 已下载桌面）

## 基线
- 代码基线：`v6.11.0`（`6.11.0+52`）
- 触发来源：张老师反馈「**外部 MCP 管理界面和工具列表没微信化、漏掉了**」

## 问题根因
v6.11.0 只把开发者中心**主页**重排成微信规格（通栏直角白卡 + 28px 彩色图标块 + 右侧灰值 + 底部脚注），但漏了三个从属页面，它们仍是旧排版（裸图标 + 1px 通栏 Divider + 残留 emoji）。

## 三处改动清单（用与主页同一套微信规格清掉）
1. **外部 MCP 服务器列表页**（`external_mcp_page.dart`）：每行裸图标 → 28px 彩色圆角块（在线绿 / 离线灰）；删净 emoji 🌐；1px 通栏 Divider → WxCell 自带 0.5px 细线。
2. **单台服务器逐工具开关页**（`dev_center_page.dart` 的 `_McpToolsDetailPage` 类内）：工具行裸图标 → 28px 彩色块（写工具 `merge_notes` 红色警示块）；删净 emoji ⚠️；1px Divider → WxCell 0.5px 细线。
3. **MCP 设备工具清单页**（26 项，同 `_McpToolsDetailPage` 类内）：同上规格，提示条 / 分组标题对齐微信排版。

## 红线（行为零改动）
- 开关 / 探测 / 导入 / 批量开关（全部开启·全部关闭）/ 默认关闭 `merge_notes` 等**逻辑一律不动**；
- 数据层 `disabledTools` + `mergedTools()` + `dispatch()` 拦截全部不碰；
- 不触碰 `app_theme.dart`、`lib/core/network`、`lib/data`、冻结区；**纯视觉层变更**。

## 改动文件
- 修改：`external_mcp_page.dart`、`dev_center_page.dart`（仅 `_McpToolsDetailPage` 类内）
- 版本号：`pubspec.yaml` `6.11.0+52` → `6.11.1+53`；`app_config.dart` `appVersion` → `6.11.1`

## 配套文档
- 版本号与文档同步见 `CHANGELOG.md`（新增 `## v6.11.1` 段）、`README.md`（版本档案表 + 徽章）
