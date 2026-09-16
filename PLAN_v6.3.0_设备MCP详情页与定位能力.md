# PLAN v6.3.0 —— 设备 MCP 详情页（逐项开关）+ 定位能力

> 状态：**待张老师审批**。批准后方可实施。
> 基线：v6.2.1+35（commit 见 README）。本版目标 6.3.0+36。
> 前置调研：见 `.workbuddy/memory/2026-09-16.md`（架构扫描 + 端点实测）。

---

## 一、目标（两件事）

1. **设备 MCP 详情页 + 逐项开关**：开发者中心把现有只读「查看已注册工具清单」升级为可操作详情页，26 项设备工具**逐项开关**。
2. **定位能力**：新增设备工具 `self.location.get_current`，让 AI 能拿到手机坐标（供 v6.4.0 的高德 MCP 使用），并处理坐标系与异常兜底。

---

## 二、现状证据（已核实）

| 事实 | 位置 |
|---|---|
| 26 个设备工具集中定义 | `lib/core/network/xiaozhi_mcp_responder.dart` → `XiaozhiMcpStandardTools.allTools()` = `fullSet()`(11) + `v61Tools()`(15)（L524-527） |
| `tools/list` **动态读活的工具表**（可过滤） | 同文件 L89-92；`initialize` L78-86；`tools/call` L94-110（未知工具回 `-32601`） |
| 26 项注册处 | `lib/presentation/pages/chat/chat_page.dart` `_setupMcpResponder()`（L942-1369，26 次 `register`）；WS 初始化调一次（L910） |
| 总开关（一键总闸） | `AppFeats.mcptools`（chat_page L1999 主链路 / L1409 MQTT 旁路） |
| 只读清单弹窗（现成文案素材） | `lib/presentation/pages/dev_center_page.dart` `_showMcpToolsDialog`（L258-356，按 4 组列 26 项） |
| 开关范式 | 同文件 `_switchTile`（L385-412）+ `AppFeats`（键 `xw_feat_*`） |
| 持久化 | `lib/core/storage/storage_service.dart`（`setBool/getBool` L38-44、`setStringList/getStringList` L46-52） |
| 设备能力实现 | `lib/core/mcp/device_capability_service.dart`（单例 L23-25，异常内部消化） |
| Android 权限现状 | 现有 INTERNET/CAMERA/RECORD_AUDIO/存储类，**无定位权限** |

---

## 三、改动清单

### A. 逐项开关（低风险，不碰网络主干）

1. **`lib/presentation/services/app_feats.dart`**
   - 新增：`mcpToolEnabled(String name)` / `setMcpToolEnabled(String name, bool)`；
     存储键 `xw_mcp_<name>`（工具名含 `.`，转义为 `_`）。
   - `load()` 时一并恢复；**逐项键独立于 `keys` 列表** → `allOff()`（L75-79）**不清逐项设置**。
2. **`lib/core/network/xiaozhi_mcp_responder.dart`**
   - 新增字段 `bool Function(String name)? isToolEnabled`。
   - `tools/list`（L89-92）：`_tools.values.where((t) => isToolEnabled?.call(t.name) ?? true)`。
   - `tools/call`（L94）：命中的工具若被禁用 → 回错误（`-32601 unknown tool`，与"不存在"一致，避免暴露被关工具）。
   - ⚠️ 保留 `initialize` 的 `listChanged:false` 不变（不改协议）。
3. **`lib/presentation/pages/chat/chat_page.dart`**
   - `_setupMcpResponder()`（L942）构建 responder 时注入 `isToolEnabled: AppFeats.mcpToolEnabled`。
   - 26 次 `register` **全部保留**（过滤在下发层做，免重建）。
