# 多端点管理和自动故障转移实现说明

## 概述

本文档说明移动端多IP/域名管理和自动故障转移的实现，确保在域名/IP失效时能够自动切换到备用端点，并支持远程更新端点列表。

> 📖 **详细部署和使用指南请参考：** [ENDPOINT_DEPLOYMENT_GUIDE.md](./ENDPOINT_DEPLOYMENT_GUIDE.md)

## 核心功能

### 1. 多端点管理

**实现位置：** `EndpointManager`

**功能：**
- 管理多个 API 端点列表
- 管理多个 Socket.io 端点列表
- 支持端点优先级设置
- 端点健康状态跟踪
- 响应时间记录

**端点信息：**
```dart
class EndpointInfo {
  final String url;           // 端点 URL
  final int priority;         // 优先级（数字越小优先级越高）
  final DateTime? lastChecked; // 最后检查时间
  final bool isHealthy;       // 是否健康
  final int failureCount;     // 失败次数
  final Duration? responseTime; // 响应时间
}
```

### 2. 健康检查机制

**实现方式：**
- 定期健康检查（每5分钟）
- 访问 `/health` 端点检查可用性
- 超时时间：5秒
- 失败阈值：连续失败3次后标记为不健康

**健康检查流程：**
1. 定时器每5分钟触发一次
2. 检查所有端点
3. 记录响应时间和健康状态
4. 自动选择最佳端点

### 3. 自动故障转移

**实现位置：** `ApiService._requestWithFailover()`

**功能：**
- API 请求失败时自动切换到备用端点
- 按优先级顺序尝试端点
- 网络错误时继续尝试下一个端点
- 标记失败的端点

**故障转移流程：**
1. 获取所有健康的端点
2. 按优先级排序
3. 依次尝试请求
4. 如果失败，标记端点并尝试下一个
5. 所有端点都失败时抛出异常

### 4. 远程端点更新

**实现方式：**
- 从远程服务器获取端点列表
- 支持备用 URL 获取配置
- 自动更新本地端点列表

**更新接口：**
```
GET /api/v1/config/endpoints

响应格式：
{
  "api_endpoints": [
    {"url": "https://api1.example.com", "priority": 0},
    {"url": "https://api2.example.com", "priority": 1}
  ],
  "socketio_endpoints": [
    {"url": "https://socket1.example.com", "priority": 0},
    {"url": "https://socket2.example.com", "priority": 1}
  ]
}
```

**更新时机：**
- 应用启动时（如果有备用 URL）
- 二维码扫描时
- 手动触发更新

### 5. Socket.io 多端点支持

**实现位置：** `SocketProvider._reconnect()`

**功能：**
- 连接失败时自动尝试其他端点
- 按优先级顺序尝试
- 连接成功后停止尝试

## 使用方式

### 1. 从二维码添加端点

```dart
// 二维码数据格式
{
  "api_url": "https://api.example.com",  // 单个端点（兼容旧格式）
  "api_endpoints": [                      // 多个端点（新格式）
    "https://api1.example.com",
    "https://api2.example.com"
  ],
  "socketio_url": "https://socket.example.com",
  "socketio_endpoints": [
    "https://socket1.example.com",
    "https://socket2.example.com"
  ]
}

// 自动添加到端点管理器
await AppConfig.instance.updateConfig(qrData);
```

### 2. 手动添加端点

```dart
// 添加 API 端点
await EndpointManager.instance.addApiEndpoint(
  'https://api.example.com',
  priority: 0,  // 优先级
);

// 添加 Socket.io 端点
await EndpointManager.instance.addSocketEndpoint(
  'https://socket.example.com',
  priority: 0,
);
```

### 3. 从远程更新端点

```dart
// 从备用 URL 获取端点列表
await EndpointManager.instance.updateEndpointsFromRemote(
  fallbackUrl: 'https://backup.example.com',
  token: 'your_token',  // 可选
);
```

### 4. 自动故障转移

**API 请求：**
```dart
// 自动使用最佳端点，失败时自动切换
final apiService = ApiService();
final result = await apiService.get('/users');
```

**Socket.io 连接：**
```dart
// 自动使用最佳端点，失败时自动切换
final socketProvider = SocketProvider();
await socketProvider.connect(token);
```

