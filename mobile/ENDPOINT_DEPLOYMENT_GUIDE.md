# 多IP/域名自动故障转移部署和使用指南

## 目录

1. [概述](#概述)
2. [后端部署](#后端部署)
3. [前端配置](#前端配置)
4. [使用范例](#使用范例)
5. [测试验证](#测试验证)
6. [故障排查](#故障排查)

## 概述

多IP/域名自动故障转移机制允许移动端应用在主要服务器失效时自动切换到备用服务器，确保服务的高可用性。

### 核心功能

- ✅ 支持多个 API 端点配置
- ✅ 支持多个 Socket.io 端点配置
- ✅ 自动健康检查（每5分钟）
- ✅ 自动故障转移
- ✅ 远程端点更新
- ✅ 优先级管理

## 后端部署

### 1. 健康检查端点

所有服务器必须实现健康检查端点：

#### FastAPI 实现示例

```python
# app/main.py 或 app/api/v1/health.py

from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter()

@router.get("/health")
async def health_check():
    """
    健康检查端点
    返回 200 表示服务正常
    """
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "service": "mop-api",
            "version": "1.0.0"
        }
    )
```

#### 测试命令

```bash
# 测试健康检查端点
curl http://your-api-server.com/health

# 预期响应
{
  "status": "healthy",
  "service": "mop-api",
  "version": "1.0.0"
}
```

### 2. 端点配置接口（从文件读取）

实现端点配置接口，从文本文件读取域名和IP列表：

#### 配置文件格式

创建配置文件 `config/endpoints.txt`：

```
# 故障转移域名列表内容
DomainList:
log.ym1.com
ym2.xyz
xx,ym3.net

# 故障转移IP列表内容
IPList:
12.34.56.78
9.10.11.12
```

**文件格式说明：**
- 以 `#` 开头的行是注释
- `DomainList:` 标记域名列表开始
- `IPList:` 标记IP列表开始
- 每行一个域名或IP
- 支持逗号分隔的多个值（如：`xx,ym3.net`）

#### FastAPI 实现示例

```python
# app/api/v1/config.py

from fastapi import APIRouter, HTTPException
from pathlib import Path
from typing import List, Dict, Optional
import os

router = APIRouter()


def parse_endpoint_file(file_path: str) -> Dict[str, List[str]]:
    """
    解析端点配置文件
    """
    file_path_obj = Path(file_path)
    
    if not file_path_obj.exists():
        return {"domains": [], "ips": []}
    
    domains = []
    ips = []
    current_section = None
    
    try:
        with open(file_path_obj, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                # 跳过空行和注释行
                if not line or line.startswith('#'):
                    continue
                
                # 检查是否是节标记
                if line.lower().startswith('domainlist:'):
                    current_section = 'domains'
                    continue
                elif line.lower().startswith('iplist:'):
                    current_section = 'ips'
                    continue
                
                # 根据当前节解析内容
                if current_section == 'domains':
                    # 支持逗号分隔的多个域名
                    domain_items = [item.strip() for item in line.split(',')]
                    for item in domain_items:
                        if item:
                            domains.append(item)
                elif current_section == 'ips':
                    # 支持逗号分隔的多个IP
                    ip_items = [item.strip() for item in line.split(',')]
                    for item in ip_items:
                        if item:
                            ips.append(item)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"读取配置文件失败: {str(e)}"
        )
    
    return {
        "domains": domains,
        "ips": ips
    }


def convert_to_endpoints(
    domains: List[str],
    ips: List[str],
    protocol: str = "https",
    api_path: str = "/api/v1",
    socket_path: str = "",
    default_port: Optional[int] = None
) -> Dict[str, List[Dict[str, any]]]:
    """
    将域名和IP列表转换为端点配置格式
    """
    api_endpoints = []
    socketio_endpoints = []
    
    priority = 0
    
    # 处理域名
    for domain in domains:
        # 构建 API URL
        if default_port:
            api_url = f"{protocol}://{domain}:{default_port}{api_path}"
        else:
            api_url = f"{protocol}://{domain}{api_path}"
        
        api_endpoints.append({
            "url": api_url,
            "priority": priority
        })
        
        # 构建 Socket.io URL
        if socket_path:
            socket_url = f"{protocol}://{domain}{socket_path}"
        elif default_port:
            socket_url = f"{protocol}://{domain}:{default_port}"
        else:
            socket_url = f"{protocol}://{domain}"
        
        socketio_endpoints.append({
            "url": socket_url,
            "priority": priority
        })
        
        priority += 1
    
    # 处理IP
    for ip in ips:
        # 构建 API URL
        if default_port:
            api_url = f"{protocol}://{ip}:{default_port}{api_path}"
        else:
            api_url = f"{protocol}://{ip}{api_path}"
        
        api_endpoints.append({
            "url": api_url,
            "priority": priority
        })
        
        # 构建 Socket.io URL
        if socket_path:
            socket_url = f"{protocol}://{ip}{socket_path}"
        elif default_port:
            socket_url = f"{protocol}://{ip}:{default_port}"
        else:
            socket_url = f"{protocol}://{ip}"
        
        socketio_endpoints.append({
            "url": socket_url,
            "priority": priority
        })
        
        priority += 1
    
    return {
        "api_endpoints": api_endpoints,
        "socketio_endpoints": socketio_endpoints
    }


@router.get("/config/endpoints")
async def get_endpoints():
    """
    从配置文件读取端点列表
    
    配置文件路径：通过环境变量 ENDPOINT_CONFIG_FILE 指定
    默认路径：config/endpoints.txt
    """
    # 获取配置文件路径
    config_file = os.getenv(
        "ENDPOINT_CONFIG_FILE",
        "config/endpoints.txt"
    )
    
    # 协议配置（可通过环境变量配置）
    protocol = os.getenv("ENDPOINT_PROTOCOL", "https")
    api_path = os.getenv("ENDPOINT_API_PATH", "/api/v1")
    socket_path = os.getenv("ENDPOINT_SOCKET_PATH", "")
    default_port = os.getenv("ENDPOINT_DEFAULT_PORT")
    if default_port:
        try:
            default_port = int(default_port)
        except ValueError:
            default_port = None
    
    # 解析配置文件
    parsed = parse_endpoint_file(config_file)
    
    # 转换为端点配置格式
    config = convert_to_endpoints(
        parsed["domains"],
        parsed["ips"],
        protocol=protocol,
        api_path=api_path,
        socket_path=socket_path,
        default_port=default_port
    )
    
    return config
```

#### 环境变量配置

可以通过环境变量配置参数：

```bash
# 配置文件路径（默认：config/endpoints.txt）
export ENDPOINT_CONFIG_FILE="config/endpoints.txt"

# 协议（默认：https）
export ENDPOINT_PROTOCOL="https"

# API路径前缀（默认：/api/v1）
export ENDPOINT_API_PATH="/api/v1"

# Socket.io路径前缀（默认：空）
export ENDPOINT_SOCKET_PATH=""

# 默认端口（可选，如果URL中没有端口）
export ENDPOINT_DEFAULT_PORT=""
```

#### 配置文件示例

创建 `config/endpoints.txt`：

```
# 故障转移域名列表内容
DomainList:
log.ym1.com
ym2.xyz
xx,ym3.net

# 故障转移IP列表内容
IPList:
12.34.56.78
9.10.11.12
```

**解析结果：**
- 域名：`log.ym1.com`, `ym2.xyz`, `xx`, `ym3.net`
- IP：`12.34.56.78`, `9.10.11.12`

**生成的端点配置：**
```json
{
  "api_endpoints": [
    {"url": "https://log.ym1.com/api/v1", "priority": 0},
    {"url": "https://ym2.xyz/api/v1", "priority": 1},
    {"url": "https://xx/api/v1", "priority": 2},
    {"url": "https://ym3.net/api/v1", "priority": 3},
    {"url": "https://12.34.56.78/api/v1", "priority": 4},
    {"url": "https://9.10.11.12/api/v1", "priority": 5}
  ],
  "socketio_endpoints": [
    {"url": "https://log.ym1.com", "priority": 0},
    {"url": "https://ym2.xyz", "priority": 1},
    {"url": "https://xx", "priority": 2},
    {"url": "https://ym3.net", "priority": 3},
    {"url": "https://12.34.56.78", "priority": 4},
    {"url": "https://9.10.11.12", "priority": 5}
  ]
}
```

#### 配置文件位置

配置文件应放在项目根目录的 `config/` 目录下：

```
/opt/mop/
  ├── config/
  │   └── endpoints.txt
  ├── app/
  └── ...
```

#### 更新配置文件

更新端点列表时，只需修改 `config/endpoints.txt` 文件，然后重启服务或触发重新加载：

```bash
# 编辑配置文件
vim config/endpoints.txt

# 重启服务（如果使用 systemd）
sudo systemctl restart mop-api

# 或发送重载信号（如果支持热重载）
kill -HUP $(pidof python)
```

### 3. 注册路由

```python
# app/main.py

from fastapi import FastAPI
from app.api.v1 import health, config

app = FastAPI()

# 注册健康检查路由
app.include_router(health.router, tags=["health"])

# 注册配置路由
app.include_router(
    config.router,
    prefix="/api/v1",
    tags=["config"]
)
```

## 前端配置

### 1. 初始化端点管理器

端点管理器在应用启动时自动初始化：

```dart
// lib/main.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化端点管理器
  await EndpointManager.instance.init();
  
  runApp(const MOPApp());
}
```

### 2. 从二维码配置端点

#### 二维码数据格式

**单端点格式（兼容旧版本）：**

```json
{
  "api_url": "https://api.example.com",
  "socketio_url": "https://socket.example.com",
  "room_id": "room123"
}
```

**多端点格式（推荐）：**

```json
{
  "api_endpoints": [
    "https://api-primary.example.com",
    "https://api-backup1.example.com",
    "https://api-backup2.example.com"
  ],
  "socketio_endpoints": [
    "https://socket-primary.example.com",
    "https://socket-backup1.example.com"
  ],
  "room_id": "room123"
}
```

**带优先级的格式（最完整）：**

```json
{
  "api_endpoints": [
    {
      "url": "https://api-primary.example.com",
      "priority": 0
    },
    {
      "url": "https://api-backup1.example.com",
      "priority": 1
    },
    {
      "url": "https://api-backup2.example.com",
      "priority": 2
    }
  ],
  "socketio_endpoints": [
    {
      "url": "https://socket-primary.example.com",
      "priority": 0
    },
    {
      "url": "https://socket-backup1.example.com",
      "priority": 1
    }
  ],
  "room_id": "room123"
}
```

#### 扫描二维码示例

```dart
// lib/screens/qr/scan_screen.dart

import 'package:mop/core/config/app_config.dart';
import 'package:mop/services/qr/qr_scanner_service.dart';

class ScanScreen extends StatefulWidget {
  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _qrScanner = QRScannerService();
  
  Future<void> _handleQRCodeScan(Barcode barcode) async {
    try {
      // 解析二维码
      final qrData = await _qrScanner.processScanResult(barcode);
      
      // 更新配置（自动添加到端点管理器）
      await AppConfig.instance.updateConfig(qrData);
      
      // 显示成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('配置更新成功')),
      );
      
      // 返回上一页
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('配置更新失败: $e')),
      );
    }
  }
}
```

### 3. 手动添加端点

```dart
// 添加 API 端点
await EndpointManager.instance.addApiEndpoint(
  'https://api-new.example.com',
  priority: 0,  // 优先级，数字越小优先级越高
);

// 添加 Socket.io 端点
await EndpointManager.instance.addSocketEndpoint(
  'https://socket-new.example.com',
  priority: 0,
);
```

### 4. 从远程更新端点

```dart
// 从备用服务器获取端点列表
await EndpointManager.instance.updateEndpointsFromRemote(
  fallbackUrl: 'https://backup-config.example.com',
  token: 'your_access_token',  // 可选，如果需要认证
);
```

#### 完整示例

```dart
// lib/services/endpoint_update_service.dart

import 'package:mop/core/services/endpoint_manager.dart';
import 'package:mop/core/services/storage_service.dart';

class EndpointUpdateService {
  /// 自动更新端点列表
  static Future<bool> autoUpdateEndpoints() async {
    try {
      // 获取当前端点列表
      final currentEndpoints = EndpointManager.instance.apiEndpoints;
      
      // 如果有端点，尝试从第一个端点获取更新
      if (currentEndpoints.isNotEmpty) {
        final primaryUrl = currentEndpoints.first.url;
        final token = await StorageService.instance.getToken();
        
        await EndpointManager.instance.updateEndpointsFromRemote(
          fallbackUrl: primaryUrl,
          token: token,
        );
        
        return true;
      }
      
      // 如果没有端点，尝试从备用配置服务器获取
      const backupConfigUrl = 'https://config-backup.example.com';
      await EndpointManager.instance.updateEndpointsFromRemote(
        fallbackUrl: backupConfigUrl,
      );
      
      return true;
    } catch (e) {
      print('更新端点失败: $e');
      return false;
    }
  }
}
```

## 使用范例

### 范例 1：基本配置（单服务器）

**场景：** 只有一个服务器，不需要故障转移

**二维码内容：**

```json
{
  "api_url": "https://api.example.com",
  "socketio_url": "https://socket.example.com"
}
```

**使用方式：**

1. 扫描二维码
2. 应用自动配置端点
3. 所有请求使用该端点

### 范例 2：主备服务器配置

**场景：** 一个主服务器和一个备用服务器

**二维码内容：**

```json
{
  "api_endpoints": [
    "https://api-primary.example.com",
    "https://api-backup.example.com"
  ],
  "socketio_endpoints": [
    "https://socket-primary.example.com",
    "https://socket-backup.example.com"
  ]
}
```

**使用方式：**

1. 扫描二维码
2. 应用自动配置两个端点
3. 主服务器优先使用
4. 主服务器失效时自动切换到备用服务器

### 范例 3：多服务器负载均衡

**场景：** 多个服务器，根据响应时间选择最快的

**二维码内容：**

```json
{
  "api_endpoints": [
    {
      "url": "https://api-server1.example.com",
      "priority": 0
    },
    {
      "url": "https://api-server2.example.com",
      "priority": 0
    },
    {
      "url": "https://api-server3.example.com",
      "priority": 0
    }
  ]
}
```

**使用方式：**

1. 扫描二维码
2. 应用配置三个相同优先级的端点
3. 健康检查记录每个端点的响应时间
4. 自动选择响应时间最短的端点

### 范例 4：远程更新端点

**场景：** 服务器端更新了端点列表，客户端自动获取

**后端配置（/api/v1/config/endpoints）：**

```json
{
  "api_endpoints": [
    {
      "url": "https://api-new-primary.example.com",
      "priority": 0
    },
    {
      "url": "https://api-new-backup.example.com",
      "priority": 1
    }
  ],
  "socketio_endpoints": [
    {
      "url": "https://socket-new-primary.example.com",
      "priority": 0
    }
  ]
}
```

**前端代码：**

```dart
// 应用启动时自动更新
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化端点管理器
  await EndpointManager.instance.init();
  
  // 从远程更新端点（如果有备用配置服务器）
  await EndpointManager.instance.updateEndpointsFromRemote(
    fallbackUrl: 'https://config-backup.example.com',
  );
  
  runApp(const MOPApp());
}

// 或者在用户登录后更新
Future<void> updateEndpointsAfterLogin() async {
  final token = await StorageService.instance.getToken();
  final currentEndpoint = EndpointManager.instance.getCurrentApiUrl();
  
  if (currentEndpoint != null) {
    await EndpointManager.instance.updateEndpointsFromRemote(
      fallbackUrl: currentEndpoint,
      token: token,
    );
  }
}
```

### 范例 5：动态切换端点

**场景：** 用户手动切换端点或应用检测到性能问题自动切换

**代码示例：**

```dart
// 获取所有端点
final endpoints = EndpointManager.instance.apiEndpoints;

// 显示端点列表供用户选择
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('选择服务器'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: endpoints.map((endpoint) {
        return ListTile(
          title: Text(endpoint.url),
          subtitle: Text(
            '优先级: ${endpoint.priority}, '
            '状态: ${endpoint.isHealthy ? "健康" : "不健康"}'
          ),
          onTap: () {
            // 手动设置当前端点
            EndpointManager.instance._currentApiEndpoint = endpoint;
            Navigator.pop(context);
          },
        );
      }).toList(),
    ),
  ),
);
```

## 测试验证

### 1. 测试健康检查

```bash
# 测试主服务器
curl http://api-primary.example.com/health

# 测试备用服务器
curl http://api-backup.example.com/health
```

### 2. 测试端点配置接口

```bash
# 获取端点配置
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.example.com/api/v1/config/endpoints

# 预期响应
{
  "api_endpoints": [
    {
      "url": "https://api-primary.example.com",
      "priority": 0
    },
    {
      "url": "https://api-backup.example.com",
      "priority": 1
    }
  ],
  "socketio_endpoints": [
    {
      "url": "https://socket-primary.example.com",
      "priority": 0
    }
  ]
}
```

### 3. 测试故障转移

**步骤：**

1. 配置多个端点
2. 断开主服务器
3. 发起 API 请求
4. 验证是否自动切换到备用服务器

**测试代码：**

```dart
// test/endpoint_failover_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mop/core/services/endpoint_manager.dart';
import 'package:mop/services/api/api_service.dart';

void main() {
  test('测试故障转移', () async {
    // 添加多个端点
    await EndpointManager.instance.addApiEndpoint(
      'https://api-primary.example.com',
      priority: 0,
    );
    await EndpointManager.instance.addApiEndpoint(
      'https://api-backup.example.com',
      priority: 1,
    );
    
    // 模拟主服务器失效
    // （在实际测试中，可以停止主服务器或使用 Mock）
    
    // 发起请求
    final apiService = ApiService();
    final result = await apiService.get('/users');
    
    // 验证请求成功（应该使用备用服务器）
    expect(result, isNotNull);
    
    // 验证当前使用的端点
    final currentEndpoint = EndpointManager.instance.getCurrentApiUrl();
    expect(currentEndpoint, 'https://api-backup.example.com');
  });
}
```

### 4. 测试远程更新

```dart
// test/endpoint_update_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mop/core/services/endpoint_manager.dart';

void main() {
  test('测试远程更新端点', () async {
    // 初始端点
    await EndpointManager.instance.addApiEndpoint(
      'https://old-api.example.com',
      priority: 0,
    );
    
    // 从远程更新
    await EndpointManager.instance.updateEndpointsFromRemote(
      fallbackUrl: 'https://config-server.example.com',
    );
    
    // 验证端点已更新
    final endpoints = EndpointManager.instance.apiEndpoints;
    expect(endpoints.length, greaterThan(0));
    expect(endpoints.any((e) => e.url.contains('new')), isTrue);
  });
}
```

## 故障排查

### 问题 1：端点不切换

**可能原因：**
- 健康检查未启用
- 所有端点都标记为不健康
- 优先级设置错误

**解决方法：**

```dart
// 检查端点状态
final endpoints = EndpointManager.instance.apiEndpoints;
for (final endpoint in endpoints) {
  print('端点: ${endpoint.url}');
  print('健康状态: ${endpoint.isHealthy}');
  print('失败次数: ${endpoint.failureCount}');
  print('最后检查: ${endpoint.lastChecked}');
}

// 手动触发健康检查
await EndpointManager.instance.checkEndpointHealth(endpoints.first);

// 手动选择端点
await EndpointManager.instance._selectBestEndpoints();
```

### 问题 2：远程更新失败

**可能原因：**
- 网络连接问题
- 认证失败
- 服务器未实现端点配置接口

**解决方法：**

```dart
// 检查网络连接
final isConnected = await NetworkService.instance.checkConnectivity();
if (!isConnected) {
  print('网络未连接');
  return;
}

// 检查 token
final token = await StorageService.instance.getToken();
if (token == null) {
  print('未登录，无法获取端点配置');
  return;
}

// 尝试更新
try {
  await EndpointManager.instance.updateEndpointsFromRemote(
    fallbackUrl: 'https://config-server.example.com',
    token: token,
  );
} catch (e) {
  print('更新失败: $e');
  // 使用现有端点继续工作
}
```

### 问题 3：健康检查失败

**可能原因：**
- 服务器未实现 `/health` 端点
- 超时时间过短
- 网络问题

**解决方法：**

```dart
// 检查健康检查端点
final endpoint = EndpointManager.instance.currentApiEndpoint;
if (endpoint != null) {
  try {
    final dio = Dio();
    dio.options.connectTimeout = Duration(seconds: 5);
    final response = await dio.get('${endpoint.url}/health');
    print('健康检查成功: ${response.statusCode}');
  } catch (e) {
    print('健康检查失败: $e');
  }
}
```

## 最佳实践

### 1. 端点配置建议

- **主服务器优先级：** 0
- **备用服务器优先级：** 1, 2, 3...
- **至少配置 2 个端点**：确保高可用性
- **使用 HTTPS：** 确保安全性

### 2. 健康检查建议

- **检查间隔：** 5分钟（可调整）
- **超时时间：** 5秒
- **失败阈值：** 3次连续失败后标记为不健康

### 3. 远程更新建议

- **更新时机：** 应用启动时、用户登录后
- **备用配置服务器：** 建议配置一个独立的配置服务器
- **缓存策略：** 本地缓存端点列表，定期更新

### 4. 监控建议

- **监控端点健康状态**
- **记录端点切换日志**
- **统计端点使用情况**
- **告警机制：** 所有端点都失效时发送告警

## 总结

多IP/域名自动故障转移机制提供了：

1. ✅ **高可用性**：主服务器失效时自动切换
2. ✅ **负载均衡**：根据响应时间选择最快服务器
3. ✅ **远程更新**：服务器端更新端点列表，客户端自动获取
4. ✅ **健康监控**：定期检查端点健康状态
5. ✅ **优先级管理**：灵活配置端点优先级

通过合理配置和使用，可以显著提高应用的稳定性和可用性。
