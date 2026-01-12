# 部署检查清单

本文档列出了生产环境部署前的所有检查项，确保系统安全、稳定运行。

## 📋 部署前检查

### 1. 环境配置检查

#### 1.1 数据库配置
- [ ] PostgreSQL 数据库已创建并运行
- [ ] 数据库用户和密码已设置（**必须修改默认密码**）
- [ ] 数据库连接池配置合理（POOL_SIZE, MAX_OVERFLOW）
- [ ] 数据库备份策略已配置

#### 1.2 Redis 配置
- [ ] Redis 服务已启动
- [ ] Redis 密码已设置（**必须修改默认密码**）
- [ ] Redis 持久化已启用（appendonly yes）
- [ ] Redis 内存限制已配置

#### 1.3 环境变量配置
- [ ] `.env` 文件已创建（从 `env.example` 复制）
- [ ] 所有敏感配置已更新（**严禁使用默认值**）：
  - [ ] `JWT_SECRET_KEY` - 使用 `openssl rand -hex 32` 生成
  - [ ] `POSTGRES_PASSWORD` - 强密码
  - [ ] `REDIS_PASSWORD` - 强密码
  - [ ] `RSA_PRIVATE_KEY` - 真实 RSA 私钥
  - [ ] `RSA_PUBLIC_KEY` - 真实 RSA 公钥
  - [ ] `JITSI_APP_SECRET` - Jitsi JWT 签名密钥
- [ ] `DEBUG=false`（生产环境）
- [ ] `LOG_LEVEL=INFO` 或 `WARNING`

### 2. 安全配置检查

#### 2.1 JWT 配置
- [ ] JWT_SECRET_KEY 长度 >= 32 字符
- [ ] JWT 过期时间配置合理（ACCESS_TOKEN: 30分钟，REFRESH_TOKEN: 7天）
- [ ] JWT 算法使用 HS256

#### 2.2 RSA 密钥配置
- [ ] RSA 密钥对已生成（2048位或更高）
  ```bash
  openssl genrsa -out private_key.pem 2048
  openssl rsa -in private_key.pem -pubout -out public_key.pem
  ```
- [ ] 私钥已安全存储（**严禁提交到代码仓库**）
- [ ] 公钥已配置到客户端

#### 2.3 CORS 配置
- [ ] `CORS_ORIGINS` 仅包含允许的域名（**严禁使用 `*`**）
- [ ] `ALLOWED_HOSTS` 已配置生产域名

#### 2.4 SSL/TLS 配置
- [ ] HTTPS 证书已配置（Let's Encrypt 或其他）
- [ ] Nginx 反向代理已配置 SSL
- [ ] WebSocket (Socket.io) SSL 支持已配置

### 3. 数据库迁移检查

- [ ] 数据库迁移脚本已运行
  ```bash
  alembic upgrade head
  ```
- [ ] 所有表已创建（users, user_devices, user_data_payload, invitation_codes, rooms, room_participants）
- [ ] 索引已创建
- [ ] 外键约束已设置

### 4. 服务启动检查

#### 4.1 依赖安装
- [ ] Python 3.11+ 已安装
- [ ] 所有依赖已安装：`pip install -r requirements.txt`
- [ ] 虚拟环境已激活（推荐）

#### 4.2 服务启动
- [ ] 服务器可以正常启动
- [ ] 健康检查端点返回 200：`/health`
- [ ] API 文档可访问（开发环境）：`/docs`
- [ ] Socket.io 连接正常：`/socket.io/`

#### 4.3 日志配置
- [ ] 日志目录已创建：`logs/`
- [ ] 日志文件权限正确
- [ ] 日志轮转配置合理（10MB，保留7天）

### 5. 功能测试检查

#### 5.1 基础功能
- [ ] 用户注册功能正常
- [ ] 用户登录功能正常
- [ ] JWT Token 生成和验证正常
- [ ] Token 刷新功能正常

#### 5.2 核心功能
- [ ] 设备注册和管理正常
- [ ] 邀请码创建和验证正常
- [ ] 数据载荷上传正常（2000条限制）
- [ ] 二维码生成和验证正常
- [ ] 房间创建和管理正常
- [ ] Jitsi JWT Token 生成正常

#### 5.3 管理功能
- [ ] 管理员登录正常
- [ ] 用户管理功能正常
- [ ] 设备管理功能正常
- [ ] 封杀功能正常
- [ ] 系统消息发送正常（Socket.io）

