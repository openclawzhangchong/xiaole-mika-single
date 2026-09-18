# PLAN_v6.10.0 次级页微信风收口 与 Design Token 治理

> 基线版本：`v6.9.1+50`（Flutter 3.32.2 / Dart 3.8.1）
> 提出日期：2026-09-18
> 触发：张老师质疑「自建 wx_* 比引第三方库划算，确定吗？」→ 重新做完整审计
> 状态：**✅ 已实施 —— 对应发布版本 `v6.10.0`**（2026-09-18）
>
> **实施结果**：新增 8 文件 / 修改 31 文件。`flutter analyze` **0 error / 0 warning**；`flutter test` **71/71**；
> 5 张 golden 重生成并**逐张目视核对**。执行方式：派 7 个子 agent 分文件并行（互斥文件集），lead 统一收口验证。
> 详见 `CHANGELOG.md` 的 `v6.10.0` 段。

---

## 决策记录（2026-09-18，张老师）

| 问题 | 决策 |
|---|---|
| 走哪个方案 | **V3 全量收敛** |
| 长按菜单位置 | **改成屏幕正中央深色 ActionSheet**（对齐微信） |
| 说话音量 Slider | **保留 Slider，只把轨道/滑块改成微信绿** |
| 验收方式 | **直接出 APK 装机看** |
| 执行方式 | 派多个子 agent 并行，我统筹、agent 断线则接手 |

**回滚锚点**：`anchor-pre-v6.10.0` → commit `d469b84`（不以 v 开头，不触发 CI）

---

## 实施规格（确定性映射表，子 agent 统一遵守）

### 字号映射 → 阶梯 **11 / 12 / 14 / 17 / 20**

| 原 fontSize | 新值 | token | 出现次数 |
|---|---|---|---|
| 11 | 11 | `captionSmall` | 7 |
| 12 | 12 | `caption` | 33 |
| 13 | **12** | `caption` | 23 |
| 14 | 14 | `subtitle` | 18 |
| 15 | **14** | `subtitle` | 8 |
| 16 | **17** | `body` | 15 |
| 17 | 17 | `body` | 5 |
| 18 | **17** | `body` | 2 |
| 20 | 20 | `title20` | 3 |
| ≥22 | **保留不动** | — | 4 |

**例外**：`chat_input_bar.dart` / `voice_record_button.dart` 的 15 → **17**（输入区与气泡正文对齐）。
**绝对不动**：`emotion_animation_overlay.dart:195` 的 `fontSize: 110`（emoji 尺寸）；`incoming_call_page.dart` 的 22；`activation_dialog.dart` 的 40。

> 选 15→14 而非 15→17、16→17 而非 16→14 的依据：**就近取整 + 平局偏收缩**，避免撑破密集列表布局。
> 16→17 是本次最有价值的一处 —— 聊天气泡原来是 16px，**微信正文是 17px**，改完更贴微信。

### 圆角映射 → **只改野生值**

| 原值 | 新值 |
|---|---|
| 10 | 8 |
| 14 | 12 |
| 2 / 4 / 5 / 6 / 7 / 8 / 12 / 36 | **保留不动** |

> **为什么不全量收敛圆角**：5/6/7/8 之间是 1px 差异，肉眼不可辨，改动是**纯风险零收益**；
> 且 `7` 是微信 28px 图标色块的正确值、`6` 是 48px 会话头像的正确值，强行改反而**破坏**微信规范。
> 真正的失控值只有 10 与 14 两个。**字号才是真问题**（13/14、15/16/17 成对冲突，会在整屏累积出"不齐"的观感）。

### 已建成的 token（基座，**不再改动**）

- `lib/app/themes/app_text_styles.dart`（**重写**）：阶梯 5 档 + 6 个颜色辅助方法。
  **关键修复**：旧版把 `color` 写死在样式里 ⇒ 深色模式不可用 ⇒ 全项目零引用沦为死代码。新版**不带颜色**。
- `lib/app/themes/app_dimens.dart`（**新建**）：圆角 / 高度 / 头像 / 间距 / 页面 token。
  旧 `AppDimens` 已从 `app_colors.dart` 移除（零引用，且同名会导致 import 冲突）。
- `lib/presentation/widgets/wx_*.dart`（**新建 6 个**）：`WxCell` / `WxCellGroup` / `WxDialog` / `WxActionSheet` / `WxIconButton` / `WxEmpty`。

