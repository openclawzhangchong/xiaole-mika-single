# PLAN v6.1.4 — 一键云端：修复「MAC / 设备ID 无法上传与恢复」

> 立项：2026-09-13 ｜ 基线：v6.1.3（`7c496b1`）｜ 状态：**待张老师审批**
> 诊断方式：两路并行只读代码调查（上传链路 / 恢复链路），结论均标注「已证实 / 推测」

---

## 0. 结论先行

**你的现象与推测都基本正确，但比"没传上去"更彻底：上传端和恢复端都没有处理设备身份。**

- **上传端**：`agentToWeb()` 打包智能体配置时 **只带 `fOta/fWs/fToken/fModel/fBoard`，没有 `fMac/fCid`** ——
  代码里还有一句注释说明这是"刻意排除"（原话：*fMac/fCid 为网页端本机身份/代理字段，App 侧不伪造*）。
- **恢复端**：`applyPullResult()` **只写** 智能体列表 / 聊天记录 / 昵称 / 手机号，
  **完全没碰** `AgentIdentityStore`（每智能体身份）和全局 `device_mac_address` / `device_client_id`。
- **所以不是"被本机配置覆盖"，而是：重装后本机身份被重新生成 → 恢复时没人把原身份装回去 → 连接自然用了新身份。**
  （你用"被覆盖"来描述结果是对的，机制上属于"两端都缺"。）

---

## 1. 完整链路梳理（你手动走的全过程）

### 涉及的三个存储位置（关键背景）

| 存什么 | 存在哪 | 键名 | 谁写 |
|---|---|---|---|
| **每智能体独立身份**（MAC/ClientID/型号） | `AgentIdentityStore`（`lib/presentation/services/agent_identity_store.dart`） | `agent_identity_mac_<agentId>`、`agent_identity_clientid_<agentId>`、`agent_identity_model_<agentId>` | 智能体配置页保存时（`agent_config_page.dart:370-375`） |
| **全局设备身份**（当前生效） | `XiaozhiDeviceInfoUtil`（`lib/core/utils/`，**冻结文件**） | `device_mac_address`、`device_client_id` | 首次使用时按 `androidId`/随机 UUID 生成并持久化 |
| **智能体配置** | SharedPreferences `agent_list` → `AgentModel` | — | 只存 `id/name/url/token/otaUrl/description`（**无 MAC/ClientID 字段**） |

> 设计背景（`agent_identity_store.dart` 顶部注释，v1.1.5 起）：全局身份是**单例**，
> 多智能体会互相覆盖串号 → 因此**每个智能体单独存一份身份**，进入对话前再由 `chat_page` 把该智能体的身份
> 通过公开 setter 应用到全局。**这就是为什么上传/恢复必须带上每智能体的身份。**

### 逐步链路（✅=正确处理，❌=缺失）

| 步骤 | 发生了什么 | MAC/ClientID 的处理 |
|---|---|---|
| **① 新建智能体**（随机 MAC，连接成功） | 配置页生成三元组 → `AgentIdentityStore.save(agentId, mac, clientId, model)`；进入对话时 `chat_page` 把它设为全局身份 → WS 握手头 `Device-Id`/`Client-Id` 使用之 | ✅ 本地保存正确 |
| **② 一键上传聊天记录到云端** | `cloud_sync_page._push()` → 读 `agent_list` + 聊天记录 → `pushAll()` → 请求体 `{phone, userName, agentId:'*', blocks, profile, agents:[agentToWeb(a)]}` | ❌ **`agentToWeb` 不含 fMac/fCid；`_push` 全程不读 `AgentIdentityStore`** |
| ②′ 云端入库 | D1 `xw_v1_agents` 存智能体配置（conf 为 JSON） | ⚠️ 该 agent 的 conf 里**没有身份字段**（**推测**：由"App 从不传"直接推出，未读服务端代码） |
| **③ 删除 App** | SharedPreferences 全部清空 | ❌ 本地那份 `agent_identity_*` 随之消失（**这是唯一副本**） |
| **④ 重新装 App** | 首次使用 → `XiaozhiDeviceInfoUtil` 按 `androidId`/随机 UUID **重新生成**全局身份 | ⚠️ 生成了一个**新身份** |
| **⑤ 从云端恢复到本机** | `_pull()` → `pullAll()` 解析出 `List<AgentModel>` → 用户确认 → `applyPullResult()` 写：智能体列表、聊天记录、昵称、手机号 | ❌ **没写 `AgentIdentityStore`、也没写全局身份** |
| **⑥ 进入对话** | `chat_page.dart:835` `AgentIdentityStore.load(agentId)` → 返回 `null`（本地没有）→ 走 else 分支：**把当前全局身份（新生成的）快照绑到该智能体**并连接 | ❌ **结果就是"用本机新身份去连原智能体"→ 连不回** |

