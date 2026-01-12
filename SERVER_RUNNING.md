# 服务器运行信息

## 🚀 服务器已启动

### 访问地址

#### 本地访问
- **API 文档**: http://127.0.0.1:8000/docs
- **ReDoc 文档**: http://127.0.0.1:8000/redoc
- **健康检查**: http://127.0.0.1:8000/health
- **登录页面**: http://127.0.0.1:8000/login
- **注册页面**: http://127.0.0.1:8000/register
- **演示页面**: http://127.0.0.1:8000/demo
- **Favicon**: http://127.0.0.1:8000/favicon.ico

#### 生产环境（配置域名后）
- **PC端网页版**: https://www.chat5202ol.xyz/login
- **移动端应用**: https://app.chat5202ol.xyz
- **API 服务**: https://api.chat5202ol.xyz/api/v1

### 服务器信息

- **主机**: 0.0.0.0
- **端口**: 8000
- **环境**: 开发模式（DEBUG=True）
- **自动重载**: 已启用

### 查看日志

```bash
# 实时查看日志
tail -f /tmp/mop_server_run.log

# 查看最后50行
tail -50 /tmp/mop_server_run.log
```

### 停止服务器

```bash
# 方法1: 使用 PID
pkill -f start_server_simple

# 方法2: 使用进程名
pkill -f uvicorn

# 方法3: 查找并杀死
ps aux | grep "start_server_simple" | grep -v grep | awk '{print $2}' | xargs kill
```

### 测试命令

```bash
# 健康检查
curl http://127.0.0.1:8000/health

# 获取 Favicon
curl -o favicon.ico http://127.0.0.1:8000/favicon.ico

# 获取免责声明
curl http://127.0.0.1:8000/api/v1/auth/agreement

# 获取多语言列表
curl http://127.0.0.1:8000/api/v1/i18n/languages
```

---

**启动时间**: 2026-01-10
**状态**: ✅ 服务器运行中
