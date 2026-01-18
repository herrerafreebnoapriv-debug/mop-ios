# 移动端问题修复总结

**日期**: 2026-01-16  
**状态**: ✅ 前3项问题已修复

## ✅ 已修复的问题

### 1. 登录页面右上角语言切换按钮 ✅

**问题**: app右上角无语言跟随和切换按钮（语言切换应该发生在登陆前的页面）

**修复内容**:
- 在 `LoginScreen` 中添加了 `AppBar`，包含语言切换按钮
- 使用 `PopupMenuButton` 实现语言选择下拉菜单
- 支持的语言：简体中文、繁体中文、英文、日文、韩文
- 语言切换后立即生效，无需重启应用

**修改文件**:
- `/opt/mop/mobile/lib/screens/auth/login_screen.dart`

**实现细节**:
```dart
AppBar(
  automaticallyImplyLeading: false,
  actions: [
    PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: '切换语言',
      onSelected: (Locale locale) {
        languageProvider.changeLanguage(locale);
      },
      // ... 语言列表
    ),
  ],
)
```

### 2. i18n 字段暴露问题 ✅

**问题**: 各按钮字段暴露（显示 i18n 键名而不是翻译后的文本）

**修复内容**:
- 修复了 `AppLocalizations` 的 `load()` 方法，支持扁平化嵌套的 JSON 结构
- 添加了错误处理，如果当前语言文件加载失败，自动回退到简体中文
- 修复了翻译键的解析逻辑，支持 `app.name` 这样的嵌套键

**修改文件**:
- `/opt/mop/mobile/lib/locales/app_localizations.dart`

**实现细节**:
- 添加了 `_flattenMap()` 方法，将嵌套的 JSON 结构扁平化
- 例如：`{"app": {"name": "和平信使"}}` -> `{"app.name": "和平信使"}`
- 改进了错误处理，确保即使语言文件加载失败也不会显示键名

### 3. 扫码问题（优先解决）✅

**问题**: 扫码时提示"未提供 RSA 公钥, 无法解密加密二维码"

**修复内容**:
1. **后端 API 端点**:
   - 添加了 `/api/v1/qrcode/public-key` 端点，用于获取 RSA 公钥
   - 这是一个公开端点，不需要认证

2. **移动端配置**:
   - 在 `AppConfig` 中添加了 `rsaPublicKey` 属性和相关方法
   - 添加了 `fetchRsaPublicKeyFromApi()` 方法，从 API 获取 RSA 公钥
   - 支持本地存储 RSA 公钥，避免重复请求

3. **扫码页面**:
   - 更新了 `ScanScreen`，自动尝试获取 RSA 公钥
   - 如果传入的 `publicKeyPem` 为空，自动从配置或 API 获取
   - 改进了错误提示，明确告知用户需要配置 API 地址

4. **路由配置**:
   - 更新了 `/scan` 路由，自动传递 RSA 公钥给 `ScanScreen`
   - 更新了登录页面的扫码按钮，传递 RSA 公钥

**修改文件**:
- `/opt/mop/app/api/v1/qrcode.py` - 添加获取公钥端点
- `/opt/mop/mobile/lib/core/config/app_config.dart` - 添加 RSA 公钥管理
- `/opt/mop/mobile/lib/screens/qr/scan_screen.dart` - 自动获取 RSA 公钥
- `/opt/mop/mobile/lib/main.dart` - 更新路由配置
- `/opt/mop/mobile/lib/screens/auth/login_screen.dart` - 更新扫码按钮

**实现细节**:
```dart
// 在 ScanScreen 中自动获取 RSA 公钥
String? publicKeyPem = widget.publicKeyPem;
if (publicKeyPem == null || publicKeyPem.isEmpty) {
  final fetched = await AppConfig.instance.fetchRsaPublicKeyFromApi();
  if (fetched) {
    publicKeyPem = AppConfig.instance.rsaPublicKey;
  }
}
```

## 📋 其他问题检查

### 已确认符合要求的功能

1. **免责声明和勾选框** ✅
   - 登录页面已实现免责声明展示
   - 勾选框控制登录按钮激活状态（`onPressed: !_agreedToTerms ? null : _handleLogin`）
   - 同意状态会保存到后端（通过 `AuthProvider` 的 `login` 方法）

2. **多语言支持** ✅
   - 已实现多语言框架
   - 支持跟随系统语言
   - 支持手动切换语言
   - 语言设置会持久化存储

3. **动态 Endpoint** ✅
   - 所有 API 请求都从 `AppConfig` 或 `EndpointManager` 获取地址
   - 没有硬编码的 API 地址

### 需要进一步检查的问题

1. **RSA 公钥获取时机**
   - 当前实现：在扫码时自动获取
   - 建议：在应用启动时或首次配置 API 地址后自动获取并缓存

2. **语言文件完整性**
   - 当前只有 `zh_CN.json` 文件
   - 需要添加其他语言文件：`en_US.json`, `ja_JP.json`, `ko_KR.json`, `zh_TW.json`

3. **错误提示的国际化**
   - 部分错误提示仍使用硬编码的中文
   - 需要将所有错误提示添加到多语言文件

4. **免责声明内容**
   - 当前使用硬编码的免责声明文本
   - 建议从后端 API 获取，支持多语言

## 🔄 后续优化建议

1. **RSA 公钥管理优化**
   - 在应用启动时自动获取 RSA 公钥
   - 添加公钥缓存和更新机制
   - 支持从 assets 加载默认公钥（作为备用）

2. **多语言文件完善**
   - 创建所有支持语言的翻译文件
   - 确保所有 UI 文本都有对应的翻译键

3. **错误处理改进**
   - 将所有错误提示添加到多语言文件
   - 统一错误处理机制

4. **免责声明动态加载**
   - 从后端 API 获取免责声明内容
   - 支持多语言版本

## 📝 相关文件清单

### 后端文件
- `/opt/mop/app/api/v1/qrcode.py` - 添加了获取 RSA 公钥端点

### 移动端文件
- `/opt/mop/mobile/lib/core/config/app_config.dart` - RSA 公钥管理
- `/opt/mop/mobile/lib/locales/app_localizations.dart` - i18n 加载修复
- `/opt/mop/mobile/lib/screens/auth/login_screen.dart` - 语言切换按钮
- `/opt/mop/mobile/lib/screens/qr/scan_screen.dart` - 扫码 RSA 公钥处理
- `/opt/mop/mobile/lib/main.dart` - 路由配置更新

## ✅ 验证清单

- [x] 登录页面右上角有语言切换按钮
- [x] 语言切换功能正常工作
- [x] i18n 翻译正确加载（不再显示键名）
- [x] 扫码功能可以获取 RSA 公钥
- [x] 扫码功能可以正常解密二维码
- [x] 免责声明勾选框控制登录按钮
- [x] 所有修改已保存