---

## 零、先纠正我上一轮的两个不准确之处

张老师的质疑是对的。我上一轮给的是**关键词计数**，不是审计，有两处需要更正：

### 更正 1：「13 处 / 9 处带 Material 味」——数字对，但画像错了

| 页 | 我上轮说的 | 实际情况 |
|---|---|---|
| `settings_page` | 13 处 Material | ✅ 数字对（8 ListTile + 1 Slider + 1 AlertDialog + 3 RadioListTile） |
| `conversation_page` | 9 处 Material | ⚠️ 数字对，但**画像错了** |

**关键更正**：`conversation_page` 的 **主列表早已是像素级微信自绘**——

```dart
Divider(height: 0.5, thickness: 0.5, indent: 76)   // 微信 0.5px 细线 + 76px 缩进（48头像+12间距+16内边距）
AgentAvatar(size: 48, radius: 6)                    // 微信圆角方形头像
Text(agent.name, fontSize: 17, fontWeight: w600)    // 微信会话标题
Text(timeStr, fontSize: 12, color: textSecondary)   // 微信右侧时间
Container(padding: symmetric(horizontal:16, vertical:10))
```

它的 Material 触点**全部集中在空态 / 错误态 / 加载态 / 两个弹窗**，主列表一个都没有。
我上轮笼统说「还带 Material 味」，会让你误以为主列表也要重做 —— **主列表恰恰是全项目最像微信的部分之一，不该动**。

### 更正 2：一个更严重的问题被我漏掉了

| token 文件 | 引用数 | 状态 |
|---|---|---|
| `AppColors`（app_colors.dart） | **244 处 / 28 个文件** | ✅ 健康，用得非常好 |
| `AppTextStyles`（app_text_styles.dart） | **0 处** | ❌ **死代码** |
| `AppDimens`（app_colors.dart 内） | **0 处** | ❌ **死代码** |

**所谓「token 三件套」实际只有 `AppColors` 是活的。** 我上轮说「由你现有 token 驱动」——只有颜色这部分成立，
字号与尺寸完全没有 token 可驱动。**这才是微信风守不住的真正根因。**

---

## 一、实测审计数据

### 1.1 字号：124 处硬编码，15 种取值

```
12px × 33   13px × 23   14px × 18   16px × 15   15px × 8
11px × 7    17px × 5    20px × 3    18px × 2
22px × 1    24px × 1    32px × 1    40px × 1    110px × 1
```

微信实际只用一套很小的阶梯（导航 17 / 正文 17 / 次要 14 / 辅助 12 / 极小 11）。
**现状是"每个开发者凭手感挑字号"** —— 13 与 14 并存、15 与 16 并存，视觉上就是"不够微信"的来源。

### 1.2 圆角：10 种取值

```
12 × 15   4 × 10   8 × 3   7 × 2   5 × 2   10 × 2   2 × 1   6 × 1   14 × 1   36 × 1
```

微信规范实际只有 2 / 4 / 8（气泡 8 + 小尖角）。`7` 和 `5` 这种值明显是随手写的。

### 1.3 `conversation_page`（280 行）逐行清单

| 行 | 控件 | 位置 | 判定 |
|---|---|---|---|
| 68 | `ElevatedButton.icon` | 空态「添加智能体」 | ⚠️ 需改（Material 实心按钮，微信是文字/描边） |
| 84 | `Divider(height:0.5, indent:76)` | 列表分隔线 | ✅ **已是微信规格，不动** |
| 96 | `Material` | 行容器 | ✅ 中性 |
| 98 | `InkWell` | 行点击 | ✅ 中性（微信也有按压态） |
| 174 | `CircularProgressIndicator` | 加载态 | ⚠️ 需改（Material 圆环） |
| 191 | `ElevatedButton` | 错误态「重试」 | ⚠️ 需改 |
| 210 | `showModalBottomSheet` | 长按菜单 | ⚠️ 需改（微信是**屏幕中央深色 ActionSheet**，不是底部白抽屉） |
| 217 / 225 | `ListTile` ×2 | 长按菜单项 | ⚠️ 需改 |
| 249 / 251 | `showDialog` + `AlertDialog` | 删除确认 | ⚠️ 需改（微信按钮**居中 + 纵向分割线**，Material 是右对齐横排） |
| 255 / 266 | `TextButton` ×2 | 确认按钮 | ⚠️ 需改 |

