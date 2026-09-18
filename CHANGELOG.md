# 更新日志（CHANGELOG）

> **约定（2026-09-13 张老师定）**：**每次版本更新都必须在这里记录**，最新版本在最上方。
> 格式：`版本号 · 日期 · 一句话主题` → 明细（修复 / 新增 / 变更 / 备注）。
> 配套要求见项目铁律：每个版本必须 push GitHub + 打 tag + README 档案行 + 确认 CI。

---

## v6.11.3 · 2026-09-18

**主题：外部 MCP 两页补白色通栏直角容器 —— v6.11.1 实施遗漏层的补全（真机截图确证）**

### 根因（张老师真机截图确证）
v6.11.1 只改了图标色块/分割线/emoji，**漏了"容器"层**：服务器列表与逐工具页的 WxCell 行**直接铺在灰色页面底上**（WxCell 的 InkWell Material 是透明的，Scaffold 灰底透出），导致 ① 观感"什么都没改"；② 0.5px 分割线在灰底上不可见；③ 文字浮在灰底上如半成品。开发者中心主页因有 `_section` 白卡包着所以正常——两页从 v6.4.0 初版就是裸 ListView，重排时未补容器，责任在 lead 的实施规格漏项。

### 变更（仅 `external_mcp_page.dart`，回调零改动）
- **服务器列表**：行包进 `Material(color: surface)` 白色通栏直角容器（上下 10/24 灰隙），0.5px 分割线在白底上显现。
- **逐工具页**：说明文字留在灰底（微信「发现页管理」式），工具行包进同款白色通栏容器；行抽成 `_buildToolTile`（回调逐字未动），末行 `showDivider:false`。

### 🧪 验证
- `flutter analyze`：**No issues**；全量 `flutter test`：**71/71**（golden 集不含这两页，基线不变）。
- **Android 构建 CI 结论**：**（占位，由 lead 回填 CI 结论）**

### 备注
- 版本号 `6.11.2+54` → `6.11.3+55`；回滚锚点 `anchor-pre-v6.11.3` = `aa971cf`。

## v6.11.2 · 2026-09-18

**主题：聊天输入栏对齐微信原版交互 —— 电话/发送互斥切换 + 侧边图标统一视觉盒（解决高低不齐与按钮拥挤）**

### 背景
张老师转来一份外部 AI 产出的输入栏改造任务。经逐条审计：**"右侧电话/发送互斥切换"这一核心交互合理采纳**；但任务中 4 处不适用于本项目被拒绝——① 固定 54 高 + 强制居中（破坏多行底部对齐向上撑的微信行为）；② 圆角 18 药丸形（微信是 ~5）；③ 硬编码 #28C76F/#F5F5F5（违反 token 纪律，且 #28C76F 非微信绿，本项目品牌色 #07C160）；④ 一行式结构没给 📷 拍照识物和 🎤 按住说话留位置（照做会砍 v3.1.0 识图与语音对讲入口）。张老师批准反提案 V1：保留四件套结构，只做三处修正。

### 变更（仅 `chat_input_bar.dart`，回调签名零改动）
- **右侧互斥切换**：输入框有文字 → 只显示绿色发送胶囊（#07C160 token，隐藏电话按钮）；清空 → 恢复电话按钮。解决"按钮拥挤"。
- **高度对齐**：侧边图标（📷🎤📞）统一 `constraints 40x36 + padding 0` 视觉盒，图标中心与输入框单行中心对齐；输入框 `minHeight 36` + `contentPadding` 垂直 8 + `isDense`；发送胶囊高 36 对齐。多行仍保持 `crossAxisAlignment: end` 底部对齐向上撑（微信行为，未采纳任务的固定 54）。
- **hint 文字**：'发消息给小乐' → '输入消息'（张老师定）。
- **间距**：输入框与两侧间距 8 → 10；左双图标间补 4。
- **不动**：圆角保持 5px（拒绝 18）、颜色全走 token、SafeArea、`onSendText/onStartVoice/onStartCall/onTakePhoto` 回调、语音/识物/通话全部功能。

### 🧪 验证
- 本地 `flutter analyze`：**No issues**（单文件）；全量 `flutter test`：**71/71**（2 张输入栏 golden 按预期重生成，旧基线已留存 /tmp/golden_old_v6112，目视核对：空态=📷+输入框+电话；有字态=发送胶囊独占右侧、电话隐藏 ✓）。
- **Android 构建 CI 结论**：**✅ success** —— run `35347340620`（attempt 1 一次通过）；APK **40,773,270 B**（sha1 `0da7d7f5`）已下载桌面 `xiaole-client-v6.11.2.apk`。

### 备注
- 版本号 `6.11.1+53` → `6.11.2+54`；回滚锚点 `anchor-pre-v6.11.2` = `e0d482c`。

## v6.11.1 · 2026-09-18

**主题：外部 MCP 管理三处从属页排版微信化 —— 28px 彩色图标块替换裸图标 + WxCell 自带 0.5px 细线替换 1px 通栏 Divider + 删净 emoji**

### 🎯 起因（张老师反馈「外部 MCP 管理界面和工具列表没微信化、漏掉了」）
v6.11.0 把开发者中心**主页**排版重排成了微信规格（通栏直角白卡 + 28px 图标色块 + 右侧灰值 + 底部脚注），但**漏了三个从属页面**，它们仍是旧排版：
1. **外部 MCP 服务器列表页**（每台服务器一行：裸图标 + 1px 通栏 Divider + 残留 emoji 🌐）；
2. **单台服务器的逐工具开关页**（`_McpToolsDetailPage`，工具行裸图标 + 1px Divider + emoji ⚠️）；
3. **MCP 设备工具清单页**（26 项，同 `_McpToolsDetailPage` 类内，裸图标 + 1px Divider）。

张老师实测反馈「外部 MCP 管理界面和工具列表没微信化、漏掉了」⇒ 本版把这三处用**与主页同一套微信规格**清掉。

### ✅ 本版做了什么（仅改 `external_mcp_page.dart` + `dev_center_page.dart` 的 `_McpToolsDetailPage` 类内，行为零改动）
1. **裸图标 → 28px 彩色圆角色块**：服务器行用 `_iconTile`（语义色走 AppColors：**在线绿 / 离线灰**），写工具（如 `merge_notes`）用**红色警示块**突出；
2. **1px 通栏 `Divider` → WxCell 自带 0.5px 细线**：分组容器统一走 WxCell / WxCellGroup，去掉自行绘制的通栏分割线；
3. **删净 emoji**：🧰 / ⚠️ 等全部移除，提示语义改用色块与灰字表达；
4. **提示条 / 分组标题对齐微信排版**：顶部「已启用 X / 共 Y 个；关闭的工具不会下发给 AI」说明条、分组灰标题字号/边距对齐主页规格。

### 📊 改动量化
- **文件：修改 2 个**（`external_mcp_page.dart`、`dev_center_page.dart` 的 `_McpToolsDetailPage` 类内）；**行为零改动**。
- 开关 / 探测 / 导入 / 批量开关（全部开启·全部关闭）/ 默认关闭 `merge_notes` 等**逻辑一律未动**；数据层 `disabledTools` + `mergedTools()` + `dispatch()` 拦截全部未碰。

### 🧪 验证

- 本地 `flutter analyze`：**0 error / 0 warning**；全量 `flutter test`：**71/71 通过**。
- **Android 构建 CI 结论**：**✅ success** —— run `35342901807`（attempt 1 一次通过）；APK **40,773,270 B**（sha1 `0f942cee`）已下载桌面 `xiaole-client-v6.11.1.apk`。

### 🔒 红线遵守
**本版未改动**：`app_theme.dart`、`lib/core/network`、`lib/data`、冻结区；开关 / 探测 / 导入 / 批量开关 / 默认关闭 `merge_notes` 等**任何行为逻辑一律未动**。**纯视觉层变更，无网络 / 存储 / 协议 / 行为变更。**

### 📌 配套文档
方案见 `PLAN_v6.11.1_外部MCP与工具清单页微信化.md`（头部状态已置 ✅ 已批准——实施中，对应发布版本 v6.11.1）。

---

## v6.11.0 · 2026-09-18

**主题：开发者中心排版重排贴微信原型 —— 通栏直角白卡 + 28px 彩色图标块替换 emoji + 入口行右侧灰值 + 底部版本脚注**

### 🎯 起因（张老师反馈「没变化」，诊断确认根因）
张老师反馈 v6.10.0「开发者中心排版无变化」。诊断确认根因：
1. v6.10.0 是**控件替换、布局骨架未动**（只是把 Material 控件换成 WxCell，分组容器仍是 iOS 圆角浮动卡风）；
2. 现有分组容器是 **iOS 圆角浮动卡风**（圆角 12 + 左右 12px 边距），与微信原型**通栏直角风**（`radius 0`、无边距、组间 10px 灰隙）**不一致**。

### ❌ 为什么 V3（仅加右侧灰值）不行
V3 不动容器与 emoji，视觉差依旧小，大概率还是「看不出变化」——正是张老师反馈的痛点。故采纳 **V1（用户批准）**。

### ⭐ 真正的目标：对齐微信原型（xiaole-wechat-prototype-v6.html 的 settings 规格）
| 维度 | 微信原型规格 | 改前 | 改后（V1） |
|---|---|---|---|
| 分组容器 | 通栏直角白卡（radius 0、无边距、组间 10px 灰隙） | iOS 圆角浮动卡 | ✅ 通栏直角白卡 |
| 图标 | 28px 彩色圆角色块 + 白图标、无 emoji | 多数行放 emoji | ✅ 28px 彩色圆角块（`_iconTile`，语义色走 AppColors） |
| 右侧信息 | 灰色 value + chevron | 只有箭头 | ✅ 入口行加右侧灰值 |
| 版本脚注 | 页面底部居中灰字 | 顶部「N 项开启」 | ✅ 移到页面底部版本脚注 |

### ✅ 本版做了什么（V1，仅改 `dev_center_page.dart` + 色板 token，行为零改动）
1. **`_section` 重写**：圆角 12 浮动卡 → **通栏直角白卡**（去左右 margin、`radius 0`），组间灰隙 10px；0.5px 分割线由 WxCell 自带（已有）。
2. **全页 emoji 下岗**：每行配 `_iconTile(icon, color)` 28px 彩色圆角图标块（复用现有方法，**语义色走 AppColors**：MCP=info 蓝、外部 MCP=primary 绿、视觉=cloudBlue、主动联系=amber、调试=gray…），原 emoji（📋🌐🤖🔋…）全部移除。
3. **入口行加右侧灰色值**（WxCell 已有 `trailingText`）：巡检间隔「每 N 分钟」/ 电话日志「最近 50 轮」/ MCP 工具「26 项」等（动态值取现有 provider/服务，不新增逻辑）。
4. **「N 项开启」从顶部移到页面底部版本脚注**：与版本号合并成两行灰字，对齐原型 `.profile-version` 位。

