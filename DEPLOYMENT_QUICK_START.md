# 🚀 Jitsi 离线一键部署快速指南

## 核心特性

✅ **完全离线**：所有 Docker 镜像保存在 `docker/images/` 目录  
✅ **一键部署**：运行 `./scripts/deploy_jitsi_offline.sh` 即可  
✅ **禁用官方**：强制使用自建服务器，禁止 `meet.jit.si`  
✅ **版本锁定**：所有版本号固定，确保可重复性  

## 📦 首次准备（需要网络，仅一次）

在有网络的环境中：

```bash
cd /opt/mop
./scripts/save_jitsi_images.sh
```

这会下载并保存所有 Jitsi 镜像到 `docker/images/` 目录。

## 🎯 离线一键部署

在目标服务器（无需网络）：

```bash
cd /opt/mop
./scripts/deploy_jitsi_offline.sh
```

脚本会自动：
1. ✅ 加载本地镜像（无需网络）
2. ✅ 创建配置目录
3. ✅ 生成环境变量文件
4. ✅ 启动所有服务

## ⚙️ 配置

编辑 `jitsi.env`：

```bash
# 必须配置（与后端 .env 一致）
JITSI_PUBLIC_URL=http://your-server-ip:8080
JITSI_JWT_APP_ID=your_jitsi_app_id
JITSI_JWT_APP_SECRET=your_jitsi_app_secret

# 自动生成（无需修改）
JITSI_JICOFO_COMPONENT_SECRET=...
JITSI_JICOFO_AUTH_PASSWORD=...
JITSI_JVB_AUTH_PASSWORD=...
```

## 🔒 安全限制

系统已强制禁用官方 Jitsi：

- ✅ **后端检查**：`create_jitsi_token()` 会拒绝官方地址
- ✅ **前端检查**：`room.html` 会阻止连接官方服务器
- ✅ **配置验证**：启动时验证服务器地址

如果配置了 `meet.jit.si`，系统会立即报错并拒绝启动。

## 📋 服务管理

```bash
# 启动
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d

# 停止
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env down

# 重启
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env restart

# 查看日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f

# 查看状态
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env ps
```

## 📁 项目结构

```
/opt/mop/
├── docker/
│   └── images/              # Docker 镜像（必需，离线部署）
│       ├── jitsi_web-latest-9242.tar.gz
│       ├── jitsi_prosody-latest-9242.tar.gz
│       ├── jitsi_jvb-latest-9242.tar.gz
│       └── jitsi_jicofo-latest-9242.tar.gz
├── docker-compose.jitsi.yml # Jitsi 配置
├── jitsi.env.example        # 环境变量模板
├── scripts/
│   ├── save_jitsi_images.sh    # 保存镜像（需要网络）
│   ├── load_jitsi_images.sh    # 加载镜像（离线）
│   └── deploy_jitsi_offline.sh # 一键部署（离线）
└── ...
```

## ⚠️ 重要提示

1. **镜像文件**：确保 `docker/images/` 目录中有镜像文件
2. **配置一致**：`jitsi.env` 和 `.env` 中的 JWT 配置必须一致
3. **服务器地址**：`JITSI_SERVER_URL` 必须与 `JITSI_PUBLIC_URL` 一致
4. **禁用官方**：严禁使用 `meet.jit.si`，系统会自动拒绝

## 🐛 故障排查

### 镜像未加载

```bash
# 手动加载
./scripts/load_jitsi_images.sh

# 或手动加载单个镜像
gunzip -c docker/images/jitsi_web-latest-9242.tar.gz | docker load
```

### 服务无法启动

```bash
# 查看日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs

# 检查配置
cat jitsi.env
```

### 端口冲突

修改 `jitsi.env` 中的端口：

```bash
JITSI_HTTP_PORT=8080    # 改为其他端口
JITSI_HTTPS_PORT=8443   # 改为其他端口
```

## 📚 详细文档

- `OFFLINE_DEPLOYMENT.md` - 完整离线部署指南
- `JITSI_DEPLOYMENT.md` - Jitsi 部署详细说明
- `JITSI_SETUP.md` - Jitsi 配置说明