**小计：11 处，其中 ✅ 5 处不用动，⚠️ 需改 6 处**（且全部在空/错/载 + 弹窗，不涉主列表）

### 1.4 `settings_page`（265 行）逐行清单

| 行 | 控件 | 位置 | 判定 |
|---|---|---|---|
| 29 | `AppBar(title:'我')` | 顶部栏 | ✅ **已微信规格**（app_theme 定制：白底 17px 居中 + 0.5px 底线） |
| 39/52/71/84/112/117/129/148 | `ListTile` ×8 | 分组行 | ⚠️ 需改 —— 注意**当前行间没有任何分割线**，微信每行之间必有 0.5px 细线（左缩进） |
| 88 | `Slider` | 说话音量 | ⚠️ 需定夺（Material 滑杆，微信无直接对应物） |
| 181–213 | `_buildSection`（Material + 灰标题 + 圆角 8 白卡） | 分组容器 | ✅ **已是微信风，保留** |
| 167–178 | `_iconTile`（28px 圆角色块 + 白图标） | 行图标 | ✅ **已是微信风，保留** |
| 220 / 222 | `showDialog` + `AlertDialog` | 主题选择 | ⚠️ 需改 |
| 227 / 238 / 249 | `RadioListTile` ×3 | 主题三选一 | ⚠️ 需改（微信用勾选，不用 radio 圆点） |

**小计：13 处，其中 ✅ 6 处不用动，⚠️ 需改 7 处**

### 1.5 全项目「已达标」清单（本次绝不动）

- `app_theme.dart` —— AppBar 白底黑字 17px 居中 + 0.5px 底线、Card 无阴影、Scaffold `#EDEDED`
- `app_colors.dart` —— 完整微信色板 + dark 全套（244 处引用，健康）
- `conversation_page` 主列表行 —— 已像素级微信
- `settings_page` 的 `_buildSection` / `_iconTile` —— 已微信风
- `chat_page` / `message_list` / `message_bubble` / `chat_input_bar` / `voice_wave_visualizer` —— 0 个 Material 控件
- `agent_avatar` / `profile_header` —— 自定义实现

---

## 二、结论：我上一轮说的「自建 wx_* 更划算」对不对？

**对一半，错一半。老实说：**

| 我的原话 | 复核结论 |
|---|---|
| 「引第三方库不划算」 | ✅ **成立**。tdesign 会带进第 4 套设计语言（蓝/卡片/阴影），且 51 组件无聊天类 |
| 「零依赖、零体积增长」 | ✅ **成立**。自建不增依赖、不增 APK 体积 |
| 「golden 可逐页控制」 | ✅ **成立**。只动 2 页就只影响 2 张 golden |
| 「由你现有 token 驱动」 | ❌ **不成立**。字号/尺寸 token 是**死的**，无 token 可驱动 |
| 隐含的「问题是缺组件」 | ❌ **归因错了**。真正的问题是 **token 纪律**，组件只是结果 |

**所以正确的实施顺序是：**

```
① 补活 token（AppTextStyles / AppDimens 真正被引用）
        ↓
② 收敛硬编码（字号 15 种 → 微信阶梯；圆角 10 种 → 3 种）
        ↓
③ wx_* 组件自然成形（组件只是 token 的具现化，不是起点）
```

一上来就写 6 个组件、但组件内部还是各写各的字号 —— 那是把硬编码从页面搬进组件，问题原封不动。

---

## 三、三个方案

### V1｜最小闭环（推荐）

**范围**：治 token 层 + 只改 `settings_page` 与 `conversation_page` 两页。**不碰 `chat_page`（2660 行）。**

| 步骤 | 内容 | 产出 |
|---|---|---|
| 1 | 重写 `AppTextStyles` 为**微信字号阶梯**（见 §4.1），使其真正被引用 | 1 文件重写（原为零调用的死代码，重写无回归风险） |
| 2 | 新建 `lib/app/themes/app_dimens.dart`，圆角/间距/行高阶梯（原 `AppDimens` 留在 app_colors.dart 内不动，避免连带影响） | 1 新文件 |
| 3 | 新建 6 个 `wx_*` 组件（见 §4.2） | 6 个新文件 |
| 4 | 改造 `conversation_page`：空态 / 错误态 / 加载态 + 长按 ActionSheet + 删除确认弹窗 | 1 文件修改 |
| 5 | 改造 `settings_page`：8 个 `ListTile` → `WxCell`（**补 0.5px 行间分割线**）+ 主题弹窗 → 微信风 | 1 文件修改 |
| 6 | 更新 golden `audit_conversation_list` / `audit_profile_page` 并目视核对 | 2 张 golden |

