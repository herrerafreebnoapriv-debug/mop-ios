# 测试和部署指南

本文档提供了完整的测试和部署流程说明。

## 📋 快速开始

### 1. 部署前检查

运行部署准备脚本，检查所有必要条件：

```bash
python scripts/prepare_deployment.py
```

该脚本会检查：
- ✅ 环境变量文件配置
- ✅ 数据库连接
- ✅ Python 依赖安装
- ✅ Docker 服务运行状态
- ✅ 数据库迁移状态
- ✅ 日志目录权限

### 2. 运行完整测试

启动服务器后，运行完整API测试：

```bash
python scripts/test_all_apis_complete.py
```

该脚本会测试：
- ✅ 用户认证
- ✅ 数据载荷 API
- ✅ 二维码 API
- ✅ Jitsi 房间 API
- ✅ Socket.io 集成信息

## 📚 详细文档

### 测试文档
- **完整测试流程**: `完整测试流程.md` - 详细的测试步骤说明
- **测试脚本**: `scripts/test_all_apis_complete.py` - 自动化测试脚本

### 部署文档
- **部署检查清单**: `DEPLOYMENT_CHECKLIST.md` - 完整的部署前检查项
- **部署准备脚本**: `scripts/prepare_deployment.py` - 自动化部署检查脚本

## 🚀 部署流程

### 步骤1: 环境准备

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

# 2. 编辑 .env 文件
# 必须修改的配置：
# - JWT_SECRET_KEY (使用 openssl rand -hex 32 生成)
# - POSTGRES_PASSWORD (强密码)
# - REDIS_PASSWORD (强密码)
# - RSA_PRIVATE_KEY (真实RSA私钥)
# - RSA_PUBLIC_KEY (真实RSA公钥)
# - JITSI_APP_SECRET (Jitsi JWT签名密钥)
# - DEBUG=false (生产环境)
```

### 步骤3: 启动数据库服务

```bash
# 使用 Docker Compose
docker-compose up -d postgres redis

# 检查服务状态
docker-compose ps
```

### 步骤4: 运行数据库迁移

```bash
# 运行 Alembic 迁移
alembic upgrade head

# 验证迁移成功
alembic current
```

### 步骤5: 创建管理员账户

```bash
# 运行创建测试账户脚本
python scripts/create_test_accounts.py
```

### 步骤6: 运行部署检查

```bash
# 运行部署准备脚本
python scripts/prepare_deployment.py
```

确保所有检查项都通过。

### 步骤7: 启动应用

**开发环境**:
```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**生产环境**:
```bash
# 使用 Gunicorn + Uvicorn Workers
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### 步骤8: 运行测试

```bash
# 运行完整API测试
python scripts/test_all_apis_complete.py
```

### 步骤9: 配置 Nginx（生产环境）

参考 `DEPLOYMENT_CHECKLIST.md` 中的 Nginx 配置说明。

## 🧪 测试说明

### 自动化测试

#### 完整API测试
```bash
python scripts/test_all_apis_complete.py
```

测试内容：
- 用户认证（登录、Token获取）
- 数据载荷 API（上传、查询、开关）
- 二维码 API（生成、验证、房间二维码）
- Jitsi 房间 API（创建、查询、加入、参与者）

#### 原有测试脚本
```bash
python scripts/test_new_apis_zh.py
```

测试内容：
- 用户管理 API
- 邀请码管理 API
- 后台管理 API

### 手动测试

访问 Swagger UI 进行手动测试：
```
http://127.0.0.1:8000/docs
```

使用步骤：
1. 打开浏览器访问上述地址
2. 找到 `/api/v1/auth/login` 端点
3. 点击 "Try it out"
4. 输入管理员账户信息
5. 复制返回的 `access_token`
6. 点击页面右上角的 "Authorize" 按钮
7. 输入 `Bearer <你的token>`
8. 现在可以测试其他需要认证的API了

### Socket.io 测试

Socket.io 需要客户端连接测试，可以使用以下工具：

1. **浏览器控制台**:
```javascript
const socket = io('http://127.0.0.1:8000', {
  auth: {
    token: 'YOUR_JWT_TOKEN'
  }
});

socket.on('connect', () => {
  console.log('Connected!');
});

socket.on('connected', (data) => {
  console.log('Server confirmed:', data);
});

// 发送心跳
setInterval(() => {
  socket.emit('ping');
}, 30000);

socket.on('pong', (data) => {
  console.log('Pong received:', data);
});
```

2. **Postman** (支持 WebSocket):
   - 创建新的 WebSocket 请求
   - URL: `ws://127.0.0.1:8000/socket.io/?EIO=4&transport=websocket`
   - 在连接时发送认证信息

## ⚠️ 安全注意事项

### 生产环境必须修改的配置

1. **JWT_SECRET_KEY**
   ```bash
   openssl rand -hex 32
   ```

2. **数据库密码**
   - PostgreSQL 密码必须强密码
   - Redis 密码必须强密码

3. **RSA 密钥对**
   ```bash
   openssl genrsa -out private_key.pem 2048
   openssl rsa -in private_key.pem -pubout -out public_key.pem
   ```

4. **Jitsi 配置**
   - JITSI_APP_SECRET 必须真实密钥
   - JITSI_SERVER_URL 必须真实服务器地址

5. **环境变量**
   - DEBUG=false
   - 关闭 API 文档（docs_url=None）

### 网络安全

- ✅ 必须使用 HTTPS（WebRTC 要求）
- ✅ CORS 配置必须限制允许的域名
- ✅ 防火墙规则必须正确配置
- ✅ 数据库用户权限最小化

## 📊 监控和日志

### 日志位置

- 应用日志: `logs/app.log`
- 日志轮转: 10MB，保留7天

### 健康检查

```bash
curl http://127.0.0.1:8000/health
```

### 监控端点

- 健康检查: `/health`
- API 文档: `/docs` (仅开发环境)

## 🔧 故障排查

### 常见问题

1. **数据库连接失败**
   - 检查 PostgreSQL 是否运行: `docker ps`
   - 检查连接配置: `.env` 文件
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
   - 检查环境变量中的换行符转义（`\n`）

5. **数据库迁移失败**
   - 检查数据库连接
   - 检查迁移脚本是否正确
   - 查看 Alembic 日志

## 📝 检查清单

部署前请确认：

- [ ] 环境变量文件已配置（`.env`）
- [ ] 所有敏感配置已修改（不使用默认值）
- [ ] 数据库服务已启动
- [ ] 数据库迁移已运行
- [ ] 管理员账户已创建
- [ ] 部署检查脚本通过
- [ ] API 测试脚本通过
- [ ] 日志目录权限正确
- [ ] Nginx 配置正确（生产环境）
- [ ] SSL 证书已配置（生产环境）

## 📞 支持

如遇到问题，请：

1. 查看服务器日志: `logs/app.log`
2. 查看 Docker 容器日志: `docker-compose logs`
3. 运行部署检查脚本: `python scripts/prepare_deployment.py`
4. 查看详细文档: `DEPLOYMENT_CHECKLIST.md`

---

**最后更新**: 2026-01-10
**版本**: 1.0.0
