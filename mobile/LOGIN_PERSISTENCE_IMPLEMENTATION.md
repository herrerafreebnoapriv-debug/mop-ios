# 登录状态持久化实现说明

## 概述

本文档说明移动端登录状态持久化的实现，确保即使在网络变化较大时仍能保持登录状态。

## 实现功能

### 1. Token 持久化存储

**实现位置：** `StorageService`

- **访问令牌（Access Token）**：保存在 SharedPreferences 中
- **刷新令牌（Refresh Token）**：保存在 SharedPreferences 中
- **用户ID**：保存在 SharedPreferences 中

**存储键名：**
- `access_token` - 访问令牌
- `refresh_token` - 刷新令牌
- `user_id` - 用户ID

### 2. 自动恢复登录状态

**实现位置：** `AuthProvider._loadAuthStatus()`

**功能：**
- 应用启动时自动从本地存储读取 token
- 如果 token 存在，自动验证并恢复用户信息
- 支持离线模式：网络不可用时保持登录状态

**流程：**
1. 应用启动时，`AuthProvider` 构造函数自动调用 `_loadAuthStatus()`
2. 从本地存储读取 token 和用户ID
3. 如果有 token，先设置登录状态为 true（不阻塞 UI）
4. 后台异步验证 token 并获取最新用户信息
5. 如果 token 过期，自动尝试刷新

### 3. Token 自动刷新机制

**实现位置：** `AuthProvider._tryRefreshToken()`

**功能：**
- 当访问 token 过期时，自动使用刷新 token 获取新的访问 token
- 刷新成功后自动更新本地存储
- 刷新失败时，只有在明确 token 无效时才清除登录状态

**策略：**
- 网络错误时保持登录状态（可能是临时网络问题）
- 只有在收到 401 Unauthorized 时才清除登录状态
- 支持多次重试

### 4. Socket.io 自动重连

**实现位置：** `SocketProvider`

**功能：**
- 自动重连机制：连接断开时自动尝试重连
- 网络状态监听：网络恢复时自动重连
- Token 更新支持：token 刷新后自动更新 Socket 连接

**重连策略：**
- 最大重连次数：10 次
- 重连延迟：3 秒
- 指数退避：重连延迟逐渐增加（1秒到5秒）

**网络监听：**
- 监听网络状态变化
- 网络恢复时自动尝试重连
- 网络断开时标记为未连接状态

### 5. 网络状态监听服务

**实现位置：** `NetworkService`

**功能：**
- 实时监听网络连接状态
- 支持 WiFi、移动数据、无网络等状态
- 提供网络状态变化回调

**使用场景：**
- Socket.io 连接管理
- API 请求重试
- 离线模式检测

## 使用流程

### 应用启动流程

```
1. main() 函数
   ├─ 初始化 SharedPreferences
   ├─ 初始化 NetworkService（开始监听网络状态）
   └─ 加载 AppConfig

2. AuthProvider 初始化
   ├─ 自动调用 _loadAuthStatus()
   ├─ 从本地存储读取 token
   ├─ 如果有 token，设置登录状态
   └─ 后台异步验证 token

3. AppMain 初始化
   ├─ 检查 AuthProvider 登录状态
   ├─ 如果已登录，自动连接 Socket.io
   └─ 根据登录状态显示相应页面
```

### 登录流程

```
1. 用户输入账号密码
2. 调用 AuthProvider.login()
3. 保存 token 到本地存储
4. 获取用户信息并保存
5. 设置登录状态为 true
6. 自动连接 Socket.io
```

### Token 刷新流程

```
1. API 请求返回 401
2. 自动调用 _tryRefreshToken()
3. 使用 refresh_token 获取新 token
4. 更新本地存储
5. 更新 Socket.io 连接（使用新 token）
6. 重试原请求
```

### Socket.io 重连流程

```
1. Socket 连接断开
2. 触发 onDisconnect 事件
3. 检查网络状态
4. 如果网络可用，安排重连（延迟3秒）
5. 执行重连
6. 如果失败，继续重试（最多10次）
```

