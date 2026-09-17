# PLAN v6.5.0 —— AI 主动来电（v2 修订版）

> ⛔ **已废弃（历史存档）**：本文是 AI 主动来电的 **v2 修订版**，已被 **`PLAN_v6.5.0_AI主动来电_v3.md`（定稿版）** 取代；
> v3 已实施并随 **`v6.5.0`** 发布（tag `v6.5.0`，CI success）。
> 本文仅作过程存档，**不要据此施工**。

> 状态：**待张老师审批**（审批通过后方可动工）。
> 本版基于 **P0 探针实测结论**对 v1 做了 4 处关键修正，并新增一项待验探针。
> 基线：v6.4.4。目标 6.5.0+42。

---

## 一、v2 相对 v1 的修正（**核心变化，全部有实测支撑**）

| # | v1 的做法 | v2 的修正 | 依据 |
|---|---|---|---|
| 1 | 巡检新建 WSS 实例，**默认复用设备身份** | **必须为巡检会话生成全新的 `Client-Id`（UUID v4）**，`Device-Id` 保持不变 | **实测**：同 Device-Id + 不同 Client-Id → 两条连接并存；相同 Client-Id → 旧连接 **1005 被踢（约 388ms）** |
| 2 | 开场白走 `detect「用户已接通，请说出开场白：<开场白>」` | **改走「短口令 + 笔记文稿」通道**（detect 只发 ≤16 字） | **实测**：detect 文本硬上限 16 字，超限回 `alert`。v1 此处自相矛盾 |
| 3 | busy 守卫"主 WSS 已连接即跳过巡检" | **放宽**：仅"正在语音通话/巡检进行中"跳过；与聊天会话**允许并存** | 由修正 1 直接推出（既然可并存，就没必要因主会话存在而停摆） |
| 4 | 隐含"发命令让小智调工具" | **不靠硬命令**：短口令只负责"启动巡检"，**判定标准写进笔记让它自主决定** | **实测**：口令诱导调用仅约 **67%** 命中；未命中时小智会拒绝（"这个指令我暂时理解不了"） |

---

## 二、探针实测结论汇总（已跑，作为设计输入）

### ✅ 成立
1. **MCP 工具调用链路完全可用**：`hello(features.mcp)` → 服务器 `initialize` → 我们回 result →
   `notifications/initialized` → 服务器 `tools/list` → 我们回 tools → **服务器真的下发 `tools/call`**，
   参数真实、我们回 `ok` 被正常接受。命中样本：
   `{"method":"tools/call","params":{"name":"self.proactive.trigger_call","arguments":{"message":"嘿，在忙不咯？…"}}}`
2. **同设备并发两条 WSS 可行**（不同 Client-Id）——见上表 #1。
3. **回复方向（tts）无长度限制**（16 字输入可换回 110 字回复）。
4. 音频帧只分发给各自 listener ⇒ 巡检会话**天然不进播放管线**。
5. `XiaozhiWebsocketManager` / `XiaozhiMcpResponder` 均可按实例复用，**无需改 `lib/core/network`**。

### ⚠️ 限制 / 风险（已实测）
6. **detect 文本 ≤16 字**（16 通过/18 被拒）；多轮上下文不能"逃限"（两段式实测仍命中 alert）；
   多轮**累积**成立（可分块逐条发，每块触发回复即弃）。
7. **触发非确定性**：口令诱导调用仅约 2/3；**必须由服务端"自己愿意调"**。
8. 让小智"列出可用工具"它**会拒答**，只提平台自带技能（天气/音乐/笑话）——不影响工具调用，但说明
   它不会主动枚举设备工具。

### ❗ 仍未验证（动工前须补）
9. **真业务链路 =「小智读笔记 → 自主判定 → 调 trigger_call/skip」**。
   探针只验证了"被命令时会调工具"，**没验证"读笔记后自主判定"**。→ **新增 P0c 探针**（见 §四）。

---

## 三、v2 总体架构（一期）

