# 视频通话邀请功能测试检查清单

## 测试场景 1：App 在前台 - 弹窗 + 聊天记录

### 前置条件
- 用户 A 和用户 B 都已登录
- 用户 B 的 App 在前台，正在查看其他页面（不在与 A 的聊天窗口）

### 测试步骤
1. 用户 A 在与 B 的聊天窗口中点击「视频通话」按钮
2. 观察用户 B 的 App

### 预期结果

#### ✅ 弹窗应该显示
- **触发时机**：后端发送 `call_invitation` Socket 事件
- **监听位置**：`chat_main_screen.dart` 中的 `_CallInvitationListener`
- **显示位置**：使用 `useRootNavigator: true`，应该在最顶层显示
- **内容**：标题「视频通话邀请」，内容「[A的名字] 邀请您进入视频通话，可共享屏幕」
- **按钮**：「拒绝」和「接受」

#### ✅ 聊天记录中应该显示系统消息
- **触发时机**：后端发送 `message` Socket 事件（系统消息）
- **监听位置**：`chat_window_screen.dart` 中的 `_subscribeToMessages`
- **显示位置**：当用户 B 打开与 A 的聊天窗口时，应该看到系统消息
- **内容**：「📹 [A的名字] 邀请您进行视频通话」
- **按钮**：系统消息下方有「拒绝」和「接受」按钮

---

## 测试场景 2：App 在前台 - 已在聊天窗口

### 前置条件
- 用户 A 和用户 B 都已登录
- 用户 B 的 App 在前台，**正在查看与 A 的聊天窗口**

### 测试步骤
1. 用户 A 在与 B 的聊天窗口中点击「视频通话」按钮
2. 观察用户 B 的 App

### 预期结果

#### ✅ 弹窗应该显示（同上）
- 即使正在查看聊天窗口，弹窗也应该显示在最顶层

#### ✅ 聊天记录中应该立即显示系统消息
- 系统消息应该**实时**出现在聊天记录中（不需要刷新）
- 应该能看到「📹 [A的名字] 邀请您进行视频通话」和按钮

---

## 测试场景 3：App 在后台或手机黑屏

### 前置条件
- 用户 A 和用户 B 都已登录
- 用户 B 的 App 在后台或手机已黑屏

### 测试步骤
1. 用户 A 在与 B 的聊天窗口中点击「视频通话」按钮
2. 观察用户 B 的手机

### 预期结果（需配置 FCM）

#### ✅ FCM 推送通知应该显示
- 手机应该收到推送通知（即使 App 在后台）
- 通知标题：「视频通话邀请」
- 通知内容：「[A的名字] 邀请您进行视频通话」
- 点击通知后应该显示全屏通话界面

#### ✅ 聊天记录中应该显示系统消息
- 当用户 B 打开 App 并查看与 A 的聊天窗口时
- 应该看到系统消息（从 API 历史消息中加载）
- 应该能看到「📹 [A的名字] 邀请您进行视频通话」和按钮

---

## 代码检查点

### 1. 后端发送逻辑

**文件**：`app/core/socketio.py` `call_invitation` 函数

检查点：
- ✅ 创建系统消息并落库（`extra_data={'call_invitation': invitation_data}`）
- ✅ 对方在线时，发送 `message` 事件（包含 `call_invitation` 和 `extra_data`）
- ✅ 发送 `call_invitation` 事件（用于弹窗）

**关键代码**：
```python
# 系统消息数据
system_message_data = {
    'id': created_msg_id,
    'sender_id': sender_id,
    'receiver_id': target_user_id,
    'message': system_message_text,
    'message_type': 'system',
    'call_invitation': invitation_data,  # 顶层
    'extra_data': {'call_invitation': invitation_data},  # extra_data 中也有
}
await sio.emit('message', system_message_data, room=f"user_{target_user_id}")
await sio.emit('call_invitation', invitation_data, room=f"user_{target_user_id}")
```

### 2. 前端弹窗逻辑