### 📊 改动量化
- **文件：修改 1 个**（`dev_center_page.dart`）+ 色板 token；**行为零改动**。
- `_McpToolsDetailPage` 的**同名 `_section` 重载未动**（其内部仍是圆角浮动卡，本次只重排主 `dev_center_page` 的 `_section`）。
- 分组灰标题**保留**（dev center 功能多，无标题难扫读——与微信原型的差异点，已向用户说明）。

### 🧪 验证

- 本地 `flutter analyze`：**0 error / 0 warning**（dev_center 单文件 No issues）；全量 `flutter test`：**71/71 通过**（golden 集不含 dev_center，5 张基线不变）。
- **Android 构建已由 CI 验证通过** ✅ —— run `35334496762`（attempt 1 `conclusion=success`）；APK **40,773,270 B**（sha1 `84fc6c2a`）已下载桌面 `xiaole-client-v6.11.0.apk`。

### 🔒 红线遵守
**本版未改动**：`app_theme.dart`、`lib/core/network`、`lib/data`、冻结区；`_switchTile` / 弹窗 / 回调 / 服务启停逻辑一律未动；`_McpToolsDetailPage._section` 重载未动。**纯视觉层变更，无网络 / 存储 / 协议 / 行为变更。**

### 📌 配套文档
方案见 `PLAN_v6.11.0_开发者中心排版重排贴微信原型.md`（头部状态已置 ✅ 已批准 V1，对应发布版本 v6.11.0）。

---

## v6.10.0 · 2026-09-18

**主题：微信风收口 —— 补活 Design Token、新建 6 个自建组件、全项目字号收敛**

### 🎯 起因（一个想法被数据推翻，却挖出真问题）
张老师提出「引入 `tdesign_flutter`，让 App 的 UI 更贴近微信聊天」。评估后**否决**该方案，但评估过程暴露了一个**更严重的既有问题**。

### ❌ 为什么不引 TDesign（结论：兼容性没问题，方向反了）

| 维度 | 结论 |
|---|---|
| 兼容性 | **完全没问题** —— 0.2.7 要求 `flutter>=3.16.0` / `dart>=3.2.6`；本项目 3.32.2 / 3.8.1 满足。**实测**：把现有 38 个依赖 + `tdesign_flutter: ^0.2.7` 放进仓库外探针工程跑 `pub get` → **179 个包零冲突**（其 pubspec 的 dependencies 只有 `flutter` SDK 本身，零第三方依赖） |
| 但方向反了 | TDesign 默认主色 `#0052D9` 蓝 + 12px 圆角卡片 + 阴影，与微信「绿 / 扁平无阴影 / 0.5px 细线」是**两套对立美学** |
| 且无聊天能力 | 官方 **51 个组件中 Chat/气泡/IM 类 = 0**（`Message` 是全局 Toast、`Popover` 是 tooltip）⇒ 聊天页该自绘仍要自绘 |
| 净结果 | 视觉更不像微信 + APK 增大（+2 个 TTF）+ 5 张 golden 失效 —— **三项全负** |

### ⭐ 真正的病根：Design Token 是「半死」的

实测引用数：

| token | 文件 | 引用数 | 状态 |
|---|---|---|---|
| `AppColors` | app_colors.dart | **244 处 / 28 文件** | ✅ 健康 |
| `AppTextStyles` | app_text_styles.dart | **0 处** | ❌ **死代码** |
| `AppDimens` | app_colors.dart 内 | **0 处** | ❌ **死代码** |

**`AppTextStyles` 为什么会死**（这是本次最有价值的发现）：
它把 `color: AppColors.textPrimary` **写死在每一个 TextStyle 里** ⇒ **深色模式下无法使用** ⇒ 没人敢用 ⇒ 全项目改为硬编码字号。
后果：**124 处硬编码 `fontSize`、15 种取值**（13 与 14 并存、15/16/17 并存、18/20 为野生值）；**10 种圆角取值**。

> 教训：**「文件存在」≠「token 在用」**。判断设计系统健康度必须统计真实引用数，不能看文件在不在。

### ✅ 本版做了什么

1. **重写 `app_text_styles.dart`** —— 只保留 **5 档阶梯 11/12/14/17/20**，**不含任何颜色**，改用 6 个辅助方法按 light/dark 自动取值（`primaryText` / `secondaryText` / `tertiaryText` / `divider` / `surface` / `background`）。这是"token 能真正被用"的前提。
2. **新建 `app_dimens.dart`** —— 圆角/高度/头像/间距/页面 token。原 `AppDimens` 从 `app_colors.dart` **迁出**（同名类若同时 import 会冲突；旧类零引用，移除安全）。
3. **新建 6 个微信风组件**（`lib/presentation/widgets/`）：`WxCell` / `WxCellGroup` / `WxDialog` / `WxActionSheet` / `WxIconButton` / `WxEmpty`。
4. **全项目字号收敛**：124 处 → 5 档阶梯。映射规则 **13→12、15→14、16→17、18→17**（就近取整 + 平局偏收缩，避免撑破密集布局）；**≥22 保留**（emoji 110 / 通话页 22 / 成功页 40）；`agent_avatar` 的 `size*0.45` 是按头像尺寸计算，**保留**。
   - ⭐ **聊天气泡 16→17** 是本次最有价值的一处改动 —— 微信正文就是 17px。
5. **会话列表长按菜单**：底部白抽屉 → **微信屏幕正中央的深色 ActionSheet**（张老师选定）。
6. **设置页**：8 个 `ListTile` → `WxCell`（**补齐行间 0.5px 细线**——原实现行间无线）；主题选择 `AlertDialog`+3×`RadioListTile` → 微信选择菜单（带对勾）；**音量 Slider 保留本体、配色改微信绿**（张老师选定）。
7. **Material 控件全面清零**：`settings` / `conversation` / `dev_center` / `external_mcp` / `cloud_sync` / `proactive_script` / `export_chat` / `log_category` / `proactive_log` / `device_edit_dialog` / `profile_header` 的 `ListTile` / `SwitchListTile` / `AlertDialog` / `showModalBottomSheet` / `RadioListTile` 全部替换。
8. 顺带把硬编码 `0xFF0ABFF4` 提取为 `AppColors.cloudBlue`。

### 📊 改动量化

- **文件：新增 8 个 / 修改 31 个**
- **硬编码字号：124 → 26**。剩余 26 处**全部正当**：8 处是 `app_text_styles.dart` 的阶梯定义本身、8 处是 `app_theme.dart` 的全局主题定义（本版刻意不碰）、4 处是 `core/utils/toast_util.dart`（不在本次范围）、**6 处是刻意例外**（emoji 110 / 通话页 22 / 成功页 40 / `size*` 计算值 ×3）。
- **残留 Material 弹窗：仅 1 处** —— `activation_dialog.dart` 的 `AlertDialog` 外壳**刻意保留**（含验证码输入 + 倒计时 + 提交回调，是复杂有状态对话框；只换视觉外壳风险最低）。

### 🧪 验证

- `flutter analyze lib/ test/` → **0 error / 0 warning**（84 条 info 级为既有告警：`avoid_print`、`withOpacity` 弃用等）
- `flutter test` → **71/71 全绿**（含 5 张 golden；本次弹窗改造不触及 golden 渲染路径，基线未失效）
- 5 张 golden 在会话列表/设置页改造后已用 `--update-goldens` 重生成，并**逐张目视核对**（聊天页 / 会话列表 / 设置页，确认无塌陷、无溢出、分隔线 76px 缩进正确）
- 期间修复子 agent 遗留的 5 处编译错误（4 处 `const` 未去 + 1 处多余 `!`）

### ⚠️ 已知取舍与偏差（**未改，留待决策**）

| 项 | 说明 |
|---|---|
| **圆角未严格单值化** | 只收敛了野生值 `10→8`、`14→12`；`5/6/7/8` 保留。理由：1px 差异肉眼不可辨，改动是纯风险零收益；且 `7` 是微信 28px 图标色块的**正确**值、`6` 是 48px 会话头像的**正确**值，强改反而**破坏**规范 |
| **54 处硬编码颜色仍在** | 多为各页图标色块的点缀色（如 `0xFFFF9500`）。本版 V3 针对**字号**收敛，颜色层原本健康（244 处 token 引用）。若要严格单值化需新增若干语义色 token，属设计决策 |
| `WxIconButton` 高 40 | 微信规范值；原 Material `FilledButton` 为 48，略矮 |
| `WxEmpty` 默认带 72px 图标 | 部分原空态无图标，视觉上多一个图标 |
| 导出页「正在生成…」 | 原内联转圈 → 沙漏图标（`WxIconButton.icon` 只接 `IconData`，是组件能力缺口） |
| `WxCell` 副标题固定 14px | 把原 12px 的巡检口令抬了一档，符合微信单元格规范，但与「12→12」映射表有出入 |

### 🔒 红线遵守

**本版未改动**：`app_theme.dart`（被 `main.dart` 全局引用，改它会连带影响 chat_page 与全部 golden —— 故新增 token 一律走**新建文件**）、`lib/core/network`、`lib/data`、冻结区。
**本版为纯视觉层变更，无网络 / 存储 / 协议 / 行为变更。**

### 📌 配套文档

新增 `PLAN_v6.10.0_次级页微信风收口与Token治理.md`（含完整审计数据、逐行控件清单、确定性映射表、V1/V2/V3 方案对比）。

---

## v6.9.1 · 2026-09-18

**主题：修复「小智 AI 识别不到外部 MCP」—— v6.8.1 的工具白名单把外部工具误杀**

### 🔴 缺陷（张老师报告的真实回归）
**症状**：v6.4.4 时小智 AI 能识别 App 外挂的外部 MCP（biji-notes / 高德地图均可用）；
**v6.8.1 起识别不到**（v6.8.1 / v6.8.2 / v6.8.3 / v6.9.0 **全部受影响**）。

**根因**：`AppFeats.mcpToolEnabled()` **同时服务「设备工具」与「外部 MCP 工具」**
（`chat_page` 只向 responder 注入这一个 `isToolEnabled`）。v6.8.1（E 项）把默认值统一改成
「只放行 5 项设备工具白名单」，而外部工具名是 `notes.*`（biji-notes）/ `amap.*`（高德），
**不在白名单** ⇒ 外部工具**全部被判禁用** ⇒ `xiaozhi_mcp_responder` 的 `tools/list` 不再下发
⇒ **AI 完全看不到外部 MCP 的工具**。引入提交：`bab45d9`（v6.8.1 WIP）。

**实跑证据（修复前，临时测试实测）**：
```
❌ 禁用 notes.search_notes / notes.add_note / amap.geocode / amap.map_around_search
✅ 启用 self.location.get_current / self.alarm.set_alarm / self.audio_speaker.set_volume
```

### ✅ 修复（1 处逻辑）
`lib/presentation/services/app_feats.dart` 的 `mcpToolEnabled()` 末尾改为**按来源分别判定默认值**：
- **非 `self.` 前缀（外部 MCP 工具）→ 默认放行 `true`**（回到 v6.4.4 行为）
- **`self.*` 设备工具 → 仍走 v6.8.1（E 项）白名单**（设计本意保留，未被破坏）