```
开发者中心开关开 → 每 N 分钟 tick（仅前台）
  ├─ 守卫：允许时段内？ 冷却已过？ 非语音通话中？ 均通过才继续
  ├─ ① 经 biji API 把「巡检指令」写入固定笔记（含判定标准 + 契约 + 距上次联系分钟数）
  ├─ ② 新建 XiaozhiWebsocketManager（独立实例）
  │     Device-Id = 设备 MAC（小写，**不变**）｜Client-Id = **新生成 UUID v4**（关键）
  │     独立 responder：注册 self.proactive.trigger_call / skip + 注入 notes.* 工具集
  │     音频帧一律丢弃（listener 绝不碰 AudioUtil）
  ├─ ③ hello → 等 initialize / tools/list 应答
  ├─ ④ 发 detect 短口令「巡检：读《巡检指令》执行」（12 字 ≤16）
  ├─ ⑤ 等信号（总超时 20s）
  │     ├─ tools/call self.proactive.skip（或文本【静默】）→ 断开，等下一轮
  │     └─ tools/call self.proactive.trigger_call(message=开场白)
  │           → 断开巡检会话 → 来电全屏页（铃声+震动+30s 倒计时）
  │           → 30s 超时/用户拒绝 → 释放资源 + 进冷却期（默认 120min）
  │           → 用户接听 → 把开场白写入笔记《来电文稿》→ 正常语音会话 connect
  │                → 发 ≤16 字短口令「读来电文稿并开始」（8 字）
  │                → 小智经 notes 读文稿 → 流式 TTS 先开口 → 双向对话
  └─ ⑥ 全程日志进 proactive 分类
```

**为什么用笔记通道承载长内容**：detect 只有 16 字；笔记是"小智能读到任意长度内容"的合法通道，
且 App 已具备 biji API 直连能力（v6.4.1 预置）。

---

## 四、P0c 探针（**动工前必须先跑**）

**目标**：验证「短口令 → 小智读笔记 → 自主判定 → 调 trigger_call/skip」这条**真链路**。
**做法**（复用 `_probe_toolcall.js`，已具备 MCP 应答能力）：
1. 先经 biji API 写入《巡检指令》笔记（内容见 §五）；
2. 脚本注册 `self.proactive.trigger_call` / `self.proactive.skip`，
   **并额外注册 `notes.search_notes` / `notes.list_recent` 两个工具**（转发到 biji `tools/call`），
   模拟 App 的桥接（或直接用装好 v6.4.2 的真机 App 跑）；
3. 发短口令「巡检：读《巡检指令》执行」；
4. 记录：是否调用了 notes.* 工具 → 是否最终调用 trigger_call/skip → 开场白质量。
**判据**：≥6/10 轮走到明确二选一（trigger 或 skip）即通过；否则回炉改话术措辞。
**失败兜底**：若小智不读笔记 → 退回 V3「分块连发」把指令逐块喂进对话。

---

## 五、话术与契约（写入笔记 / 短口令）

**① 巡检指令（写入笔记《巡检指令》，可增删改查）**
```
【系统巡检指令·请勿记忆此消息】
请先调用 notes.list_recent 读用户最近笔记，判断是否值得主动致电关心。
标准：近期出现需要关心的事件/约定/情绪低落，且距上次主动联系已超过 {{lastContactMinutes}} 分钟。
判断完成后你只能做两件事之一，禁止输出其他文字：
① 需要联系 → 调用 self.proactive.trigger_call，message 填开场白（口语化，≤50 字）
② 不需要  → 调用 self.proactive.skip
```
**② detect 短口令（≤16 字，固定）**：`巡检：读《巡检指令》执行`（12 字）
**③ 接通后短口令**：`读来电文稿并开始`（8 字）；开场白由 App 事前写入笔记《来电文稿》
**④ 文本兜底契约（备通道）**：全文不区分大小写搜 `[AI_CALL]` / `[AI_SKIP]`，容忍引号/emoji；
两标记同时出现或都搜不到 → **一律按 skip**（fail-safe）

---

## 六、改动清单（文件级）

