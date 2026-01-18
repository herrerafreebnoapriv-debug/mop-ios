# 💬 即时通讯功能访问指南

## 📍 访问方式

### 1. Web 界面访问（推荐）

#### 方式一：通过即时通讯专用域名访问 ⭐ **推荐**
- **聊天页面**: `https://log.chat5202ol.xyz/chat`
- **API 服务**: `https://log.chat5202ol.xyz/api/v1`
- **Socket.io**: `wss://log.chat5202ol.xyz/socket.io/`

#### 方式二：通过主域名访问
- **聊天页面**: `https://www.chat5202ol.xyz/chat`
- **管理员聊天页面**: `https://www.chat5202ol.xyz/chat_admin`（如果存在）

#### 方式三：通过 IP 直接访问（仅开发测试）
- **聊天页面**: `http://89.223.95.18:8000/chat`
- **管理员聊天页面**: `http://89.223.95.18:8000/chat_admin`（如果存在）

### 2. API 访问

#### 基础路径
- **即时通讯专用域名**: `https://log.chat5202ol.xyz/api/v1/chat`
- **主域名**: `https://www.chat5202ol.xyz/api/v1/chat`
- **API 服务域名**: `https://api.chat5202ol.xyz/api/v1/chat`

#### 主要 API 端点

##### 发送消息
```http
POST /api/v1/chat/messages
Content-Type: application/json
Authorization: Bearer {JWT_TOKEN}

{
  "receiver_id": 2,           // 点对点消息：接收者ID
  "room_id": null,            // 房间群聊：房间ID（与receiver_id二选一）
  "message": "你好，这是一条测试消息",
  "message_type": "text"      // text/image/file/audio/system
}
```

##### 获取消息列表
```http
GET /api/v1/chat/messages?page=1&limit=50&user_id=2&room_id=1
Authorization: Bearer {JWT_TOKEN}
```

##### 获取会话列表
```http
GET /api/v1/chat/conversations
Authorization: Bearer {JWT_TOKEN}
```

##### 标记消息为已读
```http
PUT /api/v1/chat/messages/mark-read
Content-Type: application/json
Authorization: Bearer {JWT_TOKEN}

{
  "message_ids": [1, 2, 3]
}
```

##### 获取聊天统计（仅超级管理员）
```http
GET /api/v1/chat/stats
Authorization: Bearer {JWT_TOKEN}
```

### 3. Socket.io 实时通讯

#### 连接地址
- **即时通讯专用域名（推荐）**: `wss://log.chat5202ol.xyz/socket.io/`
- **主域名**: `wss://www.chat5202ol.xyz/socket.io/`
- **API 服务域名**: `wss://api.chat5202ol.xyz/socket.io/`
- **开发环境**: `ws://89.223.95.18:8000/socket.io/`

#### 连接认证
连接时需要提供 JWT Token：
```javascript
// 使用即时通讯专用域名（推荐）
const socket = io('https://log.chat5202ol.xyz', {
  auth: {
    token: 'YOUR_JWT_TOKEN'
  }
});

// 或使用主域名
const socket = io('https://www.chat5202ol.xyz', {
  auth: {
    token: 'YOUR_JWT_TOKEN'
  }
});
```

#### 主要事件

##### 发送消息
```javascript
socket.emit('send_message', {
  target_user_id: 2,        // 点对点消息
  room_id: null,            // 房间群聊（与target_user_id二选一）
  message: '你好',
  type: 'text'
});
```

##### 接收消息
```javascript
socket.on('message', (data) => {
  console.log('收到消息:', data);
  // data: { id, sender_id, sender_nickname, message, message_type, created_at, ... }
});
```

##### 标记消息已读
```javascript
socket.emit('mark_message_read', {
  message_ids: [1, 2, 3]
});
```

##### 接收已读确认
```javascript
socket.on('message_read', (data) => {
  console.log('消息已读:', data);
  // data: { message_id, read_by, read_at }
});
```

##### 用户状态变化
```javascript
socket.on('user_status', (data) => {
  console.log('用户状态变化:', data);
  // data: { user_id, is_online, timestamp }
});
```

## 🔐 认证要求

