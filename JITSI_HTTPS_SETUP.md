# Jitsi HTTPS 配置指南

## 📋 配置概述

使用 `apiurl.chat5202ol.xyz` 作为 Jitsi Meet 的域名，通过 Nginx 反向代理提供 HTTPS 访问。

## ✅ 已完成的配置

1. **Jitsi 环境配置** (`jitsi.env`)
   - `JITSI_PUBLIC_URL=https://apiurl.chat5202ol.xyz`
   - `JITSI_JWT_ACCEPTED_AUDIENCES=https://apiurl.chat5202ol.xyz`
   - 禁用容器内 Let's Encrypt（由 Nginx 处理）

2. **后端配置** (`.env`)
   - `JITSI_SERVER_URL=https://apiurl.chat5202ol.xyz`

3. **Nginx 配置** (`/etc/nginx/sites-available/mop`)
   - 添加了 `apiurl.chat5202ol.xyz` 的 HTTP/HTTPS server 块
   - 配置反向代理到 `http://127.0.0.1:8080` (Jitsi 容器)
   - 配置了 Let's Encrypt 验证路径

## 🔧 待完成的步骤

### 步骤 1: 配置 DNS 解析

确保 DNS 解析已配置：
```
apiurl.chat5202ol.xyz → 89.223.95.18
```

验证 DNS 解析：
```bash
nslookup apiurl.chat5202ol.xyz
# 或
dig apiurl.chat5202ol.xyz +short
```

### 步骤 2: 申请 SSL 证书

确认 DNS 解析生效后，申请 Let's Encrypt 证书：

```bash
certbot certonly --webroot \
  -w /var/www/certbot \
  -d apiurl.chat5202ol.xyz \
  --email admin@chat5202ol.xyz \
  --agree-tos \
  --non-interactive
```

如果证书申请成功，证书文件将位于：
- `/etc/letsencrypt/live/apiurl.chat5202ol.xyz/fullchain.pem`
- `/etc/letsencrypt/live/apiurl.chat5202ol.xyz/privkey.pem`

### 步骤 3: 启用 Nginx SSL 配置

证书申请成功后，恢复 Nginx 配置中的 SSL 证书路径：

```bash
# 恢复 SSL 证书配置
sed -i 's|# ssl_certificate /etc/letsencrypt/live/apiurl.chat5202ol.xyz/fullchain.pem;|ssl_certificate /etc/letsencrypt/live/apiurl.chat5202ol.xyz/fullchain.pem;|' /etc/nginx/sites-available/mop
sed -i 's|# ssl_certificate_key /etc/letsencrypt/live/apiurl.chat5202ol.xyz/privkey.pem;|ssl_certificate_key /etc/letsencrypt/live/apiurl.chat5202ol.xyz/privkey.pem;|' /etc/nginx/sites-available/mop

# 测试配置
nginx -t

# 重新加载 Nginx
systemctl reload nginx
```

### 步骤 4: 重启 Jitsi 服务

重启 Jitsi 容器以应用新配置：

```bash
# 停止并删除现有容器
docker stop jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody
docker rm jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody

# 重新启动
cd /opt/mop
./scripts/start_jitsi.sh
```

### 步骤 5: 验证配置

1. **验证 HTTPS 访问**：
   ```bash
   curl -I https://apiurl.chat5202ol.xyz
   ```

2. **验证 Jitsi 服务**：
   ```bash
   docker ps --filter "name=jitsi"
   docker logs jitsi_web | tail -20
   ```

3. **测试房间访问**：
   访问：`https://apiurl.chat5202ol.xyz/test-room`

## 🔍 故障排查

### 问题 1: 证书申请失败

**原因**: DNS 解析未生效或网络问题

**解决**:
- 确认 DNS 解析：`nslookup apiurl.chat5202ol.xyz`
- 确认端口 80 可访问：`curl http://apiurl.chat5202ol.xyz/.well-known/acme-challenge/test`
- 检查防火墙：确保端口 80 和 443 开放

### 问题 2: Nginx 配置测试失败

**原因**: SSL 证书路径错误

**解决**:
- 确认证书文件存在：`ls -la /etc/letsencrypt/live/apiurl.chat5202ol.xyz/`
- 检查 Nginx 配置：`nginx -t`
- 查看错误日志：`tail -f /var/log/nginx/error.log`

### 问题 3: Jitsi 无法访问

**原因**: 容器未启动或端口映射错误

**解决**:
- 检查容器状态：`docker ps --filter "name=jitsi"`
- 检查端口映射：`docker port jitsi_web`
- 查看容器日志：`docker logs jitsi_web`

## 📝 配置说明

### 架构

```
用户 → HTTPS (443) → Nginx → HTTP (8080) → Jitsi Web 容器
```

- **外部访问**: `https://apiurl.chat5202ol.xyz` (HTTPS)
- **内部代理**: `http://127.0.0.1:8080` (HTTP)
- **SSL 终止**: Nginx 处理 SSL，Jitsi 容器使用 HTTP

### 端口说明

- **80/443**: Nginx 监听（外部访问）
- **8080**: Jitsi Web 容器（内部代理）
- **10000/udp**: Jitsi Videobridge（UDP，需要开放）
- **4443/tcp**: Jitsi Videobridge（TCP，需要开放）

## 🔐 安全注意事项

1. **防火墙配置**: 确保开放以下端口
   - 80 (HTTP，Let's Encrypt 验证)
   - 443 (HTTPS)
   - 10000/udp (Jitsi Videobridge)
   - 4443/tcp (Jitsi Videobridge)

2. **证书自动续期**: Let's Encrypt 证书有效期为 90 天
   - 证书会自动续期（如果配置了 cron）
   - 手动续期：`certbot renew`

3. **JWT 认证**: 确保后端和 Jitsi 的 JWT 配置一致
   - `JITSI_APP_ID` 必须一致
   - `JITSI_APP_SECRET` 必须一致

## 📚 相关文档

- [Jitsi 部署文档](./JITSI_DEPLOYMENT.md)
- [进入房间指南](./JOIN_ROOM_GUIDE.md)
- [WebRTC 问题解决](./WEBRTC_FIX.md)

---

**最后更新**: 2026-01-11
**状态**: ⚠️ 等待 DNS 解析和 SSL 证书申请