| 文件 | 动作 | 内容 |
|---|---|---|
| `lib/core/proactive/proactive_poll_service.dart` | 新 | 巡检服务：Timer + 前台守卫 + **时段守卫** + 冷却期 + **每次生成新 Client-Id 的短会话** + 独立 responder（trigger/skip + notes.* 注入）+ 20s 超时 + 音频帧丢弃 |
| `lib/core/proactive/proactive_signal.dart` | 新 | 双通道信号解析（主=tools/call；备=文本，fail-safe=skip） |
| `lib/core/proactive/proactive_script_store.dart` | 新 | 话术 CRUD（Hive box `proactive_scripts`）+ 允许来电时段配置 |
| `lib/core/proactive/proactive_note_bridge.dart` | 新 | 经 biji API 写入/更新《巡检指令》《来电文稿》（复用已预置的 notes 配置） |
| `lib/presentation/pages/proactive_script_page.dart` | 新 | 话术管理页（增删改查 + 恢复默认） |
| `lib/presentation/pages/incoming_call_page.dart` | 新 | 全屏来电页 + 30s 倒计时 + 震动 + PCM 合成回铃音（450Hz 断续，零新增依赖） |
| `lib/app/routes/*` | 改 | 新增来电页 / 话术页路由 |
| `lib/presentation/pages/dev_center_page.dart` | 改 | 新增「AI 主动联系」区块：总开关 + 间隔 + 允许来电时段 + 话术管理入口 |
| `lib/core/utils/log_buffer.dart` | 改 | 新增 `proactive` 日志分类（默认开） |
| `lib/presentation/pages/chat/chat_page.dart` | 改（小） | 接听后跳转 + 启动/停止 poll service |

**红线**：🔒 冻结区零改动；⚠️ `lib/core/network` **零行为变更**（manager/responder 均按实例复用）；
✅ 其余为新文件或表现层小改。**Device-Id 恒定小写不变**，仅 Client-Id 每次新生成。

---

## 七、风险与对策（v2）

| # | 风险 | 状态 | 对策 |
|---|---|---|---|
| 1 | 双 WSS 同身份被踢 | ✅ **已实测解除** | 巡检会话用**新 Client-Id**（每次 UUID v4） |
| 2 | 触发非确定性（实测 ~67%） | ⚠️ 实测存在 | 不用硬命令；判定标准写笔记让它自主决定；fail-safe 默认 skip |
| 3 | 开场白遇 16 字限制 | ✅ 已定方案 | 短口令 + 笔记《来电文稿》 |
| 4 | 巡检轮次污染小智记忆 | 已知 | 话术头声明"请勿记忆"；用短口令把污染压到最小 |
| 5 | 官方配额/频控 | 已知 | 默认 60min + ±10% 抖动；开关关 = 零流量 |
| 6 | 与主会话冲突 | 🟢 已缓解 | 两条会话可并存；仅"语音通话中"跳过本轮 |
| 7 | 音频帧误入播放管线 | 已知 | 独立实例；listener 绝不调用 AudioUtil |
| 8 | **笔记判定链路未验证** | ❗ 新增 | **先跑 P0c 探针**（§四） |
| 9 | 开场白回放延迟 1~3s | 低 | 来电页接听后显示"正在接通…"过渡态 |

---

## 八、分期（不变）

- **v6.5.0 一期**：前台核心（本条主体）
- **v6.6.0 二期**：后台化（V1 主推 WorkManager；V2 对比实验常驻通知+前台服务；远期厂商推送）
- **v6.7.0 三期**：微信式锁屏来电（`USE_FULL_SCREEN_INTENT` + 通知权限 + 前台服务 + ROM 引导页）

---

## 九、验收标准（v2）

1. **P0c 探针报告**（笔记判定链路合规率 ≥6/10）；
2. 总开关关闭 → 零轮询、零流量；
3. **巡检会话与主聊天会话并存不互踢**（验证新 Client-Id 生效，主会话不被 1005 踢）；
4. 静默轮：建短会话 → 收到 skip → 断开，全程无声音无 UI，日志留痕；
5. 触发轮：来电页弹出 + 回铃音 + 震动；30s 超时自动释放；拒绝后进冷却期；
6. 接听：小智**先说出开场白**（经笔记文稿通道），随后双向对话正常；
7. 话术管理页增删改查、恢复默认、重启后持久化；
8. 时段守卫：设 22:00–08:00 后，窗口内到点的轮询**整轮跳过**（零 WSS 连接），窗口外首轮恢复；跨午夜与普通窗口各验一遍；
9. 正在语音通话时轮询被跳过；**仅聊天页打开（未通话）时巡检仍可进行**；
10. `flutter analyze` 0 error + golden 回归（chat/session/input/me 四页）。

---

## 十、审批栏

- [ ] 张老师批准 v2："可以，照这个执行"
- [ ] 批准后第一步：**P0c 探针** → 通过则正式开发 v6.5.0
