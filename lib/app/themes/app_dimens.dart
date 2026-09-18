/// 微信风尺寸 / 圆角 / 间距 token（v6.10.0 新建）
/// ------------------------------------------------------------
/// 旧 `AppDimens` 定义在 app_colors.dart 内且**全项目零引用**（实测 lib/ 与 test/ 均 0 引用），
/// 本次迁出并补齐。若与 app_colors.dart 中的旧同名类同时 import 会类名冲突，
/// 故已从 app_colors.dart 移除旧类（零引用 ⇒ 移除安全）。
class AppDimens {
  AppDimens._();

  // ========== 圆角 ==========
  /// 2px — 极小元素（标签 / 徽标）
  static const double radiusXs = 2;

  /// 4px — 输入框 / 小按钮 / 消息气泡
  static const double radiusSm = 4;

  /// 8px — 卡片 / 分组白卡 / 弹窗内块
  static const double radiusMd = 8;

  /// 12px — 弹窗 / 大卡片
  static const double radiusLg = 12;

  /// 7px — 28px 图标色块专用（微信规范，勿改）
  static const double radiusIcon = 7;

  /// 6px — 48px 会话头像专用（微信规范，勿改）
  static const double radiusAvatar = 6;

  // ========== 高度 ==========
  /// 导航栏高
  static const double navBarHeight = 48;

  /// 底部 TabBar 高（微信 56）
  static const double tabBarHeight = 56;

  /// 输入栏高
  static const double inputBarHeight = 52;

  /// 单元格单行高
  static const double cellSingle = 56;

  /// 单元格双行高
  static const double cellDouble = 68;

  // ========== 头像 / 图标 ==========
  /// 会话列表头像 48
  static const double avatarList = 48;

  /// 消息气泡头像 40
  static const double avatarMessage = 40;

  /// 资料页头像 64
  static const double avatarProfile = 64;

  /// 设置行图标色块 28
  static const double iconTile = 28;

  // ========== 间距（8 点栅格） ==========
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;
  static const double gapXxl = 32;

  // ========== 页面 ==========
  /// 页面左右内边距（微信 16）
  static const double pagePadding = 16;

  /// 分组纵向内边距
  static const double sectionPaddingV = 8;

  /// 微信细线宽度
  static const double hairline = 0.5;
}
