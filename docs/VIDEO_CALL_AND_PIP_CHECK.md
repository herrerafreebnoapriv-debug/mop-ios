# 视频通话邀请与画中画实现检查

## 一、功能实现确认

### 1. 发起视频通话 → 对方收到弹窗 + 聊天记录系统消息（接受/拒绝）

| 环节 | 实现位置 | 状态 |
|------|----------|------|
| **后端：创建系统消息** | `app/core/socketio.py` `call_invitation` | ✅ 收到 `call_invitation` 后创建 `Message`（`message_type='system'`，`extra_data={'call_invitation': invitation_data}`）并落库 |
| **后端：推送给对方** | 同上 | ✅ 对方在线时：先 `emit('message', system_message_data, room=f"user_{target_user_id}")`，再 `emit('call_invitation', invitation_data, room=...)`；对方加入房间在连接时 `sio.enter_room(sid, f"user_{user_id}")` |
| **App：弹窗** | `chat_main_screen.dart` `_CallInvitationListener` | ✅ 监听 `SocketProvider.lastCallInvitation`，弹窗 `AlertDialog`（接受/拒绝），`useRootNavigator: true` 保证在最顶层 |
| **App：Socket 收 call_invitation** | `socket_provider.dart` | ✅ `_socket!.on('call_invitation', ...)` 写入 `_lastCallInvitation` 并 `notifyListeners()` |
| **App：聊天列表收到系统消息** | `chat_window_screen.dart` `_subscribeToMessages` | ✅ `onMessage` 回调里对点对点：若 `message_type == 'system'` 且 `receiver_id==当前用户`、`sender_id==目标用户`，则加入 `_messages` |
| **App：列表展示带按钮** | `chat_window_screen.dart` ListView + `_SystemMessageWidget` | ✅ `message_type == 'system'` 时用 `_SystemMessageWidget`，`_getCallInvitation(message)` 从 `message['call_invitation']` 或 `message['extra_data']['call_invitation']` 取数据，显示接受/拒绝按钮 |
| **历史消息带按钮** | API + 同上 | ✅ `get_messages` / `get_messages_since` 返回 `extra_data`（chat.py 已包含），打开会话拉历史后同样走 `_SystemMessageWidget` |

结论：**弹窗 + 聊天记录里带「接受/拒绝」的系统消息已实现。**

（发起方目前只发 `target_user_id`、`room_id`、`caller_name`；对方接受后通过 `POST /rooms/{room_id}/join` 拉取 Jitsi token，无需在邀请里带 token。）

---

### 2. 画中画（PiP）

| 环节 | 实现位置 | 状态 |
|------|----------|------|
| **Jitsi 启用 PiP** | `jitsi_service.dart` | ✅ `featureFlags['pip.enabled'] = true` |
| **进入 PiP** | `jitsi_service.dart` | ✅ `enterPiP()` 调用 `_jitsiMeet.enterPiP()` |
| **按返回键进 PiP 并关页** | `room_screen.dart` | ✅ `PopScope`：`onPopInvoked` 里若 `_inCall` 则 `await JitsiService.instance.enterPiP()`，再 `Navigator.pop`；含 try/catch 与短延迟 |

结论：**画中画逻辑已实现**（由 Jitsi SDK 在原生层实际进入 PiP）。

---

## 二、权限与依赖

### 视频通话邀请（弹窗 + 系统消息）

- **网络**：需联网，Socket 连接正常（已有 `INTERNET`、`ACCESS_NETWORK_STATE`）。
- **通知权限**：  
  - 弹窗不依赖系统通知权限，是应用内 `AlertDialog`。  
  - 若希望**应用在后台或进程被压后台时**仍能弹出“来电”界面，则需要：
    - 前台服务保活（你方已有 Socket 保活思路），以及
    - 在后台时用**系统通知 + 点击打开应用/全屏界面**来模拟“来电”，这才会用到**通知权限**（如 `POST_NOTIFICATIONS`）。  
  当前实现是**应用在前台或近期未被杀**时，Socket 收到 `call_invitation` 即弹窗，**不依赖通知权限**。
- **悬浮窗权限**：弹窗与聊天列表内系统消息均不依赖 `SYSTEM_ALERT_WINDOW`。

### 画中画（PiP）

- **Android 官方说明**：  
  - PiP 使用系统多窗口能力（Android 8.0+ 常见），**不需要** `SYSTEM_ALERT_WINDOW`（悬浮窗）。  
  - 不需要单独申请“画中画”权限，由应用在合适时机调用 `enterPictureInPictureMode()`（此处由 Jitsi SDK 封装）。
- **当前 manifest**：  
  - 未声明 `android:supportsPictureInPicture`；PiP 由 Jitsi 原生 Activity/View 处理，一般无需在主 Activity 声明。  
  - 若未来在 Flutter 主 Activity 自己实现 PiP，再考虑在对应 `<activity>` 加 `android:supportsPictureInPicture="true"`。

### 已有权限中与通话/体验相关的

- **相机 / 麦克风**：`CAMERA`、`RECORD_AUDIO` — 视频通话必需。
- **前台服务**：`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PROJECTION` — 保活/屏幕共享等。
- **悬浮窗**：`SYSTEM_ALERT_WINDOW` — 用于**屏幕共享**等能力，**不是**弹窗或 PiP 的必需条件。

---

## 三、总结

| 功能 | 是否实现 | 是否依赖通知权限 | 是否依赖悬浮窗权限 |
|------|----------|------------------|---------------------|
| 对方收到弹窗（接受/拒绝） | ✅ 是 | ❌ 否（仅前台/保活时） | ❌ 否 |
| 聊天记录系统消息带接受/拒绝按钮 | ✅ 是 | ❌ 否 | ❌ 否 |
| 画中画（按返回进 PiP） | ✅ 是 | ❌ 否 | ❌ 否 |

若需在**应用被切到后台或进程被回收后**仍能“来电提醒”，需要在此基础上增加：后台拉活/前台服务 + 系统通知（需 `POST_NOTIFICATIONS` 等） + 点击通知打开全屏来电界面，这属于增强项，不影响当前“弹窗 + 聊天记录按钮 + 画中画”的实现与权限结论。
