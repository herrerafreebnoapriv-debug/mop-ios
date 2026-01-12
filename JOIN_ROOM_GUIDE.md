# 如何进入 Jitsi 房间

## 📋 概述

根据项目规范，所有房间访问必须通过后端签发的 JWT Token 进行授权。本文档说明如何进入 Jitsi 视频通话房间。

## 🚀 进入房间的步骤

### 方法 1: 已登录用户加入房间（推荐）

#### 步骤 1: 登录获取用户 Token

```bash
# 登录获取访问令牌
curl -X POST http://89.223.95.18:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "your_username",
    "password": "your_password"
  }'

# 响应示例：
# {
#   "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
#   "token_type": "bearer"
# }
```

#### 步骤 2: 创建或获取房间ID

```bash
# 创建新房间
curl -X POST http://89.223.95.18:8000/api/v1/rooms/create \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "room_name": "我的房间",
    "max_occupants": 10
  }'

# 响应示例：
# {
#   "room_id": "r-a1b2c3d4",
#   "room_name": "我的房间",
#   ...
# }
```

#### 步骤 3: 加入房间获取 Jitsi JWT Token

```bash
# 加入房间（返回 Jitsi JWT Token）
curl -X POST http://89.223.95.18:8000/api/v1/rooms/r-a1b2c3d4/join \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "display_name": "张三"
  }'

# 响应示例：
# {
#   "room_id": "r-a1b2c3d4",
#   "jitsi_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
#   "jitsi_server_url": "http://89.223.95.18:8080",
#   "room_url": "http://89.223.95.18:8080/r-a1b2c3d4"
# }
```

#### 步骤 4: 访问房间页面

使用返回的 `jitsi_token` 和 `jitsi_server_url` 访问房间：

```
http://89.223.95.18:8000/room/r-a1b2c3d4?jwt={jitsi_token}&server=http://89.223.95.18:8080
```

或者直接使用返回的 `room_url`（如果前端支持自动传递 JWT）。

---

### 方法 2: 通过二维码加入（无需登录）

#### 步骤 1: 获取房间二维码

```bash
# 获取房间二维码（需要房间创建者登录）
curl -X GET http://89.223.95.18:8000/api/v1/qrcode/room/r-a1b2c3d4 \
  -H "Authorization: Bearer {access_token}"

# 响应包含二维码图片和加密数据
```

#### 步骤 2: 扫描二维码获取加密数据

前端扫描二维码后，会得到 `encrypted_data`（加密的二维码数据）。

#### 步骤 3: 通过加密数据加入房间

```bash
# 通过二维码加入房间（无需登录）
curl -X POST http://89.223.95.18:8000/api/v1/rooms/join-by-qrcode \
  -H "Content-Type: application/json" \
  -d '{
    "encrypted_data": "{从二维码扫描得到的加密数据}",
    "display_name": "访客001"
  }'

# 响应示例：
# {
#   "room_id": "r-a1b2c3d4",
#   "jitsi_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
#   "jitsi_server_url": "http://89.223.95.18:8080",
#   "room_url": "http://89.223.95.18:8080/r-a1b2c3d4"
# }
```

#### 步骤 4: 访问房间页面

使用返回的 `jitsi_token` 访问房间：

```
http://89.223.95.18:8000/room/r-a1b2c3d4?jwt={jitsi_token}&server=http://89.223.95.18:8080
```

---

## 🔧 快速测试

### 使用测试账号快速测试

```bash
# 1. 登录（使用测试账号）
TOKEN=$(curl -s -X POST http://89.223.95.18:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"testpass"}' | jq -r '.access_token')

# 2. 创建房间
ROOM_ID=$(curl -s -X POST http://89.223.95.18:8000/api/v1/rooms/create \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"room_name":"测试房间"}' | jq -r '.room_id')

# 3. 加入房间获取 Jitsi Token
RESPONSE=$(curl -s -X POST http://89.223.95.18:8000/api/v1/rooms/$ROOM_ID/join \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"测试用户"}')

JITSI_TOKEN=$(echo $RESPONSE | jq -r '.jitsi_token')
JITSI_SERVER=$(echo $RESPONSE | jq -r '.jitsi_server_url')

# 4. 构建房间 URL
echo "房间 URL: http://89.223.95.18:8000/room/$ROOM_ID?jwt=$JITSI_TOKEN&server=$JITSI_SERVER"
```

---

## 📱 Web 页面访问

### 房间页面

访问房间页面时，需要提供以下 URL 参数：

- `jwt`: Jitsi JWT Token（必需）
- `server`: Jitsi 服务器地址（必需）

示例：
```
http://89.223.95.18:8000/room/r-a1b2c3d4?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...&server=http://89.223.95.18:8080
```

### 扫码加入页面

如果使用二维码方式，可以访问：

```
http://89.223.95.18:8000/scan-join
```

然后扫描房间二维码即可自动加入。

---

## ⚠️ 注意事项

1. **JWT Token 有效期**: Jitsi JWT Token 有效期为 60 分钟，过期后需要重新获取
2. **房间人数限制**: 每个房间有最大人数限制（默认 10 人），达到上限后无法加入
3. **房间状态**: 只有活跃状态的房间才能加入
4. **JWT 认证**: 自建 Jitsi 服务器强制启用 JWT 认证，没有有效 Token 无法进入房间
5. **服务器地址**: 必须使用自建服务器 `http://89.223.95.18:8080`，严禁使用官方服务器

---

## 🔍 故障排查

### 问题 1: 无法加入房间，提示 JWT 错误

**原因**: JWT Token 无效或过期

**解决**:
- 检查 Token 是否过期（有效期 60 分钟）
- 重新调用加入房间 API 获取新的 Token
- 确认后端 `.env` 中的 `JITSI_APP_ID` 和 `JITSI_APP_SECRET` 与 `jitsi.env` 一致

### 问题 2: 房间页面无法加载 Jitsi

**原因**: Jitsi 服务器地址配置错误

**解决**:
- 确认 `JITSI_SERVER_URL` 指向自建服务器 `http://89.223.95.18:8080`
- 检查 Jitsi 容器是否正常运行：`docker ps | grep jitsi`
- 检查端口是否开放：`curl http://89.223.95.18:8080`

### 问题 3: 提示房间不存在

**原因**: 房间ID错误或房间已被删除

**解决**:
- 确认房间ID格式正确（格式：`r-{8位16进制}`）
- 检查房间是否处于活跃状态
- 使用 API 查询房间信息：`GET /api/v1/rooms/{room_id}`

---

## 📚 相关 API 文档

- 房间 API: `/api/v1/rooms`
- 认证 API: `/api/v1/auth`
- 二维码 API: `/api/v1/qrcode`

更多详细信息请参考 API 文档或代码注释。
