# Jitsi Meet Docker 自建部署说明

## 📋 重要说明

**Jitsi Meet 是 Docker 自建的，部署在本服务器上，不是使用官方服务器。**

## 🎯 核心要求

1. **强制私有域**：严禁指向官方域名 `meet.jit.si`
2. **JWT 保护**：所有房间必须通过后端签发的 JWT Token 进行授权
3. **动态 Endpoint**：通过二维码扫码注入服务器地址

## 🔧 配置要求

### 环境变量配置

在 `.env` 文件中配置：

```bash
# Jitsi Meet 配置（Docker 自建）
JITSI_APP_ID=your_jitsi_app_id
JITSI_APP_SECRET=your_jitsi_app_secret_for_jwt_signing
JITSI_SERVER_URL=https://your-jitsi-domain.com  # 必须是自建服务器地址
JITSI_ROOM_MAX_OCCUPANTS=10
```

### Docker Compose 配置

参考 `docker-compose.jitsi.yml.example` 创建 `docker-compose.jitsi.yml`

关键配置：
- `ENABLE_AUTH=1` - 启用认证
- `JWT_APP_ID` - 必须与后端配置一致
- `JWT_APP_SECRET` - 必须与后端配置一致
- `JWT_ACCEPTED_ISSUERS` - 接受的后端 App ID
- `JWT_ACCEPTED_AUDIENCES` - 接受的服务器地址

## 📱 二维码扫描流程

### 网页版（浏览器扫描）
1. 用户使用浏览器或设备自带扫描功能扫描二维码
2. 获取加密的二维码数据
3. 访问 `/scan-join` 页面，粘贴二维码数据
4. 系统通过公开端点 `/api/v1/rooms/join-by-qrcode` 验证二维码
5. 生成临时 JWT Token（无需登录）
6. 跳转到房间页面，使用 JWT Token 加入 Jitsi 房间
7. **限制**：网页版无法共享屏幕（浏览器限制）

### App 扫描
1. App 扫描二维码
2. App 内部解密二维码（或调用后端验证）
3. App 已登录，直接调用 `/api/v1/rooms/{room_id}/join`
4. 获取 JWT Token 和房间信息
5. 使用 Jitsi SDK 加入房间
6. **完整功能**：支持音视频、共享屏幕等所有功能

## 🔐 安全机制

### 二维码加密
- 使用 RSA 私钥签名加密
- 包含房间ID和动态 Endpoint
- 扫描三次后自动失效

### JWT 授权
- 后端生成 JWT Token
- 包含用户信息、房间ID、权限等
- Jitsi 服务器验证 JWT 后允许加入

### 扫描次数限制
- 每个二维码最多扫描 3 次
- 达到上限后自动失效
- 防止二维码被无限分享

## 🌐 访问流程

### 方式1：从控制台加入（已登录用户）
1. 登录后进入控制台
2. 选择房间，点击"加入"
3. 系统生成 JWT Token
4. 跳转到房间页面

### 方式2：扫码加入（未登录用户）
1. 扫描房间二维码
2. 访问 `/scan-join` 页面
3. 粘贴二维码数据
4. 系统验证并生成临时 JWT Token
5. 跳转到房间页面

### 方式3：App 扫码（已登录 App）
1. App 扫描二维码
2. 自动验证并加入房间
3. 使用完整功能

## ⚠️ 注意事项

1. **HTTPS 强制**：WebRTC 需要 HTTPS 才能使用摄像头和麦克风
2. **JWT 配置一致**：后端和 Jitsi 的 JWT 配置必须完全一致
3. **服务器地址**：`JITSI_SERVER_URL` 必须是自建服务器的地址
4. **域名解析**：确保域名正确解析到 Jitsi 服务器

## 🐛 常见问题

### Q: 为什么网页版无法共享屏幕？
A: 浏览器安全限制，网页版 Jitsi 无法共享屏幕。需要使用 App 才能共享屏幕。

### Q: 二维码扫描后是否需要登录？
A: 
- 网页版：不需要登录，使用公开端点 `/api/v1/rooms/join-by-qrcode`
- App：需要登录，使用认证端点 `/api/v1/rooms/{room_id}/join`

### Q: 是否因为加密无法实现无客户端进房间？
A: **不是**。解密在后端完成（`/api/v1/qrcode/verify` 是公开端点）。问题是加入房间需要 JWT Token，网页版通过公开端点可以获取临时 JWT Token，无需登录。

## 📝 代码说明

### 公开端点（无需登录）
- `POST /api/v1/qrcode/verify` - 验证二维码
- `POST /api/v1/rooms/join-by-qrcode` - 通过二维码加入房间

### 认证端点（需要登录）
- `POST /api/v1/rooms/{room_id}/join` - 加入房间（记录参与者信息）
