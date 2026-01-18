# API 接口对齐修复总结

## 修复时间
2026-01-17 04:04

## 修复内容

### 1. 聊天 API 接口修复

#### 发送消息
- **修复前**: `/chat/send` (POST)
- **修复后**: `/chat/messages` (POST) - 与网页端一致
- **位置**: `mobile/lib/services/api/chat_api_service.dart`

#### 标记消息已读
- **修复前**: `/chat/mark-read` (POST)
- **修复后**: `/chat/messages/mark-read` (PUT) - 与网页端一致
- **位置**: `mobile/lib/services/api/chat_api_service.dart`

### 2. Socket.io 事件修复

#### 发送消息事件
- **修复前**: `{receiver_id, room_id, message, message_type, file_id}`
- **修复后**: `{message, type, target_user_id 或 room_id}` - 与网页端一致
- **位置**: `mobile/lib/providers/socket_provider.dart`

#### 消息事件监听
- **修复前**: `socket.on('new_message', callback)`
- **修复后**: `socket.on('message', callback)` - 与网页端一致
- **位置**: `mobile/lib/providers/socket_provider.dart`

#### 标记已读事件
- **新增**: `socket.emit('mark_message_read', {message_ids})` - 与网页端一致
- **位置**: `mobile/lib/providers/socket_provider.dart`

### 3. 好友 API 接口修复

#### 获取好友列表
- **修复前**: `/friends/list` (无参数)
- **修复后**: `/friends/list?status_filter=accepted` - 与网页端一致
- **位置**: 
  - `mobile/lib/services/api/friends_api_service.dart`
  - `mobile/lib/screens/chat/contacts_tab.dart`

#### 接受/拒绝好友请求
- **修复前**: `/friends/accept` 和 `/friends/reject` (POST)
- **修复后**: `/friends/update` (PUT) - 与网页端一致
- **位置**: `mobile/lib/services/api/friends_api_service.dart`

#### 删除好友
- **修复前**: `/friends/{friend_id}` (DELETE)
- **修复后**: `/friends/remove/{friend_id}` (DELETE) - 与网页端一致
- **位置**: `mobile/lib/services/api/friends_api_service.dart`

### 4. 消息处理逻辑修复

#### 消息列表顺序
- **修复**: 后端返回降序，前端反转成升序（与网页端一致）
- **位置**: `mobile/lib/screens/chat/chat_window_screen.dart`

#### 自动标记已读
- **新增**: 加载消息后自动标记未读消息为已读（与网页端一致）
- **位置**: `mobile/lib/screens/chat/chat_window_screen.dart`

#### Socket.io 消息监听
- **修复**: 支持 `sender_id` 和 `from_user_id` 兼容字段
- **位置**: `mobile/lib/screens/chat/chat_window_screen.dart`

## 接口对照表

| 功能 | 网页端 | 移动端（修复后） | 状态 |
|------|--------|------------------|------|
| 获取会话列表 | GET `/chat/conversations` | GET `/chat/conversations` | ✅ 一致 |
| 获取消息列表 | GET `/chat/messages` | GET `/chat/messages` | ✅ 一致 |
| 发送消息（API） | POST `/chat/messages` | POST `/chat/messages` | ✅ 已修复 |
| 发送消息（Socket） | `socket.emit('send_message')` | `socket.emit('send_message')` | ✅ 已修复 |
| 标记已读（API） | PUT `/chat/messages/mark-read` | PUT `/chat/messages/mark-read` | ✅ 已修复 |
| 标记已读（Socket） | `socket.emit('mark_message_read')` | `socket.emit('mark_message_read')` | ✅ 已修复 |
| 接收消息 | `socket.on('message')` | `socket.on('message')` | ✅ 已修复 |
| 获取好友列表 | GET `/friends/list?status_filter=accepted` | GET `/friends/list?status_filter=accepted` | ✅ 已修复 |
| 搜索用户 | GET `/friends/search?keyword=xxx` | GET `/friends/search?keyword=xxx` | ✅ 一致 |
| 添加好友 | POST `/friends/add` | POST `/friends/add` | ✅ 一致 |
| 接受好友 | PUT `/friends/update` | PUT `/friends/update` | ✅ 已修复 |
| 删除好友 | DELETE `/friends/remove/{id}` | DELETE `/friends/remove/{id}` | ✅ 已修复 |
| 修改密码 | POST `/users/me/change-password` | POST `/users/me/change-password` | ✅ 一致 |

## 数据格式对照

### Socket.io 发送消息格式
```javascript
// 网页端格式
{
  message: "消息内容",
  type: "text",
  target_user_id: 123,  // 点对点
  // 或
  room_id: 456  // 群聊
}

// 移动端格式（修复后）
{
  message: "消息内容",
  type: "text",
  target_user_id: 123,  // 点对点
  // 或
  room_id: 456  // 群聊
}
```

### Socket.io 接收消息格式
```javascript
// 网页端格式
{
  id: 123,
  sender_id: 456,
  receiver_id: 789,
  room_id: null,
  message: "消息内容",
  type: "text",
  message_type: "text",
  timestamp: "2026-01-17T04:00:00Z",
  created_at: "2026-01-17T04:00:00Z"
}

// 移动端格式（修复后）
// 支持 sender_id 和 from_user_id 兼容字段
// 支持 type 和 message_type 兼容字段
```

## 测试建议

1. **消息发送测试**
   - 点对点消息发送
   - 群聊消息发送
   - Socket.io 实时推送

2. **消息已读测试**
   - 自动标记已读
   - Socket.io 已读状态同步

3. **好友功能测试**
   - 获取好友列表（仅已接受）
   - 搜索用户
   - 添加好友
   - 接受/拒绝好友请求

---
**最后更新**: 2026-01-17 04:04
