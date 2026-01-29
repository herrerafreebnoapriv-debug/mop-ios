# Jitsi 视频通话配置验证

## ✅ 当前状态：已部署并正常使用

### 1. Jitsi 服务器状态

**容器运行状态**（已验证）：
- ✅ `jitsi_web` - 运行中（端口 8080/8443）
- ✅ `jitsi_prosody` - 运行中（XMPP 服务器）
- ✅ `jitsi_jvb` - 运行中（视频桥接，端口 10000 UDP, 4443 TCP）
- ✅ `jitsi_jicofo` - 运行中（会议焦点）

**服务器可访问性**：
- ✅ `https://apiurl.chat5202ol.xyz/external_api.js` - 返回 200 OK

### 2. 配置一致性

**后端配置**（`.env`）：
```bash
JITSI_SERVER_URL=https://apiurl.chat5202ol.xyz
JITSI_APP_ID=dev_jitsi_app_id
JITSI_APP_SECRET=dev_jitsi_app_secret_for_jwt_signing
```

**Jitsi 配置**（`jitsi.env`）：
```bash
JITSI_PUBLIC_URL=https://apiurl.chat5202ol.xyz
JITSI_JWT_APP_ID=dev_jitsi_app_id
JITSI_JWT_APP_SECRET=dev_jitsi_app_secret_for_jwt_signing
JITSI_XMPP_DOMAIN=meet.jitsi
```

✅ **配置一致**：后端和 Jitsi 使用相同的服务器地址和 JWT 凭证

### 3. 视频通话流程

#### 3.1 发起通话（`chat-calls.js`）
1. 用户点击"视频通话"
2. 调用 `POST /api/v1/rooms/{room_id}/join`
3. 后端返回：
   - `jitsi_token`（JWT）
   - `jitsi_server_url`（`https://apiurl.chat5202ol.xyz`）
   - `room_url`（包含 JWT 和 server 参数）

#### 3.2 打开房间页面（`room.html`）
1. 从 URL 参数获取：
   - `jwt` - JWT token
   - `server` - Jitsi 服务器地址（`https://apiurl.chat5202ol.xyz`）
2. 动态加载 `{server}/external_api.js`
3. 配置 Jitsi Meet：
   - `domain: 'meet.jitsi'`（XMPP 域名）
   - `websocket: 'wss://apiurl.chat5202ol.xyz/xmpp-websocket'`
   - `jwt: {jwt_token}`

#### 3.3 连接验证
- ✅ 使用自建 Jitsi 服务器（非官方 `meet.jit.si`）
- ✅ JWT 认证已启用
- ✅ WebSocket 连接指向自建服务器

### 4. 安全配置

**已禁用外链**：
- ✅ 无 Google STUN 服务器
- ✅ 无 Jitsi 官方 TURN 服务器
- ✅ 无第三方 CDN 或分析服务

**日志配置**：
- ✅ Docker 日志驱动：`none`（不存储日志）
- ✅ Jitsi 日志级别：`ERROR`（仅错误）
- ✅ 前端日志：仅 `error` 级别

### 5. 测试建议

#### 5.1 功能测试
1. **发起视频通话**：
   - 登录聊天页面
   - 选择联系人
   - 点击"视频通话"按钮
   - 验证房间页面正常打开

2. **加入房间**：
   - 验证 JWT 认证通过
   - 验证 WebSocket 连接成功
   - 验证音视频正常

3. **通话邀请**：
   - 验证 Socket.io 邀请发送成功
   - 验证被邀请方收到通知

#### 5.2 配置验证
```bash
# 检查 Jitsi 容器状态
docker ps --filter "name=jitsi"

# 检查服务器可访问性
curl -I https://apiurl.chat5202ol.xyz/external_api.js

# 检查后端配置
cd /opt/mop && python3 -c "from app.core.config import settings; print(settings.JITSI_SERVER_URL)"
```

### 6. 故障排查

#### 6.1 无法连接 Jitsi
- 检查 Jitsi 容器是否运行：`docker ps --filter "name=jitsi"`
- 检查服务器地址是否正确：`curl https://apiurl.chat5202ol.xyz/external_api.js`
- 检查防火墙/反向代理配置

#### 6.2 JWT 认证失败
- 验证 `.env` 和 `jitsi.env` 中的 `JITSI_APP_ID` 和 `JITSI_APP_SECRET` 一致
- 检查 JWT token 是否过期（默认 60 分钟）
- 查看浏览器控制台错误信息

#### 6.3 WebSocket 连接失败
- 检查 `room.html` 中的 `websocket` 配置是否正确
- 验证 Nginx/反向代理是否支持 WebSocket 升级
- 检查 Prosody 是否正常运行

### 7. 维护命令

```bash
# 重启 Jitsi 服务
cd /opt/mop
docker compose -f docker-compose.jitsi.yml --env-file jitsi.env restart

# 查看 Jitsi 日志（已禁用，但可通过容器查看）
docker logs jitsi_web --tail 50
docker logs jitsi_prosody --tail 50

# 清理日志并应用配置
./scripts/clear_jitsi_logs.sh --restart
```

---

**最后更新**：2026-01-24  
**状态**：✅ 已部署并正常使用
