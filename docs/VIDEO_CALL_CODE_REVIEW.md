# 视频通话邀请功能代码审查

## 一、代码逻辑检查

### ✅ 1. 后端发送逻辑（`app/core/socketio.py`）

**函数**：`call_invitation`

**检查点**：
- ✅ 创建系统消息并落库，包含 `extra_data={'call_invitation': invitation_data}`
- ✅ 对方在线时，发送 `message` 事件（包含 `call_invitation` 和 `extra_data`）
- ✅ 发送 `call_invitation` 事件（用于弹窗）
- ✅ 类型转换：`target_user_id = int(raw_target)`

**关键代码**：
```python
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

**结论**：✅ 逻辑正确

---

### ✅ 2. 前端弹窗逻辑（`chat_main_screen.dart`）

**组件**：`_CallInvitationListener`

**检查点**：
- ✅ 在 `ChatMainScreen` 的 Stack 中使用（第 130 行）
- ✅ 监听 `SocketProvider.lastCallInvitation`
- ✅ 使用 `useRootNavigator: true` 显示弹窗
- ✅ 弹窗有「拒绝」和「接受」按钮
- ✅ 接受后调用 `JitsiService.instance.joinRoom`

**关键代码**：
```dart
final result = await showDialog<String>(
  context: context,
  barrierDismissible: false,
  useRootNavigator: true,  // ✅ 确保在最顶层
  builder: (ctx) => AlertDialog(...),
);
```

**结论**：✅ 逻辑正确

---

### ✅ 3. Socket 事件监听（`socket_provider.dart`）

**检查点**：
- ✅ `_socket!.on('call_invitation', ...)` 正确监听
- ✅ 更新 `_lastCallInvitation` 并 `notifyListeners()`
- ✅ `_socket!.on('message', ...)` 在 `onMessage` 中正确转发

**结论**：✅ 逻辑正确

---

### ✅ 4. 聊天记录系统消息接收（`chat_window_screen.dart`）

**函数**：`_subscribeToMessages`

**检查点**：
- ✅ 监听 `message` 事件
- ✅ 系统消息过滤：`isSystemMessage && isFromTargetToMe`
- ✅ 添加到 `_messages` 列表并排序

**关键代码**：
```dart
if (isSystemMessage && isFromTargetToMe) {
  // 系统消息：接收者是当前用户，发送者是目标用户（通话邀请）
  final messageId = message['id'] as int?;
  if (messageId != null) {
    final exists = _messages.any((msg) => msg['id'] == messageId);
    if (!exists) {
      setState(() {
        _messages.add(message);
        // 排序...
      });
    }
  }
}
```

**结论**：✅ 逻辑正确

---

### ✅ 5. 聊天记录系统消息显示（`chat_window_screen.dart`）

**函数**：ListView `itemBuilder`

**检查点**：
- ✅ 检查 `messageType == 'system'`
- ✅ 调用 `_getCallInvitation(message)` 解析邀请数据
- ✅ 使用 `_SystemMessageWidget` 显示，传入 `onAccept` 和 `onReject`

**关键代码**：
```dart
if (messageType == 'system') {
  final inv = _getCallInvitation(message);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: _SystemMessageWidget(
      message: message,
      onAccept: inv != null ? (...) : null,
      onReject: inv != null ? (...) : null,
    ),
  );
}
```

**结论**：✅ 逻辑正确

---

### ✅ 6. 邀请数据解析（`chat_window_screen.dart`）

**函数**：`_getCallInvitation`

**检查点**：
- ✅ 先检查顶层 `msg['call_invitation']`
- ✅ 再检查 `msg['extra_data']['call_invitation']`
- ✅ 返回 `Map<String, dynamic>?`

**关键代码**：
```dart
Map<String, dynamic>? _getCallInvitation(Map<String, dynamic> msg) {
  var v = msg['call_invitation'];
  if (v is Map) return Map<String, dynamic>.from(v);
  final ed = msg['extra_data'];
  if (ed is Map) {
    v = (ed as Map)['call_invitation'];
    if (v is Map) return Map<String, dynamic>.from(v);
  }
  return null;
}
```

**结论**：✅ 逻辑正确

---

### ✅ 7. 历史消息加载（`chat_window_screen.dart`）

**函数**：`_loadMessages`

**检查点**：
- ✅ API 返回的消息包含 `extra_data`（已在 `chat.py` 中修复）
- ✅ 系统消息过滤逻辑正确（已修复）
- ✅ 系统消息能正确显示在聊天记录中

**关键代码**：
```dart
// 系统消息：接收者是当前用户，发送者是目标用户（通话邀请）
if (isSystemMessage && isFromTargetToMe) {
  return true;
}
```

**结论**：✅ 逻辑正确（已修复）

---

## 二、数据流验证

### 场景：用户 A 发起视频通话给用户 B

#### 步骤 1：后端处理
```
1. 收到 call_invitation 事件
2. 创建系统消息（extra_data={'call_invitation': {...}}）
3. 发送 message 事件（包含 call_invitation 和 extra_data）
4. 发送 call_invitation 事件
```

#### 步骤 2：用户 B 的 App 接收

**弹窗路径**：
```
Socket call_invitation 事件
  → SocketProvider._socket.on('call_invitation')
  → _lastCallInvitation = data
  → notifyListeners()
  → _CallInvitationListener 监听 lastCallInvitation
  → showDialog(useRootNavigator: true)
  → ✅ 弹窗显示