---

## 2. 根因（两处缺陷，已证实）

**缺陷 A（上传端）** — `cloud_sync_service.dart:393` `agentToWeb()`：
```dart
conf: { fOta:…, fWs:…, fToken:…, fModel:'m5stack-core-s3', fBoard:… }   // ← 无 fMac / fCid
```
`:404` 注释把它解释为"网页端本机身份，App 侧不伪造" —— **这是旧认知**：
自 v1.1.5 起身份已是**每智能体独立**（`AgentIdentityStore`），上游逻辑却未同步。

**缺陷 B（恢复端）** — `cloud_sync_service.dart:276` `applyPullResult()`：
只写 `agent_list` / `chat_history_*` / `profile_name` / `profile_id`，**未写任何身份键**。

**性质**：**设计认知偏差导致的"双端遗漏"**，不是被某处逻辑主动覆盖。

---

## 3. 修复方案（3 处改动，全部在表现层，零红线）

> **改动文件**：`lib/presentation/services/cloud_sync_service.dart`（主）
> —— **不碰** `lib/core/utils/xiaozhi_device_info_util.dart`（冻结文件）；
> 只调用它**既有的公开 setter**，与 `agent_config_page` / `chat_page` / `settings_page` 现有用法一致。

### 改动 1：上传带上身份（`pushAll` + `agentToWeb`）

- `pushAll()`（:160）在既有 `for (final a in agents)` 循环里，**先批量读取身份**：
  ```dart
  final identities = <String, Map<String, String>>{};
  for (final a in agents) {
    final id = await AgentIdentityStore.load(a.id);
    if (id != null) identities[a.id] = id;   // {mac, clientId, model}
  }
  ```
- `agentToWeb(AgentModel a, {Map<String, String>? identity})` **增加可选参数**（保持向后兼容），
  在 `conf` 里补上：
  ```dart
  if (identity != null) ...{
    'fMac': identity['mac'],
    'fCid': identity['clientId'],
  }
  ```
- `_post('/push', ...)` 的 `agents:` 改为 `agents.map((a) => agentToWeb(a, identity: identities[a.id])).toList()`

### 改动 2：恢复时把身份装回本地（`pullAll` + `applyPullResult`）

- `pullAll()`（:222）解析 `r['agents']` 时，**顺便提取身份**（原始 JSON 里有 `conf.fMac/fCid`）：
  ```dart
  final identities = <String, Map<String, String>>{};
  for (final a in rawAgents) {
    final conf = (a['conf'] as Map?) ?? const {};
    final mac = conf['fMac'] as String?;
    final cid = conf['fCid'] as String?;
    final id  = a['id'] as String?;
    if (id != null && mac != null && cid != null) {
      identities[id] = {'mac': mac, 'clientId': cid};
    }
  }
  ```
  → 结果里带上 `result['identities'] = identities`