**文件**：`mobile/lib/screens/chat/chat_main_screen.dart` `_CallInvitationListener`

检查点：
- ✅ 监听 `SocketProvider.lastCallInvitation`
- ✅ 使用 `useRootNavigator: true` 显示弹窗
- ✅ 弹窗有「拒绝」和「接受」按钮

### 3. 前端聊天记录逻辑

**文件**：`mobile/lib/screens/chat/chat_window_screen.dart`

检查点：
- ✅ `_subscribeToMessages` 监听 `message` 事件
- ✅ 系统消息过滤：`isSystemMessage && isFromTargetToMe`
- ✅ `_getCallInvitation` 能正确解析 `call_invitation` 或 `extra_data.call_invitation`
- ✅ `_SystemMessageWidget` 正确显示按钮

### 4. 历史消息加载

**文件**：`mobile/lib/screens/chat/chat_window_screen.dart` `_loadMessages`

检查点：
- ✅ API 返回的消息包含 `extra_data`
- ✅ 系统消息过滤逻辑正确（已修复）
- ✅ `_getCallInvitation` 能从 `extra_data` 解析邀请数据

---

## 调试日志检查

### 发起视频通话时（用户 A）

查看日志应该看到：
```
📹 发送视频通话邀请: target_user_id=X, room_id=Y, caller_name=Z
📤 发送 Socket 事件: call_invitation, data: {...}
```

### 接收视频通话邀请时（用户 B）

#### 弹窗相关日志：
```
📹 收到 call_invitation 事件: {...}
✓ 已设置 lastCallInvitation，将触发弹窗
```

#### 聊天记录相关日志：
```
📨 收到 message 事件: type=system, id=XXX
📹 收到系统消息（通话邀请）: id=XXX, sender=X, receiver=Y, message=...
✓ 添加系统消息到聊天列表: id=XXX
📹 渲染系统消息: message=..., hasInvitation=true, inv={...}
✓ 从顶层 call_invitation 解析到邀请数据: room_id=...
```

---

## 常见问题排查

### 问题 1：弹窗不显示

**可能原因**：
1. `call_invitation` 事件未收到
2. `SocketProvider.lastCallInvitation` 未更新
3. `_CallInvitationListener` 未正确监听

**检查**：
- 查看日志是否有「收到 call_invitation 事件」
- 检查 Socket 连接状态
- 检查 `useRootNavigator: true` 是否设置

### 问题 2：聊天记录中看不到系统消息

**可能原因**：
1. `message` 事件未收到
2. 系统消息过滤逻辑错误
3. `extra_data` 未正确解析

**检查**：
- 查看日志是否有「收到 message 事件: type=system」
- 检查 `isSystemMessage && isFromTargetToMe` 条件
- 检查 `_getCallInvitation` 是否能解析到数据

### 问题 3：系统消息没有按钮

**可能原因**：
1. `_getCallInvitation` 返回 null
2. `extra_data` 格式错误

**检查**：
- 查看日志「渲染系统消息: hasInvitation=？」
- 检查后端发送的 `extra_data` 格式
- 检查 `_getCallInvitation` 的解析逻辑

---

## 测试命令

### 查看后端日志
```bash
tail -f /var/log/mop-backend.log | grep -i "call_invitation\|系统消息\|message.*user_"
```

### 查看 App 日志（通过 adb）
```bash
adb logcat | grep -i "call_invitation\|系统消息\|fcm\|推送"
```

---

## 预期行为总结

| 场景 | 弹窗 | 聊天记录系统消息 | 按钮 |
|------|------|----------------|------|
| App 在前台（不在聊天窗口） | ✅ 应该显示 | ✅ 打开聊天窗口后显示 | ✅ 有 |
| App 在前台（在聊天窗口） | ✅ 应该显示 | ✅ 实时显示 | ✅ 有 |
| App 在后台（需 FCM） | ⚠️ 需 FCM 推送 | ✅ 打开 App 后显示 | ✅ 有 |
