# 多端点配置快速参考示例

## 二维码配置示例

### 示例 1：单服务器（兼容旧版本）

```json
{
  "api_url": "https://api.example.com",
  "socketio_url": "https://socket.example.com",
  "room_id": "room123"
}
```

### 示例 2：主备服务器

```json
{
  "api_endpoints": [
    "https://api-primary.example.com",
    "https://api-backup.example.com"
  ],
  "socketio_endpoints": [
    "https://socket-primary.example.com",
    "https://socket-backup.example.com"
  ],
  "room_id": "room123"
}
```

### 示例 3：多服务器（带优先级）

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
      "url": "https://socket-backup.example.com",
      "priority": 1
    }
  ],
  "room_id": "room123"
}
```

### 示例 4：混合格式（兼容性最佳）

```json
{
  "api_url": "https://api-primary.example.com",
  "api_endpoints": [
    "https://api-primary.example.com",
    "https://api-backup.example.com"
  ],
  "socketio_url": "https://socket-primary.example.com",
  "socketio_endpoints": [
    "https://socket-primary.example.com",
    "https://socket-backup.example.com"
  ],
  "room_id": "room123"
}
```

## 后端配置示例

### 配置文件格式

创建 `config/endpoints.txt` 文件：

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

### FastAPI 健康检查端点

```python
# app/api/v1/health.py

from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter()

@router.get("/health")
async def health_check():
    """健康检查端点"""
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "service": "mop-api",
            "version": "1.0.0"
        }
    )
```

### FastAPI 端点配置接口（从文件读取）

```python
# app/api/v1/config.py

from fastapi import APIRouter, HTTPException
from pathlib import Path
from typing import List, Dict, Optional
import os

router = APIRouter()

def parse_endpoint_file(file_path: str) -> Dict[str, List[str]]:
    """解析端点配置文件"""
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
                
                if not line or line.startswith('#'):
                    continue
                
                if line.lower().startswith('domainlist:'):
                    current_section = 'domains'
                    continue
                elif line.lower().startswith('iplist:'):
                    current_section = 'ips'
                    continue
                
                if current_section == 'domains':
                    domain_items = [item.strip() for item in line.split(',')]
                    for item in domain_items:
                        if item:
                            domains.append(item)
                elif current_section == 'ips':
                    ip_items = [item.strip() for item in line.split(',')]
                    for item in ip_items:
                        if item:
                            ips.append(item)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"读取配置文件失败: {str(e)}"
        )
    
    return {"domains": domains, "ips": ips}

def convert_to_endpoints(
    domains: List[str],
    ips: List[str],
    protocol: str = "https",
    api_path: str = "/api/v1",
    socket_path: str = "",
    default_port: Optional[int] = None
) -> Dict[str, List[Dict[str, any]]]:
    """将域名和IP列表转换为端点配置格式"""
    api_endpoints = []
    socketio_endpoints = []
    priority = 0
    
    for domain in domains:
        api_url = f"{protocol}://{domain}{api_path}" if not default_port else f"{protocol}://{domain}:{default_port}{api_path}"
        socket_url = f"{protocol}://{domain}{socket_path}" if socket_path else (f"{protocol}://{domain}:{default_port}" if default_port else f"{protocol}://{domain}")
        
        api_endpoints.append({"url": api_url, "priority": priority})
        socketio_endpoints.append({"url": socket_url, "priority": priority})
        priority += 1
    
    for ip in ips:
        api_url = f"{protocol}://{ip}{api_path}" if not default_port else f"{protocol}://{ip}:{default_port}{api_path}"
        socket_url = f"{protocol}://{ip}{socket_path}" if socket_path else (f"{protocol}://{ip}:{default_port}" if default_port else f"{protocol}://{ip}")
        
        api_endpoints.append({"url": api_url, "priority": priority})
        socketio_endpoints.append({"url": socket_url, "priority": priority})
        priority += 1
    
    return {
        "api_endpoints": api_endpoints,
        "socketio_endpoints": socketio_endpoints
    }

