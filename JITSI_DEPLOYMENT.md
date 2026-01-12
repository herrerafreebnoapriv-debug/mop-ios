# Jitsi Meet Docker 自建部署指南

## 📋 概述

本指南用于部署自建的 Jitsi Meet Docker 集群，与后端 FastAPI 应用集成。

## 🎯 架构组件

1. **jitsi_web** - Jitsi Web 前端（用户界面）
2. **jitsi_prosody** - XMPP 服务器（信令）
3. **jitsi_jvb** - Videobridge（视频桥接）
4. **jitsi_jicofo** - Conference Focus（会议焦点）

## 🚀 快速部署

### 步骤 1: 配置环境变量

```bash
cd /opt/mop
cp jitsi.env.example jitsi.env
```

编辑 `jitsi.env`，设置以下关键配置：

```bash
# Jitsi 公共访问地址（必须配置）
JITSI_PUBLIC_URL=http://your-server-ip:8080
# 或使用域名：JITSI_PUBLIC_URL=https://jitsi.yourdomain.com

# JWT 配置（必须与后端 .env 一致）
JITSI_JWT_APP_ID=your_jitsi_app_id
JITSI_JWT_APP_SECRET=your_jitsi_app_secret_for_jwt_signing

# JWT 接受的 Issuer 和 Audience
JITSI_JWT_ACCEPTED_ISSUERS=your_jitsi_app_id
JITSI_JWT_ACCEPTED_AUDIENCES=http://your-server-ip:8080
```

### 步骤 2: 运行部署脚本

```bash
cd /opt/mop
./scripts/setup_jitsi.sh
```

脚本会自动：
- 创建配置目录
- 生成认证密码
- 拉取 Docker 镜像
- 启动所有服务

### 步骤 3: 配置后端

确保后端 `.env` 文件中的配置与 `jitsi.env` 一致：

```bash
# 后端 .env
JITSI_APP_ID=your_jitsi_app_id  # 必须与 jitsi.env 中的 JITSI_JWT_APP_ID 一致
JITSI_APP_SECRET=your_jitsi_app_secret_for_jwt_signing  # 必须与 jitsi.env 中的 JITSI_JWT_APP_SECRET 一致
JITSI_SERVER_URL=http://your-server-ip:8080  # 必须与 jitsi.env 中的 JITSI_PUBLIC_URL 一致
```

### 步骤 4: 验证部署

```bash
# 检查容器状态
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env ps

# 查看日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f

# 测试访问
curl http://your-server-ip:8080
```

## 🔧 手动部署

如果不想使用脚本，可以手动执行：

```bash
# 1. 创建配置目录
sudo mkdir -p /opt/jitsi-meet-cfg/{web,prosody,jvb,jicofo}
sudo chown -R 1000:1000 /opt/jitsi-meet-cfg

# 2. 配置环境变量（编辑 jitsi.env）

# 3. 启动服务
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d
```

## 📊 服务管理

### 启动服务
```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d
```

### 停止服务
```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env down
```

### 重启服务
```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env restart
```

### 查看日志
```bash
# 所有服务日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f

# 特定服务日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f jitsi_web
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f jitsi_prosody
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f jitsi_jvb
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f jitsi_jicofo
```

### 查看状态
```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env ps
```

## 🔐 安全配置

### JWT 认证（必须）

1. **启用认证**：`JITSI_ENABLE_AUTH=1`
2. **禁用访客**：`JITSI_ENABLE_GUESTS=0`
3. **认证类型**：`JITSI_AUTH_TYPE=jwt`
4. **JWT 配置**：必须与后端配置完全一致

### 端口配置

默认端口（可修改）：
- **HTTP**: 8080
- **HTTPS**: 8443
- **JVB UDP**: 10000
- **JVB TCP**: 4443
- **XMPP**: 5222

### 生产环境建议

1. **启用 HTTPS**：
   - 设置 `JITSI_DISABLE_HTTPS=0`
   - 配置 `JITSI_ENABLE_LETSENCRYPT=1`
   - 设置 `JITSI_LETSENCRYPT_DOMAIN` 和 `JITSI_LETSENCRYPT_EMAIL`

2. **使用域名**：
   - 设置 `JITSI_PUBLIC_URL=https://jitsi.yourdomain.com`
   - 配置 DNS 解析

3. **防火墙配置**：
   - 开放端口：80, 443, 10000/udp, 4443/tcp
   - 限制 XMPP 端口（5222）仅内网访问

## 🐛 故障排查

### 问题 1: 容器无法启动

```bash
# 检查日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs

# 检查配置目录权限
ls -la /opt/jitsi-meet-cfg
sudo chown -R 1000:1000 /opt/jitsi-meet-cfg
```

### 问题 2: JWT 认证失败

1. 检查 `jitsi.env` 和 `.env` 中的 JWT 配置是否一致
2. 检查 `JITSI_JWT_ACCEPTED_ISSUERS` 和 `JITSI_JWT_ACCEPTED_AUDIENCES`
3. 查看 prosody 日志：`docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs jitsi_prosody`

### 问题 3: 无法连接房间

1. 检查端口是否开放
2. 检查 `JITSI_PUBLIC_URL` 配置是否正确
3. 检查防火墙规则
4. 查看所有服务日志

### 问题 4: 视频/音频无法工作

1. 检查 UDP 端口 10000 是否开放
2. 检查 STUN 服务器配置
3. 检查网络连接

## 📝 配置说明

### 关键环境变量

| 变量 | 说明 | 必需 |
|------|------|------|
| `JITSI_PUBLIC_URL` | Jitsi 公共访问地址 | ✅ |
| `JITSI_JWT_APP_ID` | JWT App ID（与后端一致） | ✅ |
| `JITSI_JWT_APP_SECRET` | JWT App Secret（与后端一致） | ✅ |
| `JITSI_XMPP_DOMAIN` | XMPP 域名（内部使用） | ✅ |
| `JITSI_ENABLE_AUTH` | 启用认证（必须为 1） | ✅ |
| `JITSI_ENABLE_GUESTS` | 启用访客（必须为 0） | ✅ |

### 端口映射

| 容器端口 | 主机端口 | 协议 | 说明 |
|---------|---------|------|------|
| 80 | 8080 | TCP | HTTP |
| 443 | 8443 | TCP | HTTPS |
| 10000 | 10000 | UDP | JVB 视频 |
| 4443 | 4443 | TCP | JVB TCP |
| 5222 | 5222 | TCP | XMPP |

## 🔗 与后端集成

### 后端配置

后端 `.env` 文件必须配置：

```bash
JITSI_APP_ID=your_jitsi_app_id
JITSI_APP_SECRET=your_jitsi_app_secret_for_jwt_signing
JITSI_SERVER_URL=http://your-server-ip:8080  # 与 JITSI_PUBLIC_URL 一致
```

### 测试连接

1. 启动后端服务
2. 登录并创建房间
3. 点击"加入房间"
4. 应该能正常连接到 Jitsi 房间

## 📚 参考文档

- [Jitsi Docker 官方文档](https://github.com/jitsi/docker-jitsi-meet)
- [Jitsi JWT 配置](https://github.com/jitsi/docker-jitsi-meet/blob/master/ENV.md#authentication-using-json-web-tokens-jwt)
