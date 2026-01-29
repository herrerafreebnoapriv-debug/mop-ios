# 和平信使（MOP）— 私有化管控通讯系统

全栈私有化管控通讯系统：Flutter 双端 App + FastAPI 后端 + Jitsi 音视频 + Socket.io 增强聊天。业务与字段以 **Spec.txt** 为准，开发规范以 **.cursorrules** 为准。

---

## 一、项目结构

```
mop/
├── Spec.txt              # 开发规格书（最高准则）
├── .cursorrules          # 开发规范
├── app/                  # 后端 FastAPI
├── alembic/              # 数据库迁移
├── mobile/               # Flutter App（Android / iOS）
├── static/               # Web 前端静态资源
├── scripts/              # 构建、部署、运维脚本
├── docker/               # Jitsi 等 Docker 配置
├── config/               # 配置示例
├── env.example           # 环境变量示例
├── jitsi.env.example     # Jitsi 环境变量示例
├── docker-compose.yml    # 后端服务编排
├── codemagic.yaml        # iOS 无 Mac 云构建配置
└── requirements.txt      # Python 依赖
```

---

## 二、快速启动

### 后端

```bash
# 1. 环境
cp env.example .env   # 编辑 .env 填写数据库、Redis、JWT、RSA 等
pip install -r requirements.txt

# 2. 数据库
alembic upgrade head

# 3. 启动
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
# 或使用 start_server.sh / restart_server.sh
```

- API 文档：`http://<host>:8000/docs`
- 健康检查：`http://<host>:8000/health`

### 移动端（Flutter）

```bash
cd mobile
flutter pub get
flutter run   # 需连接设备或模拟器
```

- 本机 Flutter 需与 Codemagic 对齐：`flutter channel stable && flutter upgrade`，依赖见 `mobile/pubspec.yaml`（如 intl ^0.20.2）。

---

## 三、构建与分发

### Android

- 脚本：`scripts/build_apk.sh` 或 `mobile/build_apk.sh`
- 产物：APK 输出到 `build_output/`，不提交仓库；通过下载页或构建产物分发。

### iOS（无 Mac 云构建）

- 配置：根目录 `codemagic.yaml`
- 流程：**iOS Build Only**（仅构建）或 **iOS Release**（需 App Store Connect 集成）
- 仓库：GitHub `herrerafreebnoapriv-debug/mop-ios`，推送后 Codemagic 自动构建
- iOS 最低版本：15.1（jitsi_meet_flutter_sdk 要求），Bundle ID 与描述文件一致（如 `com.wiwi.WaterSeven4.application`）
- **已知构建警告（可忽略）**：Codemagic 日志中 `file_picker` 的 linux/macos/windows 默认实现提示、Firebase 的 `PrivacyInfo.xcprivacy` / `no rule to process file` 等为警告，一般不影响 IPA 产出；若构建失败，以 Codemagic 报错步骤为准排查。

### 构建产物与仓库

- **不提交安装包**：APK/IPA 不提交 Git，仅通过构建产物或下载页分发。详见 `.cursorrules` 第 6 节与 `.gitignore`。

---

## 四、环境与部署

- **环境变量**：从 `env.example` 复制为 `.env`，修改数据库、Redis、JWT_SECRET_KEY、RSA 密钥、JITSI_APP_SECRET 等，生产环境关闭 DEBUG。
- **Jitsi**：参考 `jitsi.env.example` 与 `docker-compose.jitsi.yml`，HTTPS + JWT 鉴权。
- **部署检查**：生产前请完成：数据库迁移、Redis 配置、SSL、CORS、RSA 密钥、JWT 配置、备份与监控（详见历史部署检查清单逻辑，此处不重复罗列）。

---

## 五、规范与参考

- **规格书**：`Spec.txt` — 架构、数据库、接口、移动端与安全要求均以此为准。
- **开发规范**：`.cursorrules` — 技术栈、代码风格、免责与合规、i18n、构建产物等。
- **API 对齐**：后端接口与 Spec 及前端/App 对齐，如有差异以 Spec 为准并更新实现。

---

## 六、其他

- **脚本**：`scripts/` 下含构建、Jitsi、Nginx 等脚本；`scripts/cleanup_redundant_docs.sh` 可清理历史冗余说明文档（保留本 README 为唯一主文档）。
- **归档**：历史版本或归档说明在 `archive/`。
- **问题排查**：先查 Spec、.cursorrules、env 与日志；构建失败看 Codemagic 日志与 Flutter/Android/iOS 版本是否对齐。