**收益**：可见 Material 味清零（两页）；字号/圆角首次有纪律；为后续页面提供可复用基座。
**风险**：低。改动集中在 `lib/presentation`（✅ 自由区）+ 新增主题文件；`chat_page` 零接触。

### V2｜只统一弹窗（最小、可立即做）

只把 3 个 Material 弹窗换成微信风：
- `conversation_page` 长按菜单 → 中央深色 ActionSheet
- `conversation_page` 删除确认 → 微信风双按钮弹窗
- `settings_page` 主题选择 → 底部 ActionSheet + 勾选

**不动 token、不动列表、不动空态。** 约 1 个文件级改动 + 2 个新组件。
**收益**：立刻消除最扎眼的"安卓味"。**风险**：近零。

### V3｜全项目字号收敛（最大、风险最高）

把 124 处硬编码字号**全部**收敛到微信阶梯。**包含 `chat_page` 2660 行。**
**代价**：全量 5 张 golden 失效、聊天页有回归风险、收益（肉眼几乎看不出）与风险严重不匹配。
**结论：不推荐。** 但可作为 v6.11+ 的长期技术债逐步偿还。

---

## 四、规格设计

### 4.1 微信字号阶梯（替换现有 AppTextStyles）

现有 `AppTextStyles` 的问题：值是 32/24/20/16/14/12/11 + 16(agentName)/13(agentDescription)，**与页面实际用的 17 不一致**（页面用 17，token 写 16）。新阶梯：

| Token | 字号 | 字重 | 用途 | 对齐微信 |
|---|---|---|---|---|
| `navTitle` | 17 | w500 | 导航栏标题 | 微信 nav 17 |
| `cellTitle` | 17 | w400 | 会话标题 / 设置行主文 | 微信 17 |
| `cellTitleStrong` | 17 | w600 | 会话名（加粗） | 微信会话名 |
| `cellSubtitle` | 14 | w400 | 设置行副文 / 会话摘要 | 微信 gray 14 |
| `body` | 17 | w400 | 正文 / 消息气泡 | 微信正文 17 |
| `caption` | 12 | w400 | 时间 / 辅助说明 | 微信 12 |
| `captionSmall` | 11 | w400 | 时间戳 / 极小辅助 | 微信 11 |
| `sectionHeader` | 14 | w400 | 分组灰标题 | 对应现有 settings 分组标题 |
| `button` | 17 | w400 | 弹窗按钮「取消/确定」 | 微信弹窗按钮 17 |

> ⚠️ 注意：**气泡正文**目前在 `message_bubble.dart` 里，属聊天页 —— V1 不动它，只把阶梯定义好备用。

### 4.2 六个 `wx_*` 组件（全部由 AppColors + 新 token 驱动）

| 组件 | 替换对象 | 微信规格 |
|---|---|---|
| `WxCell` | `ListTile` | 高 56（单行）/ 68（双行）；左内边距 16；标题 17；副标题 14 gray；右侧箭头 `#C7C7CC`；**行间 0.5px 细线，左缩进 = 16 + 左图标宽 + 12** |
| `WxCellGroup` | `_buildSection` 内联 | 灰分组标题（14 gray，16 外边距）+ 白卡（圆角 8，**无阴影**） |
| `WxDialog` | `AlertDialog` | 宽 270；圆角 12；标题 17 w500 居中；正文 14 居中；按钮区**居中平分 + 上下 0.5px 分割线**；取消为灰、确认为绿（危险操作为红 `#FA5151`） |
| `WxActionSheet` | `showModalBottomSheet` | **屏幕正中**深色圆角容器（`#4C4C4C` 0.95）；选项 17px 白字；取消项独立白底；项间 0.5px 分割线 |
| `WxIconButton` | `ElevatedButton` | 文字按钮：绿 `#07C160` 17px；描边按钮：1px 绿边 + 绿字 + 圆角 4 |
| `WxEmpty` | 空态 `Column` | 图标 72 gray + 主文 16 gray + 副文 14 gray + 可行动按钮；间距 16/8/24 |

