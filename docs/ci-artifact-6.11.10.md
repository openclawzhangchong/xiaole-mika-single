# 6.11.10+62 构建基线（保活候选 ⑤/⑥ + 预连接）

## 1. 源码基线

| 项 | 值 |
|---|---|
| 仓库 | `openclawzhangchong/xiaole-client-flutter-2027` |
| 分支 / commit | `master` / **`8450dbf`** |
| tag | **无**（建议 `v6.11.10`） |
| `version` | `6.11.10+62` |
| 改动 | `WsProbeMode` 增至 `off/detect/stop/pair/mcp`（默认 off）；`_ensureConnectedThen` 2s 预连接 + 失败提示；`[RECONNECT]` 统计；`tools/ws_probe_judge.ps1` |

## 2. CI 产物

| 项 | 值 |
|---|---|
| run | **41818628352** ✅ success（headSha `8450dbf`） |
| artifact | `xiaole-apk-6.11.10+62-8450dbf` |
| APK | `xiaole-6.11.10+62-8450dbf-release.apk`，**40,822,866 B** |
| SHA-256 | `251c014c81e4ede7033557a415a3b948986730f7980c838efd3626b9f14b688a` |
| 本机路径 | `C:\Users\Administrator\AppData\Local\Temp\xiaole-apk\v61110\` |
| analyze | **0 error** |

## 3. 装机注意

- 当前设备仍为合并版 **6.11.5/57**；实验时装本版用 `install -r`（**禁止 `-d`**），跑完还原。
- 本版默认 `off`，装完不会发任何保活消息；要测 ⑤/⑥ 需在开发者中心「WS 保活探针」显式切换。
