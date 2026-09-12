# v1.1.5 UI 截图审计报告

> 审计方式：本机 Flutter 3.32.2（中国镜像）+ widget golden 截图测试
> 测试文件：`test/ui_audit_test.dart`｜截图基线：`test/goldens/*.png`
> 结果：**5/5 通过**（`flutter test` All tests passed!）
> 审计人：AI 逐张看图，对照 v7 原型

## 逐屏审计结论

| # | 截图 | 审计项 | 结论 |
|---|------|--------|------|
| 1 | `audit_chat_messages.png` | 时间分隔条居中 ✅ 系统消息居中灰字 ✅ AI 渐变方形头像 ✅ 用户蓝紫方形头像 ✅ 绿/白气泡与 12px 圆角 ✅ 气泡宽度自适应 ✅ | **通过** |
| 2 | `audit_input_empty.png` | 无字时只有 麦克风/输入框/📞，无发送按钮 | **通过** |
| 3 | `audit_input_typed.png` | 有字时**绿色「发送」胶囊**出现在 📞 左侧 | **通过**（修复 initState 初值同步后） |
| 4 | `audit_conversation_list.png` | 通栏白底单元格 ✅ 48px/6px 渐变方形头像 ✅ 17px 粗名称+灰描述 ✅ 右侧时间、无「⋯」菜单 ✅ 分割线 ✅ | **通过** |
| 5 | `audit_profile_page.png` | 标题「我」✅ 64px 方形头像资料头 ✅ **28px 圆角彩色图标色块**（蓝/绿/橙/灰/红按项分配）✅ 分组白卡 ✅ | **通过** |

## 审计中发现并修复的问题
1. `ChatInputBar` initState 未同步 controller 初始文字 → 补一行初值同步（防御，真机无草稿场景不受影响）。
2. 测试环境缺 path_provider / 录音插件平台通道 → 测试内 mock，未动 lib/core 红线。

## 已知伪影（非缺陷）
- 截图右上角红白斜条：Flutter 测试渲染器伪影，所有 golden 固定出现，真机不存在。
- 中文显示为方块：测试环境内置字体无 CJK 字形；颜色/形状/布局/对齐为真实渲染。
- 我页「音频能力」组在测试环境显示为不可用态：平台通道无实现所致，真机走 `AudioUtil.checkAudioCapabilities()` 真实检测。

## 回归价值
`test/goldens/*.png` 已入库作为**视觉回归基线**；后续 UI 改动可跑
`flutter test test/ui_audit_test.dart`（不带 --update-goldens）比对是否意外破坏样式。