### 1. Web 页面访问
- 需要先登录获取 JWT Token
- Token 存储在 localStorage 或 sessionStorage
- 页面会自动使用 Token 进行 API 调用

### 2. API 访问
- 所有 API 请求需要在 Header 中携带 JWT Token：
  ```
  Authorization: Bearer {JWT_TOKEN}
  ```

### 3. Socket.io 连接
- 连接时需要在 `auth` 参数中提供 Token
- 连接成功后会自动验证用户身份

## 📱 使用流程

### 步骤 1: 登录获取 Token
```bash
# 登录获取 JWT Token
curl -X POST http://89.223.95.18:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "phone_or_username": "your_phone_or_username",
    "password": "your_password"
  }'
```

### 步骤 2: 访问聊天页面
1. 打开浏览器访问 `https://log.chat5202ol.xyz/chat`（推荐）
   - 或访问 `https://www.chat5202ol.xyz/chat`
2. 如果未登录，会自动跳转到登录页面
3. 登录成功后会自动跳转回聊天页面

### 步骤 3: 使用聊天功能
- **查看会话列表**: 页面左侧显示所有会话
- **发送消息**: 在输入框中输入消息，点击发送
- **实时接收**: 通过 Socket.io 实时接收新消息
- **标记已读**: 查看消息后自动标记为已读

## 🛠️ 开发测试

### 使用 curl 测试 API

#### 发送消息
```bash
curl -X POST http://89.223.95.18:8000/api/v1/chat/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "receiver_id": 2,
    "message": "测试消息",
    "message_type": "text"
  }'
```

#### 获取会话列表
```bash
curl -X GET "http://89.223.95.18:8000/api/v1/chat/conversations" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

#### 获取消息列表
```bash
curl -X GET "http://89.223.95.18:8000/api/v1/chat/messages?page=1&limit=50" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### 使用 JavaScript 测试 Socket.io

```javascript
// 引入 Socket.io 客户端库
<script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>

// 连接 Socket.io
const socket = io('http://89.223.95.18:8000', {
  auth: {
    token: 'YOUR_JWT_TOKEN'
  }
});

// 监听连接成功
socket.on('connected', (data) => {
  console.log('连接成功:', data);
});

// 发送消息
socket.emit('send_message', {
  target_user_id: 2,
  message: '你好',
  type: 'text'
});

// 接收消息
socket.on('message', (data) => {
  console.log('收到消息:', data);
});
```

## 📋 功能特性

### ✅ 已实现功能
1. **点对点消息**: 用户之间的一对一聊天
2. **房间群聊**: 多人房间内的群组聊天
3. **消息历史**: 查询历史消息记录
4. **会话列表**: 查看所有会话（点对点和房间）
5. **未读消息**: 统计未读消息数量
6. **实时推送**: 通过 Socket.io 实时推送新消息
7. **消息已读**: 标记消息为已读状态
8. **在线状态**: 显示用户在线/离线状态
9. **权限控制**: 普通用户只能查看和操作自己的消息

### 🔒 权限说明
- **普通用户**: 
  - 只能查看和发送与自己相关的消息
  - 只能查看自己参与的会话
  - 只能标记接收者是自己的消息为已读
  
- **超级管理员**:
  - 可以查看所有消息和会话
  - 可以发送消息到任意房间
  - 可以查看聊天统计信息

## 🐛 常见问题

### Q: 无法连接到 Socket.io？
A: 检查以下几点：
1. JWT Token 是否有效
2. 服务器是否运行在正确的端口
3. 防火墙是否允许 WebSocket 连接
4. CORS 配置是否正确

### Q: 消息发送失败？
A: 检查以下几点：
1. JWT Token 是否过期
2. 接收者ID或房间ID是否正确
3. 是否有权限发送消息（房间参与者验证）
4. 消息内容是否符合要求（长度、格式等）

### Q: 无法看到会话列表？
A: 检查以下几点：
1. 是否已登录
2. Token 是否有效
3. 是否有相关的消息记录
4. 权限是否正确（普通用户只能看到自己的会话）

## 📞 技术支持

如有问题，请查看：
- API 文档: `http://89.223.95.18:8000/docs`
- 项目文档: 查看项目根目录下的文档文件

---

**最后更新**: 2026-01-12
