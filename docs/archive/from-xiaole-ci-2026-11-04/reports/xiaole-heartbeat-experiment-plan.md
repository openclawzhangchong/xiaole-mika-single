# v6.11.8 心跳实验方案：**已就绪** ｜ 4 候选：`hello` / `detect` / `abort` / `ping(对照)` ｜ 判定阈值：安静 3 分钟不出 `1005` = 该消息算"业务活跃"，~70s 仍断 = 排除 ｜ 需要设备窗口 **20 分钟（实验）+ 约 5 分钟（切换/核对/回退）≈ 25 分钟**，不含装机

- 代码已合入 master：commit `0450cb8`（`feat(v6.11.8)`），文档 commit `8483e99`。
- 云端 CI：run **41809567015** ✅ success（8m37s），artifact `xiaole-apk-6.11.8+60-0450cb8`，APK **40,806,486 B**，sha256 `f1b23bd35188f5729aab6cfb3f55c60f8e573c98d8db70525a2a1eed37a285e1`；`flutter analyze` 0 error。
- **未装机**（按指令），未动手机、未卸载/重装、未使用 `-d`。

---

## 一、4 个候选与判定

| 候选 | 每 30s 发送的业务消息 | 想验证什么 |
|---|---|---|
| ① `hello` | 完整握手：`{"type":"hello","version":1,"device_id":<本机>,"features":{"mcp":true},"transport":"websocket","audio_params":{opus/16k/1ch/60ms}}` | 重发 hello 会不会被服务端当作"业务活跃" |
| ② `detect` | `{"type":"listen","state":"detect"}` | 文档里唯一与"唤醒态"相关的消息是否算活跃 |
| ③ `abort` | `{"type":"abort","reason":"heartbeat"}` | 控制类消息（打断）是否算活跃 |
| ④ `ping` | **不发业务消息**，仅保留 WS 层 `pingInterval=25s` | 对照组：已知结果是 ~70s 被 `1005`（用来证明实验环境没被污染） |

判定（同一台 realme `36c77fb6`、同一智能体、**安静不说话**，每候选跑 4–5 分钟）：

- **PASS**：整个 4–5 分钟内 **没有任何 `code=1005`**，且能撑过 **3 分钟** ⇒ 该消息算"业务活跃"，可作为业务层保活接入（做成可配置间隔，保留 WS `pingInterval`）。
- **FAIL**：仍在 ~60–70s 出现一次 `code=1005` ⇒ 排除该候选。
- `ping` 作为对照应 **FAIL**；若对照也 PASS，说明环境/时段异常（比如服务端策略变了），当天数据作废重跑。
- 副作用观察（需同时记录）：`hello` 是否引起服务端重新下发 `stt/tts` 或重置会话；`detect` 是否让服务端开始等音频（出现 `stt` 或超时报错）；`abort` 是否打断正在播的 TTS（实验全程不说话，理论上无影响，但要记录服务器回帧）。

---

## 二、代码实现（可开关，默认关）

- `lib/core/network/xiaozhi_websocket_manager.dart`
  - 新增 `enum WsProbeMode { off, hello, detect, abort, ping }` 与构造参数 `probeMode` / `probeInterval`（默认 `off` / 30s）。
  - 连接建立后启动探针；断开时结算并输出一条汇总。
  - **统一日志前缀 `[PROBE]`**，记录点齐全：
    - 启动：`[PROBE] 启动 mode=… interval=…s`
    - 每次发送：`[PROBE] tick mode=… seq=N interval=…s t=…s recv=N`
    - 首个服务器帧：`[PROBE] 本连接首个服务器帧 t=…s`
    - 断开：`[PROBE] 停止（服务器断开 code=…）mode=… 存活=…s 发送=N 收到帧=N`
  - 对照组/关闭：`[PROBE] 本连接不发业务保活消息 mode=ping/off（…WS ping=25s）`
