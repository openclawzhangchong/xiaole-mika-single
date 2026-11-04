# 设备基线快照：36c77fb6（RMX3161）

> 用途：这是 **2026-11-04 起「设备写权限唯一归属」的起点记录**，用于追责与 69 验收对比。
> 采集方式：全部为只读命令（`dumpsys` / `pm path` / `ls` / `reverse --list` / `date`），未做任何写操作。

## 1. 采集时刻

| 项 | 值 |
|---|---|
| 宿主采集时间 | 2026-11-04 23:03（CST） |
| 设备时间 | `Wed Nov 4 23:03:43 CST 2026` |
| 机型 / 系统 | `RMX3161` / Android `12` / API `31` |
| 序列号 | `36c77fb6`（另一台 `0123456789ABCDEF` 不在本线范围） |

## 2. 已安装包状态

| 项 | 值 |
|---|---|
| package | `com.zcstudy.xiaole` |
| versionCode | **67** |
| versionName | **6.11.12-mika1** |
| minSdk / targetSdk | `30` / `35` |
| firstInstallTime | **2026-11-04 22:55:58** |
| lastUpdateTime | 2026-11-04 22:55:58 |
| installerPackageName | `com.android.packageinstaller`（走 ColorOS 安装向导装成，非 adb 直装） |
| pm path | `package:/data/app/~~wbk15JJSmf-cIvq3_xN81w==/com.zcstudy.xiaole-CK4qY1D_IyONFtbWdCDRVQ==/base.apk` |
| 前台 Activity | `com.zcstudy.xiaole/.MainActivity` |

说明：`firstInstallTime == lastUpdateTime` 且时间为 22:55:58，证明这是**全新建装**（此前的数据在 22:51:00 的显式卸载中已清零，见 `docs/signing-baseline.md` §3）。

## 3. adb reverse

```
（空 —— 无任何 forward/reverse 映射）
```

## 4. `<设备临时目录>` 内容清单

| 大小(B) | 时间 | 文件 | 备注 |
|---|---|---|---|
| 6,605,626 | 2026-11-02 20:35 | `app-release.` | 旧残留（文件名截断，非本次产物） |
| 0 | 2026-10-15 00:39 | `b.png` | 空文件残留 |
| 76,416 | 2026-11-02 08:52 | `mobilecli.dex` | 调试用 dex |
| 74,142,884 | **2026-11-04 22:34** | `mika-single-v1.apk` | **单包线推入**，与当前安装的 67 同尺寸，高度疑似同源 |
| 146 | 2026-11-03 19:15 | `mika_audio_mute_10351` | Mika 音频静音账本（`AudioMuteLedger`），uid 为旧安装值 |
| 40,904,782 | **2026-11-04 22:14** | `x68.apk` | **本线推入的 68**（`sha256=aa6b569f…`） |
| 74,142,884 | **2026-11-04 22:13** | `xiaole-merged.apk` | **另一条线推入**的合并包 |
| 6,605,626 | 2026-11-02 20:35 | `zcm.apk` | 旧残留 |
| — | 2026-10-23 08:11 | `dalvik-cache/` | 系统缓存目录 |

### 4.1 清理后（2026-11-04 23:1x，`ls -l <设备临时目录>` 原始输出）

```
total 83
drwxrwxrwx 3 shell shell  3488 2026-10-23 08:11 dalvik-cache
-rw-rw-rw- 1 shell shell   146 2026-11-03 19:15 mika_audio_mute_10351
-rw-rw-rw- 1 shell shell 76416 2026-11-02 08:52 mobilecli.dex
```

已删（均为本线/单包线推上去的副本，装机不依赖，运行中的包在 `/data/app`）：
`x68.apk`、`xiaole-merged.apk`、`mika-single-v1.apk`、`b.png`、`app-release.`、`zcm.apk`。

保留并说明原因：

| 文件 | 判定 |
|---|---|
| `mika_audio_mute_10351` | **App 实际使用**：`mika/.../cap/phone/shell/ShellService.kt` 里有 `AudioMuteLedger(File(stateDir, "mika_audio_mute_$allowedUid"))`，是 Mika 的音频静音账本。`10351` 是**旧安装的 uid**，当前包重装后 uid 已变，此文件属孤儿；但按要求"查不清先留"，未删 |
| `mobilecli.dex` | 在本仓库与单包源码里**均无引用**，疑似外部 adb 工具/旧实验残留；未删，待你确认后处理 |
| `dalvik-cache/` | 系统缓存，按指令不动 |

## 5. 与 22:51–22:55 事件的对应关系

| 时间 | 事件 | 证据位置 |
|---|---|---|
| 22:51:00 | 包被显式卸载（`deletePackageX`，`isReInstall=false`）→ App 数据清零 | `docs/signing-baseline.md` §3 |
| 22:51:16 | ColorOS 拦截下一条 adb 安装（`allowInterceptAdbInstallInInstallStage`） | 同上 |
| 22:55:58 | 安装向导被人工确认，67（`6.11.12-mika1`）装成，`firstInstallTime` 重置 | 同上 |

## 6. 纪律（自本快照起生效）

1. **`36c77fb6` 的写操作只归本线**（另一条线 67 安装已完成，此后不得再写）。
2. 任何装机一律**禁止 `adb uninstall`**，`-99` 只能靠人工过三连弹（复选框 → 授权本次安装 → 仍然继续）。
3. 本线下一次写操作 = 装 69；装前先复核本快照的 `versionCode=67`，装后记录新的 `firstInstallTime` 作为验收起点。
4. 验收基线与判定脚本见 `docs/acceptance-69.md`。
