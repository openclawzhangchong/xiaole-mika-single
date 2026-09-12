# 小乐 App v4.3.0 改造方案（草案 v1 · 已审批）

> 审批时间：2026-09-09 20:55 ｜ 审批人：用户（「同意！」）
> 需求来源：用户四项需求（2026-09-09）+ 《小智硬件 Android 迁移指南.md》（桌面）
> 状态：**已实施并发布 ✅（v4.3.0，2026-09-09）**

---

## 需求与决策记录

| # | 需求 | 关键决策（用户拍板） |
|---|------|---------------------|
| 1 | 添加智能体时随机生成的设备型号/id 弃用手机型号，统一 `m5stack-core-s3 + esp32-s3/flash 16MB/psram 8MB` | 新生成+存量都矫正；MAC/ClientID 一律不动 |
| 2 | 表情功能移入开发者中心做开关 | **默认关**；emoji 前缀保留（消息内容） |
| 3 | 「我」页新增导出本地聊天记录（学习网页版） | 系统分享面板（share_plus）；完全对齐网页版 v1.3.1 规格 |
| 4 | 「通用」下「语言」「清除缓存」先隐藏注释，以后再开发 | 整块注释，连 section 一起隐藏 |

## 模块一：设备型号统一 `m5stack-core-s3`（新生成 + 存量矫正）

> 背景：OTA 识别层（board/chip/flash/psram/application）v3.1.0/v4.0.1 起已统一合规，
> 服务器识别不受影响；本模块只清展示/存储层残留。依据：《小智硬件 Android 迁移指南》硬件画像。

1.1 `agent_config_page.dart`（添加/编辑智能体页）
- 「设备型号」初始值 `xiaole-voice-v1` → `m5stack-core-s3`；🎲 重新生成由随机改为**固定填入** `m5stack-core-s3`；hint 同步更新。
- 表单加载时读到旧值（手机型号 fallback / `xiaole-voice-v1`）→ 显示并保存矫正为 `m5stack-core-s3`。
- MAC（小写随机）、Client ID（UUID v4）生成规则**一律不动**（动了会换设备身份、需重新激活）。

1.2 存量矫正（两条通道）
- 全局通道：App 启动时一次性检查全局型号覆盖值，非 `m5stack-core-s3` 则写入矫正。
- 独立身份通道：聊天页应用 per-agent 身份时，`AgentIdentityStore` 里非 `m5stack-core-s3` 的旧型号矫正并写回存储（旧智能体快照绑定分支同样取矫正值）。

1.3 「我」页设备型号的手动编辑能力保留。

## 模块二：表情动画开关移入开发者中心（默认关）

2.1 `app_feats.dart`：开关清单新增 `emotion`，默认 `false`；语义化 getter `AppFeats.emotion`。
2.2 `dev_center_page.dart`：「能力开关」区新增「😄 表情动画」行。
2.3 `chat_page.dart`：`_showEmotionAnimation` 入口判 `AppFeats.emotion`，关=跳过全屏动画。
2.4 行为变化明示：升级后全屏表情动画**默认消失**，需开发者中心开启；消息内 emoji 前缀**保留**（属服务端下发的消息内容，过滤会改变消息文本——AI 建议，用户未反对）。

## 模块三：「我」页导出本地聊天记录（完全对齐网页版 v1.3.1）

3.1 依赖：pubspec 新增 `share_plus`（系统分享面板）。
3.2 新增导出设置页：范围（全部智能体默认/单选）+ 格式（TXT/JSON，默认 JSON 对齐网页版）+ 起止日期过滤（可空）+ 打开时统计「N 个智能体 · M 条消息」；无完整时间戳的历史消息在启用日期过滤时排除（对齐网页版规则）。
3.3 导出内容复刻网页版：TXT 模板（头部信息 + 分智能体分段 + `[时间] 我/系统/智能体名：内容`，BOM 防中文乱码，图片消息占位 `[图片]`）；JSON 结构（app/version/exportedAt/range/totalMessages/agents）。
3.4 交付：生成文件 → Android 系统分享面板；文件名 `xiaole聊天_范围_日期.格式`（非法字符替换）。
3.5 入口：设置页「账号与云」区新增「导出聊天记录」ListTile（一键云端下方）。

## 模块四：「语言」「清除缓存」隐藏注释

4.1 `settings_page.dart`「通用」区两个 TODO 空壳 ListTile 连同 section 包裹整体注释，标注「暂隐藏，待开发后恢复」。

## 通用事项

5.1 版本 `4.2.0+16 → 4.3.0+17`（pubspec + AppConfig）。
5.2 改动范围：仅 `lib/presentation/` + `pubspec.yaml`；**lib/core、lib/data、OTA appName 红线零触碰**，发版前 `git diff v4.2.0 -- lib/core/ lib/data/` 校验为空。
5.3 质量门：`flutter analyze` 0 错误 → golden 套件回归（我页合法演进更新基线）→ CI tag `v4.3.0` → APK 下载桌面字节校验。

## 实施记录（2026-09-09 回填）

- **代码**：远端 commit `86e67ecbb5de17fb717e697f4c0fb8bbb6f18b0a`（本地 8a78873，API 创建带 gpgsig 故 sha 不同；19 文件 +643/-31），tag `v4.3.0`。
- **质量门**：flutter analyze 0 error（改动文件 0 告警）；红线校验 `git diff b207428 -- lib/core/ lib/data/` 为空 ✅；golden 套件三轮 5/5 稳定（我页基线随导出入口/隐藏通用区更新）。
- **CI**：run `34357670313`（build-apk.yml，tag v4.3.0 触发）**success**。
- **APK**：`C:\Users\Administrator\Desktop\xiaole-client-v4.3.0.apk`，59,372,282 字节（与 Release 资产一致），sha1 `7d94a65c1c666426…`。
- **实施偏差（与草案的差异，均已在代码注释说明）**：
  - 3.2「无完整时间戳的历史消息在启用日期过滤时排除」在 App 侧不适用：`MessageModel.timestamp` 为非空 required `DateTime`，App 消息天然全有时间戳，故日期过滤直接按 ts 比较、无排除分支。
  - 1.2 全局矫正入口落在 `chat_page.initState`（`AgentIdentityStore.normalizeGlobalModel()` 幂等），独立身份矫正落在 `_initializeWebSocket` 身份应用段；「我」页设备型号展示保持**单跳只读**（golden 固定 pump 下多跳异步链会时序漂移），矫正收敛在前述两处（激活流程必经添加页，覆盖完整）。
- **待用户真机验收**：①新添加智能体型号显示 `m5stack-core-s3`；②存量旧智能体连上后型号自动矫正；③表情动画默认消失、开发者中心可开启；④「导出聊天记录」TXT/JSON+日期过滤走系统分享面板；⑤设置页无「语言/清除缓存」。
