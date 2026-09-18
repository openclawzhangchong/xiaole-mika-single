# 方案：v6.11.3 · 外部 MCP 两页补白色通栏直角容器

> **状态：✅ 已实施**，对应发布版本 **v6.11.3**（CI 结论与 APK 见 CHANGELOG 验证列）

## 根因（张老师真机截图确证）
v6.11.1 漏了"容器"层：服务器列表与逐工具页的 WxCell 行直接铺在灰底上（InkWell 透明、Scaffold 灰底透出），0.5px 分割线不可见、观感未变。责任在 lead 的 v6.11.1 实施规格漏项。

## 实施
仅改 `external_mcp_page.dart`：两页行装进 `Material(color: surface)` 白色通栏直角容器（上下灰隙 10/24）；逐工具页说明文字留灰底（微信「发现页管理」式）；工具行抽 `_buildToolTile`（回调逐字未动），末行 showDivider:false。

## 红线
🔒 行为零改动；不碰冻结区/network/data。
