# 视频通话邀请流程（App 端功能视图）

## 场景

- **A** 在与 **B** 的聊天窗口点击「视频通话」按钮。
- **B** 应即时收到带「接受」「拒绝」的弹窗。
- **双方** 在会话中看到一条带「进入房间」按钮的系统消息（折中方案：以消息为主入口，双方均可点击进入）。
- **B** 可点弹窗「接受」或聊天内「进入房间」进入通话。

---

## 入口与视图

### 1. 视频通话按钮（主叫入口）

- **位置**：与 B 的聊天窗口底部输入栏右侧，点击 **「+」** 弹出菜单，选择 **「视频通话」**。
- **代码**：`ChatInputBar` → `PopupMenuButton` → `case 'video': onStartVideoCall()` → `ChatWindowScreen._startVideoCall()` → `ChatVideoCallService.startVideoCall()`。
- **前置**：相机、麦克风权限通过后才会发邀请并跳转 Jitsi 房间页。

### 2. 被叫弹窗（B 即时收到）

- **触发**：后端向 B 的 Socket 房间 `user_{B}` 发送 `call_invitation` 事件。
- **监听**：`ChatMainScreen` 的 body 中有 **`_CallInvitationListener`**，挂载时向 `SocketProvider` 注册 `addListener`，并在挂载后立即执行一次 `_onSocketProviderChanged()`，避免邀请在监听前到达而漏显。
- **逻辑**：`SocketProvider.lastCallInvitation` 被置位后 `notifyListeners()`，`_onSocketProviderChanged` 读取邀请、去重、清空后调 `_showInvitationDialog(invitation)`，弹出 **AlertDialog**：标题「视频通话邀请」，内容「{caller} 邀请您进入视频通话，可共享屏幕」，按钮「拒绝」「接受」。
- **接受**：发送 `call_invitation_response`（accepted: true），然后 `JitsiService.instance.joinRoom(roomId, userName)` 进入通话。
- **拒绝**：仅发送 `call_invitation_response`（accepted: false）。

### 3. 会话内系统消息（折中方案：双方都以「进入房间」为主入口）

- **来源**：主叫发 `call_invitation` 后，后端落库一条 `message_type=system`、带 `extra_data.call_invitation` 的消息，并向 **A**、**B** 的 Socket 房间各发一条 `message` 事件；同时向 A 发 `call_invitation_sent`（含 `system_message`），供主叫写入会话。
- **文案**：`📹 {caller_name} 邀请您进行视频通话，点击下方「进入房间」加入。`，明确以聊天内按钮为入口。
- **展示**：`ChatMessageList` 中 `message_type == 'system'` 时用 **`SystemMessageWidget`** 展示；`getCallInvitation(message)` 能从消息顶层或 `extra_data` 取到 `room_id` 等。
- **按钮**  
  - **主叫（A）**：显示 **「进入房间」**，点击后直接 `JitsiService.instance.joinRoom`，不发送 response。  
  - **被叫（B）**：显示 **「进入房间」** + **「拒绝」**；点「进入房间」时发 response(accepted: true) 并进房，点「拒绝」只发 response(accepted: false)。
- **多语言**：`chat.enter_room`（进入房间）、`common.reject`（拒绝）等已在 zh_CN / en_US / zh_TW 配置。

---

## 数据流简图

```
A 点击「视频通话」
  → ChatVideoCallService.startVideoCall()
  → socket.sendEvent('call_invitation', { target_user_id: B, room_id, caller_name })
  → Navigator.push(RoomScreen)  // A 先进入房间页

后端 socketio call_invitation 处理
  → 落库 system 消息
  → emit('message', system_message_data) → user_{A}、user_{B}
  → emit('call_invitation', invitation_data) → user_{B}
  → emit('call_invitation_sent', { system_message }) → user_{A}

B 端
  → Socket 收到 'call_invitation' → lastCallInvitation + notifyListeners
  → _CallInvitationListener 弹窗（接受/拒绝）
  → Socket 收到 'message' → messageStream → ChatWindowScreen 若在与 A 的会话则插入系统消息（接受/拒绝）

A 端
  → Socket 收到 'message' 或 'call_invitation_sent' → 在与 B 的会话中插入系统消息（进入房间）
```

---

## 排查清单（若 B 收不到弹窗或双方看不到消息）

1. **B 是否已连 Socket**  
   登录后 `App._initializeApp()` 会调 `socketProvider.autoConnect()`；若 B 未登录或断线，收不到 `call_invitation`。

2. **B 是否在含 `_CallInvitationListener` 的页面**  
   弹窗只在 **ChatMainScreen** 下挂载的 `_CallInvitationListener` 中显示（消息/联系人/设置任一 tab，或已 push 到 ChatWindowScreen 时 ChatMainScreen 仍在栈下）。若 B 在登录页或其它不包含 ChatMainScreen 的 route，不会弹窗，但进入与 A 的会话后仍能看到系统消息并点「接受」。

3. **后端是否向 B 推送**  
   确认 `call_invitation` 中 `target_user_id` 为 B 的 id，且后端 `emit(..., room=f"user_{target_user_id}")`；服务端日志应有「已通过 Socket 发送系统消息（通话邀请）给用户 {B}」等。

4. **双方是否看到同一条系统消息**  
   - 主叫：通过 `message` 或 `call_invitation_sent.system_message` 写入当前会话；若主叫已在 Jitsi 页，返回会话后应看到带「进入房间」的消息。  
   - 被叫：通过 `message` 写入当前会话，展示「接受」「拒绝」。  
   若仍看不到，可查接口 `/chat/messages` 是否返回该条 `message_type=system`、含 `extra_data.call_invitation` 的消息；进入会话后 2s 延迟刷新会再拉一次历史。

5. **视频通话按钮是否可见**  
   在 **与某人的聊天窗口** 底部，点击右侧 **「+」**，菜单中应有「视频通话」；若没有，检查是否在群聊（当前仅点对点会发 `call_invitation`）或 `ChatInputBar` 的 `onStartVideoCall` 是否正确传入。

---

## 相关代码位置

| 功能           | 文件 |
|----------------|------|
| 视频通话按钮   | `mobile/lib/screens/chat/widgets/chat_input_bar.dart` |
| 发起邀请与跳转 | `mobile/lib/screens/chat/services/chat_video_call_service.dart` |
| 被叫弹窗监听   | `mobile/lib/screens/chat/chat_main_screen.dart`（`_CallInvitationListener`） |
| 会话内系统消息 | `mobile/lib/screens/chat/widgets/chat_message_list.dart`、`system_message_widget.dart` |
| Socket 事件    | `mobile/lib/providers/socket_provider.dart`（`call_invitation`、`message`、`call_invitation_sent`） |
| 后端邀请与推送 | `app/core/socketio.py`（`call_invitation`、落库、emit） |
