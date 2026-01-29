# App 端无法主动接收消息 & 即时通讯方案讨论

**状态**：根因已修复并落地（Provider 内统一 `message` / `message_read` 流 + 聊天页消费流 + dispose 取消订阅）。

---

## 一、现状与根因分析

### 1.1 当前流程

- **连接**：`SocketProvider.autoConnect()` 在登录后 / `Consumer2` 检测到未连接时调用，`connect(token)` 建连并 `_setupEventHandlers()`。
- **收消息**：仅 `ChatWindowScreen` 在 `initState` 里 `_subscribeToMessages()` → `socketProvider.onMessage(cb)`，向当前 socket 注册 `socket.on('message', cb)`。
- **服务端**：连接时 `enter_room(sid, "user_{user_id}")`，发消息时 `emit('message', ..., room="user_{receiver_id}")`，逻辑正确。

### 1.2 根因：重连后丢失 `message` 监听

- `message` **未**在 `_setupEventHandlers` 里注册，只通过 `onMessage()` 在聊天页注册。
- 重连时 `connect()` 会 `disconnect` → `dispose` 旧 socket，再 `IO.io(...)` 创建**新** socket，只挂 `_setupEventHandlers`（connect/disconnect、system_message、call_invitation 等），**不会**再挂 `message`。
- 聊天页的 `_subscribeToMessages` 只在 `initState` 跑一次，**不会**在重连后重新注册。
- **结果**：重连后新 socket 上没有 `message` 监听，收不到任何新消息，只能手动刷新拉历史。

### 1.3 其他可能加剧问题的点

| 点 | 说明 |
|----|------|
| **连接时机** | `_subscribeToMessages` 里 `if (socketProvider.isConnected)` 才注册。若进聊天时尚未连接完成，则直接不注册，同样收不到。 |
| **仅聊天页订阅** | 消息列表 / 会话列表页没有订阅 `message`，未读、最后一条等不会实时更新，只能刷新。 |
| **后台/杀进程** | 切后台或网络切换时 WebSocket 易被系统断线，重连后若未重新订阅，继续收不到。 |
| **多端 `on` 不 `off`** | 多次 `socket.on('message', cb)` 会叠多个 cb；离开聊天页未 `off`，有泄露与重复处理风险（当前重连会换 socket，旧 handler 被 dispose 掉，但设计上仍不干净）。 |

---

## 二、推荐修复（在保留 Socket.io 的前提下）

### 2.1 必做：把 `message` 收拢到 Provider，重连不丢

**思路**：在 `SocketProvider._setupEventHandlers` 里**统一**注册一次 `message`，重连时每次新 socket 都会带上。业务侧只“消费”消息，不再直接 `onMessage` 注册。

- 在 Provider 内：
  - 使用 `StreamController<Map<String, dynamic>>` 或 `ValueNotifier<List<Map<String, dynamic>>>` 等，把收到的 `message` 事件推上去。
  - 在 `_setupEventHandlers` 里 `_socket!.on('message', (data) { ... })`，解析后 `add` / `notifyListeners`。
- 聊天页 / 会话列表：
  - 监听该 Stream 或 Notifier，按 `receiver_id` / `room_id` 过滤后更新 UI。
- 这样**重连**、**新 socket** 都会重新执行 `_setupEventHandlers`，即重新挂上 `message`，不会因“只在一处 initState 注册”而丢失。

### 2.2 建议：连接成功后再订阅 / 重连后重绑 UI

- 若保留“按页订阅”的模式：
  - 监听 `SocketProvider` 的 `isConnected`（或 `connect`/`reconnect` 回调）。
  - 进聊天页时若已连接则注册；若未连接则等 `isConnected == true` 再注册。
  - 重连后 `isConnected` 从 false→true，各页可在此刻**重新**绑定 `message` 逻辑（若还是用 Provider 内流，则只需重新 `listen`，无需再 `socket.on`）。
- 避免“只在 initState 检查一次 isConnected”，否则未连接时永远不订阅。

### 2.3 建议：离开聊天页时 `off('message', cb)`

- 若某处仍直接 `socket.on('message', cb)`，保存 `cb` 的引用，在 `dispose` 时 `socket.off('message', cb)`，避免重复注册和泄露。
- 若完全改为 Provider 内单一 `message` 源 + 流，则只需取消对流的 `listen`，无需 `off`。

