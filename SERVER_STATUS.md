# 服务器状态报告

**日期**: 2026-01-10  
**问题**: 502 Bad Gateway  
**状态**: ✅ 已修复

## 问题诊断

### 原因
- Nginx 正在运行，但后端服务器（FastAPI/Uvicorn）未运行
- Nginx 配置指向 `127.0.0.1:8000`，但该端口没有服务监听
- 导致所有请求返回 502 Bad Gateway

### 解决方案
1. ✅ 启动后端服务器
2. ✅ 验证服务器正常运行
3. ✅ 创建启动脚本便于后续管理

## 当前状态

### 后端服务器
- **状态**: ✅ 运行中
- **PID**: 5898
- **端口**: 8000
- **健康检查**: http://127.0.0.1:8000/health ✅

### Nginx
- **状态**: ✅ 运行中
- **端口**: 80, 443
- **配置**: 指向 `127.0.0.1:8000`

## 启动命令

### 手动启动
```bash
cd /opt/mop
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/mop_server.log 2>&1 &
```

### 使用启动脚本
```bash
/opt/mop/start_server.sh
```

### 检查状态
```bash
# 检查进程
ps aux | grep uvicorn | grep -v grep

# 检查端口
netstat -tlnp | grep 8000

# 检查健康
curl http://127.0.0.1:8000/health

# 查看日志
tail -f /tmp/mop_server.log
```

## 建议

### 1. 创建 systemd 服务（推荐）
创建 `/etc/systemd/system/mop-backend.service`:
```ini
[Unit]
Description=MOP Backend API Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mop
Environment="PATH=/usr/bin:/usr/local/bin"
ExecStart=/usr/bin/python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
StandardOutput=append:/opt/mop/logs/app.log
StandardError=append:/opt/mop/logs/app.log

[Install]
WantedBy=multi-user.target
```

然后：
```bash
sudo systemctl daemon-reload
sudo systemctl enable mop-backend
sudo systemctl start mop-backend
sudo systemctl status mop-backend
```

### 2. 使用 Supervisor（备选）
安装并配置 Supervisor 来管理进程。

### 3. 使用 Docker Compose（生产环境推荐）
使用 Docker Compose 管理所有服务，包括自动重启。

## 日志位置

- **服务器日志**: `/tmp/mop_server.log`
- **应用日志**: `/opt/mop/logs/app.log`
- **Nginx 错误日志**: `/var/log/nginx/error.log`
- **Nginx 访问日志**: `/var/log/nginx/access.log`

---

**最后更新**: 2026-01-10 22:43
