# PLAN v6.4.0 —— 外部 MCP 接入（App 内增删改 + 桥接）

> 状态：**第二步，待 v6.3.0 完成后启动**（本文件先定方向，细节届时细化）。
> 基线：v6.3.0。目标 6.4.0+37。

---

## 一、目标

在 App 内**新增/修改/删除多条外部 MCP 服务器**（streamable HTTP），并让 AI 真正能用它们的工具。
首批：**biji-notes**（必接）+ **amap-maps**（可接）。

---

## 二、关键结论（已调研 + 实测）

1. **协议方向**：小智协议里**我们的 App 是 MCP Server（被调用方）**；协议**不支持**设备上报 MCP 接入点 URL 让服务器回连。
2. **可行路径 = App 兼任 MCP Client 桥接**：App 连外部 server → 把其工具**加前缀合并进设备 `tools/list`** → AI 调用时 App 转发 `tools/call`。
   **无需改协议**（`tools/list` 本就是动态的）。
3. **端点实测（已亲自发 MCP 握手，均 200、纯 JSON、无 SSE/无 session）**：

| server | url | 协议 | 工具数 |
|---|---|---|---|
| biji-notes | `zhangchong-biji-web.pages.dev/api/mcp/rpc`（Bearer） | 2025-06-18 | **13** |
| amap-maps | `mcp.amap.com/mcp?key=…` | 2025-03-26 | **15** |

→ 用 **HTTP + JSON-RPC**（项目已有 `http`/`dio`）即可，**不需要引入 MCP 库**。

4. **⚠️ 唯一待验证前置**：官方云 `api.tenclass.net` 是否接受设备上报的**非 `self.` 前缀**工具并喂给 AI。
   → **实施第一步：加一个非 `self.` 探针工具实测**；若只认 `self.`，则外部工具**统一套 `self.` 前缀**绕过。

---

## 三、决策（张老师已定）

| 项 | 结论 |
|---|---|
| 接入范围 | **两个都接**（体积不增，实测远端拉取、零新增依赖） |
| 工具命名 | **加前缀**：`notes.` / `amap.` |
| 开关粒度 | **服务器级 + 逐工具**（与 v6.3.0 一致） |
| 交付节奏 | v6.3.0 之后 |

---

## 四、改动清单（方向）

1. **`lib/core/mcp/external_mcp_client.dart`（新）**：外部 MCP 客户端（HTTP + JSON-RPC）
   - `initialize` → `notifications/initialized` → `tools/list` → `tools/call`；
   - 支持自定义 headers（如 biji-notes 的 `Authorization: Bearer …`）；
   - 超时/重试/异常一律内部消化并回报状态。
2. **`lib/core/mcp/external_mcp_store.dart`（新）**：多配置持久化（名称/url/headers/type/enabled/逐工具开关）。
3. **`lib/presentation/pages/external_mcp_page.dart`（新）**：增删改列表页
   - 每台：连接状态（在线/失败）、工具数、**服务器开关**；点进去**逐工具开关**；支持粘贴上面的 JSON 片段导入。
4. **`lib/core/network/xiaozhi_mcp_responder.dart`**：`tools/list` **合并**外部工具（前缀命名）；`tools/call` 命中外部工具时转发。
5. **`lib/presentation/pages/chat/chat_page.dart`**：WS 握手前**预拉取**外部工具（因服务器会缓存 `tools/list`，须在会话建立时就在列表中）。
6. **开发者中心入口**：新增「🌐 外部 MCP」入口（风格同现有条目）。

---

## 五、风险与对策

| 风险 | 对策 |
|---|---|
| 官方云不接受非 `self.` 工具名 | 探针实测；必要时统一加 `self.` 前缀 |
| 工具总数 26+28=54，AI 选择分散 | 逐工具/逐服务器开关收窄；默认只开常用 |
| 外部调用多一跳公网、弱网失败 | 短超时 + 明确错误回包，不影响设备本地工具 |
| token/key **明文存本地** | 明确告知；后续可选加密（本版先提示） |
| 服务器缓存工具列表 | 会话建立时预拉取；必要时重连刷新 |
| 🔒 红线 | 不碰协议握手字段与音频冻结区；`lib/core/network` 仅按登记方式改（对照 xiaoleweb.md） |

---

## 六、验证清单
- [ ] 探针验证官方云前缀限制（**前置**）
- [ ] `analyze` 0 error、warning 无新增
- [ ] golden 回归
- [ ] 真机：配好 biji-notes → AI 能 `notes.search_notes` 搜到笔记、`notes.add_note` 记笔记
- [ ] 真机：配好 amap → 配合 v6.3.0 定位工具 → AI 能"附近搜/导航"
- [ ] 断网/服务下线：不崩溃、不阻塞设备本地工具

## 七、版本
`6.3.0+36` → **`6.4.0+37`**（定位已在 v6.3.0 完成，原 v6.4.1 取消）
