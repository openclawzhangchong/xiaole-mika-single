# 验收与证据归档（2026-11-04）

**来源**：验收线工作区 `Temp\xiaole-ci`（迁移过一版到 `<WORKSPACE>\xiaole-client-flutter-2027`，随后按"只留一个仓库"决定删除）。
**放置方式**：由验收线 `Copy-Item` 复制进来，**未做任何 git add/commit**；本仓库唯一写者仍为单包线。
**不要覆盖 `docs/` 下的同名在线文档**：本目录是历史快照，在线文档以单包线维护的版本为准。

## 文件

| 文件 | 用途 |
|---|---|
| `acceptance-69.md` | 6.11.15+69 全功能逐项点验（15 项、次数矩阵、正则与阈值、装机顺序） |
| `ws-idle-reclaim-evidence-2026-11-04.md` | 保活/空闲回收证据链（含 §12 中文边界实测、§12.4 emoji 被服务端规范化） |
| `device-baseline-36c77fb6-2026-11-04.md` | 设备基线（RMX3161 / Android 12 / versionCode 67 / tmp 清理记录） |
| `signing-baseline.md` | 签名基线（证书 SHA-256 `9d2da880…a169`、keystore、`-99` 取证、"同包名必须同签名"） |
| `进度与续接.md` | 验收线进度与红线区（含"同包名必须同签名"、emoji 语义禁令） |
| `boundary-61114/` | 中文边界四批测量脚本 + 汇总 + `raw-logs.zip`（45 组注入原始日志） |
| `reports/` | 12 份历史诊断/验证报告 |
| `logs/keepalive-logs-2026-11.zip` | A/B/C/T/V + cand5 共 7 份保活原始日志，16.89 MB → 1.88 MB |

## 关于 `logs/` 是否入库

**已入库**。证据文档只引用了 3 处 `[KEEPALIVE]`、3 处 `[RECONNECT]`、0 处 `[TEXTSPLIT]`，但原始 tick/重连/分段日志是唯一一份，压缩后仅 1.88 MB，为保证据完整不剔除。

## 两份保活证据文档的差异（为什么都留）

在线版 `docs/ws-idle-reclaim-evidence.md` 与归档版 `ws-idle-reclaim-evidence-2026-11-04.md` 的**唯一实质差异**是归档版多一节 **`§12.4 已知服务端行为：emoji 会被规范化`**（18 行）：

- `emo10`（10 个 emoji / 40 字节）：云端**收**并回了 TTS，但 `stt` 回声与原文不一致（emoji 被剥离/改写）；
- `emo8` / `emo9`：云端收，无 alert，回声缺失或与原文不同；
- 结论：这是**服务端文本规范化**，不是客户端切段丢字 → 不计入"丢字"判据；且 emoji 不能承载交互语义（确认/选择必须用文字或按钮）。

保留两份的理由：在线版是"约定与复现步骤"的活文档（会被继续改），归档版是当日**带实验原始判定**的时间切片（不可再改写）。比对命令：

```bash
git diff --no-index docs/ws-idle-reclaim-evidence.md \
  docs/archive/from-xiaole-ci-2026-11-04/ws-idle-reclaim-evidence-2026-11-04.md
```

## 如何复现测量

| 想复现什么 | 用什么 | 前置条件 |
|---|---|---|
| 中文/英文/emoji 分段边界 | `boundary-61114/zh-boundary*.ps1` + `summary*.csv` | 设备已装对应版本、开发者模式已授权（`devAuthed`），用 `[DEBUGINJECT]` 的 `am start` 注入文本 |
| 注入方式 | `adb -s <serial> shell am start -n com.zcstudy.xiaole/.MainActivity --es debug_send_text_seg "<文本>"` | 文本里的引号需转义；日志看 `[DEBUGINJECT]` 的码点/字节数 |
| 保活/空闲回收 | `logs/keepalive-logs-2026-11.zip` 里的原始 logcat | 45s `listen{state:"stop"}` 节奏，关键字 `[KEEPALIVE]` / `[RECONNECT]` |
| 装机与验收 | `acceptance-69.md`、`reports/xiaole-device-verify-runbook.md` | ColorOS 三连弹人工过窗；**禁止 `adb uninstall` 绕过** |

归档目录整体说明：这里是**历史证据与验收资产**，从纯小乐上游线工作区迁入（该工作区已于 2026-11-04 删除）。

## 补充红线（归档时未能写回原文）

- **先入库再清目录**：只在本地有价值的脚本/证据/报告，先归档进仓库并提交，再删本地目录。与"同包名必须同签名"并列。
- 归档当日（2026-11-04）`xiaole-client-flutter-2027` 工作区已交出控制权：代码改动一律提给单包线；验收线只保留设备写权限与验收执行。
