# 签名基线：同包名必须同签名

> 级别：**不可违反**，与「品牌名铁律（内部标识与外部品牌分离）」并列。
> 适用范围：`com.zcstudy.xiaole` 的**纯小乐包**、**单包/合并版**（mika 合包）等一切同 `applicationId` 的产物。
> 最后更新：2026-11-04（真机 RMX3161 实测取证）

---

## 0. 规矩本身

**同一 `applicationId` 的每一个 APK，必须用同一张证书签名。**

判定只有一条：`apksigner verify --print-certs` 输出的
`Signer #1 certificate SHA-256 digest` 必须完全一致。

本项目的唯一基准值：

```
com.zcstudy.xiaole
9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169
```

完整指纹见 §2。基线值变更 = 换包身份 = 所有存量用户必须卸载重装 = 数据全丢，因此**默认永不改变**。

### 0.1 为什么跨签名不能覆盖

Android 的包管理在覆盖安装时，第一步就比对「已安装包的签名」与「新包签名」：

- 一致 → 原地替换，`/data/data/com.zcstudy.xiaole` 保留；
- 不一致 → 直接 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，**系统不给任何"确认后继续"的选项**。

唯一绕过方式就是先 `uninstall` 再 `install`，而 `uninstall` 会连同
`/data/data/com.zcstudy.xiaole` 一起删除。

### 0.2 数据丢失的具体后果（本项目已发生过一次）

一次误卸载清掉的不是"缓存"，而是：

| 丢失项 | 后果 |
|---|---|
| 开发者模式授权（`AppFeats.devAuthed`） | 需重新输密码 `devPassword` 解锁，调试用 adb 注入通道同时失效 |
| 本地智能体选择 / 设备身份缓存 | 列表为空，需重新选择或恢复智能体，设备上线身份变了 |
| WebSocket 地址与 Token、OTA 地址 | 需重新填写（若未做过「一键云端」备份则只能重配） |
| 其它本地偏好（MCP 开关、权限引导进度等） | 全部回到默认值 |

用户视角就是"App 突然变成新装的，之前配的全没了"。

### 0.3 如何验证（两条命令，逐包比对）

```powershell
# 单包
apksigner verify --print-certs <a.apk> | Select-String "SHA-256 digest"
# 另一包
apksigner verify --print-certs <b.apk> | Select-String "SHA-256 digest"
```

两行必须逐字符相同。CI 里已经内置同样的校验（见 §4）。

---

## 1. 2026-11-04 的实测比对（本次事故取证）

| 产物 | 路径 | versionCode | 证书 SHA-256 |
|---|---|---|---|
| v6.11.5（设备基线 57） | `xiaole-apk\xiaole-apk-6.11.5+57-c315bc4\...apk` | 57 | `9d2da880…a169` |
| v6.11.14（68，`61f60ec`） | `xiaole-apk\v61114b\xiaole-apk-6.11.14+68-61f60ec\...apk` | 68 | `9d2da880…a169` |
| 合并版 | `temp_20261104_05\dist\xiaole-mika-merged-release.apk` | 57 | `9d2da880…a169` |

**结论：三者同一张证书，签名不构成任何安装障碍。**
用户此前怀疑"68 与合并版签名不一致导致 `-99`、导致数据被清"，**该假设已被证据否定**。
`-99` 与数据丢失的真实成因见 §3。

---

## 2. keystore 基线（唯一来源）

| 项 | 值 |
|---|---|
| keystore 文件 | `android/app/xiaole-release.p12`（随仓库提交，**全项目仅此一份**） |
| 类型 | PKCS12 |
| alias | `xiaole` |
| storePassword | `REDACTED-KEYSTORE-PASSWORD`（CI/构建可用 `XIAOLE_KEYSTORE_PASSWORD` 覆盖） |
| keyPassword | `REDACTED-KEYSTORE-PASSWORD`（CI/构建可用 `XIAOLE_KEY_PASSWORD` 覆盖） |
| 证书 DN | `C=CN, O=ZCStudy, CN=XiaoLe Release` |
| 算法 | RSA 2048 / SHA256withRSA |
| 证书 SHA-256 | `9d2da8805e784801e13c54a635e8bf528db303a235adb5633745cadceb12a169` |
| 证书 SHA-1 | `6a81d05a40349ca21cc1ae10ab640b66c5a5e372` |
| 证书 MD5 | `3dce90c2a8b4c1756216cde5da94321e` |

> 说明：本项目定位为不追求密钥保密的自用/公开仓库（keystore 与密码本就随仓库提交），
> 因此基线里直录密码；**若日后改为对外分发，必须先把这张 keystore 换成受管密钥并迁移包名**，
> 不能原地换签名。

### 2.1 keystore base64（供单包仓库导入同一份）