优先级不变：运行时缓存 > 已存值 > 默认值。外部工具的启停仍由「外部 MCP」页负责：
整台 `ExternalMcpServer.enabled` + 逐工具 `disabledTools`。

### 🧪 新增回归测试（`test/mcp_tool_default_test.dart`，6 例）
1. 外部工具（内置 `notes.` / `amap.` 及**任意自定义前缀**）**默认必须启用**
2. 设备工具白名单 5 项默认开、其余默认关（E 项本意未被破坏）
3. **已存值优先于默认值**：关过的外部工具冷启动后仍关；开过的白名单外设备工具仍开

> 这次正是**缺这类测试**才让缺陷从 v6.8.1 一路溜到 v6.9.0。

### 📌 顺带澄清（避免误判）：「外部 MCP → 逐工具开关」页**一直存在**
`external_mcp_page.dart` 的 `_ExternalMcpToolsPage`（**点服务器列表项进入**）自 v6.4.0 就有，
v6.9.0 还给它加了「全部关闭 / 全部开启」。
**缺陷期间它看起来没效果** —— 因为被白名单整层杀掉，关不关 AI 都看不到
⇒ 容易误以为"App 里没有逐工具开关功能"。本次修复后该页**才真正生效**，
v6.9.0 新增的「已启用 N/M」也**与真实下发情况一致**。

### 自检
- `flutter analyze --no-pub`：**0 error**（5 warning 为既有基线）
- 新增测试 **6/6**；全量 `flutter test`：**71/71**（原 65 + 新 6）
- **Android 构建已由 CI 验证通过** ✅ —— run `35294530211`（`conclusion=success`），
  Release `v6.9.1` 已产出 `app-release.apk`（41,018,286 B ≈ 39.1 MB），已下载到桌面 `xiaole-client-v6.9.1.apk`
  （字节数与 v6.9.0 一致 —— 本次只改 1 行判定逻辑 + 新增测试，不含资源变更）。

---

## v6.9.0 · 2026-09-18

**主题：外部 MCP「工具太多会爆掉」—— 让逐工具开关看得见、好用**

### 🎯 需求背景
张老师反馈：外部接进来的一个 MCP 服务器可能有 **20 个甚至 100 个**工具，
全量注册给 AI 会占满上下文、干扰判断；**实际每个 MCP 只想要其中一两个工具**。

### ⚠️ 重要前提：逐工具开关**此前已存在**（v6.4.0）
- 数据层 `ExternalMcpServer.disabledTools`（逐工具关闭名单，存**原始**工具名）
- `ExternalMcpManager.mergedTools()`：剔除被关的工具 ⇒ **不下发给 AI**
- `ExternalMcpManager.dispatch()`：被关工具被调用时返回「该外部工具已被关闭」
- 页面：开发者中心 → 🌐 外部 MCP → **点某台服务器** → 逐工具开关

⇒ 本次**不是从零实现**，而是补上「看不见、不好用」的缺口。

### ✨ 本次改动（**仅 1 个文件**：`lib/presentation/pages/external_mcp_page.dart`）
1. **服务器列表直接显示「已启用 N/M 个工具」**
   - 原：只显示「在线 · N 个工具」，看不出有几个被关、也看不出能逐工具管。
   - 现：`在线 · 已启用 2/20 个工具`。
2. **工具页新增批量开关**（右上角 ⋮）：「**全部关闭 / 全部开启**」
   - 直击痛点：20 个只要 1 个 → 原来得手动关 **19 次**；现在**先全关、再挑要的**。
   - 全部关闭 = 把当前在线的全部工具名写入 `disabledTools`；全部开启 = 清空。
   - 操作后 Toast 提示「已全部关闭（可再逐个挑要用的）」。
3. **工具页顶部加计数与说明**：「已启用 X / 共 Y 个；关闭的工具不会下发给 AI」。
4. 仅在有工具（`tools.isNotEmpty`）时显示批量菜单，空态不误触。

### 🔒 未改动（最小化原则）
数据层 (`external_mcp_store.dart`)、管理器 (`external_mcp_manager.dart`)、协议层
(`xiaozhi_mcp_responder.dart`) **一律未动**；**默认策略仍为「全开」**
（仅 `merge_notes` 等破坏性工具默认关闭），**未**改为白名单。

### ⚠️ 已知边界（留待决策）
黑名单语义下，**服务器侧新增工具时会默认启用**，需要再手动关一次。
若要彻底改成「默认全关、手动挑」（白名单体验），需改 `applyDefaultDisabled()` 的默认策略 ——
属策略变更，未擅自实施。

### 自检
- `flutter analyze --no-pub`：**0 error**（warning 5 条为既有基线，未新增）
- 全量 `flutter test`：**65/65 通过**（本页不在 golden 覆盖范围内，基线不受影响）
- **Android 构建已由 CI 验证通过** ✅ —— run `35283801890`（`conclusion=success`），
  Release `v6.9.0` 已产出 `app-release.apk`（41,018,286 B ≈ 39.1 MB），已下载到桌面 `xiaole-client-v6.9.0.apk`。

---

## v6.8.3 · 2026-09-18

**主题：AI 主动来电「电话日志」跟踪（A 项）+ 智能体头像升级（C 项）—— 第二版-下收官**

> 本版把 `PLAN_v6.8.x_后台化与功能优化_已完成.md` **第二版**的三项全部做完：
> B（挂断修复）、E（默认值）、D（聊天页进入即最新）已随 v6.8.1/v6.8.2 落地，本版补齐 **A** 与 **C**。

### ✨ ① A 项：MCP 电话日志跟踪（诊断用）

**需求**：开发者中心能看到**每一轮**巡检的完整过程，**包括"跳过"的轮次及其原因**，
并能**一键复制**整段贴给 AI 诊断。

- **新增旁路记录层 `lib/core/proactive/proactive_round_log.dart`**
  - **定位：只读旁路，零行为变更** —— 三守卫 / 22s 超时 / 12s 重发 / 4 个 MCP 工具 / 时序**一个字都没改**；
  - 每轮记录字段：**时间**、**本轮实际发出的口令**（detect 口令 + 12s 未响应时的轮换重发）、
    **是否被调用 `get_script`**、**是否收到 `trigger_call` / `skip`**、**开场白原文**、
    **本轮耗时**、**close code**、**服务器 `alert`**、**结束原因**；
  - **跳过轮也留痕且写明具体原因**：`时段外` / `冷却中` / `语音通话中` / `上一轮未结束` /
    `服务未初始化` / `WS 地址为空`（守卫原始措辞「窗口外/冷却期内」由 `_mapGuardReasonToSkip` 统一收口）；
  - **最近 50 轮环形缓冲**（超出丢最旧，不无限增长）；
  - **持久化**（SharedPreferences 键 `xw_proactive_round_log`）—— **App 重启后日志仍在**；
    存储不可用时**优雅降级为纯内存**，绝不抛异常；
  - ⚠️ **写入顺序铁律**：`recordXxx` 是同步 API，但落盘前必须 `await load()`，
    否则 App 启动后的**第一次记录会用"只有一条"的数组覆盖掉全部旧历史**（已按此实现）。
  - logger 名以 `Proactive` 开头 ⇒ 运行日志自动归入 `LogBuffer` 的 **`proactive` 分类**
    （页面是"结构化视图"，日志照写，两边打通）。
- **close code / alert 的采集方式**：**只在巡检自己的 WS listener 里旁听**
  （`XiaozhiEventType.disconnected` 的 `data` 即 close code；文本帧 `{"type":"alert",...}` 取 status+message），
  `lib/core/network` **零改动**。`endRound` 断开后等 ~200ms 让断开事件到达，拿不到就记 `—`，不卡收尾。
- **新增页面 `lib/presentation/pages/proactive_log_page.dart`**：卡片式展示（最新置顶），
  顶部说明 + 右上角**「复制全部」**（纯文本，含全部字段）+ **「清空」**（二次确认）。
- **入口**：开发者中心 →「AI 主动联系」组 → **「📞 电话日志」**。

**验收对照**：① 跑一轮静默(skip) → 页面出现记录且写明判定=静默 ✅；
② 被守卫跳过 → 写明**具体原因** ✅；③ 触发轮 → 记录含**开场白原文** ✅；
④ 「复制全部」→ 剪贴板含上述全部字段、格式可读 ✅；⑤ 超过 50 轮丢弃最旧、不卡顿 ✅。

### ✨ ② C 项：头像升级（文字 + 预设色板 + 本地图片）

**现状问题**：头像是"固定底色 + 固定符号"，用户觉得比较土。

- **文字头像**：取**智能体名字中的第 N 个字**；**默认第 1 字**，可选 **第 2 字 / 第 3 字 / 末字 / 自填一字**；
  越界或名字为空时**回落第 1 字**，名字为空回落 `乐`。
- **预设色板（12 套，不做任意取色器）**：全部采用「**深/中深底 + 白字**」或「**很浅底 + 深灰字 0x2C2C2E**」
  两种安全组合，规避"中明度底 + 白字发虚"，保证**任何底色下文字都清晰可读**。
  每套色板在代码里都注明了底/字组合理由。
- **本地图片头像**：`image_picker` 从相册选图（`maxWidth/Height 512`）→ **拷贝到 App 私有目录
  `agent_avatars/`**（不引用相册原路径，避免路径失效）→ 优先级 **图片 > 文字**；
  提供**「清除图片」**一键回落文字头像；替换图片时**自动删除旧文件**；
  文件不存在/读失败（典型：重装后路径失效）**优雅回落文字头像**。
- **⭐ 全部仅存本地（红线）**：
  - 配置存 `SharedPreferences`（`xw_avatar_<agentId>`），图片存 App 私有目录；
  - **绝不写入 `AgentModel`、绝不碰 `cloud_sync_service.dart`** ⇒
    **重装 App 自动回落文字头像**（私有目录与 prefs 一并清空），
    **同账号在另一台设备恢复云端数据不会把图片/配置带过去**；
  - 页面上明确告知用户："头像仅保存在本机，不会同步到云端；重装 App 后会回到文字头像"。
- **生效范围统一**：`AgentAvatar` 组件内部自洽（读本地配置），
  **会话列表 / 聊天页消息气泡 / 通话全屏层 / 来电页**全部走同一组件；
  通过 `AgentAvatarStore.revision`（ValueNotifier）实现**跨页即时刷新**；
  组件**首帧同步读缓存**（已是稳定文字头像，**不闪烁**）。
- **向后兼容**：`agentId` 为空且无 `configOverride` 时**完全沿用旧的渐变 + 符号渲染**
  ⇒ **「我」页用户头像（`profile_header.dart`）本次一行不改、视觉不变**。
- **编辑入口**：智能体配置页 —— 头像编辑器（预览 + 取字 ChoiceChip + 色板圆点 + 相册选图/清除图片）。
  编辑模式**即时落盘**；新建模式待 `identityAgentId` 确定后在保存流程中写入。

### 🔧 ③ 工程细节

- 无新增依赖（`image_picker` / `path_provider` 早已在 pubspec 中）。
- **golden 基线更新**：`audit_chat_messages.png`、`audit_conversation_list.png` 因头像升级按预期更新
  （**已用实际渲染图目视核对**：isolated diff **仅落在头像方块内**，无任何布局位移；`audit_profile_page` 不变）。