@router.get("/config/endpoints")
async def get_endpoints():
    """从配置文件读取端点列表"""
    config_file = os.getenv("ENDPOINT_CONFIG_FILE", "config/endpoints.txt")
    protocol = os.getenv("ENDPOINT_PROTOCOL", "https")
    api_path = os.getenv("ENDPOINT_API_PATH", "/api/v1")
    socket_path = os.getenv("ENDPOINT_SOCKET_PATH", "")
    default_port = os.getenv("ENDPOINT_DEFAULT_PORT")
    if default_port:
        try:
            default_port = int(default_port)
        except ValueError:
            default_port = None
    
    parsed = parse_endpoint_file(config_file)
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

### 配置文件示例

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

**解析说明：**
- `#` 开头的行为注释
- `DomainList:` 标记域名列表开始
- `IPList:` 标记IP列表开始
- 每行一个或多个域名/IP（逗号分隔）
- 空行会被忽略

**解析结果：**
- 域名：`log.ym1.com`, `ym2.xyz`, `xx`, `ym3.net`
- IP：`12.34.56.78`, `9.10.11.12`

## 前端使用示例

### 扫描二维码配置

```dart
// lib/screens/qr/scan_screen.dart

import 'package:mop/core/config/app_config.dart';
import 'package:mop/services/qr/qr_scanner_service.dart';

Future<void> handleQRCodeScan(Barcode barcode) async {
  try {
    // 解析二维码
    final qrData = await QRScannerService.instance.processScanResult(barcode);
    
    // 更新配置（自动添加到端点管理器）
    await AppConfig.instance.updateConfig(qrData);
    
    print('配置更新成功');
  } catch (e) {
    print('配置更新失败: $e');
  }
}
```

### 手动添加端点

```dart
// 添加 API 端点
await EndpointManager.instance.addApiEndpoint(
  'https://api-new.example.com',
  priority: 0,
);

// 添加 Socket.io 端点
await EndpointManager.instance.addSocketEndpoint(
  'https://socket-new.example.com',
  priority: 0,
);
```

### 从远程更新端点

```dart
// 从备用服务器获取端点列表
await EndpointManager.instance.updateEndpointsFromRemote(
  fallbackUrl: 'https://config-backup.example.com',
  token: 'your_access_token',  // 可选
);
```

### 检查端点状态

```dart
// 获取所有端点
final apiEndpoints = EndpointManager.instance.apiEndpoints;
final socketEndpoints = EndpointManager.instance.socketEndpoints;

// 获取当前使用的端点
final currentApiUrl = EndpointManager.instance.getCurrentApiUrl();
final currentSocketUrl = EndpointManager.instance.getCurrentSocketUrl();

// 检查端点健康状态
for (final endpoint in apiEndpoints) {
  print('端点: ${endpoint.url}');
  print('健康状态: ${endpoint.isHealthy}');
  print('优先级: ${endpoint.priority}');
  print('失败次数: ${endpoint.failureCount}');
  print('响应时间: ${endpoint.responseTime?.inMilliseconds}ms');
}
```

### 监听端点变化

```dart
// 监听端点变化
EndpointManager.instance.onEndpointChanged = (endpoint) {
  print('端点已切换: ${endpoint.url}');
};

// 监听端点列表更新
EndpointManager.instance.onEndpointsUpdated = (endpoints) {
  print('端点列表已更新，共 ${endpoints.length} 个端点');
};
```

## 测试命令示例

### 测试健康检查

```bash
# 测试主服务器
curl http://api-primary.example.com/health

# 测试备用服务器
curl http://api-backup.example.com/health
```

### 测试端点配置接口

```bash
# 获取端点配置（无需认证）
curl https://api.example.com/api/v1/config/endpoints

# 获取端点配置（需要认证）
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.example.com/api/v1/config/endpoints
```

