# 离线部署快速指南

## 🎯 核心特性

- ✅ **完全离线**：所有 Docker 镜像保存在本地
- ✅ **一键部署**：自动化脚本，无需手动操作
- ✅ **版本锁定**：所有版本号固定，确保可重复性
- ✅ **禁用官方**：强制使用自建 Jitsi 服务器

## 🚀 快速开始

### 1. 准备镜像（首次部署或更新时）

在有网络的环境中运行：

```bash
cd /opt/mop
./scripts/save_jitsi_images.sh
```

### 2. 离线一键部署

在目标服务器运行：

```bash
cd /opt/mop
./scripts/deploy_jitsi_offline.sh
```

### 3. 配置环境变量

编辑 `jitsi.env`：

```bash
JITSI_PUBLIC_URL=http://your-server-ip:8080
JITSI_JWT_APP_ID=your_jitsi_app_id
JITSI_JWT_APP_SECRET=your_jitsi_app_secret
```

### 4. 启动服务

```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d
```

## 📦 项目结构

```
/opt/mop/
├── docker/
│   └── images/              # Docker 镜像（离线部署必需）
│       ├── jitsi_web-latest-9242.tar.gz
│       ├── jitsi_prosody-latest-9242.tar.gz
│       ├── jitsi_jvb-latest-9242.tar.gz
│       └── jitsi_jicofo-latest-9242.tar.gz
├── docker-compose.jitsi.yml # Jitsi Docker Compose 配置
├── jitsi.env.example        # 环境变量模板
├── scripts/
│   ├── save_jitsi_images.sh    # 保存镜像（需要网络）
│   ├── load_jitsi_images.sh    # 加载镜像（离线）
│   └── deploy_jitsi_offline.sh # 一键部署（离线）
└── ...
```

## 🔒 安全限制

系统已强制禁用官方 Jitsi：

- ✅ 后端 JWT 生成时检查服务器地址
- ✅ 前端房间页面检查服务器地址
- ✅ 配置验证时检查服务器地址

如果检测到官方服务器地址，会立即拒绝并报错。

## 📝 详细文档

- `OFFLINE_DEPLOYMENT.md` - 完整离线部署指南
- `JITSI_DEPLOYMENT.md` - Jitsi 部署详细说明
- `JITSI_SETUP.md` - Jitsi 配置说明