### 2.4 可选：降级与轮询

- 检测到长时间未收到任何 message（或 ping/pong 超时）时，可自动 fallback 到**短轮询**（例如每 N 秒请求一次 `/chat/messages`），保证至少能拉到新消息。
- 作为 WebSocket 不稳定时的兜底，而不是替代 Socket.io。

---

## 三、是否要换掉 Socket.io？替代方案简述

### 3.1 结论先行

- **当前问题本质是“监听生命周期 + 重连未再订阅”**，不是协议本身。优先做第二节的修复，再观察。
- 若修完后仍有**系统性**的连接受限（如部分网络/运营商下 WS 经常断、无法建连），再考虑**补充** fallback（轮询/SSE）或**替换**为更适配移动端的方案。

### 3.2 可替代 / 互补方案对比

| 方案 | 类型 | 优点 | 缺点 | 适用场景 |
|------|------|------|------|----------|
| **维持 Socket.io，修订阅** | WS + 封装 | 与现有后端一致，改造成本低 | 依赖 WebSocket，弱网/强管控网络下可能断线 | **首选**：先修复再观察 |
| **原生 WebSocket** | WS | 无额外依赖，控制细 | 需自实现重连、心跳、鉴权、房间语义；后端要单独 WS 或改现有 Socket.io | 想彻底掌控协议时 |
| **HTTP 长轮询** | HTTP | 实现简单，穿透性好 | 延迟高、请求多，实时性差 | 作 Socket 的**降级** |
| **Server-Sent Events (SSE)** | HTTP 长连接 | 单向推送简单，比轮询实时 | 仅 server→client；发消息仍走 REST | 推送为主、发消息不多的场景 |
| **Ably / Pusher / PubNub** | 托管服务 | 高可用、多端 SDK、省运维 | 收费、数据过第三方，需改后端推送逻辑 | 不想自维护实时基础设施时 |
| **Firebase Realtime DB / Firestore** | 托管 DB + 实时 | 实时同步成熟，与 FCM 同生态 | 架构变化大，后端要写 Firestore 或桥接 | 已深度用 Firebase 且愿改架构时 |
| **MQTT（如 EMQX）** |  Pub/Sub | 轻量、省电、弱网友好 | 后端要引入 MQTT broker，模型与当前 chat 不同 | IoT、弱网优先场景 |
| **gRPC 流** | RPC + 流 | 双向流、类型安全 | 接入成本高，通常 overkill | 已有 gRPC 技术栈时 |

### 3.3 实际建议

1. **短期**：  
   - 按第二节把 `message` 收拢到 Provider、重连不丢订阅，并做好连接成功后再订阅 / 重连后重绑。  
   - 可选：加简单轮询 fallback。  

2. **若仍经常断线、收不到**：  
   - 增加 **SSE** 或 **长轮询** 作为收消息的补充通道；发消息继续 REST。  
   - 或评估 **Ably/Pusher** 等托管方案，后端只负责 publish，客户端 subscribe。  

3. **一般不建议**：  
   - 在未做上述修复前，直接换成另一种实时框架；问题多半仍会以别的形式存在（连接管理、订阅生命周期等）。  

---

## 四、小结

- **收不到消息**：主因是重连后 `message` 监听未再注册，以及依赖 `isConnected` 的订阅时机不当。  
- **推荐**：在 `SocketProvider` 内统一处理 `message`，重连必带；业务侧只消费。再补上连接/重连后的订阅与 `off` 规范。  
- **替代框架**：可作补充或远期选项；当前优先修复 Socket.io 使用方式，再视网络与运维成本决定是否引入 SSE/轮询或托管服务。

---

## 五、已落实的修改（摘要）

1. **SocketProvider**
   - 新增 `messageStream`、`messageReadStream`（broadcast）。
   - 在 `_setupEventHandlers` 中统一注册 `message`、`message_read`，推入对应流；重连后新 socket 会再次执行，监听不丢失。
   - `dispose` 时关闭两个 `StreamController`。

2. **ChatWindowScreen**
   - 移除对 `onMessage`、`on('message_read')` 的调用及 `isConnected` 判断。
   - 在 `_subscribeToMessages` 中订阅 `messageStream`、`messageReadStream`，按当前会话过滤后更新 `_messages` 与已读。
   - `dispose` 时 `cancel` 上述两个 `StreamSubscription`。
