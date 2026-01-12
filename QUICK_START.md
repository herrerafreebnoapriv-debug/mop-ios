# 快速启动指南

## 🚀 启动服务器

### 方法 1：使用启动脚本（推荐）
```bash
start_demo.bat
```

### 方法 2：手动启动
```bash
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

## 🌐 访问地址

启动服务器后，在浏览器中访问：

1. **多语言演示页面**：
   ```
   http://127.0.0.1:8000/demo
   ```

2. **API 文档（Swagger UI）**：
   ```
   http://127.0.0.1:8000/docs
   ```

3. **健康检查**：
   ```
   http://127.0.0.1:8000/health
   ```

## ✨ 功能演示

### 1. 测试语言切换（无需登录）
1. 打开演示页面：`http://127.0.0.1:8000/demo`
2. 点击页面上的语言按钮（如"简体中文"、"English"等）
3. 观察页面文本立即切换为对应语言

### 2. 测试语言持久化（需要登录）
1. 先注册一个测试账号：
   - 访问 `http://127.0.0.1:8000/docs`
   - 使用 `/api/v1/auth/register` 端点注册
   - 或直接在演示页面注册
2. 登录账号
3. 切换语言（例如切换到英文）
4. 刷新页面 → 语言应该保持为英文
5. 登出后重新登录 → 语言应该仍然是英文（已持久化）

### 3. 测试 API 多语言响应
1. 在演示页面切换不同语言
2. 点击"测试健康检查"和"测试根端点"按钮
3. 观察 API 响应中的文本是否对应当前语言
4. 注意应用名称：中文显示"和平信使"，英文显示"MOP"

## 🔧 前置条件

### 1. 确保数据库和 Redis 运行
```bash
docker compose up -d
```

### 2. 检查服务状态
```bash
docker ps
```

应该看到：
- `mop_postgres` - 运行中
- `mop_redis` - 运行中

### 3. 运行数据库迁移（如果尚未运行）
```bash
alembic upgrade head
```

## 📝 API 测试示例

### 使用 curl 测试多语言 API

#### 1. 健康检查（中文）
```bash
curl -H "Accept-Language: zh-CN,zh;q=0.9" http://127.0.0.1:8000/health
```

#### 2. 健康检查（英文）
```bash
curl -H "Accept-Language: en-US,en;q=0.9" http://127.0.0.1:8000/health
```

#### 3. 获取支持的语言列表
```bash
curl http://127.0.0.1:8000/api/v1/i18n/languages
```

#### 4. 获取当前语言
```bash
curl -H "Accept-Language: en-US,en;q=0.9" http://127.0.0.1:8000/api/v1/i18n/current
```

#### 5. 切换语言（需要登录）
```bash
curl -X POST http://127.0.0.1:8000/api/v1/i18n/switch \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"language": "en_US"}'
```

## 🐛 故障排除

### 问题 1：无法连接到服务器
**错误**：`ERR_CONNECTION_REFUSED`

**解决方案**：
1. 检查服务器是否正在运行
2. 确认端口 8000 未被占用
3. 检查防火墙设置

### 问题 2：数据库连接失败
**错误**：`数据库初始化失败`

**解决方案**：
1. 确认 Docker 容器正在运行：`docker ps`
2. 检查 `.env` 文件中的数据库配置
3. 确认数据库迁移已运行：`alembic upgrade head`

### 问题 3：循环导入错误
**错误**：`ImportError: cannot import name 'get_current_user'`

**解决方案**：
- 已修复，确保使用最新代码

### 问题 4：语言切换不生效
**检查清单**：
1. 确认已登录（语言持久化需要登录）
2. 检查浏览器控制台是否有错误
3. 确认 API 返回成功响应

## 📚 相关文档

- `I18N_IMPLEMENTATION.md` - 完整的 i18n 实现文档
- `README_I18N_DEMO.md` - 演示页面详细说明
- `I18N_STATUS.md` - i18n 功能状态报告

## 💡 提示

- 服务器启动后会自动检测代码变化并重载（`--reload` 模式）
- 演示页面使用 localStorage 保存登录 token
- 所有 API 响应都支持多语言，根据 `Accept-Language` 请求头自动选择语言

---

**祝使用愉快！** 🎉
