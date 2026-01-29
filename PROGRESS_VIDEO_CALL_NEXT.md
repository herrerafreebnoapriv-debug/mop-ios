# 视频通话 - 现状与下一步

**更新时间**: 2026-01-24  
**目标**: 完成视频通话端到端流程（聊天内发起 → Jitsi 房间 → 对方接听）

---

## 一、已完成部分

### 1. 前端

| 模块 | 文件 | 功能 |
|------|------|------|
| 通话组件 | `static/chat-calls.js` | `startVideoCall`：生成 roomId → 调 `/rooms/create`（可选）→ `/rooms/{roomId}/join` → 开新窗口 `room_url`；1:1 时 `socket.emit('call_invitation', ...)` |
| | | `showInvitation`：弹窗显示「对方邀请您进入通话」 |
| | | `acceptInvitation`：用 `room_url` 或 `/rooms/{id}/join` 后 `window.open(room_url)` |
| | | `rejectInvitation`：`emit('call_invitation_response', { accepted: false })` |
| 房间页 | `static/room.html` | 读 `room`、`jwt`、`server`（query），加载 Jitsi `external_api.js`（来自 `server`），初始化 Jitsi Meet，品牌「和平信使」 |

### 2. 后端

| 模块 | 说明 |
|------|------|
| **POST /api/v1/rooms/{room_id}/join** | 需登录，为 `room_id` 签发 Jitsi JWT，返回 `room_id`、`jitsi_token`、`jitsi_server_url`、`room_url`。不做房间库表校验。 |
| **GET /room/{room_id}** | 返回 `room.html`，房间参数靠前端 URL query（`jwt`、`server`） |
| **Socket.io** | `call_invitation`：接收邀请 → 转发 `user_{target_user_id}`；`call_invitation_sent` 回给发起方；`call_invitation_response` 处理接受/拒绝 |

### 3. 配置与基础设施

- Jitsi JWT：`create_jitsi_token`（`app/core/security`），与 `JITSI_APP_ID`、`JITSI_APP_SECRET` 一致
- `JITSI_SERVER_URL`：自建 Jitsi 地址，供 `room_url` 的 `server` 参数及 `external_api.js` 使用
- 自建 Jitsi：`docker-compose.jitsi.yml`、`jitsi.env`、`JITSI_DEPLOYMENT.md`

---

## 二、待确认 / 待完成

### 1. 聊天内「创建房间」逻辑

- 前端会请求 **POST /api/v1/rooms/create**，但 `rooms.py` 当前**没有**该路由；创建失败时前端会继续走 join。
- **建议**：若无需房间预创建逻辑，可保留现状（仅 join）；若需要，则新增 `POST /rooms/create`（例如仅做校验或记录）。

### 2. Jitsi 部署与 HTTPS

- **Spec**：WebRTC 需 HTTPS；Jitsi 必须可访问且与 `JITSI_SERVER_URL` 一致。
- **待做**：确认自建 Jitsi 已部署、`jitsi.env` 与后端 `.env` 对齐，且 `JITSI_SERVER_URL` 为 HTTPS（例如 `https://jitsi.xxx.com`）。

### 3. `room_url` 的 `base_url`

- `room_url` 形如：`{base_url}/room/{room_id}?jwt=...&server=...`
- `base_url` 来自 `request.base_url`。若前端经 `https://log.chat5202ol.xyz` 访问，需保证反向代理正确转发 `Host`/`X-Forwarded-*`，否则 `base_url` 可能错，导致 `room_url` 指向错误域名。

### 4. 邀请流程与 UI

- 1:1 场景：发起方 `startVideoCall` → join → 新窗口打开房间；同时 `call_invitation` 发给对方。
- 对方：`call_invitation` 弹窗 → 接受则 `room_url` 新窗口打开。
- **待验证**：  
  - 邀请弹窗在不同标签页/设备上的表现；  
  - 拒绝后发起方是否有相应提示（若需）。

### 5. 房间页与动态 Endpoint

- **规则**：禁止前端写死 API 地址；`room_url` 的 `server` 来自后端，符合「动态 Endpoint」。
- 确保 `room.html` 仅使用 URL 中的 `room`、`jwt`、`server`，不自行拼后端 API 基地址。

---

## 三、建议的下一步（按优先级）

1. **确认 Jitsi 可用**  
   - 部署/启动 Jitsi Docker，配置 `jitsi.env` 与 `.env`。  
   - 用 `curl` 或浏览器直接访问 `JITSI_SERVER_URL`，确认 `external_api.js` 可加载。

2. **端到端联调**  
   - 两账号在聊天页 1:1：A 发起视频通话 → B 收到邀请 → B 接受 → 双方均能进入 Jitsi 房间并音视频互通。  
   - 检查 `room_url` 是否可正常打开、`jwt` 与 `server` 是否正确。

3. **（可选）POST /rooms/create**  
   - 若产品上需要「创建房间」语义或审计，再加该接口；否则可保持仅 join。

4. **错误与边界**  
   - Join 失败、Jitsi 加载失败、无 `server` 等：前端友好提示；必要时记日志便于排查。

5. **移动端**  
   - 若 App 内也要视频通话，需复用同一 `room_url` / join 流程，并在客户端内用 WebView 或 Jitsi SDK 打开房间；与当前 Web 流程对齐即可。

---

## 四、相关文件速查

| 类型 | 路径 |
|------|------|
| 前端通话 | `static/chat-calls.js` |
| 房间页 | `static/room.html` |
| 后端房间 | `app/api/v1/rooms.py` |
| Socket 邀请 | `app/core/socketio.py`（`call_invitation`、`call_invitation_response`） |
| Jitsi JWT | `app/core/security.py`（`create_jitsi_token`） |
| 配置 | `.env`（`JITSI_APP_ID`、`JITSI_APP_SECRET`、`JITSI_SERVER_URL`），`jitsi.env` |
| 部署 | `JITSI_DEPLOYMENT.md`，`docker-compose.jitsi.yml` |

---

*延续自 `PROGRESS_IMAGE_FEATURE.md`（图片功能已完成）*
