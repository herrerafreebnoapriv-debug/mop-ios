# Docker 镜像加速器配置指南

## 问题说明
当前遇到 Docker 镜像拉取失败的问题，错误信息：`tls: received record with version 2103 when expecting version 303`
这是网络连接问题，需要配置 Docker 镜像加速器或代理。

## 解决方案

### 方案 1：配置 Docker Desktop 镜像加速器（推荐）

#### Windows 用户：
1. 打开 Docker Desktop
2. 点击右上角设置（齿轮图标）
3. 选择 **Docker Engine**
4. 在 JSON 配置中添加以下内容：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.nju.edu.cn",
    "https://docker.mirrors.sjtug.sjtu.edu.cn"
  ]
}
```

5. 点击 **Apply & Restart** 重启 Docker Desktop

#### 配置完成后，再次运行：
```powershell
docker compose up -d
```

### 方案 2：使用代理（如果公司/学校网络需要）

1. 在 Docker Desktop 设置中找到 **Resources → Proxies**
2. 配置您的 HTTP/HTTPS 代理地址
3. 保存并重启 Docker Desktop

### 方案 3：手动拉取镜像（临时方案）

如果上述方案都不行，可以尝试手动拉取镜像：

```powershell
# 先拉取 PostgreSQL 镜像
docker pull postgres:15-alpine

# 再拉取 Redis 镜像
docker pull redis:7-alpine

# 然后启动服务
docker compose up -d
```

### 方案 4：使用已存在的镜像（如果有）

如果本地已经有这些镜像，可以检查：

```powershell
# 查看本地镜像列表
docker images | Select-String -Pattern "postgres|redis"

# 如果有，可以直接启动
docker compose up -d
```

## 验证配置

配置完成后，运行以下命令验证：

```powershell
# 检查 Docker 配置
docker info | Select-String -Pattern "Registry Mirrors"

# 测试拉取镜像
docker pull hello-world
```

如果 `hello-world` 能成功拉取，说明配置成功，可以尝试启动项目了。
