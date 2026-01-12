# 语言配置迁移进度

**创建时间**: 2026-01-11  
**目标**: 移除简体中文，只保留指定的10种语言，移除所有硬编码文本

## ✅ 已完成

### 1. 后端配置更新
- ✅ 更新 `app/core/i18n.py`：
  - 移除 `zh_CN` (简体中文)
  - 只保留指定的10种语言
  - 更新默认语言为 `en_US`
  - 更新语言映射表

- ✅ 更新 `app/db/models.py`：
  - 默认语言改为 `en_US`

- ✅ 更新 `app/core/permissions.py`：
  - 所有默认语言参数改为 `en_US`

- ✅ 更新 `app/api/v1/admin.py`：
  - 创建房主时的默认语言改为 `en_US`

- ✅ 删除 `app/locales/zh_CN.json`

- ✅ 创建缺失的语言资源文件：
  - `zh_TW.json` (繁体中文)
  - `es_ES.json` (西班牙语)
  - `fr_FR.json` (法语)
  - `de_DE.json` (德语)
  - `ja_JP.json` (日语)
  - `ko_KR.json` (韩语)
  - `pt_BR.json` (葡萄牙语)
  - `ru_RU.json` (俄语)
  - `ar_SA.json` (阿拉伯语)

- ✅ 添加 `GET /api/v1/i18n/translations` 端点

### 2. 前端工具
- ✅ 创建 `static/i18n.js` 前端i18n工具文件

## 📋 待完成

### 1. 前端页面更新（高优先级）
- ⚠️ `static/login.html`：
  - 移除硬编码中文文本（"手机号/用户名"、"密码"、"登录"等）
  - 更新语言选择器，移除简体中文选项
  - 使用 i18n.js 加载翻译
  - 使用 data-i18n 属性标记需要翻译的元素

- ⚠️ `static/register.html`：
  - 移除硬编码中文文本
  - 更新语言选择器
  - 集成 i18n.js

- ⚠️ `static/dashboard.html`：
  - 移除硬编码中文文本
  - 更新语言选择器
  - 集成 i18n.js

- ⚠️ `static/room.html`：
  - 移除硬编码中文文本
  - 集成 i18n.js

- ⚠️ `static/scan_join.html`：
  - 移除硬编码中文文本
  - 集成 i18n.js

### 2. 语言资源文件完善
- ⚠️ 为新创建的语言文件添加完整翻译（目前使用英文作为占位符）

### 3. 测试
- ⚠️ 测试所有页面的多语言切换
- ⚠️ 测试登录/注册页面的i18n功能
- ⚠️ 测试默认语言检测

## 🔧 技术细节

### 支持的语言列表
1. `en_US` - English (默认)
2. `zh_TW` - 繁體中文
3. `es_ES` - Español
4. `fr_FR` - Français
5. `de_DE` - Deutsch
6. `ja_JP` - 日本語
7. `ko_KR` - 한국어
8. `pt_BR` - Português (Brasil)
9. `ru_RU` - Русский
10. `ar_SA` - العربية

### 前端i18n使用方法

```html
<!-- 1. 引入 i18n.js -->
<script src="/static/i18n.js"></script>

<!-- 2. 使用 data-i18n 属性 -->
<label data-i18n="auth.login.username_label">手机号/用户名</label>
<input type="text" data-i18n="auth.login.username_placeholder" placeholder="手机号/用户名">

<!-- 3. 在 JavaScript 中使用 -->
<script>
// 初始化
await window.i18n.init();

// 获取翻译
const text = window.i18n.t('auth.login.success');

// 切换语言
await window.i18n.switchLanguage('zh_TW');
</script>
```

### API 端点

- `GET /api/v1/i18n/languages` - 获取支持的语言列表
- `GET /api/v1/i18n/current` - 获取当前语言设置
- `GET /api/v1/i18n/translations?lang=en_US` - 获取指定语言的翻译资源
- `POST /api/v1/i18n/switch` - 切换用户语言偏好（需登录）

## 📝 注意事项

1. **默认语言**: 已改为 `en_US` (英语)
2. **语言检测**: 优先使用用户设置，其次浏览器语言，最后回退到英语
3. **硬编码文本**: 所有前端页面必须使用 i18n，不允许硬编码
4. **登录页面**: 必须移除所有硬编码的中文文本，包括：
   - "手机号/用户名"
   - "密码"
   - "登录"
   - "注册"
   - "用户须知和免责声明"
   - 等等

## 🚀 下一步

1. 更新 `login.html` 页面
2. 更新 `register.html` 页面
3. 更新其他前端页面
4. 完善语言资源文件的翻译