## 关键代码说明

### AuthProvider 自动恢复

```dart
Future<void> _loadAuthStatus() async {
  final token = await StorageService.instance.getToken();
  _isAuthenticated = token != null && token.isNotEmpty;
  
  if (_isAuthenticated) {
    // 先设置登录状态（不阻塞 UI）
    _isAuthenticated = true;
    notifyListeners();
    
    // 后台验证 token
    _validateTokenInBackground(token!);
  }
}
```

### Token 刷新

```dart
Future<void> _tryRefreshToken() async {
  final refreshToken = await StorageService.instance.getRefreshToken();
  final result = await authApiService.refreshToken(refreshToken);
  
  if (result != null) {
    // 更新 token
    await StorageService.instance.saveToken(result.accessToken);
    // 重新获取用户信息
    final user = await _authApiService.getCurrentUser();
    // 更新状态
  }
}
```

### Socket.io 自动重连

```dart
void _setupEventHandlers() {
  _socket!.onDisconnect((_) {
    _isConnected = false;
    // 如果还有 token，尝试重连
    if (_currentToken != null && !_isReconnecting) {
      _scheduleReconnect(_currentToken!);
    }
  });
}
```

## 网络变化处理

### 场景 1：WiFi 切换到移动数据

1. NetworkService 检测到网络类型变化
2. Socket.io 连接可能短暂断开
3. 自动触发重连机制
4. 使用新网络重新连接

### 场景 2：网络完全断开

1. NetworkService 检测到无网络
2. Socket.io 标记为未连接
3. 保持登录状态（token 仍在本地）
4. 网络恢复时自动重连

### 场景 3：网络恢复

1. NetworkService 检测到网络恢复
2. 触发网络状态变化回调
3. SocketProvider 自动尝试重连
4. 如果 token 过期，自动刷新

## 离线模式支持

### 功能
- 登录状态在离线时保持
- Token 保存在本地，不依赖网络
- 网络恢复时自动同步状态

### 限制
- 无法进行需要网络的 API 调用
- Socket.io 连接断开
- 用户信息可能不是最新的

## 注意事项

1. **Token 过期处理**
   - 自动刷新机制确保 token 过期时自动更新
   - 只有在明确 token 无效时才清除登录状态

2. **网络错误处理**
   - 网络错误时不立即清除登录状态
   - 区分网络错误和认证错误

3. **重连限制**
   - Socket.io 重连有最大次数限制（10次）
   - 避免无限重连消耗资源

4. **用户体验**
   - 登录状态恢复不阻塞 UI
   - 后台异步验证和重连
   - 提供清晰的状态反馈

## 测试建议

### 测试场景

1. **应用重启**
   - 登录后关闭应用
   - 重新打开应用
   - 验证是否自动登录

2. **网络切换**
   - WiFi 切换到移动数据
   - 移动数据切换到 WiFi
   - 验证 Socket.io 是否自动重连

3. **网络断开**
   - 断开网络连接
   - 等待一段时间
   - 恢复网络连接
   - 验证是否自动重连

4. **Token 过期**
   - 模拟 token 过期（修改本地 token）
   - 触发 API 请求
   - 验证是否自动刷新 token

5. **长时间离线**
   - 断开网络
   - 等待较长时间（如1小时）
   - 恢复网络
   - 验证登录状态是否保持

## 后续优化建议

1. **Token 预刷新**
   - 在 token 即将过期前自动刷新
   - 避免请求时 token 已过期

2. **重连策略优化**
   - 根据网络质量调整重连延迟
   - 使用指数退避算法

3. **状态同步**
   - 网络恢复时同步用户信息
   - 检查是否有未读消息

4. **错误恢复**
   - 更智能的错误处理
   - 区分可恢复和不可恢复的错误

5. **性能优化**
   - 减少不必要的网络请求
   - 优化重连逻辑