- `test/ui_audit_test.dart` 的 `MessageList` 调用由 `avatarStyleIndex` 改为 `agentId` + `agentName`。
- **新增单测** `test/proactive_round_log_test.dart`（4 例）：环形缓冲截断、JSON 往返、`toPlainText` 字段完整、跳过原因具体化。

### 🐞 ④ lead 复核阶段发现并修复的 2 个**真 bug**（C 项核心路径）

`AgentAvatarStore` 初版有两个**会让"保存过的头像配置完全不生效"**的缺陷，均已修复并补**回归测试**守住：

1. **`read()` 用默认值覆盖了刚读进来的已存配置**
   `read()` 原本是"先 `_lazyLoad()` → 再无条件 `_cache[id] = 默认值`"。
   而 `_lazyLoad()` 的存储读取是**同步完成**的（会把真值写进缓存），紧接着就被默认值覆盖
   ⇒ **每个 agent 的首次 `read()` 都返回默认值，且此后缓存被钉死为默认值**，
   用户保存过的"取字模式 / 色板 / 图片"永远不生效。
   **修复**：`_lazyLoad()` 之后**读回缓存**，只有真的没有已存值时才回落默认值。
2. **`_lazyLoad()` 在 build 期间同步 `revision.value++`**
   `read()` 在 `AgentAvatar.build()` 里被调用，同步 notify 会让正在构建的
   `ValueListenableBuilder` 被 `markNeedsBuild`
   ⇒ 触发 `setState() or markNeedsBuild() called during build` 断言（存过配置后必现）。
   **修复**：**同步把已存配置写进缓存**（保证首帧就是正确的文字头像、不闪烁），
   但**刷新通知推迟到微任务**；首次填充时当前帧已读到新值，**根本无需通知**。
3. 顺带修复：配置页 `AgentAvatarStore.load()` 原本只信缓存，会显示成默认值 ——
   改为**总是回读存储**（存储不可用时才回落缓存/默认）。

新增 `test/agent_avatar_store_test.dart`（**10 例**）专门守这两条：
"存 → 清内存 → 再读必须拿回已存值"、色板安全字色约束、取字模式与越界回落、脏数据不崩。

### 自检

- `flutter analyze --no-pub`：**0 error / 0 warning**（既有 info 级风格提示不计，未引入新问题）。
- 全量 `flutter test`：**65 / 65 通过**（v6.8.2 为 51；本版 +4 电话日志单测 +10 头像单测）。

### 🧪 ⑤ 测试网加固：色板对比度从「亮度代理」升级为「真算 WCAG 对比度」

原断言只查"白字要求底色亮度 < 0.45"，**这是个会漏判的代理指标**：
亮度 0.448 的底色配白字只有 **2.1:1**，肉眼基本读不清，却仍能通过断言。
现改为**直接计算 WCAG 2.x 对比度** `(L亮+0.05)/(L暗+0.05)`，要求**渐变两端**（最暗处与最亮处）
都 **≥ 4.5:1（AA 正文级）**，失败时打印实际比值与具体色值。

- **负向对照已实测**：故意把"深蓝"最亮端改成 `0x7FAEF5`（亮度 0.4138，旧断言**会放过**）→
  新断言立即报错 `对比度仅 2.26:1，低于 WCAG AA 的 4.5:1` ✅（随后已还原，`git status` 仅剩测试文件）。
- 12 套色板**实测全部达标**，最差一套（深蓝亮端）为 **4.63:1**，安全边际充足。

### 🚀 ⑥ 发布与 CI

| 项 | 值 |
|---|---|
| 远端 tag | `v6.8.3` |
| 远端 commit | `bc5d0980`（tree `6468b5bf`，与本地工作树**逐字节一致**，已校验） |
| CI run | **35256912342**（`Build Android APK`，**第 2 次尝试 success**） |
| APK | `app-release.apk` **41,018,286 字节**，sha1 `10ff76c268cec7776b0d12f30d8da7b8bf36136e` |

#### ⚠️ 发布过程中遇到的"假失败"（重要，别再误判）

本 tag 的**第 1 次** CI 尝试结论是 **failure**，但**并不是代码问题**：

```
2026-09-17T18:23:34Z  ✓ Built build/app/outputs/flutter-apk/app-release.apk (41.0MB)   ← APK 构建成功
2026-09-17T18:26:47Z  ##[error] request to https://uploads.github.com/.../releases/390946356/assets?name=app-release.apk
                                  failed, reason: socket hang up                        ← 上传 Release 资产时网络中断
```

**根因**：`softprops/action-gh-release@v1` 把 41MB APK 上传到 `uploads.github.com` 时
**上游网络抖动（socket hang up，约 3 分钟后断）** —— 属于**瞬时基础设施故障**，
与代码、配置均无关（同一 workflow 在 `8517cdd8` / `7511bf90` 两次运行均成功，APK 字节数完全相同）。

**处置**：用 `POST /repos/{o}/{r}/actions/runs/{id}/rerun-failed-jobs` 重跑 →
**attempt 2 全绿**，Release 资产上传成功。
**教训**：CI 红灯**先看失败在哪一步** —— 若 `Built ... app-release.apk` 已打出、失败在 `Create Release`，
则是**发布环节的瞬时故障，重跑即可**，**不要**去改代码、更不要改版本号重发。

> 备注：本次**未**为此修改 workflow。理由：① 根因是上游瞬时故障，非配置缺陷；
> ② 该 workflow 已在 8 次发布中成功，改动未经真机验证风险更高；
> ③ `workflow_dispatch` 手动触发与 job 重跑已构成足够的兜底通道。
> 若后续该故障复现 ≥2 次，再考虑给 Release 步骤加"失败后重试一次"的包装。

### ⚠️ ⑦ 已知边界（本版**未**改，留待决策）：Android Auto Backup 可能带回头像图片

需求 ④ 要求"**重装 App 后自动回落到文字头像**"。Dart 侧已严格保证（配置与图片均在**本地私有**存储，
**不写入 `AgentModel`、不碰 `cloud_sync_service.dart`**），普通重装**确实会回落**。

但 `android/app/src/main/AndroidManifest.xml` **未声明 `android:allowBackup`**，
即采用 Android 默认值 **`true`** —— 意味着若用户开启了系统"备份到云端 / 换机迁移"，
`SharedPreferences`（含 `xw_avatar_<agentId>`）与私有目录下的 `agent_avatars/*.png`
**可能随系统备份被还原**，此时图片会"跟着回来"。

- 这**不影响**需求 ⑤（"同账号在另一台设备恢复**云端数据**不会带过去"）—— 我们自己的云同步路径已完全隔离；
- 但严格意义上**削弱**了需求 ④（重装回落）在"开了系统备份"场景下的成立性。

**待决策的三种修法**（各有代价，故未擅自实施）：

| 方案 | 做法 | 代价 |
|---|---|---|
| A | `android:allowBackup="false"` | **全局**关闭备份，用户其它本地数据（智能体/设置）也失去备份保护 |
| B | 加 `dataExtractionRules` / `fullBackupContent`，排除 prefs 与头像目录 | 规则按**文件**粒度，排除 prefs 会连带丢失其它设置 |
| C | 头像图片改存 `getApplicationCacheDirectory()`（缓存目录默认不进 Auto Backup） | 系统清理缓存时**图片会随机消失**（比"重装回落"更差） |

**AI 建议（可选采纳）**：优先考虑 **B + 只排除头像目录**（`agent_avatars/`），
并**接受** prefs 中的 `xw_avatar_*` 键可能被还原（因为图片文件已被排除，键无对应文件时会
自动走 `errorBuilder` **回落文字头像**）—— 这样既保住其它数据备份，又满足"重装回落"。

### 版本号

- `pubspec.yaml`：`6.8.2+47` → **`6.8.3+48`**
- `lib/app/config/app_config.dart`：`appVersion` → **`6.8.3`**

---

## v6.8.2 · 2026-09-18

**主题：真正修复 Android 构建失败（补 core library desugaring）+ 聊天页进入即显示最新消息**

> ⚠️ **v6.8.1 构建仍失败、无 APK**：它修对了 workmanager（`:workmanager:compileReleaseKotlin` 不再报错），
> 但**还差一步**——CI 在 `:app:checkReleaseAarMetadata` 报了新的、也是**真正的**阻断项。本版补齐。

### 🔴 ① 修复 Android 构建失败（**关键**）
- **v6.8.1 的 CI 报错（run 35243265913）**：
  ```
  An issue was found when checking AAR metadata:
    1. Dependency ':flutter_local_notifications' requires core library desugaring to be enabled for :app.
  ```
- **根因**：`flutter_local_notifications` 的 AAR 元数据**强制要求**开启 **core library desugaring**（Java 8+ API 脱糖），
  而 `android/app/build.gradle.kts` 未开启 ⇒ `:app:checkReleaseAarMetadata` 直接失败。
- **修复**（`android/app/build.gradle.kts`，新增两处）：
  - `compileOptions { isCoreLibraryDesugaringEnabled = true ... }`
  - 新增 `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`（AGP 8.9.1 支持 2.1.x）
- **说明**：这是**新增 flutter_local_notifications 带来的配置要求**，非我们代码问题；
  workmanager 的问题已在 v6.8.1 修好（本版不再报 workmanager 错误）。

### 🎯 ② 聊天页进入即显示最新消息（D 项）
- **现象**：进入聊天页默认停在**最早**消息，要发一句才会滚到最新。
- **根因**：原实现用"延迟 100ms 后 `animateTo(maxScrollExtent)`"**靠时序**够底部，布局未完成时滚不到位。
- **修复**：`MessageList` 改为**倒置列表**（`reverse: true`，最新消息即列表起点，**不依赖任何滚动时序**）；
  索引映射改为 `msgIndex = len-1-(index-typingOffset)`；时间分隔条判据改用 `msgIndex`（与显示方向解耦）；
  `chat_page._scrollToBottom()` 目标由 `maxScrollExtent` 改为 **offset 0**。
- **验证**：用 golden 实际渲染图**目视核对消息顺序**（系统→AI→用户→AI→系统，最新在底部）**未弄反**；
  `goldens/audit_chat_messages.png` 按预期更新。
- **已知取舍**：消息少于屏幕时内容贴底（微信为贴顶）；长会话无影响。如需贴顶，可后续加"填充撑到顶"布局。

### 自检
- `flutter analyze`：0 error；全量 `flutter test`：**51/51 通过**。
- **Android 构建已由 CI 验证通过** ✅ —— run `35245226751`（`conclusion=success`），
  Release `v6.8.2` 已产出 `app-release.apk`（40,739,666 bytes ≈ 38.9 MB），已下载到桌面 `xiaole-client-v6.8.2.apk`。
  ⇒ **Android 构建失败问题至此彻底解决**（v6.8.0 的 workmanager Kotlin 问题 + v6.8.1 暴露的 desugaring 问题，两步修完）。

---

## v6.8.1 · 2026-09-17

