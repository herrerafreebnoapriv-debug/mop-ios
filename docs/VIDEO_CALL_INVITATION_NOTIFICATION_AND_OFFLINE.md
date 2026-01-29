# 视频通话邀请：通知与「对方离线也发送」

## 一、讨论：为何已建立通话却未收到邀请通知

### 1.1 两种「通知」含义

| 类型 | 含义 | 触发条件 |
|------|------|----------|
| **应用内弹窗** | 在 App 内弹出的「视频通话邀请」对话框（接受/拒绝） | 被叫已连上 Socket，且当前界面在含 `_CallInvitationListener` 的页面（如 ChatMainScreen 或其子页） |
| **系统级推送** | 手机通知栏/锁屏上的「xxx 邀请您进行视频通话」 | 依赖 FCM/APNs：后端发 FCM，设备收到后由系统展示；App 在后台或未打开时主要靠此唤醒 |

「已建立视频通话但未收到通话邀请通知」通常指：

- **没收到系统级推送**：来电时没有通知栏/锁屏提醒，或只在打开会话后才看到消息。
- 或 **没收到应用内弹窗**：被叫在线但没弹出接受/拒绝对话框（例如当时不在 ChatMainScreen、或 Socket 未连上）。

### 1.2 邀请发送策略（无论对方是否在线）

设计原则：**只要主叫发起邀请，就视为「已发送」**，不因对方离线而失败。

- **始终执行**  
  - 创建一条「视频通话邀请」系统消息并**落库**。  
  - 向**主叫**推送 `message` + `call_invitation_sent`（含 `system_message`），主叫在会话中一定能看到这条记录。  
- **被叫在线**  
  - 向被叫 Socket 推送 `message` + `call_invitation`（应用内弹窗用）。  
  - 再发 **FCM/APNs**（用于后台/锁屏时唤醒，或补一条通知）。  
- **被叫离线**  
  - 不向被叫发 Socket（对方没连接）。  
  - 同样发 **FCM/APNs**：设备上线或 App 被系统/用户拉起后，有机会收到「通话邀请」通知；打开会话后从历史消息中看到邀请并点「接受」进房。  

因此：**对方不在线也会发送**——邀请已落库 + 主叫必收 + 被叫侧尽量通过推送送达；被叫上线后拉历史即可看到邀请消息。

---

## 二、当前实现要点

### 2.1 后端（`app/core/socketio.py`）

1. **邀请必落库**  
   收到 `call_invitation` 后先写一条 `message_type=system`、`extra_data.call_invitation` 的消息，主叫、被叫拉历史都能看到。

2. **主叫必收**  
   - `emit('message', system_message_data, room=user_{sender_id})`  
   - `emit('call_invitation_sent', { ..., system_message })`  
   主叫在会话中一定有一条带「进入房间」的系统消息。

3. **被叫在线**  
   - `emit('message', ...)`、`emit('call_invitation', ...)` 到 `user_{target_user_id}`（应用内弹窗 + 会话内消息）。  
   - 再调 `send_video_call_push(...)` 发 FCM，用于后台/锁屏通知。

4. **被叫离线**  
   - 不向被叫发 Socket。  
   - 仍向主叫发 `call_invitation_sent`（含 `system_message`），主叫会话内照常显示。  
   - **同样调用** `send_video_call_push(...)`，被叫设备上线或打开 App 后有机会收到「通话邀请」系统通知。

### 2.2 推送依赖（FCM）

- **配置**：环境变量 `FCM_SERVER_KEY`（Firebase 服务端密钥）。未配置则不打 FCM，仅落库 + Socket（在线时）。  
- **Token**：被叫设备需在「设备注册/更新」时把 FCM token 上报，后端写入 `UserDevice.ext_field_1`（JSON 含 `fcm_token`）。  
- **依赖**：`pip install pyfcm`；未安装则推送逻辑跳过，不影响邀请落库与主叫展示。

---

## 三、排查流程：未收到通话邀请通知

按下面顺序排查，可快速区分是「应用内弹窗」还是「系统推送」问题，以及是否与「对方离线」有关。

### 3.1 应用内弹窗（被叫在线时应弹出）

| 步骤 | 检查项 | 说明 |
|------|--------|------|
| 1 | 被叫是否已连 Socket | 登录后 App 会 `autoConnect()`；断网/未登录则收不到任何 Socket 事件。 |
| 2 | 被叫是否在含监听器的页面 | 弹窗由 `_CallInvitationListener`（在 ChatMainScreen body）响应；若被叫在登录页或其它不含 ChatMainScreen 的 route，不会弹窗，但进会话后应看到系统消息。 |
| 3 | 后端是否向被叫房间推送 | 日志中应有「已通过 Socket 发送系统消息（通话邀请）给用户 {target_user_id}」及向 `user_{target_user_id}` 发送 `call_invitation`。 |
| 4 | 客户端是否收到 `call_invitation` | App 日志中应有「📞 [Socket] 收到 call_invitation 事件」；若没有，多为 Socket 未连或未加入 `user_{被叫id}` 房间。 |

### 3.2 系统级推送（通知栏/锁屏）

| 步骤 | 检查项 | 说明 |
|------|--------|------|
| 1 | `FCM_SERVER_KEY` 是否配置 | 未配置则 `send_video_call_push` 直接返回，不打 FCM。 |
| 2 | 被叫设备是否上报 FCM token | 设备注册/更新接口是否带 `fcm_token`，且后端写入 `UserDevice.ext_field_1`（含 `fcm_token`）。 |
| 3 | 是否安装 pyfcm | 未安装则推送代码跳过，日志可有「pyfcm 未安装」。 |
| 4 | 对方离线时是否也发推送 | 当前实现：**对方离线时也会调用** `send_video_call_push`，与在线时同一逻辑，仅无 Socket 推送。 |

### 3.3 对方离线时行为

| 步骤 | 检查项 | 说明 |
|------|--------|------|
| 1 | 邀请是否仍落库 | 是；主叫发邀请后，系统消息一定写入 DB。 |
| 2 | 主叫是否仍看到会话内消息 | 是；主叫收到 `call_invitation_sent`（含 `system_message`），会话中显示「进入房间」。 |
| 3 | 被叫离线是否仍发 FCM | 是；在「对方不在线」分支中同样调用 `send_video_call_push`，对方上线/打开 App 后可收到通知（若 FCM 与 token 正常）。 |
| 4 | 被叫上线后如何看到邀请 | 打开与主叫的会话，拉历史消息即可看到系统消息，点「接受」进房。 |

---

## 四、小结

- **邀请始终发送**：主叫一点「视频通话」就落库 + 主叫必收；**不依赖对方是否在线**。  
- **对方在线**：Socket 推送（应用内弹窗 + 会话消息）+ FCM（系统通知）。  
- **对方离线**：无 Socket 推送，但**仍发 FCM**；对方上线后还可从会话历史中看到邀请并进房。  
- **未收到通知**时：先区分是「应用内弹窗」还是「系统推送」，再按第三节对应分支逐项排查（Socket/页面/后端日志、FCM 配置/token/pyfcm、离线分支是否执行）。