```

**聊天记录路径**：
```
Socket message 事件（系统消息）
  → SocketProvider.onMessage
  → chat_window_screen._subscribeToMessages
  → 检查 isSystemMessage && isFromTargetToMe
  → 添加到 _messages
  → ListView 渲染
  → _getCallInvitation 解析
  → _SystemMessageWidget 显示按钮
  → ✅ 聊天记录中显示系统消息和按钮
```

---

## 三、潜在问题排查

### 问题 1：弹窗不显示

**可能原因**：
1. `call_invitation` 事件未收到
2. `SocketProvider.lastCallInvitation` 未更新
3. `_CallInvitationListener` 未正确监听

**检查方法**：
- 查看日志：`📹 收到 call_invitation 事件`
- 检查 Socket 连接状态
- 确认 `useRootNavigator: true` 已设置

### 问题 2：聊天记录中看不到系统消息

**可能原因**：
1. `message` 事件未收到
2. 系统消息过滤逻辑错误
3. `extra_data` 未正确解析

**检查方法**：
- 查看日志：`📨 收到 message 事件: type=system`
- 查看日志：`📹 收到系统消息（通话邀请）`
- 检查 `isSystemMessage && isFromTargetToMe` 条件
- 检查 `_getCallInvitation` 是否能解析到数据

### 问题 3：系统消息没有按钮

**可能原因**：
1. `_getCallInvitation` 返回 null
2. `extra_data` 格式错误

**检查方法**：
- 查看日志：`📹 渲染系统消息: hasInvitation=？`
- 查看日志：`✓ 从顶层 call_invitation 解析到邀请数据` 或 `✓ 从 extra_data.call_invitation 解析到邀请数据`
- 检查后端发送的 `extra_data` 格式

---

## 四、代码审查结论

### ✅ 所有关键逻辑都已正确实现

1. **后端**：正确创建系统消息并发送 Socket 事件
2. **弹窗**：正确监听 `call_invitation` 事件并显示
3. **聊天记录**：正确接收系统消息并显示按钮
4. **历史消息**：正确加载并显示系统消息

### ⚠️ 需要实际测试验证

虽然代码逻辑看起来正确，但需要实际测试来验证：
1. Socket 事件是否能正确传递
2. 数据格式是否匹配
3. UI 渲染是否正常

### 📋 测试建议

1. **使用调试日志**：已添加详细的 `debugPrint` 日志，可以通过 `adb logcat` 查看
2. **检查后端日志**：`tail -f /var/log/mop-backend.log | grep call_invitation`
3. **分步测试**：
   - 先测试弹窗（确保 Socket 事件能收到）
   - 再测试聊天记录（确保系统消息能显示）
   - 最后测试按钮功能（确保能加入通话）

---

## 五、如果测试失败

### 检查清单

1. **Socket 连接**：确认用户 B 的 Socket 已连接
2. **用户在线状态**：确认后端能正确识别用户 B 在线
3. **房间加入**：确认用户 B 已加入 `user_{user_id}` 房间
4. **数据格式**：确认后端发送的数据格式与前端期望一致
5. **日志输出**：查看所有调试日志，定位问题点

### 常见修复

如果弹窗不显示：
- 检查 `_CallInvitationListener` 是否在 `ChatMainScreen` 中
- 检查 `useRootNavigator: true` 是否设置

如果聊天记录中没有系统消息：
- 检查 `_subscribeToMessages` 是否被调用
- 检查系统消息过滤逻辑
- 检查 `extra_data` 是否正确传递