单包仓库把下面内容存为 `android/app/xiaole-release.p12.base64`，解码回 p12 后使用；
**不要另行生成 keystore**。

```text
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
```

解码校验（应得到 2672 字节，且指纹与 §2 一致）：

```powershell
[IO.File]::WriteAllBytes("android/app/xiaole-release.p12", [Convert]::FromBase64String((Get-Content "android/app/xiaole-release.p12.base64" -Raw)))
keytool -list -v -keystore android/app/xiaole-release.p12 -storepass REDACTED-KEYSTORE-PASSWORD -storetype PKCS12
```

---

## 3. 本次 `Failure [-99]` + 数据被清的真实成因（签名已排除）

取证时间：2026-11-04 22:46–22:56，真机 RMX3161（Android 12 / API 31）。

| # | 证据（logcat 原文节选） | 说明 |
|---|---|---|
| 1 | 22:46:49 `installStage com.zcstudy.xiaole ... installerPackageName=pc, installerUid=2000` / `Update package ... Retain data and using new` | adb 安装被正常受理，且**保留数据**更新成功 |
| 2 | 22:51:00.299 `Force stopping ... deletePackageX` / 22:51:01 `isReInstall=false` | 包被**显式卸载**（不是被覆盖安装拒绝）→ 数据在这一刻清零 |
| 3 | 22:51:16.426 `installStage allowInterceptAdbInstallInInstallStage pkg:com.zcstudy.xiaole; stagedDir /data/app/vmdl2104142499.tmp` | ColorOS **拦截 adb 安装**，改走自家安装向导 |
| 4 | 22:51:16.5 起 `com.android.packageinstaller/oplus.OPlusPackageInstallerActivity` 获得焦点，直到 22:55:58 才出现 `InstallAppProgress` | 安装会话卡在**人工确认页**（"已知悉该应用存在风险"→"授权本次安装"→"仍然继续"），未确认即中止 → adb 回包 `Failure [-99]` |
| 5 | 22:55:58 安装完成，`installerPackageName=com.android.packageinstaller`，`firstInstallTime=22:55:58` | 只有走完向导才装成功；`firstInstallTime` 重置，再次证明前面的包是被卸载的 |
| 6 | `settings get global verifier_verify_adb_installs` = `1` | "验证通过 USB 安装的应用"处于开启状态，正是触发向导的条件 |

结论：

1. `-99` **不是签名冲突**，是 ColorOS 对 adb 安装的拦截 + 向导未确认；
2. 数据丢失 **不是覆盖安装失败造成的**，是 22:51:00 的显式卸载造成的
   （签名不一致的覆盖只会报 `UPDATE_INCOMPATIBLE` 并原样保留数据，绝不会自动卸载）；
3. 因此"68 与合并版签名不同"的假设不成立——三个包指纹一致（§1）。

### 3.1 以后怎么避免（装机清单）

- 装包前确保屏幕亮、无悬浮窗遮挡（抖音极速版胶囊会抢点击，先 `am force-stop`）；
- 看到 `OPlusPackageInstallerActivity` 就按顺序点：复选框 →「授权本次安装」→ 风险弹窗「仍然继续」→ 完成页「打开应用」；
- **绝不用 `adb uninstall` 去"解决" `-99`**（那正是本次数据丢失的直接原因）；
- 需要临时绕开向导时，可在开发者选项里关闭「验证通过 USB 安装的应用」（`verifier_verify_adb_installs`），装完再打开；
- 装前先备份：App 内「一键云端」；开发者中心抄下 WS/OTA 地址与 Token。

---

## 4. CI 如何保证"只引用一处 keystore"

- keystore 只存在于 `android/app/xiaole-release.p12`，随仓库提交；
- `android/app/build.gradle.kts` 的 `signingConfigs.release` 直接 `storeFile = file("xiaole-release.p12")`，不读外部路径；
- 密码只从 `XIAOLE_KEYSTORE_PASSWORD` / `XIAOLE_KEY_PASSWORD` 取，`.github/workflows/build-apk.yml` 内统一写一份；
- CI 的 `Verify APK metadata & signature` 步骤会打印 `apksigner verify --print-certs` 到 Job Summary，出包即可核对指纹；
- **禁止**：任何仓库/任何人再生成第二张 keystore；任何"临时换个签名试试"的操作。

### 4.1 单包仓库对齐要求

1. `applicationId` 与纯小乐包完全一致：`com.zcstudy.xiaole`；
2. 用 §2.1 的 base64 导入同一张 p12，alias `xiaole`，密码同 §2；
3. CI 出包后贴 `print-certs`，SHA-256 必须等于 §2 的值；
4. 改 `applicationId` 或换签名 = 新包身份，必须提前告知，不能静默发版。
