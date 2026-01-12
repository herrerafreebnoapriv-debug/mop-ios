# 项目依赖版本锁定清单

本文档记录所有依赖、镜像和工具的具体版本号，确保环境可重复性和稳定性。

**更新原则：**
- 所有版本号必须明确指定，禁止使用 `latest` 或浮动标签（如 `15-alpine`）
- 更新版本需要更新此文档并说明原因
- 生产环境部署前必须验证新版本兼容性

---

## Docker 镜像版本

### 基础服务镜像

| 服务 | 镜像名称 | 版本 | 说明 |
|------|----------|------|------|
| PostgreSQL | postgres | `15.5-alpine` | 使用 Alpine 版本以减小镜像大小 |
| Redis | redis | `7.4.7-alpine` | 使用 Alpine 版本以减小镜像大小 |
| Nginx | nginx | `1.27.3-alpine` | 用于反向代理和静态文件服务（未来使用） |

### Jitsi Meet 镜像（私有化部署）

| 服务 | 镜像名称 | 版本 | 说明 |
|------|----------|------|------|
| Jitsi Web | jitsi/web | `stable` | Jitsi Web 界面（使用官方 stable 标签） |
| Jitsi Prosody | jitsi/prosody | `stable` | Jitsi XMPP 服务器 |
| Jitsi JVB | jitsi/jvb | `stable` | Jitsi Videobridge（视频桥接） |
| Jitsi Jicofo | jitsi/jicofo | `stable` | Jitsi Conference Focus（会议焦点） |
| Jitsi Jigasi | jitsi/jigasi | `stable` | Jitsi Gateway SIP（SIP 网关，可选） |

**注意：** Jitsi 官方使用 `stable` 标签作为稳定版本。`stable-9242` 等格式的标签在 Docker Hub 上不存在，应使用 `stable` 标签。

---

## Python 依赖版本

Python 版本要求：`>= 3.11, < 3.13`

详细版本见 `requirements.txt`，所有依赖均已固定版本号。

### 核心框架版本

| 包名 | 版本 | 说明 | 版本策略 |
|------|------|------|----------|
| FastAPI | `0.115.14` | Web 框架 | 稳定版（最新 0.128.0，使用稳定主流版） |
| Uvicorn | `0.32.1` | ASGI 服务器 | 稳定版 |
| SQLAlchemy | `2.0.38` | ORM 框架 | 稳定版（最新 2.0.45，使用稳定版） |
| Pydantic | `2.9.2` | 数据验证 | 稳定版 |
| Alembic | `1.14.0` | 数据库迁移工具 | 稳定版 |

### 数据库驱动版本

| 包名 | 版本 | 说明 |
|------|------|------|
| asyncpg | `0.30.0` | PostgreSQL 异步驱动 |
| psycopg2-binary | `2.9.10` | PostgreSQL 同步驱动（用于 Alembic） |

### 其他关键依赖

| 包名 | 版本 | 说明 | 版本策略 |
|------|------|------|----------|
| redis | `5.0.8` | Redis 客户端 | 稳定版（最新 7.1.0，但遵循稳定策略使用 5.0.x 系列） |
| python-jose | `3.3.0` | JWT 处理 | 稳定版 |
| cryptography | `43.0.3` | 加密库 | 稳定版 |
| python-socketio | `5.11.4` | Socket.io 支持 | 稳定版 |

**版本策略说明：**
- 采用"稳定主流版本"策略，不追最新版本
- 例如：Redis 客户端最新是 7.1.0，但使用稳定版 5.0.8
- 例如：FastAPI 最新是 0.128.0，但使用稳定版 0.115.14
- 类似策略：iPhone 17 出来用 16，Win11 出来用 Win10，Ubuntu 24 出来用 22.04

---

## 系统依赖版本（Ubuntu 22.04）

### Node.js（用于前端构建，如需要）

| 工具 | 版本 | 说明 |
|------|------|------|
| Node.js | `20.11.0` LTS | 长期支持版本 |

### Nginx 配置

Nginx 将通过 Docker 镜像部署，版本：`1.27.3-alpine`

预配置文件位置：`docker/jitsi/nginx/nginx.conf`

---

## 版本更新记录

| 日期 | 更新项 | 旧版本 | 新版本 | 更新原因 |
|------|--------|--------|--------|----------|
| 2026-01-08 | 初始版本锁定 | - | 见上表 | 确保环境可重复性 |
| 2026-01-08 | 更新到稳定主流版本 | 见旧版本 | 见新版本 | 采用稳定主流版本策略（不追最新） |

---

## 如何更新版本

1. **更新依赖版本：**
   ```bash
   # 更新 requirements.txt
   pip install --upgrade <package-name>==<new-version>
   pip freeze > requirements.txt
   ```

2. **更新 Docker 镜像版本：**
   - 修改 `docker-compose.yml` 中的镜像标签
   - 更新 `VERSIONS.md` 中的版本记录
   - 测试新版本兼容性

3. **更新 Jitsi 镜像版本：**
   - 查阅 [Jitsi 官方文档](https://github.com/jitsi/docker-jitsi-meet) 获取最新稳定版本
   - 更新 `docker-compose.jitsi.yml`（未来创建）
   - 在测试环境验证功能

---

## 版本验证清单

更新版本后，必须验证以下功能：

- [ ] 数据库连接和查询正常
- [ ] Redis 连接和操作正常
- [ ] JWT 生成和验证正常
- [ ] Socket.io 连接正常
- [ ] Jitsi Meet 视频通话正常（如已部署）
- [ ] Nginx 反向代理正常（如已部署）