**主题：修复 v6.8.0 的 Android 构建失败（后台化真正可用）+ 修复「挂断后仍在说话」+ 调整默认开关**

> 本版包含三件事：①**构建修复**（让 v6.8.0 的后台化能真正打出包）；②**B 项**挂断缺陷修复；③**E 项**默认值调整（27 项 MCP 工具仅默认开 5 项、📷 相机按钮默认关，仅对新装用户生效）。
> 版本号 `6.8.0+45` → `6.8.1+46`，`appVersion` → `6.8.1`。

### 🔴 修复（① v6.8.0 Android 构建失败 —— **这是本版最重要的修复**）
- **现象**：tag `v6.8.0` 的 CI `Build APK` 失败（run 35238877295），**未产出任何 APK**。
- **根因（CI 日志确认）**：
  - `workmanager-0.5.2` 的 Kotlin 源码引用 Flutter 嵌入层类解析失败 →
    `Execution failed for task ':workmanager:compileReleaseKotlin'`（3 处 `Unresolved reference`）。
  - 之所以被钉在 0.5.2：`pubspec` 写的是 **`^0.5.2`，而 Dart 的 caret 对 `0.x` 只允许补丁级升级**，
    即被锁死在 `0.5.x`（2023 年版本），永远不会升到 0.6+。
- **修复过程（逐个版本实测排除，避免再赌一次 CI）**：
  | 版本 | 结论 |
  |---|---|
  | `0.10.x` | ❌ 要求 `flutter >= 3.38.0`（本项目 Flutter 3.32.2，装不上） |
  | `0.9.2+1` / `0.9.3` | ❌ 依赖 `workmanager_apple >= 0.9.5`，同样要求 Flutter ≥3.38 → pub 直接禁止 |
  | `0.9.0` | ⚠️ 能解析，但 `workmanager_apple 0.9.4` 与 `workmanager_platform_interface 0.9.4` **签名不匹配**
    （缺少 `foregroundServiceConfig`）→ **Dart 编译失败**（上游包发布的内部不一致组合） |
  | **`0.8.0`** | ✅ **采用**：要求 `flutter >= 3.32.0`（与本项目匹配），且**版本组合内部一致** |
- **改动**：`workmanager: ^0.5.2` → **`workmanager: 0.8.0`**（精确锁定，避免 `^` 语义再被带偏）；
  API 适配为 0.8.0 的 `ExistingWorkPolicy.replace`（选 `replace` 而非 `keep`：用户改巡检间隔时需按新频率重建任务）。
- **验证**：`flutter analyze` 0 error；**全量 `flutter test` 51/51 通过**。

### 修复（② B 项：挂断后仍在说话）
- **根因（只读诊断已确认）**：挂断路径只做了"停麦克风 / 发 listen stop / 复位 UI"，缺四件事 → "说完拜拜挂断后它又补一句"：① 从未停止本机播放（已进入缓冲的 PCM 继续外放）；② `abort` 被 `_isAiPlaying` 门控（挂断瞬间该标志常已为 false，指令根本没发出，服务器继续推 TTS）；③ WS 未断开（同时承载文字聊天）；④ 收到音频帧的 `_handleBinaryMessage()` 没有"挂断后丢弃"的守卫。
- **挂断即静音**：`_endVoiceCall()` 补 `AudioUtil.stopPlaying()`（停止录音之后），立即释放播放引擎。
- **挂断即通知**：`abort` 改为**无条件**发送（去掉 `_isAiPlaying` 门控），只要连着就发；同时复位 `_isAiPlaying` 与播放定时器。
- **挂断即丢弃（弱化方案）**：引入"挂断后 5 秒静默窗口"——`_voiceHangupAt` 记录挂断时刻，`_handleBinaryMessage()` 开头若处于窗口内则丢弃迟到音频帧。
  - **关键判定**：纯文字聊天的 TTS 也走同一条 `_handleBinaryMessage()` 播放路径，故**不能**用"非通话就全丢"的全局守卫（会误伤主会话文字聊天），改用"挂断后短窗口丢弃"的弱化方案。
  - 用户主动发起新交互（发文字消息 / 开始通话 / 接听主动来电）会**立即解除**该窗口，保证文字聊天与后续通话的 TTS 不被误伤。
- **主动来电同理**：接听（`_playProactiveOpening`）走同一套机制（解除窗口）；拒绝/超时由 `IncomingCallPage._release()` 释放回铃音，本就不播 TTS，无需额外处理。

### 变更（E 项：默认开关）
- **27 项 MCP 设备工具默认白名单**：新增集中常量 `AppFeats.mcpDefaultOnTools`（定位 / 设闹钟 / 导航 / 调亮度 / 调音量 5 项），`mcpToolEnabled()` 改为"白名单内 `?? true`、其余 `?? false`"；优先级为 运行时缓存 > 已存值 > 默认白名单。
- **📷 相机按钮默认关**：`AppFeats.defaults['vision']` 由 `true` 改为 `false`（聊天栏相机按钮由 `AppFeats.vision` 控制显隐）。
- **只对"新装用户"生效**：未存过的开关才走默认白名单；已装用户本地已存的开关不会被默认值覆盖（不迁移、不回滚）。
- **「全部关闭」仍有效**：总开关 `mcptools` 关闭即屏蔽全部 MCP 请求（既有行为），含新增的默认开项。

### 红线遵守
- 未改动 `lib/core/network` 行为；未触碰音频编解码参数；Device-Id 恒为小写；未引入新依赖；未改动主动来电（v6.5.0 / v6.8.0）既有可用行为（B 项仅做"静音 + 无条件 abort + 挂断后窗口丢弃"三类补充）。

---

## v6.8.0 · 2026-09-17

**主题：AI 主动来电「后台化」—— 退出 App / 锁屏后也能巡检并触发来电（WorkManager 周期唤醒 + 高优先通知）**

> 本版即原方案里的"二期"。它**不是"才做主动来电"，而是"让 v6.5.0 已做好的主动来电，在用户退出 App 之后也能继续跑"**。技术路线采用 **V1 主推：WorkManager 周期唤醒**（无常驻通知、无前台服务，最省电、最抗杀）；**V2「常驻通知 + 前台服务」本次不做**，留待后续真机存活率实测对比。

### 新增（核心能力）
- **后台周期唤醒**：`workmanager` 注册 `PeriodicTask`（task name `proactive_poll`），系统按周期拉起 App 跑**一轮**巡检再睡；命中触发时用**高优先临时通知**（标题"小乐想和你通话"，正文用开场白或退化文案"点开听听它想说什么"）呈现，点通知进入来电流程。
- **后台入口** `lib/core/proactive/proactive_background.dart`（`@pragma('vm:entry-point') callbackDispatcher`）：
  - 按顺序最小初始化 `WidgetsFlutterBinding.ensureInitialized()` → `StorageService.instance.init()` → `AppFeats.load()` → `ProactiveScriptStore.init()`；任一步失败 catch 住安全退出，**绝不崩**。
  - **总开关守卫**：`AppFeats.proactive` 为 false → 直接返回、零流量、零网络请求。
  - **只跑一轮**：后台**绝不**调用 `start()`（那是常驻 Timer），跑完即返回。
  - **前后台互斥**：读前台"心跳"时间戳（`xw_proactive_fg_heartbeat`，前台 `_tick` 每次更新），若最近 ~5 分钟内更新过 → 本轮跳过，避免重复巡检。
  - 命中 `trigger_call`：把开场白 + agentId/agentName 持久化为"待处理来电"（`xw_proactive_pending_call`），再发高优先通知（后台 isolate 无 UI，不能直接弹来电页）。
- **与总开关联动**：开关开启 → 注册周期任务；关闭 → `cancelByUniqueName`（保证关闭=零唤醒、零流量）。App 启动（`main.dart`）与开发者中心开关、以及"全部关闭"均调用 `ProactiveBackground.syncWithSwitch()`。

### 新增（通知）
- `flutter_local_notifications` 高优先通知渠道（`importance: high` + 声音/震动），点击默认拉起 App；App 启动/回到前台时读"待处理来电"→ 自动进入 `IncomingCallPage`（复用已有来电页）。
- Android 13+ 运行时申请 `POST_NOTIFICATIONS`（用已有 `permission_handler`）；被拒不崩溃，置标记 `xw_proactive_notif_denied` 并在开发者中心 AI 主动联系区块提示"通知被禁，来电无法提醒"。

### 新增（引导页）
- `lib/presentation/pages/background_guide_page.dart`：**三步引导**（① 电池优化白名单 ② 自启动 ③ 后台运行限制），每步一行说明 + "去设置"按钮（`android_intent_plus` 打开系统页）。**查不到各厂商 ROM 状态则不展示伪造状态，只给入口**。入口放在开发者中心「AI 主动联系」区块内。

### 守卫复用（关键工程约束）
- 抽出顶层函数 `checkGuardReason()` 为**三守卫唯一实现**：①允许来电时段外 ②冷却期内 ③语音通话中。前台 `_tick()` 与后台 `runGuardedRoundForBackground()` **共用同一份**，杜绝复制粘贴两份（详见 `lib/core/proactive/proactive_poll_service.dart`）。`runGuardedRoundForBackground()` 为新增"带守卫的单轮入口"，返回是否命中触发。

### 依赖与配置
- `pubspec.yaml`：版本 `6.7.1+44` → `6.8.0+45`；**新增依赖 `workmanager ^0.5.2`、`flutter_local_notifications ^17.2.0`**（均为 Flutter 3.32.2 / Dart 3.8.1 兼容版）。
- `android/app/src/main/AndroidManifest.xml`：新增 `POST_NOTIFICATIONS` / `RECEIVE_BOOT_COMPLETED` / `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`。

### 红线遵守
- 未改动前台主动来电（v6.5.0）既有行为；未触碰 `lib/core/network`；未写用户真实笔记库（biji）；Device-Id 恒为 MAC 小写、巡检 Client-Id 每轮新生成（沿用既有逻辑）；任何后台异常均被 catch，不影响 App 启动。

### ⚠️ 本机无法验证、必须真机验证的项
- 后台唤醒是否真的在锁屏/退后台后按计划触发（受 WorkManager 最小 15 分钟周期与厂商 ROM 管控影响）。
- 锁屏存活率、通知点击拉起、厂商 ROM 对后台任务的杀进程行为。
- 各厂商"电池优化/自启动/后台运行限制"设置页跳转路径是否准确。
- 高优先通知在锁屏/勿扰下的呈现（heads-up 行为因 ROM 而异）。

---

## v6.7.1 · 2026-09-17

**主题：用户协议/隐私政策页 —— 品牌名纠正（9 处）+ 产品定位文案新增 + 权限清单排版自适应**

> 本版为第零版（F + G 项），插队先修 6.7.0 刚发布的用户可见缺陷。