## 配置说明

### 健康检查配置

```dart
static const Duration _healthCheckInterval = Duration(minutes: 5);  // 检查间隔
static const Duration _healthCheckTimeout = Duration(seconds: 5);   // 超时时间
static const int _maxFailureCount = 3;  // 最大失败次数
```

### 重连配置

```dart
static const int _maxReconnectAttempts = 10;  // 最大重连次数
static const Duration _reconnectDelay = Duration(seconds: 3);  // 重连延迟
```

## 端点选择策略

### 优先级规则

1. **健康状态优先**：只选择健康的端点
2. **优先级排序**：数字越小优先级越高
3. **响应时间**：如果优先级相同，选择响应时间短的

### 故障处理

1. **网络错误**：继续尝试下一个端点
2. **认证错误**：直接抛出异常，不切换端点
3. **服务器错误**：标记端点失败，尝试下一个

## 数据持久化

### 存储位置

- **SharedPreferences**
  - `api_endpoints` - API 端点列表
  - `current_api_endpoint` - 当前使用的 API 端点
  - `socketio_endpoints` - Socket.io 端点列表
  - `current_socketio_endpoint` - 当前使用的 Socket.io 端点

### 数据格式

端点信息以 JSON 格式存储，包含：
- URL
- 优先级
- 最后检查时间
- 健康状态
- 失败次数
- 响应时间

## 后端接口要求

### 健康检查端点

```
GET /health

响应：200 OK（任何 2xx-4xx 状态码都视为健康）
```

### 端点配置端点

```
GET /api/v1/config/endpoints

请求头：
  Authorization: Bearer {token}  // 可选

响应：
{
  "api_endpoints": [
    {
      "url": "https://api1.example.com",
      "priority": 0
    },
    {
      "url": "https://api2.example.com",
      "priority": 1
    }
  ],
  "socketio_endpoints": [
    {
      "url": "https://socket1.example.com",
      "priority": 0
    },
    {
      "url": "https://socket2.example.com",
      "priority": 1
    }
  ]
}
```

## 使用场景

### 场景 1：主域名失效

1. 主域名 `api1.example.com` 失效
2. 健康检查检测到失败
3. 自动切换到备用域名 `api2.example.com`
4. 后续请求使用新域名

### 场景 2：网络切换

1. WiFi 网络切换到移动数据
2. 当前端点可能暂时不可达
3. 自动尝试其他端点
4. 找到可用端点后继续工作

### 场景 3：远程更新

1. 服务器端更新了端点列表
2. 客户端从备用 URL 获取新列表
3. 自动更新本地端点列表
4. 使用新的端点进行连接

### 场景 4：负载均衡

1. 配置多个相同优先级的端点
2. 根据响应时间选择最快的
3. 自动分散请求到不同端点

## 注意事项

1. **端点格式**
   - 必须包含协议（http:// 或 https://）
   - 不需要包含路径（如 /api/v1）

2. **优先级设置**
   - 数字越小优先级越高
   - 相同优先级时按响应时间选择

3. **健康检查**
   - 健康检查端点必须是 `/health`
   - 如果服务器没有健康检查端点，会标记为不健康

4. **故障恢复**
   - 不健康的端点会定期重新检查
   - 恢复健康后会自动使用

5. **兼容性**
   - 兼容旧的单端点配置方式
   - 新功能不影响现有功能

## 测试建议

### 测试场景

1. **单端点失效**
   - 配置多个端点
   - 手动断开主端点
   - 验证是否自动切换

2. **所有端点失效**
   - 断开所有端点
   - 验证错误处理

3. **端点恢复**
   - 断开端点后恢复
   - 验证是否自动使用恢复的端点

4. **远程更新**
   - 从远程获取端点列表
   - 验证是否更新成功

5. **优先级测试**
   - 配置不同优先级的端点
   - 验证是否按优先级选择

## 后续优化建议

1. **智能选择**
   - 根据网络类型选择端点
   - 根据地理位置选择最近的端点

2. **预检查**
   - 在请求前预检查端点健康状态
   - 减少失败请求

3. **统计信息**
   - 记录端点使用统计
   - 根据统计信息优化选择

4. **动态调整**
   - 根据成功率动态调整优先级
   - 自动降级频繁失败的端点
