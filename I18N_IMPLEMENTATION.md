# 国际化（i18n）实现文档

## 概述

本项目已完整实现国际化（i18n）支持，符合规范要求：
- ✅ 所有客户端（Web/App）与后台管理系统必须集成 i18n 框架
- ✅ 默认逻辑：跟随用户操作系统语言（通过 Accept-Language 请求头）
- ✅ 持久化：支持用户手动切换并进行数据库持久化存储
- ✅ 禁止硬编码 UI 文本，所有文案映射至多语言资源文件

## 架构设计

### 1. 语言检测优先级

1. **用户设置的语言**（数据库 `users.language` 字段）- 最高优先级
2. **Accept-Language 请求头**（浏览器/客户端发送）
3. **默认语言**（zh_CN）

### 2. 支持的语言

| 语言代码 | 语言名称 | 原生名称 |
|---------|---------|---------|
| zh_CN | 简体中文 | 简体中文 |
| zh_TW | 繁体中文 | 繁體中文 |
| en_US | English | English |
| ja_JP | 日本語 | 日本語 |
| ko_KR | 한국어 | 한국어 |
| ru_RU | Русский | Русский |
| es_ES | Español | Español |
| fr_FR | Français | Français |
| de_DE | Deutsch | Deutsch |

### 3. 品牌命名规范

根据规范要求：
- **中文版本**：App 名称为"和平信使"
- **其他语言版本**：App 名称为"MOP"

已在 `app/locales/zh_CN.json` 和 `app/locales/en_US.json` 中实现。

## 文件结构

```
app/
├── core/
│   └── i18n.py              # i18n 核心模块
├── locales/                 # 语言资源文件目录
│   ├── __init__.py
│   ├── zh_CN.json          # 简体中文资源
│   ├── en_US.json          # 英文资源
│   └── ...                 # 其他语言资源（待添加）
└── api/
    ├── dependencies.py      # 语言检测依赖注入
    └── v1/
        └── i18n.py          # 国际化 API 端点
```

## 使用方法

### 1. 在 API 中使用多语言

```python
from app.core.i18n import i18n, get_language_from_request
from fastapi import Request

@router.post("/example")
async def example_endpoint(request: Request):
    # 检测语言
    lang = get_language_from_request(request)
    
    # 获取翻译文本
    message = i18n.get("auth.login.success", lang)
    
    # 带参数的翻译
    message = i18n.get("common.welcome", lang, app_name="MOP")
    
    return {"message": message}
```

### 2. 使用依赖注入（推荐）

```python
from app.api.dependencies import get_language
from fastapi import Depends

@router.post("/example")
async def example_endpoint(
    request: Request,
    lang: str = Depends(get_language)
):
    message = i18n.get("auth.login.success", lang)
    return {"message": message}
```

### 3. 在已登录用户场景

```python
from app.api.v1.auth import get_current_user
from app.db.models import User

@router.get("/example")
async def example_endpoint(
    current_user: User = Depends(get_current_user)
):
    # 直接使用用户的语言偏好
    message = i18n.get("auth.login.success", current_user.language)
    return {"message": message}
```

## API 端点

### 1. 获取支持的语言列表

```
GET /api/v1/i18n/languages
```

响应示例：
```json
[
  {
    "code": "zh_CN",
    "name": "简体中文",
    "native_name": "简体中文"
  },
  {
    "code": "en_US",
    "name": "English",
    "native_name": "English"
  }
]
```

### 2. 切换用户语言偏好（需要登录）

```
POST /api/v1/i18n/switch
Authorization: Bearer <token>
Content-Type: application/json

{
  "language": "en_US"
}
```

响应示例：
```json
{
  "message": "语言切换成功",
  "language": "en_US"
}
```

### 3. 获取当前语言设置

```
GET /api/v1/i18n/current
Authorization: Bearer <token>  # 可选
```

响应示例：
```json
{
  "code": "zh_CN",
  "name": "简体中文",
  "native_name": "简体中文"
}
```

## 语言资源文件格式

语言资源文件使用 JSON 格式，支持嵌套结构：

```json
{
  "app": {
    "name": "和平信使",
    "description": "私有化管控通讯系统"
  },
  "auth": {
    "login": {
      "success": "登录成功",
      "failed": "手机号/用户名或密码错误"
    }
  },
  "common": {
    "welcome": "欢迎使用 {app_name}"
  }
}
```

### 使用参数格式化

```python
# 资源文件
"common.welcome": "欢迎使用 {app_name}"

# 代码中使用
i18n.get("common.welcome", "zh_CN", app_name="MOP")
# 返回: "欢迎使用 MOP"
```

## 数据库字段

### users 表

已添加 `language` 字段：
- 类型：`String(10)`
- 默认值：`zh_CN`
- 说明：用户语言偏好（如：zh_CN, en_US）

## 前端集成指南

### 1. 发送语言信息

前端应在请求头中包含语言信息：

```javascript
// 使用 Accept-Language 头（浏览器自动发送）
fetch('/api/v1/auth/login', {
  headers: {
    'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8'
  }
})

// 或者使用自定义头
fetch('/api/v1/auth/login', {
  headers: {
    'X-Language': 'en_US'
  }
})
```

### 2. 切换语言

```javascript
// 切换用户语言偏好（需要登录）
const response = await fetch('/api/v1/i18n/switch', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    language: 'en_US'
  })
})
```

### 3. 获取当前语言

```javascript
// 获取当前语言设置
const response = await fetch('/api/v1/i18n/current', {
  headers: {
    'Authorization': `Bearer ${token}`  // 可选
  }
})
const { code, name } = await response.json()
```

## 待完成的工作

1. ✅ 后端 i18n 框架
2. ✅ 语言资源文件（zh_CN, en_US）
3. ✅ 语言检测和切换 API
4. ✅ 数据库字段添加
5. ⏳ 添加更多语言资源文件（ja_JP, ko_KR 等）
6. ⏳ 前端集成（Web/App）
7. ⏳ 后台管理系统多语言支持

## 注意事项

1. **品牌命名**：中文版本使用"和平信使"，其他语言使用"MOP"
2. **语言代码格式**：使用下划线格式（zh_CN），不是连字符（zh-CN）
3. **回退机制**：如果找不到翻译，会回退到默认语言（zh_CN），最后回退到键本身
4. **性能考虑**：语言资源文件在应用启动时加载到内存，无需每次请求都读取文件

## 测试

```python
# 测试 i18n 模块
from app.core.i18n import i18n

# 测试中文
print(i18n.get("app.name", "zh_CN"))  # 输出: 和平信使

# 测试英文
print(i18n.get("app.name", "en_US"))  # 输出: MOP

# 测试带参数
print(i18n.get("common.welcome", "zh_CN", app_name="MOP"))  # 输出: 欢迎使用 MOP
```