### 品牌名纠正（9 处，用户可见 UI 文案：小智 → 小乐）
- `lib/presentation/pages/user_agreement_page.dart`（6 处）：内置 AI 助手名、自由聊天、实时语音交流、拍照问、主动来电问候、越来越多才多艺。
- `lib/presentation/pages/privacy_policy_page.dart`（2 处）：语音对话核心通道、拍照让…识别。
- `lib/presentation/pages/dev_center_page.dart`（1 处）：AI 主动联系副标题"由小智读本地口令判断…" → "由小乐…"。
- **注释 / 日志 / 协议表述一律未动**：底层 22 处「小智」（小智服务器/硬件/协议、`///` 注释、`xiaozhi_service` 连接事件等）全部保留。其中 `xiaozhi_service.dart:195` `'连接小智服务失败'` 属内部事件（仅用于完成连接 future，不经任何 Toast/UI 呈现），确认不进入用户可见提示。

### 新增（F 项 · 用户协议页）
- 新增「产品定位」段落（插在"小乐是什么"介绍段之后），复用语页既有 `_section` / `_p` 辅助方法：
  - 【小乐适合谁】两类人：长期记忆陪伴的人；要指挥一大摊设备、把活儿派出去再收回结果的人。
  - 【小乐能做什么】7 条（含多设备协作端、存网盘/发微信等规划能力，按张老师要求原样写入，未改成"面向/可扩展"）。

### 修复（G 项 · 隐私政策页）
- 「权限清单」`_perm` 改为上下堆叠自适应布局：权限名在上、用途/后果在下；`Text` 加 `softWrap: true`，任意屏宽（≤360dp 窄屏/常规/大屏）自动换行、不溢出、不截断、不横向滚动；深浅色模式均正常。

### 版本号
- `pubspec.yaml`：`6.7.0+43` → `6.7.1+44`
- `lib/app/config/app_config.dart`：`appVersion` → `'6.7.1'`（注释同步）

---

## v6.5.0 · 2026-09-17

**主题：AI 主动来电（方案 D —— 口令存本地 + 设备 MCP 工具取回）**

### 功能
前台定时巡检 → 小智读**本地口令**自主判断 → 命中则弹**全屏模拟来电**（回铃音+震动+30s 倒计时）
→ 用户接听后小智**先开口说开场白** → 进入正常双向对话。

### 架构（经 5 个实机探针逐步验证后定稿）
```
Timer → 三守卫(时段/冷却/非通话中) → 新建独立短 WSS 会话
  Device-Id = 设备 MAC（小写不变）｜Client-Id = 每轮全新 UUID v4
  注册 4 个设备工具：self.proactive.get_script / trigger_call / skip / get_opening
  → 发【轮换短口令】(≤16字) → 小智调 get_script 取回指令全文 → 判定
  → trigger_call(message=开场白) → 来电页 → 接听 → 发「说开场白」→ 小智调 get_opening 读出
```

### 为何是这套（关键实测结论，务必保留）
1. **detect 文本硬上限 16 字** ⇒ 长指令只能经**工具返回值**下发，不能走文本；
2. **服务器按 Device-Id 维护长期记忆** ⇒ 同一条固定指令重复发只有第一次生效
   ⇒ **必须多条口令轮换**（实测：轮换 5/6 明确二选一 vs 固定 0/6 触发）；
3. **同设备并发双 WSS 仅在 Client-Id 不同时允许**（相同则旧连接 1005 被踢约 388ms）；
4. **biji 笔记只能新建、不能改删** ⇒ 笔记通道必然堆积 ⇒ **本方案完全不写笔记**。

### 新增文件
| 文件 | 内容 |
|---|---|
| `lib/core/proactive/proactive_script_store.dart` | 口令多条 CRUD + **轮换游标** + 允许来电时段 + 恢复默认 |
| `lib/core/proactive/proactive_poll_service.dart` | 巡检服务：Timer + 三守卫 + 每轮新 Client-Id 短会话 + 4 工具注册 + 22s 超时 + 12s 未调则换口令重发 |
| `lib/core/proactive/proactive_ringtone.dart` | `flutter_pcm_sound` 合成 450Hz 断续回铃音（**零新增依赖**） |
| `lib/presentation/pages/incoming_call_page.dart` | 全屏来电页（30s 环形倒计时 + 接听/拒绝 + 资源释放幂等） |
| `lib/presentation/pages/proactive_script_page.dart` | 口令管理页（增删改查/启用停用/设为当前/恢复默认，**≤16 字**限制） |
| `test/proactive_test.dart` | 10 条单测（时段窗口含跨午夜、轮换与回退、序列化往返） |

### 改动文件
- `dev_center_page.dart`：新增「🤖 AI 主动联系」区块（总开关 + 巡检间隔 + 允许来电时段 + 口令管理入口）
- `chat_page.dart`：启停巡检 + `onTriggered` 弹来电页 + **接听后经 `self.proactive.get_opening` 回放开场白**
- `app_feats.dart`：新增 `proactive` 开关（默认关，入 `keys` 使「全部关闭」一并关掉）
- `log_buffer.dart`：新增 `proactive` 日志分类（默认开）
- `app_routes.dart` / `app_pages.dart`：新增 `incomingCall` / `proactiveScript` 路由

### 红线
🔒 冻结区零改动；⚠️ **`lib/core/network` 零行为变更**（manager/responder 仅按实例复用公开 API）；
**不写任何笔记**；巡检会话音频帧一律丢弃、绝不调用 `AudioUtil`；**不引入新依赖**。
**Device-Id 恒定小写不变，仅 Client-Id 每轮新生成。**

### 已知限制（一期）
巡检仅**前台/聊天页**生效（后台化留 v6.6.0）；离开聊天页会停止巡检。

### 自检
- `flutter analyze`：**0 error**；warning 5 条均为既有基线（`app_pages.dart` / `xiaozhi_service.dart`）。
- 单测 `test/proactive_test.dart` 10/10 通过；全量测试见提交说明（`AUDIT5` 为已知固有 flaky）。
- 回滚锚点：tag `anchor-pre-v6.5.0`（= v6.4.4 `30f52956`）。

---

## v6.4.4 · 2026-09-17

**主题：服务器 alert 按开发者 / 普通用户身份分流——开发者看原文、普通用户看友好弹窗**

### 背景
v6.4.3 虽然让 alert 在 UI 上可见了，但**不管是谁都显示服务器技术原文**（如 `Detect is only for wake words, do not send long texts.`），普通用户看不懂、体验差。张老师要求：**开发者看原文（正确），普通用户看友好弹窗**，用一个开关区分。

### 新增（dev）
- `lib/presentation/services/app_feats.dart`：`keys` 追加 `'rawServerAlert'`、`defaults` 加 `'rawServerAlert': false`（**默认关 = 普通用户模式**）。放进 `keys` 是**有意为之**——这样「全部关闭」(`allOff()`) 会一并把它关掉，语义正确（一键回到普通用户模式）。并加语义化 getter `AppFeats.rawServerAlert`。
- `lib/presentation/pages/dev_center_page.dart`：「能力开关」分组内新增一条 `_switchTile`：标题 `⚠️ 显示服务端原始提示`、副标题说明开发者/普通用户双模式、key `'rawServerAlert'`。

### 变更（chat）
- `lib/presentation/pages/chat/chat_page.dart` 的 `case 'alert':` 按开关分流：
  - `AppFeats.get('rawServerAlert')` 为真 → 开发者模式：保持 v6.4.3 行为（追加「⚠️ 服务端提示」原文 + ERROR 时弹红条）。
  - 否则 → 普通用户模式：追加友好气泡 + 弹「发送失败」友好弹窗，**不暴露技术细节**。
  - `alertText` 为空时直接 `break`（此前为空也走分支，现在提前跳过，行为更干净）。
- 新增两个私有辅助方法（风格与 `_showError` 一致）：
  - `String _friendlyAlertText(String raw)`：大小写不敏感地把技术原文映射成人话——含 `long texts` / `detect is only` →「这条消息有点长，没能发出去～ 把内容缩短一些再发一次吧。」；其他 →「消息没能发送成功，请稍后重试，或换个说法再试一次。」
  - `void _showFriendlyAlertDialog(String text)`：`showDialog` + `AlertDialog`（微信风简洁），标题「发送失败」、内容为入参、单按钮「知道了」关闭；首行 `if (!mounted) return;`。

### 红线遵守
- 未触碰 `lib/core/network`（仅改 presentation 层 + `app_feats`）。
- 不改这条消息的发送逻辑、不加客户端长度限制。
- 未引入新依赖。

### 版本号
- `pubspec.yaml`：`6.4.3+40` → `6.4.4+41`
- `lib/app/config/app_config.dart`：`appVersion` → `'6.4.4'`（注释同步）

---

## v6.4.3 · 2026-09-17

**主题：修复「服务器 alert 未被处理」——长文本被拒等关键提示此前在 UI 上完全不可见**

### 背景（一个真实存在的静默 Bug）
App 发出的**所有文字**（含平时打字聊天）都走同一条通道：`listen` + `state:"detect"`
（写死在 `lib/core/network/xiaozhi_websocket_manager.dart:279-299` 的 `sendTextRequest`，
全文无任何长度检查/截断）。官方服务器对 detect 文本有硬性长度上限（实测 **16 字通过 / 18 字被拒**），
超限会回：
```json
{"type":"alert","status":"ERROR","message":"Detect is only for wake words, do not send long texts."}
```
**但客户端此前完全没有处理 `alert` 消息** —— `_handleTextMessage` 的 switch 只有
`tts / stt / hello / llm / mcp` 分支，`alert` 落到 `default` 只记一行日志后丢弃。
⇒ **用户发长句时消息被服务器静默拒绝，界面上毫无提示**，用户以为已经发出去了。

### 修复（最小改动，1 个文件）
`lib/presentation/pages/chat/chat_page.dart` 的 `_handleTextMessage` 新增 `case 'alert':`：
- 记 warning 日志（含 status 与 message 原文）；
- 非空时追加一条**系统气泡**「⚠️ 服务端提示：<原文>」（持久可见、可回溯）；
- `status == ERROR` 时额外弹一次提示条，让问题**立刻可见**。

不改发送逻辑、不加客户端长度限制（避免臆测阈值；阈值以服务端实际返回为准，现在服务端会明说）。

### 自检
- `flutter analyze`：0 error；warning 仍为既有 5 条基线。
- 全量 `flutter test` 回归（见提交说明）。
- 版本 `6.4.2+39` → `6.4.3+40`。

### 真机验收
在聊天框发一条**超过 20 字**的消息 → 现在应能看到「⚠️ 服务端提示：Detect is only for wake words…」
（此前完全无提示）。若不再出现该提示，说明服务端策略已变，另行核对。

---

## v6.4.2 · 2026-09-17

**主题：修复历史遗留 Bug ——「一键云端」恢复到本机后，智能体不立刻出现在首页/聊天列表**

### 现象
从云端恢复（pull）后，**恢复下来的智能体不会立即出现在 App 首页/聊天列表**；
必须**再手动新增一个智能体**，云端恢复的那些才"顺便"一起显示出来。

### 根因（两名诊断员独立复核 + lead 亲自核对代码行，结论一致）
- 列表的状态源是 Riverpod 的 `agentListProvider`（`lib/core/providers/agent_provider.dart:15-18`），
  `ConversationPage` 用 `ref.watch(agentListProvider)` 响应式渲染。
