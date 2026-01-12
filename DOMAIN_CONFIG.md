# 域名配置说明

## 域名分配

根据项目需求，域名配置如下：

### 主域名
- **chat5202ol.xyz** → 89.223.95.18
  - 用途：主域名，可重定向到 www 或作为备用

### PC端网页版
- **www.chat5202ol.xyz** → 89.223.95.18
  - 用途：PC端网页版前端应用
  - 访问：https://www.chat5202ol.xyz

### API服务
- **api.chat5202ol.xyz** → 89.223.95.18
  - 用途：后端 API 服务
  - 访问：https://api.chat5202ol.xyz/api/v1

### 移动端应用
- **app.chat5202ol.xyz** → 89.223.95.18
  - 用途：移动端打包应用（保留用于移动端）
  - 访问：https://app.chat5202ol.xyz

## 配置更新

### 1. 环境变量配置 (.env)

已更新 `env.example` 文件，包含以下配置：

```bash
# CORS 允许的源（PC端网页版和移动端应用域名）
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,https://www.chat5202ol.xyz,https://app.chat5202ol.xyz,https://chat5202ol.xyz

# 允许的主机列表
ALLOWED_HOSTS=localhost,127.0.0.1,chat5202ol.xyz,www.chat5202ol.xyz,api.chat5202ol.xyz,app.chat5202ol.xyz

# Socket.io CORS 源
SOCKETIO_CORS_ORIGINS=http://localhost:3000,http://localhost:8080,https://www.chat5202ol.xyz,https://app.chat5202ol.xyz,https://chat5202ol.xyz
```

### 2. 前端页面配置

登录和注册页面已更新，支持自动检测 API 地址：

- 如果访问 `www.chat5202ol.xyz` 或 `app.chat5202ol.xyz`，自动使用 `https://api.chat5202ol.xyz/api/v1`
- 如果访问本地开发环境，使用相对路径 `/api/v1`

### 3. Nginx 配置

已更新 `docker/nginx/nginx.conf.example`，包含三个 server 块：

1. **api.chat5202ol.xyz** - API 服务
   - 代理所有 `/api/` 和 `/socket.io/` 请求到后端

2. **www.chat5202ol.xyz** - PC端网页版
   - 代理 API 请求到 `api.chat5202ol.xyz`
   - 提供静态文件和前端应用

3. **app.chat5202ol.xyz** - 移动端应用
   - 代理 API 请求到 `api.chat5202ol.xyz`
   - 提供移动端应用文件

## 部署说明

### 步骤1：更新 .env 文件

复制 `env.example` 到 `.env` 并确认域名配置：

```bash
cp env.example .env
# 编辑 .env 文件，确认 CORS_ORIGINS 和 ALLOWED_HOSTS 配置正确
```

### 步骤2：配置 SSL 证书

确保 SSL 证书支持以下域名：
- chat5202ol.xyz
- www.chat5202ol.xyz
- api.chat5202ol.xyz
- app.chat5202ol.xyz

可以使用通配符证书 `*.chat5202ol.xyz` 或 SAN 证书。

### 步骤3：配置 Nginx

1. 复制 Nginx 配置示例：
   ```bash
   cp docker/nginx/nginx.conf.example /etc/nginx/sites-available/mop
   ```

2. 根据实际部署情况修改配置：
   - 确认 SSL 证书路径
   - 确认后端服务地址
   - 确认静态文件路径

3. 启用配置：
   ```bash
   ln -s /etc/nginx/sites-available/mop /etc/nginx/sites-enabled/
   nginx -t
   systemctl reload nginx
   ```

### 步骤4：验证配置

1. **验证 API 服务**：
   ```bash
   curl https://api.chat5202ol.xyz/health
   ```

2. **验证 PC端网页版**：
   - 访问：https://www.chat5202ol.xyz/login
   - 检查 API 请求是否正常

3. **验证移动端应用**：
   - 访问：https://app.chat5202ol.xyz
   - 检查 API 请求是否正常

## 注意事项

1. **CORS 配置**：确保后端 `.env` 文件中的 `CORS_ORIGINS` 包含所有前端域名
2. **SSL 证书**：所有域名必须配置有效的 SSL 证书（HTTPS）
3. **DNS 解析**：确保所有域名的 A 记录都指向 89.223.95.18
4. **防火墙**：确保服务器防火墙允许 80 和 443 端口访问
5. **移动端打包**：`app.chat5202ol.xyz` 保留用于移动端应用打包，不要用于网页版

## 测试检查清单

- [ ] DNS 解析正确（所有域名指向 89.223.95.18）
- [ ] SSL 证书配置正确（所有域名支持 HTTPS）
- [ ] API 服务可访问（https://api.chat5202ol.xyz/health）
- [ ] PC端网页版可访问（https://www.chat5202ol.xyz/login）
- [ ] 移动端域名可访问（https://app.chat5202ol.xyz）
- [ ] CORS 配置正确（前端可以调用 API）
- [ ] WebSocket 连接正常（Socket.io）
- [ ] 登录/注册功能正常

---

**最后更新**：2026-01-10
**状态**：✅ 配置已完成，等待部署验证