- `applyPullResult()`（:276）在写智能体列表之后、写聊天记录之前，**逐个写回身份**：
  ```dart
  final identities = (result['identities'] as Map<String, Map<String, String>>?) ?? const {};
  for (final a in agents) {
    final id = identities[a.id];
    if (id != null) {
      await AgentIdentityStore.save(a.id,
          mac: id['mac']!, clientId: id['clientId']!, model: kUnifiedDeviceModel);
    }
  }
  ```

### 改动 3（可选，建议做）：把"当前主智能体"的身份也对齐到全局

恢复后若**立即**要用旧身份连接，全局值还停留在新生成的身份上。可在 `applyPullResult` 末尾：
```dart
// 取第一个（或当前选中）智能体，把身份应用为全局，避免"恢复后首次连接仍用新身份"
final first = identities[agents.first.id];
if (first != null) {
  await XiaozhiDeviceInfoUtil.instance.setDeviceMacAddress(first['mac']!);
  await XiaozhiDeviceInfoUtil.instance.setDeviceClientId(first['clientId']!);
  await XiaozhiDeviceInfoUtil.instance.setDeviceModel(kUnifiedDeviceModel);
}
```
（**只调用公开 setter，不改冻结文件**；`chat_page` 进入对话时本来也会按 agentId 应用身份，此处只是让"恢复后立即连接"也正确。）

---

## 4. 风险与兼容性

| 风险 | 评估 / 应对 |
|---|---|
| **云端能否存下 fMac/fCid** | `conf` 在 D1 里是 JSON 结构，**新增字段预期可透传**；⚠️ 仍属**推测**（未读服务端代码）→ **实施后需真机验证一次"上传→换机/重装→恢复"闭环**；若服务端白名单过滤字段，则需云端配合（届时另行报告） |
| 改动触碰冻结文件？ | ❌ **不触碰** `xiaozhi_device_info_util.dart`，仅调用其公开 setter ✓ |
| 旧数据兼容 | 云端历史数据**没有** fMac/fCid → 恢复时 `identities` 为空 → **跳过写身份**（行为同现在），**不会更糟** ✓ |
| 多智能体 | 身份按 `agentId` 逐个保存/恢复，不会串号 ✓ |
| 上传体积 | 每 agent 仅多 2 个字符串（MAC 17 字节 + UUID 36 字节），可忽略 ✓ |

---

## 5. 验证方式

**静态**：`flutter analyze --no-pub` 0 error、无新增 warning；golden 照常。

**真机闭环（关键，必须走一遍）**：
1. 新建智能体 A（记下**配置页显示的 MAC 与 ClientID**）→ 成功连接
2. 一键上传到云端 → 恢复页/云端数据中应能看到该 agent 的身份字段
3. **删除 App → 重装**
4. 从云端恢复 → 进智能体 A 的配置页：**MAC/ClientID 应与第 1 步记录的一致**（而不是新生成的）
5. 进对话 → **能连回原智能体**（这正是本次要修的目标）
6. 回归：未上传过身份的老智能体，恢复后行为与现在一致（不崩、不串）

**独立验证员**：复核改动 3 处、`AgentIdentityStore` 键名一致、旧数据兼容分支、以及"是否真的没碰冻结文件"。

---

## 6. 发布与回滚

- 版本 **v6.1.4**；commit → push → **tag v6.1.4** → 确认 CI → **GitHub Release** → README 档案行（按项目铁律）
- **回滚锚点**：v6.1.3（`7c496b1`）

---

## 7. 待张老师确认

1. **改动 3（恢复后把首个智能体身份设为全局）要不要做？** 建议做——否则"恢复完成后第一次连接"仍可能用新身份，
   要等进一次该智能体才被 `chat_page` 纠正。
2. 是否需要**顺带把"云端已有但缺身份的老数据"标记出来**（恢复时提示"该智能体缺少设备身份，需重新配置"）？
   —— 这会让问题更透明，但会增加一点改动量。

*方案结束 — 审批通过后按 §3 实施。*
