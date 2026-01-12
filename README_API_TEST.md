# API 测试指南

## 启动应用

### 方法1：使用批处理文件（Windows）
```bash
start_server.bat
```

### 方法2：使用命令行
```powershell
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

### 方法3：直接运行
```powershell
python app/main.py
```

## 访问 API 文档

启动应用后，访问：
- **Swagger UI**: http://127.0.0.1:8000/docs
- **ReDoc**: http://127.0.0.1:8000/redoc
- **OpenAPI JSON**: http://127.0.0.1:8000/openapi.json

## API 端点

### 认证相关 API

#### 1. 用户注册
```bash
POST /api/v1/auth/register
Content-Type: application/json

{
  "phone": "13800138000",
  "username": "testuser",
  "password": "test123456",
  "nickname": "测试用户",
  "invitation_code": null
}
```

#### 2. 用户登录
```bash
POST /api/v1/auth/login
Content-Type: application/x-www-form-urlencoded

username=13800138000
password=test123456
```

**注意**: 登录接口使用 OAuth2 表单格式，`username` 字段可以是手机号或用户名。

#### 3. 获取当前用户信息
```bash
GET /api/v1/auth/me
Authorization: Bearer <access_token>
```

#### 4. 刷新令牌
```bash
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "<refresh_token>"
}
```

#### 5. 用户登出
```bash
POST /api/v1/auth/logout
Authorization: Bearer <access_token>
```

## 使用 Python requests 测试

```python
import requests

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

# 1. 注册
response = requests.post(
    f"{API_PREFIX}/auth/register",
    json={
        "phone": "13800138000",
        "username": "testuser",
        "password": "test123456",
        "nickname": "测试用户"
    }
)
print(response.json())

# 2. 登录
response = requests.post(
    f"{API_PREFIX}/auth/login",
    data={
        "username": "13800138000",  # 可以是手机号或用户名
        "password": "test123456"
    }
)
tokens = response.json()
access_token = tokens["access_token"]

# 3. 获取用户信息
response = requests.get(
    f"{API_PREFIX}/auth/me",
    headers={"Authorization": f"Bearer {access_token}"}
)
print(response.json())
```

## 使用 curl 测试（PowerShell）

```powershell
# 注册
$body = @{
    phone = "13800138000"
    username = "testuser"
    password = "test123456"
    nickname = "测试用户"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/auth/register" -Method POST -Body $body -ContentType "application/json"

# 登录
$formData = @{
    username = "13800138000"
    password = "test123456"
}

Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/auth/login" -Method POST -Body $formData
```

## 注意事项

1. **首次注册需要同意免责声明**: 注册后需要设置 `agreed_at` 字段才能登录
2. **数据库迁移**: 确保已运行 `alembic upgrade head` 创建数据库表
3. **数据库连接**: 确保 PostgreSQL 和 Redis 容器正在运行

## 故障排查

如果 API 返回 404：
1. 检查应用是否正在运行
2. 检查路由是否正确注册：访问 http://127.0.0.1:8000/docs 查看可用路由
3. 检查应用启动日志是否有错误