- `lib/presentation/services/app_feats.dart`：`xw_ws_probe_mode`（默认 `off`）、`xw_ws_probe_interval_sec`（默认 30，钳制 10–120）；`allOff()` 归零；`wsProbeRevision` 变更通知。
- `lib/presentation/pages/chat/chat_page.dart`：创建管理器时读取配置；监听 `wsProbeRevision`，**切换候选后立即重建连接**（否则"当前候选有效 → 永远等不到 70s 自动重连"就切不到下一个）。
- `lib/presentation/pages/dev_center_page.dart`：开发者中心「调试 → **WS 心跳实验**」，5 个选项（关闭 / ①hello / ②detect / ③abort / ④ping）。
- 版本 `6.11.8+60`；`AppConfig.appVersion=6.11.8`。

> 生产默认 `off`：不改变现有行为（6.11.7 的无感重连照常工作）。

---

## 三、设备窗口内的执行清单（等你说"窗口开始"再动）

**Preflight（不通过就停）**
```powershell
adb devices -l                                  # 必须看见 36c77fb6 的 realme；另一台 XXB/b906 忽略
adb -s 36c77fb6 shell dumpsys package com.zcstudy.xiaole | Select-String -Pattern "versionCode|versionName|lastUpdateTime|installerPackageName"
adb -s 36c77fb6 reverse --list                  # 应为空
```
装机（**禁止 `-d`**，`versionCode=60` 正常覆盖 57）：
```powershell
adb -s 36c77fb6 install -r "<TEMP>\xiaole-apk\v6118\xiaole-apk-6.11.8+60-0450cb8\xiaole-6.11.8+60-0450cb8-release.apk"
```
> 若 realme 安全安装器弹窗拦截，按既有流程勾选风险确认/授权安装（后台 install 返回 `Success` 即成功）。

**每个候选（5 分钟一轮）**
```powershell
# 1) 清日志 + 开始抓（日志落在本机文件里）
adb -s 36c77fb6 logcat -c
adb -s 36c77fb6 logcat -v time | Select-String -Pattern "PROBE|1005|已连接|连接已断开|收到消息" | Tee-Object -FilePath <TEMP>\xiaole-apk\probe_<mode>.log
# 2) 进聊天页 → 开发者中心「调试 → WS 心跳实验」选候选（密码 zc19901111）
#    （切换即重建连接；聊天页保持在前台，别锁屏）
# 3) 静置 5 分钟，不说话、不切后台
# 4) 结算：看 probe_<mode>.log 里有无 code=1005；有则记下存活秒数
```
候选顺序建议：`ping`（对照，先建立基线）→ `detect` → `hello` → `abort`。若某个候选 PASS，**仍需跑完对照**；`abort` 放最后，避免打断其它候选的 TTS 观察。
切下一个候选时无需等待自然断线：开发者中心选新候选会自动重建连接（`wsProbeRevision`）。

**收尾**
```powershell
# 回退到关闭（生产默认），避免实验配置留在手机上
adb -s 36c77fb6 shell am force-stop com.zcstudy.xiaole   # 或手动在开发者中心选「关闭」
```
若 4 个候选全部 FAIL：结论 = 云端按业务消息空闲回收且无轻量续命消息可用，生产继续保持 6.11.7「无感重连」（不消除回收，只让用户无感）；本次实验代码保持默认关，不进入默认路径。

---

## 四、交付物

| 类型 | 位置 |
|---|---|
| 本报告 | `<HOME>\Documents\Trae-CN\temp_20261104_03\xiaole-heartbeat-experiment-plan.md` |
| 入库证据（时间序列 + 原始日志 + 实验设计/阈值） | 仓库 `docs/ws-idle-reclaim-evidence.md`（README 新增「🔬 关键技术点」一节指向它） |
| 6.11.7 合并版基线（另一任务读） | 仓库 `docs/ci-artifact-6.11.7.md`（commit `0a713ef`、APK 路径、sha256、签名指纹；未改其它任务目录） |
| CI 产物 | 本机 `...\xiaole-apk\v6118\xiaole-apk-6.11.8+60-0450cb8\`（APK / SHA256SUMS / analyze.log） |

---

## 五、结论一句话

**方案就绪、代码已出包但未装机**：`ping` 对照 + `detect` / `hello` / `abort` 三候选，安静 3 分钟无 `1005` 即判"该消息算业务活跃"，否则排除；给我 **20 分钟实验窗口 + 5 分钟机动**（`-s 36c77fb6`，禁止 `-d`），跑完就能决定是"接入业务层保活"还是"保持无感重连"。
