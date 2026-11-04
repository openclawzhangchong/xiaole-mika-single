# 6.11.10+62 构建基线（保活候选 ⑤/⑥ + 预连接）

## 1. 源码基线

| 项 | 值 |
|---|---|
| 仓库 | `openclawzhangchong/xiaole-client-flutter-2027` |
| 分支 / commit | `master` / **`3d5819f`**（含预连接音频回灌与松手清空） |
| tag | **无**（建议 `v6.11.10`） |
| `version` | `6.11.10+62` |
| 改动 | `WsProbeMode` 增至 `off/detect/stop/pair/mcp`（默认 off）；`_ensureConnectedThen` 2s 预连接 + 断线音频缓存/回灌 + 失败提示；`[RECONNECT]` 统计；`tools/ws_probe_judge.ps1` |

## 2. CI 产物

| 项 | 值 |
|---|---|
| run | **41819784156** ✅ success（headSha `3d5819f`） |
| artifact | `xiaole-apk-6.11.10+62-3d5819f` |
| APK | `xiaole-6.11.10+62-3d5819f-release.apk`，**40,822,866 B** |
| SHA-256 | `1a161d2d080df9b50cdecc19015fc3abd530a2a06bb976c4b8d6f2775a360d49` |
| 本机路径 | `<TEMP>\xiaole-apk\v61110-final\` |
| analyze | **0 error** |

## 3. 装机注意

- 当前设备仍为合并版 **6.11.5/57**；实验时装本版用 `install -r`（**禁止 `-d`**），跑完还原。
- 本版默认 `off`，装完不会发任何保活消息；要测 ⑤/⑥ 需在开发者中心「WS 保活探针」显式切换。