#### 5.4 Socket.io 功能
- [ ] WebSocket 连接正常
- [ ] 心跳监测正常
- [ ] 在线状态同步正常
- [ ] 消息推送正常
- [ ] 系统指令下发正常

### 6. 性能检查

- [ ] 数据库连接池配置合理
- [ ] Redis 连接正常
- [ ] API 响应时间 < 500ms（正常情况）
- [ ] 并发连接测试通过
- [ ] Socket.io 连接数测试通过

### 7. 监控和日志

- [ ] 日志记录正常
- [ ] 错误日志可查看
- [ ] 系统监控已配置（可选）
- [ ] 告警机制已配置（可选）

### 8. 备份和恢复

- [ ] 数据库备份脚本已准备
- [ ] 备份策略已制定
- [ ] 恢复流程已测试

## 🚀 部署步骤

### 步骤1: 准备环境
```bash
# 1. 克隆代码
git clone <repository-url>
cd MOP

# 2. 创建虚拟环境
python -m venv venv
source venv/bin/activate  # Linux/Mac
# 或
venv\Scripts\activate  # Windows

# 3. 安装依赖
pip install -r requirements.txt
```

### 步骤2: 配置环境变量
```bash
# 1. 复制环境变量模板
cp env.example .env

# 2. 编辑 .env 文件，修改所有敏感配置
# 特别注意：
# - JWT_SECRET_KEY
# - POSTGRES_PASSWORD
# - REDIS_PASSWORD
# - RSA_PRIVATE_KEY
# - RSA_PUBLIC_KEY
# - JITSI_APP_SECRET
```

### 步骤3: 启动数据库服务
```bash
# 使用 Docker Compose 启动 PostgreSQL 和 Redis
docker-compose up -d postgres redis

# 等待服务就绪
docker-compose ps
```

### 步骤4: 运行数据库迁移
```bash
# 运行 Alembic 迁移
alembic upgrade head

# 验证表已创建
# 可以连接到数据库检查
```

### 步骤5: 创建管理员账户
```bash
# 运行创建测试账户脚本（会创建管理员账户）
python scripts/create_test_accounts.py
```

### 步骤6: 启动应用
```bash
# 开发环境
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 生产环境（使用 Gunicorn + Uvicorn Workers）
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### 步骤7: 配置 Nginx（生产环境）
```bash
# 1. 复制 Nginx 配置模板
cp docker/nginx/nginx.conf.example /etc/nginx/sites-available/mop

# 2. 修改配置中的域名和证书路径
# 3. 创建符号链接
ln -s /etc/nginx/sites-available/mop /etc/nginx/sites-enabled/

# 4. 测试配置
nginx -t

# 5. 重载 Nginx
systemctl reload nginx
```

### 步骤8: 运行测试
```bash
# 运行完整测试脚本
python scripts/test_all_apis_complete.py
```

## ⚠️ 安全注意事项

1. **敏感信息保护**
   - 所有密钥和密码必须从环境变量加载
   - `.env` 文件必须添加到 `.gitignore`
   - 生产环境密钥必须与开发环境不同

2. **网络安全**
   - 必须使用 HTTPS（WebRTC 要求）
   - CORS 配置必须限制允许的域名
   - 防火墙规则必须正确配置

3. **数据库安全**
   - 数据库用户权限最小化
   - 定期备份数据库
   - 使用强密码

4. **应用安全**
   - 生产环境关闭 DEBUG 模式
   - 关闭 API 文档（`docs_url=None`）
   - 启用请求速率限制（建议）

## 📝 部署后检查

- [ ] 所有 API 端点正常响应
- [ ] Socket.io 连接正常
- [ ] 日志记录正常
- [ ] 错误处理正常
- [ ] 性能满足要求
- [ ] 监控告警正常

## 🔧 故障排查

### 常见问题

1. **数据库连接失败**
   - 检查 PostgreSQL 是否运行
   - 检查连接配置是否正确
   - 检查网络连接

2. **Socket.io 连接失败**
   - 检查 Nginx WebSocket 配置
   - 检查 CORS 配置
   - 检查防火墙规则

3. **JWT Token 验证失败**
   - 检查 JWT_SECRET_KEY 是否一致
   - 检查 Token 是否过期
   - 检查 Token 格式是否正确

4. **RSA 加密失败**
   - 检查 RSA 密钥格式是否正确
   - 检查环境变量中的换行符转义

---

**最后更新**: 2026-01-10
**版本**: 1.0.0