**依赖方向**：`wx_* → app_colors.dart + app_text_styles.dart + app_dimens.dart`，**不反向依赖任何页面**，保证零循环。

---

## 五、实施批次与验收

| 批次 | 内容 | 验收 |
|---|---|---|
| B1 | 新建 `app_dimens.dart` + 重写 `app_text_styles.dart` | `flutter analyze` 0 error；全量测试仍 71/71（零调用方 → 必然不破坏） |
| B2 | 新建 6 个 `wx_*` 组件 | `flutter analyze` 0 error；新组件各配 1 个最小 widget 测试 |
| B3 | 改 `conversation_page` | golden `audit_conversation_list` 更新 + 目视核对；测试全绿 |
| B4 | 改 `settings_page` | golden `audit_profile_page` 更新 + 目视核对；测试全绿 |
| B5 | 版本号 + 文档同步 | `pubspec.yaml` / `app_config.dart` 双处一致；README 徽章 + 档案行 + 状态列；CHANGELOG 新段；进度与续接.md 回填 |

**回滚锚点**：开做前先打 tag（如 `v6.9.1-stable`），确保可退回。

---

## 六、红线遵守声明

| 区域 | 本方案是否触碰 |
|---|---|
| 🔒 冻结区（`xiaozhi_device_info_util.dart` / OTA appName / 音频编解码参数） | ❌ 不碰 |
| ⚠️ `lib/core/network` | ❌ 不碰 |
| ⚠️ `lib/data` | ❌ 不碰 |
| ⚠️ `app_theme.dart` | ❌ **不碰**（它被 `main.dart` 全局引用，改它会连带影响 chat_page 与全部 golden） |
| ✅ `lib/presentation` | ✅ 仅 `settings_page` / `conversation_page` 两文件 |
| ✅ 新增文件 | ✅ 1 + 6 = 7 个新文件 |

**本方案不含任何行为变更**（无网络 / 无存储 / 无协议），纯视觉层。

---

## 七、golden 策略

现状：`test/ui_audit_test.dart` 产出 5 张（chat_messages / input_empty / input_typed / conversation_list / profile_page）。
测试环境用 FlutterTest 内置字体，**中文显示为方块**，因此 golden 只能核对**颜色 / 形状 / 布局 / 对齐**，不能核对文案。

- V1 只影响 `audit_conversation_list`（AUDIT 4）与 `audit_profile_page`（AUDIT 5）
- 流程：改 → `flutter test --update-goldens test/ui_audit_test.dart` → **逐张目视核对 diff 是否只落在预期区域** → 提交
- ⚠️ 已知：AUDIT 5 有 0.28% 固有 flaky（FutureBuilder 时序），复跑即绿；若不确定就复跑确认

---

## 八、待张老师确认（4 个问题，我不猜）

1. **走哪个方案？** V1 最小闭环 / V2 只统一弹窗 / V3 全项目字号收敛 / 暂不做
2. **长按菜单的位置**：微信是**屏幕正中央的深色 ActionSheet**；你现在是**底部白色抽屉**。改成中央深色属于**可见的行为变化**（位置变了），要改吗？
3. **说话音量的 Slider**：微信设置里没有 Material 滑杆的对应物（微信一般用「进度条 + 加减」或直接跳系统音量）。保留系统 Slider / 改成微信式条 / 移除改为只显示数值？
4. **字号阶梯要不要严格锁定**：V1 只把新阶梯用于这两页；但项目里另有 124 处硬编码（含 chat_page）。是否接受"**只改这两页，其余按兵不动**"，还是要求"凡是碰到的页面顺手收敛"？

---

## 附：本次审计的原始证据

- `flutter --version` → Flutter 3.32.2 / Dart 3.8.1
- `grep -rn "AppTextStyles\." lib/` → 1 命中（仅私有构造函数），实际引用 **0**
- `grep -rn "AppDimens\." lib/` → 1 命中（仅私有构造函数），实际引用 **0**
- `grep -rn "AppColors\." lib/` → **244 命中 / 28 文件**
- `grep -rn "fontSize:" lib/` → **124 命中**，15 种取值
- `grep -rhn "BorderRadius.circular" lib/` → 10 种取值
- `conversation_page.dart` / `settings_page.dart` 全文件逐行通读
- `test/ui_audit_test.dart` 全文件通读