- **新增/修改/删除**三条路径都经由 `AgentListNotifier.addAgent/updateAgent/deleteAgent`，
  它们在写存储后都会 **`await loadAgents()`**（`agent_provider.dart:29-47`）把存储重读进 `state`
  —— 这就是"刷新动作"。
- 而**云端恢复**走 `CloudSyncService.applyPullResult()`（`lib/presentation/services/cloud_sync_service.dart:340-399`），
  它**直接往 SharedPreferences 写 `agent_list` / `chat_history_*` / 身份等**（数据完整、await 无遗漏），
  但**完全不碰 `agentListProvider`**，没有任何通知内存状态的动作。
- 且 `CloudSyncPage` 原本是普通 `StatefulWidget`（**没有 `ref`**），结构上无法调用 provider；
  恢复后仅 `_load()` 刷新了本页的"云端绑定状态"。
- 另：`agentListProvider` **不是 autoDispose**，所以"返回首页/重进页面"**也不会重读磁盘**。
  ⇒ 只有当用户新增智能体触发 `loadAgents()` 时，才会读到已含恢复数据的存储。

### 修复（最小改动，1 个文件）
`lib/presentation/pages/cloud_sync_page.dart`：
1. `CloudSyncPage` 由 `StatefulWidget` → **`ConsumerStatefulWidget`**（`_CloudSyncPageState` → `ConsumerState<CloudSyncPage>`），以获得 `ref`；
2. 在 `_pull()` 中 `await CloudSyncService.applyPullResult(result: r);` 之后补一行
   **`await ref.read(agentListProvider.notifier).loadAgents();`**
   —— 与 `addAgent` 内部的刷新动作完全等价；
3. 新增 `import 'package:flutter_riverpod/flutter_riverpod.dart';` 与 `'../../core/providers/agent_provider.dart'`。

数据格式、云端协议、存储 key **均未改动**；不涉及下拉刷新等额外改动（按"最小改动"要求）。

### 自检
- `flutter analyze`：**0 error**；warning 仍为既有 5 条基线（`app_pages.dart` / `xiaozhi_service.dart`，未触碰）。
- **全量 `flutter test` 连跑 3 次：2 次 27/27 全绿，1 次仅在 `AUDIT 5` 报 0.28% / 14,706px** ——
  **与本仓记录的固有 flaky 数值完全一致**（我页/设置页 FutureBuilder 时序漂移），与本次改动无关；
  且 golden 文件**未发生任何变更**。CI 不跑测试，不阻塞。
- 版本 `6.4.1+38` → `6.4.2+39`。

### 真机验收
从云端恢复完成后，**应立刻**在首页/聊天列表看到恢复下来的智能体（无需再新增一个触发）。

---

## v6.4.1 · 2026-09-17

**主题：内置预置「笔记 + 高德」两台外部 MCP（开箱即用，用户可改 key）**

- **首次启动自动写入预置**：`biji-notes`（13 工具，前缀 `notes.`）与 `amap-maps`（15 工具，前缀 `amap.`），
  不必再手动导入配置。用 `xw_external_mcp_seeded` 标记**只写一次**——用户删除后不会被自动塞回。
- **用户可自行改用 key**：进编辑页改 `headers`（笔记的 Bearer token）或 `url` 里的 `key=`（高德）即可；
  **不修改就走预置默认值**。
- **「恢复预置」入口**：管理页右上角菜单「恢复预置（笔记/高德）」，空列表页也有「载入预置」按钮；
  按 id 去重，**不会重复添加**。
- 破坏性工具 `merge_notes` 的"默认关闭"逻辑统一收敛到 `ExternalMcpManager.applyDefaultDisabled()`，
  新增 / JSON 导入 / 预置三条路径共用；仅在用户未做过逐项选择时生效，不覆盖用户显式选择。
- 版本 `6.4.0+37` → `6.4.1+38`。

### ⚠️ 安全提示（张老师已知悉并确认）
预置的 token / key 会**打进 APK**，APK 内字符串可被提取，等同"半公开"。
适用于自有服务；建议在高德开放平台为 key 配置**域名白名单 / 调用配额**并定期轮换。

### 自检
- `flutter analyze`：**0 error**（warning 仍为既有 5 条基线）。
- **全量 `flutter test` 27/27 通过**（外部 MCP 单测 15 + 定位 6 + golden AUDIT 1-5 + 冒烟 1）。
- golden **未发生任何文件变更**（AUDIT 5 的偶发失败属本仓已知冷缓存假象，连跑两次 update-goldens 后即稳）。

---

## v6.4.0 · 2026-09-17

**主题：外部 MCP 接入（App 内增删改 + 加前缀桥接给 AI）**

- **新增「🌐 外部 MCP」管理能力**（开发者中心新增入口 → `lib/presentation/pages/external_mcp_page.dart`）
  - 支持**多条**外部 MCP 服务器配置的增 / 删 / 改 / 停用，配置仅存本机。
  - 支持**粘贴 JSON 导入**：直接贴 `{"mcpServers":{...}}` 片段即可（自动解析 url / headers / 前缀）。
  - 列表显示每台服务器的**连接状态**：在线 · N 个工具 / 连接失败原因。
  - **两级开关**：整台服务器启用开关 + 进入后**逐工具开关**。
  - 安全默认：会写/删数据的工具在 UI 上标注，其中 `merge_notes`（合并会删数据）**首次探测成功后默认关闭**。
- **桥接机制**（`lib/core/mcp/external_mcp_client.dart` / `external_mcp_manager.dart` / `external_mcp_store.dart`）
  - App 兼任 MCP **客户端**，连接外部 streamable-HTTP MCP 服务器；
  - 外部工具按 **前缀** 暴露给 AI：`{prefix}.{原始工具名}`（如 `notes.search_notes`、`amap.maps_geo`），
    与设备工具（`self.*`）合并后在 `tools/list` 一并返回，AI 调用时由 App 转发到对应服务器。
  - 建连时**预拉取**外部工具，确保首轮 `tools/list` 就能看到。
  - `xiaozhi_mcp_responder.dart` **纯加法**：新增两个可选回调 `extraToolsProvider` / `externalCaller`
    （为 null 时行为与改动前完全一致）。
- **`self.location.get_current`（v6.3.0 定位）与高德 MCP 打通**：AI 可取本机 GCJ-02 坐标后调用
  `amap.maps_around_search` / `maps_direction_*` 等。
- 版本 `6.3.0+36` → `6.4.0+37`。

### ⚠️ 本版关键坑（实测，务必保留）
1. **biji-notes 有双重 UA 校验**：Cloudflare + 源站挡非浏览器 UA。
   `Dart/3.x`、`okhttp`、`curl` → **401**（源站伪装成"凭证格式不正确"），空 UA → **403**。
   ⇒ 请求**必须**带浏览器式 `User-Agent`。
2. **amap 的 `Accept` 必须同时含 `application/json` 和 `text/event-stream`**，否则 **406**。
3. **鉴权失败形态不同**：biji → HTTP **401**；**amap 错误 key 是 HTTP 200 + body `{"status":"0","info":"INVALID_USER_KEY"}`**
   ⇒ 绝不能只看状态码，必须解析 body。
4. 响应三态：顶层 `error` / `result.isError` / 正常 `result.content[0].text`；
   amap 的 text 是 JSON 字符串、biji 是纯文本 —— 一律原样透传。
5. 两服务器均无状态（无 `Mcp-Session-Id`、无需 `notifications/initialized`）。
6. Dart **没有 `?[]` 空安全下标运算符**（本版踩到过，须逐层判空）。

### 自检
- `flutter analyze`：**0 error**；warning 5 条均为既有基线（`app_pages.dart` / `xiaozhi_service.dart`，本次未触碰）。
- **全量 `flutter test` 25/25 通过**（外部 MCP 单测 13 + 定位 6 + golden AUDIT 1-5 + 冒烟 1；单测用 stub 客户端，不发真实网络）。

---

## v6.3.0 · 2026-09-16

**主题：设备 MCP 详情页（逐项开关）+ 定位能力（self.location.get_current）**

### ✨ 新增：设备 MCP 工具「逐项开关」

- 开发者中心「📋 查看已注册的工具清单」由**只读弹窗**升级为**可操作详情页**（`dev_center_page.dart`）：26+1 项 MCP 设备工具每项行尾带 `Switch`，可独立开启/关闭。
- `AppFeats` 新增 `mcpToolEnabled(name)` / `setMcpToolEnabled(name, bool)`；持久化键 `xw_mcp_<name>`（工具名中的 `.` 转义为 `_`）。`load()` 一并恢复逐项设置；**逐项键独立于 `keys` 列表，`allOff()` 不清空**（总闸「全部关闭」= 普通用户模式，逐项偏好保留）。
- `xiaozhi_mcp_responder.dart`（**纯加法**）：新增可选字段 `bool Function(String name)? isToolEnabled`
  - `tools/list` 用 `.where((t) => isToolEnabled?.call(t.name) ?? true)` 过滤；
  - `tools/call` 命中被禁用工具 → 回 `-32601 unknown tool`（与"不存在"一致，不暴露被关工具）；
  - `initialize` 的 `listChanged:false` 等协议字段**保持不变**。
- `chat_page.dart`：`_setupMcpResponder()` 注入 `isToolEnabled: AppFeats.mcpToolEnabled`（26 处 `register` 全部保留，过滤在下发层做）。

### ✨ 新增：定位能力（self.location.get_current，第 27 项工具）

- 新增 `lib/core/mcp/location_service.dart`（单例）：`getCurrent()` 流程——
  ① 权限检查/申请（复用 `permission_handler`，拒绝 / 永久拒绝均返回结构化原因）；
  ② 检查定位服务是否开启（未开返回「请打开定位」）；
  ③ `geolocator` 高精取位（**超时 8s** 降级到最近已知位置）；
  ④ **WGS-84 → GCJ-02 转换**（内置纯函数 `wgs84ToGcj02`，已写单测校验已知点）；
  ⑤ 返回 `{latitude, longitude, accuracy, coordType:'gcj02', provider}`。**所有异常内部消化，绝不抛出或阻塞 UI**。
- `xiaozhi_mcp_responder.dart` 新增工具定义 `self.location.get_current`（无参 inputSchema）。
- `chat_page.dart` 注册第 27 项 → 调用 `LocationService.instance.getCurrent()`（取位结果在聊天回显一条系统消息）。
- `pubspec.yaml` 新增 `geolocator ^13.0.0`（锁定 Flutter 3.32.2 / Dart 3.8.1 兼容版，实测 13.0.4 解析通过）；`AndroidManifest.xml` 新增 `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`。

### 🔒 红线遵守

- `xiaozhi_mcp_responder.dart` 改动为**纯加法**（新增字段 + 两处过滤/拦截分支 + 1 个工具定义）；hello/initialize 既有协议字段、音频编解码参数、既有冻结文件均未触碰。
- 除 `geolocator` 外**未引入任何新依赖**（`permission_handler` 为既有）。

### ✨ 变更

