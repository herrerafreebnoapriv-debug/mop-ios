# Jitsi 完全使用自部署域名配置

## ✅ 配置完成：完全使用自部署域名 `apiurl.chat5202ol.xyz`

### 1. 前端配置 (`static/room.html`)

**所有域名配置均使用自部署域名**：

```javascript
// 使用实际服务器域名（从 serverUrl 参数获取）
let serverHost = serverUrl.replace(/^https?:\/\//, '').replace(/\/$/, '');
// serverHost = 'apiurl.chat5202ol.xyz'

// Jitsi Meet API 的 domain 参数
options.domain = serverHost;  // apiurl.chat5202ol.xyz

// hosts.domain 配置（客户端连接使用）
options.configOverwrite.hosts.domain = serverHost;  // apiurl.chat5202ol.xyz

// WebSocket 连接地址
options.configOverwrite.websocket = 'wss://apiurl.chat5202ol.xyz/xmpp-websocket';

// BOSH 连接地址（备用）
options.configOverwrite.bosh = 'https://apiurl.chat5202ol.xyz/http-bind';
```

**关键点**：
- ✅ `domain` 使用实际域名（可解析）
- ✅ `hosts.domain` 使用实际域名（客户端连接）
- ✅ `websocket` 和 `bosh` 使用实际域名
- ✅ 不再使用内部域名 `meet.jitsi` 作为客户端配置

### 2. 后端配置 (`.env`)

```bash
JITSI_SERVER_URL=https://apiurl.chat5202ol.xyz
JITSI_APP_ID=dev_jitsi_app_id
JITSI_APP_SECRET=dev_jitsi_app_secret_for_jwt_signing
```

### 3. Jitsi 服务器配置 (`jitsi.env`)

```bash
# 公共访问地址（用于生成 JWT 和客户端连接）
JITSI_PUBLIC_URL=https://apiurl.chat5202ol.xyz

# XMPP 域名（Prosody 内部使用，不影响客户端）
JITSI_XMPP_DOMAIN=meet.jitsi
```

**说明**：
- `JITSI_PUBLIC_URL`：客户端访问的实际域名
- `JITSI_XMPP_DOMAIN`：Prosody 内部 XMPP 域名，客户端通过实际域名连接时，Prosody 会自动映射

### 4. 工作流程

1. **用户发起视频通话**：
   - 后端返回 `jitsi_server_url: https://apiurl.chat5202ol.xyz`
   - 房间 URL 包含 `server` 参数：`/room/{room_id}?jwt=...&server=https://apiurl.chat5202ol.xyz`

2. **打开房间页面**：
   - `room.html` 从 URL 获取 `server` 参数
   - 提取域名：`serverHost = 'apiurl.chat5202ol.xyz'`
   - 配置 Jitsi Meet：
     - `domain: 'apiurl.chat5202ol.xyz'`
     - `hosts.domain: 'apiurl.chat5202ol.xyz'`
     - `websocket: 'wss://apiurl.chat5202ol.xyz/xmpp-websocket'`

3. **连接 Jitsi 服务器**：
   - 客户端使用实际域名连接
   - Prosody 自动处理域名映射（实际域名 → 内部 XMPP 域名）
   - JWT 认证通过

### 5. 验证方法

#### 5.1 检查前端配置
```bash
# 检查 room.html 中的域名配置
grep -A 2 "options.domain = serverHost" /opt/mop/static/room.html
grep -A 2 "hosts.domain = serverHost" /opt/mop/static/room.html
```

#### 5.2 检查后端配置
```bash
# 检查后端 JITSI_SERVER_URL
grep "^JITSI_SERVER_URL=" /opt/mop/.env
```

#### 5.3 检查 Jitsi 服务器配置
```bash
# 检查 Jitsi PUBLIC_URL
grep "^JITSI_PUBLIC_URL=" /opt/mop/jitsi.env
```

#### 5.4 功能测试
1. 发起视频通话
2. 打开浏览器开发者工具（F12）
3. 检查 Network 标签：
   - WebSocket 连接应指向 `wss://apiurl.chat5202ol.xyz/xmpp-websocket`
   - 不应出现 `meet.jitsi` 的 DNS 解析请求
4. 检查 Console 标签：
   - 不应出现"找不到 meet.jitsi 的服务器 IP 地址"错误

### 6. 注意事项

1. **Prosody 内部域名**：
   - `JITSI_XMPP_DOMAIN=meet.jitsi` 是 Prosody 内部使用的
   - 客户端通过实际域名连接，Prosody 会自动映射
   - 无需修改 Prosody 配置

2. **DNS 解析**：
   - 确保 `apiurl.chat5202ol.xyz` 可以正常解析
   - 确保 SSL 证书有效

3. **防火墙/反向代理**：
   - 确保 `/xmpp-websocket` 和 `/http-bind` 路径可访问
   - 确保 WebSocket 升级请求正常

### 7. 故障排查

#### 7.1 仍提示"找不到 meet.jitsi"
- 检查浏览器缓存，硬刷新（Ctrl+Shift+R）
- 检查 `room.html` 中的 `hosts.domain` 是否已更新为 `serverHost`
- 检查浏览器控制台，查看实际使用的域名

#### 7.2 WebSocket 连接失败
- 检查 `websocket` 配置是否正确
- 检查 Nginx/反向代理是否支持 WebSocket
- 检查防火墙规则

#### 7.3 JWT 认证失败
- 检查 `JITSI_PUBLIC_URL` 是否与实际域名一致
- 检查 JWT token 中的 `aud` 字段是否匹配

---

**最后更新**：2026-01-24  
**状态**：✅ 完全使用自部署域名配置完成
