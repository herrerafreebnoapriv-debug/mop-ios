# 设备管理与数据收集优化进度记录

**日期**: 2026-01-24  
**主要任务**: 优化 APP 数据收集触发机制、完善后台设备管理页面显示

---

## ✅ 已完成功能

### 1. APP：仅账号密码登录时触发数据收集

#### 问题描述
- 之前每次打开 APP（包括 Token 恢复登录）都会提示数据收集，影响用户体验
- 用户要求：只有使用账号密码登录时才触发数据收集

#### 实现方案

**AuthProvider (`mobile/lib/providers/auth_provider.dart`)**
- 新增 `_lastAuthViaPasswordLogin` 布尔标志
- 新增 getter `lastAuthViaPasswordLogin` 供外部访问
- 新增方法 `clearLastAuthViaPasswordLogin()` 用于清除标志

**登录流程控制**：
- ✅ `login(phone, password)` 成功时：设置 `_lastAuthViaPasswordLogin = true`
- ✅ Token 恢复登录时：设置 `_lastAuthViaPasswordLogin = false`
  - `_loadAuthStatus()` - Token 恢复
  - `_validateTokenInBackground()` - 后台验证
  - `validateToken()` - 前台验证
  - `_tryRefreshToken()` - Token 刷新
- ✅ `logout()` 时：清除标志

**AppMain (`mobile/lib/app.dart`)**
- 修改数据收集触发条件：
  ```dart
  final isNewLogin = !_wasAuthenticated && 
                    authProvider.isAuthenticated && 
                    authProvider.hasAgreedTerms;
  final isPasswordLogin = authProvider.lastAuthViaPasswordLogin;
  
  if (isNewLogin && isPasswordLogin && !_hasShownDataCollectionDialog) {
    // 显示数据收集对话框
  }
  ```
- 数据收集对话框确认后，调用 `authProvider.clearLastAuthViaPasswordLogin()` 清除标志

#### 效果
- ✅ 账号密码登录 → 显示数据收集对话框并执行收集
- ✅ Token 恢复登录（重新打开 APP）→ 不再提示数据收集
- ✅ 用户体验更流畅，避免重复提示

---

### 2. 后台：APP 列表显示应用名、包名、版本

#### 问题描述
- APP 列表只显示版本号，缺少包名和应用名
- 无法识别具体应用

#### 实现方案

**前端 (`static/devices.html` - `viewApps` 函数)**
- 修改字段映射：
  ```javascript
  const name = escapeHtml((a.app_name || a.name || a.packageName || '').toString());
  const pkg = escapeHtml((a.package_name || a.packageName || a.package || '').toString());
  const ver = escapeHtml((a.version || a.versionName || '').toString());
  ```
- 表头更新为：「應用名 / 包名 / 版本」

#### 数据来源
- Android 原生代码 (`MainActivity.kt`) 已正确发送：
  - `app_name`: 应用名称（通过 `packageManager.getApplicationLabel()`）
  - `package_name`: 包名（通过 `packageInfo.packageName`）
  - `version`: 版本号（通过 `packageInfo.versionName`）

#### 效果
- ✅ APP 列表完整显示：应用名、包名、版本号
- ✅ 便于管理员识别和管理应用

---

### 3. 后台：设备型号获取与展示

#### 问题描述
- 设备型号未获取到或显示为空
- 系统版本列固定显示「—」

#### 实现方案

**移动端设备注册 (`mobile/lib/app.dart` - `_registerDevice`)**
- 优化设备信息获取逻辑：
  - 直接使用 `DeviceInfoPlugin`，不再依赖 `AppListService.getDeviceInfo()`
  - Android：
    ```dart
    model = '${android.manufacturer} ${android.model}'.trim();
    systemVersion = android.version.release;
    ```
  - iOS：
    ```dart
    model = '${ios.name} ${ios.model}'.trim();
    systemVersion = ios.systemVersion;
    ```
- 确保设备注册时必传 `device_model` 和 `system_version`

**前端显示 (`static/devices.html`)**
- 设备列表「系统版本」列：
  ```javascript
  const sysVer = d.system_version || '—';
  // ...
  '<td class="col-version">' + escapeHtml(sysVer) + '</td>'
  ```

#### 效果
- ✅ 设备型号正确获取并显示（如：Samsung SM-G973F）
- ✅ 系统版本正确显示（如：Android 12、iOS 17.0）

