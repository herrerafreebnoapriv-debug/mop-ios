# MOP 项目部署指南 - 版本 v0112-0930

## 📦 压缩包信息

- **版本标签**: v0112-0930
- **压缩包**: `mop-v0112-0930.tar.gz`
- **文件大小**: 3.5M
- **MD5校验**: `d0de37526b02e544eab26b1c45ead52d`
- **包含文件数**: 260个文件

## ✅ 包含内容

压缩包包含完整的项目代码：
- ✅ Python 应用代码 (`app/`)
- ✅ 前端静态文件 (`static/`)
- ✅ 数据库迁移脚本 (`alembic/`)
- ✅ 工具脚本 (`scripts/`)
- ✅ Docker 配置文件 (`docker-compose.yml`, `docker-compose.jitsi.yml`)
- ✅ Python 依赖文件 (`requirements.txt`)
- ✅ 文档和配置文件

## ⚠️ 不包含内容（需要手动配置）

- ❌ `.env` 文件（敏感配置，需手动创建）
- ❌ `.git` 目录（版本历史）
- ❌ Python 虚拟环境（需重新创建）
- ❌ 数据库数据（需初始化）

## 🚀 快速部署步骤

### 1. 解压项目

```bash
# 上传压缩包到服务器
scp mop-v0112-0930.tar.gz root@your-server:/opt/

# 解压到目标目录
cd /opt
tar -xzf mop-v0112-0930.tar.gz -C mop
cd mop
```

### 2. 创建虚拟环境并安装依赖

```bash
# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt
```

### 3. 配置环境变量

```bash
# 复制环境变量模板
cp .env.backup .env

# 编辑 .env 文件，配置以下关键项：
# - DATABASE_URL (PostgreSQL连接)
# - JITSI_SERVER_URL (Jitsi服务器地址)
# - JITSI_APP_ID (Jitsi应用ID)
# - JITSI_APP_SECRET (Jitsi密钥)
# - RSA_PRIVATE_KEY (RSA私钥)
# - RSA_PUBLIC_KEY (RSA公钥)
# - SECRET_KEY (FastAPI密钥)
```

### 4. 初始化数据库

```bash
# 运行数据库迁移
alembic upgrade head

# 初始化二维码配置
python3 scripts/init_qrcode_configs.py

# （可选）创建超级管理员
python3 scripts/set_super_admin.py
```

### 5. 启动服务

```bash
# 方式1: 使用启动脚本
bash start_server.sh

# 方式2: 直接使用 uvicorn
uvicorn app.main:app --host 0.0.0.0 --port 8000

# 方式3: 使用 systemd（需配置服务文件）
systemctl start mop-backend
```

### 6. 配置 Nginx（如需要）

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## 📋 部署检查清单

- [ ] 解压项目文件
- [ ] 创建并激活虚拟环境
- [ ] 安装 Python 依赖
- [ ] 配置 `.env` 文件
- [ ] 初始化数据库（运行迁移）
- [ ] 初始化二维码配置
- [ ] 创建超级管理员账户
- [ ] 启动后端服务
- [ ] 配置 Nginx 反向代理
- [ ] 测试 API 端点 (`/health`)
- [ ] 测试登录功能
- [ ] 测试房间创建和加入

## 🔧 依赖要求

- Python 3.8+
- PostgreSQL 12+
- Redis（可选，用于缓存）
- Nginx（推荐，用于反向代理）

## 📝 主要功能

版本 v0112-0930 包含以下功能：

1. **扫码配置管理**
   - 最大扫码次数设置
   - 加密模式/明文模式选择
   - 配置项友好名称显示

2. **系统统计**
   - 单行显示格式
   - 实时数据更新

3. **用户管理**
   - 用户列表查看
   - 用户状态管理
   - 角色权限控制

4. **房间管理**
   - 房间创建和编辑
   - 二维码生成
   - 参与者管理

## 🆘 常见问题

### Q: 启动后出现数据库连接错误？
A: 检查 `.env` 文件中的 `DATABASE_URL` 配置，确保 PostgreSQL 服务正在运行。

### Q: 无法访问前端页面？
A: 检查 Nginx 配置和静态文件路径，确保 `static/` 目录可访问。

### Q: Jitsi 房间无法连接？
A: 检查 Jitsi 服务是否运行，确认 `.env` 中的 Jitsi 配置正确。

## 📞 技术支持

如遇到问题，请检查：
1. 服务器日志：`/tmp/mop_server.log`
2. Nginx 错误日志：`/var/log/nginx/error.log`
3. 应用日志：查看控制台输出

---

**版本**: v0112-0930  
**创建时间**: 2026-01-12  
**MD5**: d0de37526b02e544eab26b1c45ead52d
