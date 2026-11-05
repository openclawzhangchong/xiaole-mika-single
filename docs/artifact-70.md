# 70 产物记录（v6.11.15-mika1 / versionCode 70）

> 本文件只记录"哪个提交 → 哪个构建 → 哪个二进制 → 哪张证书"，不含本机路径。
> 本机下载位置只写在装机清单里，由验收线在窗口内使用。

## 构建

| 项 | 值 |
|---|---|
| 仓库 | `openclawzhangchong/xiaole-mika-single`（唯一 public 正版） |
| workflow | `build-merged-apk.yml`（`workflow_dispatch`，ref `master`） |
| run id | `41867359843` |
| conclusion | `success` |
| 构建提交（headSha） | `4c5fb96daf70aef73deda394e41426265d6915f6` |
| 起止（UTC） | `2026-11-04T16:27:15Z` → `2026-11-04T16:44:50Z` |
| artifact 名 | `xiaole-single-apk` |
| artifact 压缩包大小 | 118,669,774 B |
| 下载方式 | `gh run download 41867359843 --repo openclawzhangchong/xiaole-mika-single --name xiaole-single-apk` |

> 说明：归档提交 `b30a0cb` 在构建提交之后，只动 `docs/`，不改 Dart/Gradle 代码，所以产物与 `4c5fb96` 等价；记录的"对应提交"按触发时的 HEAD `4c5fb96`。

## 产物

| 架构 | 文件名 | 字节数 | SHA-256 |
|---|---|---|---|
| arm64（主分发） | `xiaole-6.11.15-mika1-arm64.apk` | 59,897,491 | `d3ccdaa7e524beff30dc3a55913d9e4ec37bda7e69b2c9ab0c730d5e04cbc780` |
| universal（arm64+armv7） | `xiaole-6.11.15-mika1-universal.apk` | 71,641,216 | `05439d22f7a3a59ce83fac41bef749b9f79c176105964d7704c166d129729c95` |

- 包名：`com.zcstudy.xiaole`；`versionName = 6.11.15-mika1`；`versionCode = 70`；`minSdk 30` / `targetSdk 35`。
- 两个包 versionCode 相同，仅文件名与 ABI 不同；`SHA256SUMS.txt` 由 CI 生成，与本地 `Get-FileHash` 结果一致。
- 另有 `.idsig`（v4 签名辅助文件）与 `permissions-*.txt`、`micgate-test.log`、`analyze.log` 同包附带。

## 签名（与纯小乐基线逐位相同）

```
V3.0 Signer: certificate DN: C=CN, O=ZCStudy, CN=XiaoLe Release
V3.0 Signer: certificate SHA-256 digest: 9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169
V3.0 Signer: public key SHA-256 digest: a1213c3352b0a46d3e1a07ee9120e0e379505e34feca938fd9490a2d14ef24bc
```

- 验证方式：`apksigner verify --print-certs xiaole-6.11.15-mika1-arm64.apk`，CI 内断言 `XIAOLE_CERT_SHA256` 通过才会产出 artifact。
- 签名方案：v3 为 `true`，v1/v2 为 `false`（AGP 默认按 minSdk 30 只签 v3；Android 11+ 正常安装）。
- keystore 来源：`ANDROID_KEYSTORE_BASE64` secret 运行时解码，构建后 `rm`；仓库与历史中均无 p12。

## 与 69 的差异

- 尺寸：arm64 59,893,395 → 59,897,491（+4,096 B）；universal 71,633,024 → 71,641,216（+8,192 B），增量来自新增的原生日志通道。
- 代码差异（相对 69 / `414a5bd`）：`lib/core/utils/native_log.dart`、`MainActivity` 的 `xiaole/log` 通道与 `BOOT` 锚点、`VoiceRecordButton` 权限闸门与「去开启」引导、`MicGate` 成功日志修正。
