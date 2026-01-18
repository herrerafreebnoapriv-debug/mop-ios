# 聊天功能测试指南

## 🧪 测试环境准备

### 1. 数据库检查
```bash
# 检查消息表是否存在
cd /opt/mop
python3 -c "
import asyncio
from app.db.session import get_db
from app.db.models import Message
from sqlalchemy import select, func

async def check():
    async for session in get_db():
        result = await session.execute(select(func.count(Message.id)))
        print(f'消息数: {result.scalar()}')
        break

asyncio.run(check())
"
```

### 2. 确保服务运行
```bash
# 检查后端服务是否运行
curl http://localhost:8000/health

# 检查Socket.io是否可用
# 访问 http://localhost:8000/socket.io/
```

---

## 📋 测试清单

### 测试1：API 端点测试

#### 1.1 获取消息列表（需要登录）
```bash
# 1. 登录获取Token
TOKEN=$(curl -X POST "http://localhost:8000/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"zhanan089","password":"your_password"}' \
  | jq -r '.access_token')

# 2. 获取消息列表
curl -X GET "http://localhost:8000/api/v1/chat/messages?page=1&limit=50" \
  -H "Authorization: Bearer $TOKEN"

# 3. 获取聊天统计
curl -X GET "http://localhost:8000/api/v1/chat/stats" \
  -H "Authorization: Bearer $TOKEN"

# 4. 获取会话列表
curl -X GET "http://localhost:8000/api/v1/chat/conversations" \
  -H "Authorization: Bearer $TOKEN"
```

#### 1.2 标记消息已读
```bash
# 标记消息为已读（需要消息ID）
curl -X PUT "http://localhost:8000/api/v1/chat/messages/mark-read" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message_ids": [1, 2, 3]}'
```

---

### 测试2：Socket.io 连接测试

#### 2.1 使用浏览器控制台测试

打开浏览器控制台，访问 `http://localhost:8000/chat`，执行：

```javascript
// 1. 连接Socket.io
const socket = io('/', {
    auth: { token: localStorage.getItem('access_token') }
});

// 2. 监听连接事件
socket.on('connect', () => {
    console.log('✅ Socket.io 连接成功');
});

socket.on('connected', (data) => {
    console.log('✅ 服务器确认连接:', data);
});

// 3. 监听消息
socket.on('message', (data) => {
    console.log('📨 收到消息:', data);
});

socket.on('message_read', (data) => {
    console.log('✅ 消息已读:', data);
});

// 4. 发送测试消息（点对点）
socket.emit('send_message', {
    target_user_id: 2,  // 目标用户ID
    message: '测试消息',
    type: 'text'
});

// 5. 标记消息已读
socket.emit('mark_message_read', {
    message_ids: [1, 2, 3]  // 消息ID列表
});
```

---

### 测试3：前端界面测试

#### 3.1 用户端聊天界面 (`/chat`)

**测试步骤：**
1. 访问 `http://localhost:8000/chat`
2. 使用超级管理员账号登录
3. 检查功能：
   - ✅ Socket.io 连接是否成功
   - ✅ 会话列表是否显示
   - ✅ 能否发送消息
   - ✅ 能否接收消息
   - ✅ 消息历史是否加载
   - ✅ 已读状态是否显示
   - ✅ 自动标记已读是否工作

**预期结果：**
- 左侧显示会话列表
- 点击会话后右侧显示聊天界面
- 发送消息后立即显示
- 接收消息后自动更新
- 滚动到底部时自动标记已读

#### 3.2 后台管理聊天页面 (`/static/chat_admin.html`)

**测试步骤：**
1. 访问 `http://localhost:8000/dashboard`
2. 点击"实时通讯"菜单按钮
3. 检查功能：
   - ✅ 统计卡片是否显示
   - ✅ 消息列表是否加载
   - ✅ 筛选功能是否正常
   - ✅ 标记已读功能是否正常
   - ✅ 会话列表是否显示

**预期结果：**
- 显示总消息数、未读消息等统计
- 消息列表可以筛选和分页
- 可以标记消息为已读
- 会话列表显示所有会话

