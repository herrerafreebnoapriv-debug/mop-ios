# 离线部署指南

## 🎯 设计目标

**完全离线部署**：所有资源保存在本地，不依赖任何网络环境，开箱即可一键部署。

## 📦 本地资源

### 1. Docker 镜像（已保存）

所有 Jitsi Docker 镜像保存在 `docker/images/` 目录：

```
docker/images/
├── jitsi_web-latest-9242.tar.gz
├── jitsi_prosody-latest-9242.tar.gz
├── jitsi_jvb-latest-9242.tar.gz
└── jitsi_jicofo-latest-9242.tar.gz
```

### 2. 配置文件

- `docker-compose.jitsi.yml` - Docker Compose 配置
- `jitsi.env.example` - 环境变量模板
- `scripts/` - 部署脚本

## 🚀 一键部署流程

### 步骤 1: 准备镜像（首次或更新时）

在有网络的环境中：

```bash
cd /opt/mop
./scripts/save_jitsi_images.sh
```

这会：
- 从 Docker Hub 拉取最新镜像
- 保存为 tar.gz 文件到 `docker/images/`
- 可以打包到项目中

### 步骤 2: 离线部署

在目标服务器（无需网络）：

```bash
cd /opt/mop

# 一键部署
./scripts/deploy_jitsi_offline.sh
```

脚本会自动：
1. ✅ 检查 Docker 环境
2. ✅ 加载本地镜像（无需网络）
3. ✅ 创建配置目录
4. ✅ 生成环境变量文件
5. ✅ 启动所有服务

### 步骤 3: 配置环境变量

编辑 `jitsi.env`：

```bash
# 必须配置
JITSI_PUBLIC_URL=http://your-server-ip:8080
JITSI_JWT_APP_ID=your_jitsi_app_id
JITSI_JWT_APP_SECRET=your_jitsi_app_secret

# 自动生成（无需修改）
JITSI_JICOFO_COMPONENT_SECRET=...
JITSI_JICOFO_AUTH_PASSWORD=...
JITSI_JVB_AUTH_PASSWORD=...
```

### 步骤 4: 重启服务

```bash
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env restart
```

## 🔒 安全限制

### 禁用官方 Jitsi

系统已强制禁用官方 Jitsi 服务器：

1. **后端检查**：
   - `create_jitsi_token()` 函数会检查服务器地址
   - 如果包含 `meet.jit.si` 或 `jit.si`，会抛出异常

2. **前端检查**：
   - `room.html` 会检查服务器地址
   - 如果使用官方域名，会显示错误并阻止连接

3. **配置验证**：
   - 部署脚本会验证配置
   - 确保使用自建服务器地址

## 📋 版本锁定

所有版本号锁定在 `VERSIONS.md`：

- Jitsi Web: `latest-9242`
- Jitsi Prosody: `latest-9242`
- Jitsi JVB: `latest-9242`
- Jitsi Jicofo: `latest-9242`

镜像文件命名格式：`jitsi_<service>-latest-9242.tar.gz`

## 🛠️ 脚本说明

### save_jitsi_images.sh

保存镜像到本地（需要网络）：

```bash
./scripts/save_jitsi_images.sh
```

功能：
- 拉取所有 Jitsi 镜像
- 保存为 tar.gz 文件
- 压缩以节省空间

### load_jitsi_images.sh

从本地加载镜像（无需网络）：

```bash
./scripts/load_jitsi_images.sh
```

功能：
- 查找 `docker/images/` 目录中的镜像文件
- 解压并加载到 Docker
- 验证加载结果

### deploy_jitsi_offline.sh

一键离线部署：

```bash
./scripts/deploy_jitsi_offline.sh
```

功能：
- 加载本地镜像
- 创建配置目录
- 生成环境变量
- 启动所有服务

## 📦 打包项目

为了完全离线部署，需要打包以下内容：

```bash
# 项目结构
/opt/mop/
├── docker/
│   └── images/          # Docker 镜像（必需）
│       ├── jitsi_web-latest-9242.tar.gz
│       ├── jitsi_prosody-latest-9242.tar.gz
│       ├── jitsi_jvb-latest-9242.tar.gz
│       └── jitsi_jicofo-latest-9242.tar.gz
├── docker-compose.jitsi.yml  # Docker Compose 配置
├── jitsi.env.example         # 环境变量模板
├── scripts/                   # 部署脚本
│   ├── save_jitsi_images.sh
│   ├── load_jitsi_images.sh
│   └── deploy_jitsi_offline.sh
└── ...其他项目文件
```

## 🔄 更新镜像

如果需要更新镜像版本：

1. 修改 `VERSIONS.md` 中的版本号
2. 修改 `docker-compose.jitsi.yml` 中的镜像标签
3. 运行 `save_jitsi_images.sh` 保存新镜像
4. 更新项目中的镜像文件

## ⚠️ 注意事项

1. **镜像文件大小**：
   - 每个镜像约 200-500MB
   - 压缩后约 100-300MB
   - 总共约 1-2GB

2. **存储空间**：
   - 确保有足够的磁盘空间
   - 建议至少 10GB 可用空间

3. **Docker 版本**：
   - 需要 Docker 20.10+
   - 需要 Docker Compose 2.0+

4. **权限**：
   - 脚本需要执行权限
   - 配置目录需要 1000:1000 权限

## 🐛 故障排查

### 问题：镜像加载失败

```bash
# 检查镜像文件是否存在
ls -lh docker/images/

# 手动加载单个镜像
gunzip -c docker/images/jitsi_web-latest-9242.tar.gz | docker load
```

### 问题：服务无法启动

```bash
# 查看日志
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs

# 检查配置
cat jitsi.env
```

### 问题：端口冲突

修改 `jitsi.env` 中的端口配置：

```bash
JITSI_HTTP_PORT=8080    # 改为其他端口
JITSI_HTTPS_PORT=8443   # 改为其他端口
```

## 📝 总结

✅ **完全离线**：所有资源本地化  
✅ **一键部署**：自动化脚本  
✅ **版本锁定**：确保可重复性  
✅ **禁用官方**：强制使用自建服务器  
✅ **开箱即用**：无需网络环境  