### 预期响应

```json
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

## 实际部署场景示例

### 场景 1：单服务器部署

**配置：**
```json
{
  "api_url": "https://api.example.com",
  "socketio_url": "https://socket.example.com"
}
```

**特点：**
- 简单配置
- 无故障转移
- 适合小型部署

### 场景 2：主备服务器部署

**配置：**
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

**特点：**
- 主服务器优先
- 主服务器失效时自动切换
- 适合中型部署

### 场景 3：多区域部署

**配置：**
```json
{
  "api_endpoints": [
    {
      "url": "https://api-beijing.example.com",
      "priority": 0
    },
    {
      "url": "https://api-shanghai.example.com",
      "priority": 1
    },
    {
      "url": "https://api-guangzhou.example.com",
      "priority": 2
    }
  ]
}
```

**特点：**
- 多区域部署
- 根据地理位置选择
- 适合大型部署

### 场景 4：负载均衡部署

**配置：**
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

**特点：**
- 相同优先级
- 根据响应时间选择
- 自动负载均衡

## 常见问题示例

### Q1: 如何添加新的端点？

**A:** 使用 `addApiEndpoint` 或 `addSocketEndpoint` 方法：

```dart
await EndpointManager.instance.addApiEndpoint(
  'https://api-new.example.com',
  priority: 1,
);
```

### Q2: 如何手动切换端点？

**A:** 目前不支持直接手动切换，但可以通过设置优先级来实现：

```dart
// 将目标端点优先级设为 0
await EndpointManager.instance.addApiEndpoint(
  'https://api-target.example.com',
  priority: 0,  // 最高优先级
);
```

### Q3: 如何清除所有端点？

**A:** 使用 `clearAll` 方法：

```dart
await EndpointManager.instance.clearAll();
```

### Q4: 如何查看当前使用的端点？

**A:** 使用 `getCurrentApiUrl` 或 `getCurrentSocketUrl` 方法：

```dart
final currentApiUrl = EndpointManager.instance.getCurrentApiUrl();
print('当前 API 端点: $currentApiUrl');
```

### Q5: 健康检查失败怎么办？

**A:** 检查以下几点：

1. 服务器是否实现了 `/health` 端点
2. 网络连接是否正常
3. 超时时间是否足够

```dart
// 手动触发健康检查
final endpoint = EndpointManager.instance.currentApiEndpoint;
if (endpoint != null) {
  final isHealthy = await EndpointManager.instance.checkEndpointHealth(endpoint);
  print('端点健康状态: $isHealthy');
}
```

## 最佳实践示例

### 1. 应用启动时初始化

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化存储
  final prefs = await SharedPreferences.getInstance();
  StorageService.instance.init(prefs);
  
  // 初始化网络监听
  NetworkService.instance.init();
  
  // 初始化端点管理器
  await EndpointManager.instance.init();
  
  // 从远程更新端点（可选）
  await EndpointManager.instance.updateEndpointsFromRemote(
    fallbackUrl: 'https://config-backup.example.com',
  );
  
  runApp(const MOPApp());
}
```

### 2. 登录后更新端点

```dart
Future<void> afterLogin() async {
  final token = await StorageService.instance.getToken();
  final currentEndpoint = EndpointManager.instance.getCurrentApiUrl();
  
  if (currentEndpoint != null && token != null) {
    // 从当前端点获取最新配置
    await EndpointManager.instance.updateEndpointsFromRemote(
      fallbackUrl: currentEndpoint,
      token: token,
    );
  }
}
```

### 3. 定期更新端点

```dart
// 每30分钟更新一次端点列表
Timer.periodic(Duration(minutes: 30), (timer) async {
  final token = await StorageService.instance.getToken();
  if (token != null) {
    await EndpointManager.instance.updateEndpointsFromRemote(
      fallbackUrl: 'https://config-backup.example.com',
      token: token,
    );
  }
});
```