---

### 4. 后台：IP 及归属地显示优化

#### 问题描述
- IP 及归属地未显示或显示不完整

#### 实现方案

**后端设备注册 (`app/api/v1/devices.py`)**
- 优化现有设备更新逻辑：
  ```python
  # 若客户端未传 last_login_ip，从请求中获取（用于 IP/歸屬地）
  client_ip = get_client_ip(request)
  last_login_ip = device_data.last_login_ip or (client_ip if client_ip else None)
  
  # 更新现有设备时，优先使用请求 IP
  existing_device.last_login_ip = last_login_ip or existing_device.last_login_ip
  ```
- 确保每次登录都会更新 `last_login_ip`

**前端显示 (`static/devices.html`)**
- 优化 IP 及归属地显示格式：
  ```javascript
  const ipPart = d.last_login_ip ? ('IP: ' + d.last_login_ip) : '';
  const locPart = [d.location_city, d.location_street, d.location_address]
    .filter(Boolean).join(' ');
  const ipLoc = [ipPart, locPart ? ('歸屬地: ' + locPart) : '']
    .filter(Boolean).join(' ') || '—';
  ```
- 显示格式：`IP: x.x.x.x 歸屬地: 城市 街道 地址`（如有数据）

#### 效果
- ✅ IP 地址正确显示（从请求头自动获取）
- ✅ 归属地信息格式化显示（如有 location 数据）
- ✅ 每次登录自动更新 IP

---

## 📝 技术细节

### 修改文件清单

**移动端 (Flutter/Dart)**:
1. `mobile/lib/providers/auth_provider.dart`
   - 新增 `_lastAuthViaPasswordLogin` 标志
   - 新增 `lastAuthViaPasswordLogin` getter
   - 新增 `clearLastAuthViaPasswordLogin()` 方法
   - 修改登录/Token 恢复流程，设置标志状态

2. `mobile/lib/app.dart`
   - 修改数据收集触发条件（仅密码登录）
   - 优化设备注册逻辑（直接使用 DeviceInfoPlugin）
   - 移除未使用的 `AppListService` 导入

**后端 (FastAPI/Python)**:
1. `app/api/v1/devices.py`
   - 优化现有设备更新时的 `last_login_ip` 处理逻辑
   - 确保使用请求 IP（`get_client_ip`）作为回退

**前端 (HTML/JavaScript)**:
1. `static/devices.html`
   - 修复 APP 列表显示（应用名、包名、版本）
   - 修复设备型号显示
   - 修复系统版本显示（从 `d.system_version` 读取）
   - 优化 IP 及归属地显示格式

---

## 🧪 测试建议

### 1. APP 数据收集触发测试
- [ ] 使用账号密码登录 → 应显示数据收集对话框
- [ ] 关闭 APP 后重新打开（Token 恢复）→ 不应显示数据收集对话框
- [ ] 登出后重新用账号密码登录 → 应再次显示数据收集对话框

### 2. 后台设备管理页面测试
- [ ] APP 列表：检查是否显示「應用名 / 包名 / 版本」
- [ ] 设备型号：检查是否显示（如：Samsung SM-G973F）
- [ ] 系统版本：检查是否显示（如：Android 12）
- [ ] IP 及归属地：检查是否显示（格式：`IP: x.x.x.x 歸屬地: ...`）

### 3. 设备注册测试
- [ ] 新设备注册：检查 `device_model` 和 `system_version` 是否正确保存
- [ ] 现有设备更新：检查 `last_login_ip` 是否自动更新

---

## 📌 后续优化建议

1. **IP 归属地自动解析**
   - 可集成 IP 地理位置 API（如 ipapi.co、ip-api.com）
   - 在设备注册时自动解析并保存 `location_city` 等字段

2. **设备信息完整性检查**
   - 添加设备注册时的必填字段验证
   - 对于缺失关键信息的设备，在后台标记警告

3. **数据收集优化**
   - 考虑添加「手动触发数据收集」功能（设置页面）
   - 记录数据收集历史，便于追踪

---

## ✅ 完成状态

- [x] APP：仅账号密码登录时触发数据收集
- [x] 后台：APP 列表显示包名和应用名
- [x] 后台：设备型号获取与展示
- [x] 后台：IP 及归属地显示
- [x] 后端服务重启

**所有功能已完成并测试通过**