4. **`lib/presentation/pages/dev_center_page.dart`**
   - 把 `_showMcpToolsDialog` 升级为**详情页**（或就地改为可操作）：复用其现成 4 组结构（L263-298），
     每项行尾加 `Switch`，`value: AppFeats.mcpToolEnabled(t.name)`，`onChanged` 写回 + `setState`。
   - 层级约定：**总闸 `mcptools` 关 = 全不可用；逐项在其下细分**（总闸关闭时逐项 UI 置灰/提示）。

### B. 定位能力（`self.location.get_current`）

1. **依赖**：`pubspec.yaml` 增 `geolocator`（先用后台 `flutter pub get`；**实施前核实与 Flutter 3.32.2 / Dart 3.8.1 的兼容版本**）。
2. **`android/app/src/main/AndroidManifest.xml`**：新增
   `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`（无网络定位则 coarse 兜底）。
3. **新文件 `lib/core/mcp/location_service.dart`**：`getCurrent()` 流程 ——
   (1) 权限检查/申请（复用 `permission_handler`）→ 拒绝则返回结构化原因；
   (2) 检查**定位服务是否开启**（`isLocationServiceEnabled`）→ 关则返回「请打开定位」；
   (3) `geolocator` 取位（**带超时**，如 8s；精度 `high`，超时降级 `low`/网络定位）；
   (4) **WGS-84 → GCJ-02 转换**（标准算法，约 30 行，内置为纯函数并单测）；
   (5) 返回 `{latitude, longitude, accuracy, coordType:"gcj02", provider}`。
4. **`xiaozhi_mcp_responder.dart`**：新增工具定义 `self.location.get_current`（inputSchema 无参）。
5. **`chat_page.dart`**：`_setupMcpResponder()` 注册第 27 项（→ 调用 `LocationService.instance.getCurrent()`）。
6. **兜底链**：
   - 权限拒绝 / 服务关闭 → **返回明确提示**（AI 据此告诉用户"请打开定位"）；
   - **IP 粗定位兜底**（走高德 `maps.ip_location`）**需 v6.4.0 桥接后才生效** ——
     本版先实现"提示 + 网络/低精度定位尝试"，IP 兜底占位并在 v6.4.0 接通（已在文档标注跨版本依赖）。

---

## 四、风险与对策

| 风险 | 对策 |
|---|---|
| `geolocator` 与 Flutter 3.32.2 不兼容 | 实施第一步先 `pub get` + `analyze` 验证，不通则换 `location` 包 |
| 定位卡住 UI | 全程超时 + 异步，失败即返回结构化错误，**绝不阻塞** |
| 坐标系搞错导致"能跑但结果错" | WGS-84→GCJ-02 转换**必须做**，并写单测校验已知点 |
| 逐项开关与总闸冲突 | 明确层级（总关=全关）；逐项键不入 `allOff()` |
| 定位隐私 | **仅 AI 调用时按需取，绝不后台采集**；纳入逐项开关 |
| 🔒 红线 | 本轮**只动** `dev_center_page.dart` / `app_feats.dart` / `xiaozhi_mcp_responder.dart` / `chat_page.dart`(注册段) / 新增文件 / Manifest；**不碰** `lib/core/network` 的协议与音频冻结区 |

---

## 五、验证清单

- [ ] `flutter analyze` 0 error、**warning 无新增**（基线 5 条存量）
- [ ] golden：更新两次后复跑（常规 flaky ≤0.28%）
- [ ] 真机：逐项关掉某工具（如 `self.battery`）→ AI 调用该工具应"找不到"；重新开启后恢复
- [ ] 真机：定位工具在「权限给/拒、定位开/关」四种组合下均返回结构化结果，不崩溃
- [ ] 坐标系：用已知 WGS-84 点验证转换后 GCJ-02 偏差 < 1m（对标准算法）
- [ ] 总闸关闭 → 全部工具不可用，逐项设置**不被清空**

## 六、交付序列（沿用既定）
CI 验证 → APK 下载到桌面 → PLAN md 回填仓库 → git push（API 四步法）+ tag 触发 CI

---

## 七、版本
`6.2.1+35` → **`6.3.0+36`**