---

### 测试4：点对点消息测试

#### 4.1 准备两个用户

**用户A（发送者）：**
- 用户名：`zhanan089`（超级管理员）
- ID：1

**用户B（接收者）：**
- 需要创建测试用户或使用现有用户
- ID：2

#### 4.2 测试流程

1. **用户A发送消息**
   ```javascript
   socket.emit('send_message', {
       target_user_id: 2,
       message: '你好，这是一条测试消息',
       type: 'text'
   });
   ```

2. **检查数据库**
   ```sql
   SELECT * FROM messages WHERE sender_id = 1 AND receiver_id = 2;
   ```

3. **用户B接收消息**
   - 用户B打开聊天界面
   - 应该能看到用户A发送的消息
   - 消息状态应为"未读"

4. **用户B标记已读**
   - 用户B打开消息
   - 自动或手动标记为已读
   - 用户A应该看到消息状态变为"已读"

---

### 测试5：房间群聊测试

#### 5.1 创建测试房间

```bash
# 创建房间
curl -X POST "http://localhost:8000/api/v1/rooms/create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "room_id": "test-room-001",
    "room_name": "测试房间",
    "max_occupants": 10
  }'
```

#### 5.2 加入房间

```bash
# 加入房间
curl -X POST "http://localhost:8000/api/v1/rooms/test-room-001/join" \
  -H "Authorization: Bearer $TOKEN"
```

#### 5.3 发送房间消息

```javascript
socket.emit('send_message', {
    room_id: 1,  // 房间ID（数据库ID，不是room_id字段）
    message: '这是房间消息',
    type: 'text'
});
```

#### 5.4 验证

- 房间内所有参与者都应该收到消息
- 消息应该保存到数据库，`room_id` 字段不为空

---

## 🐛 常见问题排查

### 问题1：Socket.io 连接失败

**检查：**
1. 后端服务是否运行
2. Nginx WebSocket 配置是否正确
3. CORS 配置是否正确
4. JWT Token 是否有效

**解决：**
```bash
# 检查后端日志
tail -f logs/app.log

# 检查Socket.io连接
# 浏览器控制台查看错误信息
```

### 问题2：消息未保存到数据库

**检查：**
1. 数据库连接是否正常
2. 消息表是否存在
3. 数据库迁移是否执行

**解决：**
```bash
# 检查数据库迁移状态
alembic current

# 如果迁移未执行
alembic upgrade head
```

### 问题3：消息已读状态不同步

**检查：**
1. Socket.io 事件是否正确监听
2. `mark_message_read` 事件是否触发
3. 数据库更新是否成功

**解决：**
- 检查浏览器控制台日志
- 检查后端日志
- 验证Socket.io事件名称是否正确

---

## ✅ 测试通过标准

### 功能测试
- [x] API 端点正常响应
- [x] Socket.io 连接成功
- [x] 消息可以发送和接收
- [x] 消息保存到数据库
- [x] 消息历史可以加载
- [x] 已读状态可以同步
- [x] 点对点消息正常
- [x] 房间群聊正常

### 界面测试
- [x] 用户端聊天界面正常显示
- [x] 后台管理页面正常显示
- [x] 响应式设计正常工作
- [x] 错误提示正常显示

### 性能测试
- [x] 消息发送延迟 < 100ms
- [x] 消息历史加载 < 1s
- [x] Socket.io 连接稳定

---

## 📊 测试结果记录

### 测试时间
- 开始时间：___________
- 结束时间：___________

### 测试结果
- API 测试：✅ / ❌
- Socket.io 测试：✅ / ❌
- 前端界面测试：✅ / ❌
- 点对点消息测试：✅ / ❌
- 房间群聊测试：✅ / ❌
- 已读状态同步：✅ / ❌

### 发现的问题
1. _________________________________
2. _________________________________
3. _________________________________

---

**文档版本**: v1.0  
**创建时间**: 2026-01-12  
**适用版本**: MOP v0112-0930+