- `pubspec.yaml` 6.2.1+35 → **6.3.0+36**；`app_config.dart` appVersion 6.2.1 → **6.3.0**；README 徽章与版本表同步。
- 定位隐私：仅 AI 调用时按需取位，绝不后台采集；纳入逐项开关（可在详情页关闭 `self.location.get_current`）。

### ⚠️ 跨版本依赖（已知）

- IP 粗定位兜底（走高德 `maps.ip_location`）需 v6.4.0 桥接后才生效；本版先实现「提示 + 网络/低精度定位尝试」，IP 兜底占位。

---

## v6.2.1 · 2026-09-13

**主题：聊天页底部「连接错误」红条降噪（屏蔽瞬时网络错误弹窗）**

### 🐛 修复/优化：DNS/连接类瞬时错误不再弹红条

- **现象**：App 底部偶尔弹出红条「连接错误：WebSocketChannelException: SocketException: Failed host lookup: 'api.tenclass.net' (errno=7)」。
  （注：`apitenclass.net` 为截图漏点号，实为小智公共服务器 `api.tenclass.net`；`errno=7`=DNS 解析失败。）
- **根因**：WS 通道 socket 报错 → `xiaozhi_websocket_manager.dart:_onError` 派发 `error` 事件 →
  `chat_page.dart` 原统一弹红条（`_showError('连接错误: …')`）。
  这类错误多为**网络瞬时抖动**（WiFi↔流量切换、信号短暂丢失、DNS 暂不可达），**自动重连会恢复**，红条纯属打扰。
- **修复**（`lib/presentation/pages/chat/chat_page.dart` 仅此一文件）：
  1. 报错分支新增分类：错误串含 `SocketException`/`Failed host lookup`/`Connection refused`/`Network is unreachable`/
     `Connection timed out`/`Connection reset`/`创建WebSocket失败`/`WebSocketChannelException` → 判定为**瞬时网络错误**；
  2. 瞬时网络错误：**不再弹红条**，改为顶部状态栏显示「网络异常，正在自动重连…」+ 记日志（`logger.severe`）；
  3. **需用户处理的错误仍弹红条**：身份拒绝(432x)、自动重连已达上限、OTA 认证失败等（这些错误串不含上述关键词，天然命中 else 分支）。
- **不丢信息**：聊天页顶部本就有常驻「连接状态栏」（`chat_page.dart:300–355`，断线时带「重连」按钮），
  降级后用户仍能看到状态并可手动重连；自动重连成功即恢复正常。
- **冻结文件未动**：`xiaozhi_websocket_manager.dart` 仅消费其事件，未修改协议/编解码参数。

### ✨ 变更

- `pubspec.yaml` 6.2.0+34 → 6.2.1+35；`app_config.dart` appVersion 6.2.0 → 6.2.1；README 徽章与版本表同步。

---

## v6.2.0 · 2026-09-13

**主题：一键云端「设备身份」上传与恢复修复 + 新增「清空云端数据」**

### 🐛 修复：一键云端 MAC / 设备 ID 无法恢复（恢复后连不回原智能体）

- **现象**：新建智能体（随机 MAC，可正常连接）→ 一键上传 → 删除 App → 重装 → 从云端恢复，
  **智能体名称与聊天记录恢复成功，但 MAC 与设备 ID 没有恢复**（被重装后本机新生成的身份顶替）→ 连不回原智能体。
- **根因（已证实，两端都缺）**：
  1. **上传端** `cloud_sync_service.dart` 的 `agentToWeb()` 只序列化 `fOta/fWs/fToken/fModel/fBoard`，
     **不含 `fMac`/`fCid`**（原注释称"fMac/fCid 为网页端本机身份，App 侧不伪造" —— 该认知已过时：
     自 v1.1.5 起设备身份已是**每智能体独立**，且网页版 conf 一直存这两键）；
  2. **恢复端** `applyPullResult()` 只写 `agent_list` / 聊天记录 / 昵称 / 手机号，**完全不写身份**；
  3. 重装 App 后 SharedPreferences 清空 → 本机按 androidId **重新生成**全局身份 →
     进入对话时 `AgentIdentityStore.load(agentId)` 返回 null → 用**新身份**连接。
- **修复**（`lib/presentation/services/cloud_sync_service.dart`）：
  1. `pushAll`：循环内 `AgentIdentityStore.load(agentId)` → 传给 `agentToWeb(a, identity:)`，
     `conf` 补 `fMac` / `fCid`（与网页版 9 键结构对齐）；
  2. `pullAll`：解析时提取 `conf.fMac`/`fCid` 汇总为 `identities`，随结果返回；
  3. `applyPullResult`：**写回** `AgentIdentityStore.save(agentId, mac, clientId, model)`；
     并把**首个智能体**的身份经 `XiaozhiDeviceInfoUtil` 公开 setter 设为**全局身份**（避免恢复后首次连接仍用新身份）。
- **兼容**：云端老数据没有这两个键 → 自动跳过身份写回（行为同旧版，不会更糟）；多智能体按 agentId 分别存取，不串号。
- **云端零改动**：`/push` 的 `agents` 是**整体 JSON 透传**（存 `users.agents_json`），`/pull` 原样返回。

### ✨ 新增：一键云端「🗑 清空云端数据」

- **App**：一键云端页（已绑定状态）新增红色按钮 → **二次确认弹窗**（明示删除范围 + 不可恢复）→ 调用云端。
- **云端**：新增 `POST /clear`（`xiaole-web-2027/cloud/src/worker.js`）：
  手机号 + 用户名**双因子核验** → `DELETE FROM chat_blocks WHERE session_id LIKE 'phone:%'` +
  `DELETE FROM users WHERE phone=?`；返回删除计数。**已部署上线并验证**。
- **边界**：只清云端；本机数据不受影响。

---

## v6.1.3 · 2026-09-13

**主题：开发者中心可查看已注册的全部 MCP 工具**

- **新增**：开发者中心「🧰 MCP 设备工具」下方新增 **「📋 查看已注册的工具清单」** →
  弹窗**分组列出全部 26 项**（工具名 + 中文用途），底部附「闹钟/日程/短信/拨号/分享需你确认才生效」提示。
- 开关副标题更新为「26 项（音量/闹钟/日程/拨号/短信/导航/截屏…）」。
- **改动范围：仅 `dev_center_page.dart`**（已验证 `git status` 只有该业务文件变更）。

---

## v6.1.2 · 2026-09-13

**主题：修复截屏的 GPU 资源泄漏**

- **修复**：`self.screen.snapshot` 中 `ro.toImage()` 得到的 `ui.Image` **用完未 `dispose()`** →
  每次截屏泄漏一张图的显存（多次截屏可能 OOM）。改为 `try { ... } finally { img.dispose(); }`。
- 来源：独立验证员发现的第二个实锤问题。

---

## v6.1.1 · 2026-09-13

**主题：修复截屏工具失效**

- **修复**：`self.screen.snapshot` 恒返回"当前界面不支持截屏" ——
  v6.1.0 方案里要求"用 `RepaintBoundary` 包住聊天页根视图"**实施时漏做**，
  导致 `findRenderObject()` 永远拿不到 boundary。
  修复：`chat_page.dart` 加 `GlobalKey _snapshotKey` + `build()` 根视图包 `RepaintBoundary(key: _snapshotKey)`
  + 执行器改从该 key 取 boundary。
- 来源：独立验证员发现的实锤缺陷（静态分析查不出）。
- 遗留：本次引入显存泄漏（见 v6.1.2）。

---

## v6.1.0 · 2026-09-13

**主题：MCP 设备工具能力扩展（11 → 26 项）**

- **修复 3 个真机 bug**：
  1. `set_volume` 由「软件增益」改为**控制系统媒体音量**（根治"显示 100% 实际只有一半响度"）；
  2. **新增 `self.alarm.set_alarm`** —— 经 `AlarmClock.ACTION_SET_ALARM` 调用**真·系统时钟闹钟**
     （App 关闭 / 手机重启仍会响）。原先无此工具，AI 只能拿倒计时凑数 → "说设好了实际只设了 App 内提醒"；
  3. `schedule.create_event` 由内存 Timer 改为**写系统日历**（根治"日程设了没用"）。
- **补齐官方标准 5 项**：`screen.set_brightness`（应用级，免 WRITE_SETTINGS）/`screen.get_info`/
  `get_system_info`/`screen.snapshot`/`reboot`（映射为"重连+清空会话"，description 明确不重启手机）。
- **免权限系统能力 5 项**：`phone.dial`（只预填不直拨）/`message.send_sms`/`map.navigate`/
  `system.open_settings`/`system.open_url`。
- **其他 5 项**：`show_toast`/`share.text`/`clipboard.get`·`clipboard.set`/到点 **TTS 语音播报**（系统自带引擎，不下载模型）。
- **诚实性设计**：intent 类工具只能"发起请求"，返回值统一含 `requested: true` + 明确提示，杜绝"AI 说设好了实际没设"。
- **顺手修复**：通话全屏收起按钮未走 `_collapseVoiceCallOverlay` → 收起后系统 UI 不恢复（沉浸式残留）。
- **依赖**：+4（`flutter_volume_controller 2.0.1` / `android_intent_plus` / `screen_brightness` / `flutter_tts`）；
  `torch_light` 因要求 Dart SDK ^3.12（本项目 3.8.1）**未采用**，手电筒不做。
  **全部新能力免危险权限，AndroidManifest 零改动**。

---

## v6.0.1 · 2026-09-13

**主题：修复 v6.0.0 的 CI 失败并发布正式版**

- **修复**：`Free disk space` 步骤误删 `$AGENT_TOOLSDIRECTORY`（= `/opt/hostedtoolcache`，**Flutter/Java 工具链所在**）
  → `flutter: command not found`。清理范围收窄为仅 `.NET`/`Boost`，并注释禁止删工具链与 NDK。
- **同时**：补齐 `abiFilters`（ARM 限定）修复 CI 磁盘耗尽；将工作流迁移为 `build-apk-v2.yml`（新增 `workflow_dispatch` 兜底）；
  把**完整项目树（~200 文件）**纳入版本管理（修复"重建仓库历史不完整导致回滚丢文件"）。
- **发布**：GitHub Release「小乐 v6.0.1 ⭐ 正式版（通话全屏）」，APK 约 37MB。

---

## v6.0.0 · 2026-09-12

**主题：正式版——基于 v4.4.0 原版，唯一新增「通话界面全屏」**

- **新增**：通话中隐藏顶端工具栏（`appBar: _showVoiceCallOverlay ? null : AppBar(...)`）+ 系统沉浸式
  （`immersiveSticky`/`edgeToEdge` 进出配对）；展开/收起封装为 `_expandVoiceCallOverlay()` /
  `_collapseVoiceCallOverlay()` 成对方法；`dispose` 亦恢复系统 UI。
- **封存**：v4.5.x–v4.6.2 的语音扩展能力（麦克风灵敏度 / 端侧声纹 / 本地唤醒 KWS / 46 唤醒词配置）
  **全部封存未删除** —— 本地 tag `archive-voice-wip-20260912` 与远端 tag `v4.5.0`~`v4.6.2`（含 Release APK）可随时找回。
- **范围**：通信协议零改动、音频编解码参数零改动。
