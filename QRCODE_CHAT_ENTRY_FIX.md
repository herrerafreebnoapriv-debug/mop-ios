# 二维码生成逻辑修复 - 使用聊天页面入口

**日期**: 2026-01-16  
**状态**: ✅ 已修复

## 🐛 问题描述

APP端是聊天功能而不是后台，问题出现在后台的二维码生成逻辑上，应该使用聊天页面的入口。

**原问题**:
- 二维码生成时，`api_url` 使用的是 `settings.JITSI_SERVER_URL`（Jitsi服务器地址）
- 但APP端是聊天功能，应该使用聊天页面的API入口（`log.chat5202ol.xyz/api/v1`）

## ✅ 修复内容

### 1. 修复加密二维码的 `api_url`

**修改文件**: `/opt/mop/app/api/v1/qrcode.py`

**修复位置**: 
- `get_room_qrcode()` 函数中的加密二维码生成逻辑
- `get_room_qrcode_image()` 函数中的加密二维码生成逻辑

**修复前**:
```python
data = {
    "room_id": room_id,
    "api_url": settings.JITSI_SERVER_URL,  # ❌ 使用Jitsi服务器地址
}
```

**修复后**:
```python
# 从请求中获取基础URL，构建聊天页面的API地址
base_url = str(request.base_url).rstrip('/') if request else ''

# 构建API地址：优先使用聊天页面的域名
if base_url and 'log.chat5202ol.xyz' in base_url:
    # 来自聊天页面，使用当前请求的域名
    api_url = f"{base_url}/api/v1"
elif base_url and ('www.chat5202ol.xyz' in base_url or 'api.chat5202ol.xyz' in base_url):
    # 来自后台管理系统，使用聊天页面的API地址
    api_url = base_url.replace('www.chat5202ol.xyz', 'log.chat5202ol.xyz').replace('api.chat5202ol.xyz', 'log.chat5202ol.xyz') + '/api/v1'
else:
    # 使用默认聊天页面API地址
    api_url = "https://log.chat5202ol.xyz/api/v1"

data = {
    "room_id": room_id,
    "api_url": api_url,  # ✅ 使用聊天页面的API入口
}
```

### 2. 修复未加密二维码的 URL

**修复位置**: 
- `get_room_qrcode()` 函数中的未加密二维码生成逻辑
- `get_room_qrcode_image()` 函数中的未加密二维码生成逻辑

**修复前**:
```python
base_url = str(request.base_url).rstrip('/')
room_url = f"{base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
# ❌ 使用当前请求的base_url（可能是后台管理系统）
```

**修复后**:
```python
# 构建聊天页面的基础URL
if base_url and 'log.chat5202ol.xyz' in base_url:
    chat_base_url = base_url
elif base_url and ('www.chat5202ol.xyz' in base_url or 'api.chat5202ol.xyz' in base_url):
    # 来自后台管理系统，使用聊天页面域名
    chat_base_url = base_url.replace('www.chat5202ol.xyz', 'log.chat5202ol.xyz').replace('api.chat5202ol.xyz', 'log.chat5202ol.xyz')
else:
    chat_base_url = "https://log.chat5202ol.xyz"

# 构建房间URL（使用聊天页面的入口）
room_url = f"{chat_base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
# ✅ 使用聊天页面的入口
```

## 📋 域名映射逻辑

### 聊天页面域名
- **主域名**: `log.chat5202ol.xyz`
- **API入口**: `https://log.chat5202ol.xyz/api/v1`
- **房间页面**: `https://log.chat5202ol.xyz/room/{room_id}`

### 后台管理系统域名
- **主域名**: `www.chat5202ol.xyz`
- **API服务**: `api.chat5202ol.xyz`
- **用途**: 后台管理系统

### 二维码生成逻辑

1. **如果请求来自聊天页面** (`log.chat5202ol.xyz`):
   - 使用当前请求的域名构建API地址
   - 例如: `https://log.chat5202ol.xyz/api/v1`

2. **如果请求来自后台管理系统** (`www.chat5202ol.xyz` 或 `api.chat5202ol.xyz`):
   - 自动转换为聊天页面域名
   - 例如: `https://www.chat5202ol.xyz` → `https://log.chat5202ol.xyz/api/v1`

3. **开发环境或无法获取域名**:
   - 使用默认聊天页面地址: `https://log.chat5202ol.xyz/api/v1`

## 🔄 修复后的效果

### 加密二维码
- ✅ `api_url` 现在指向聊天页面的API入口
- ✅ APP扫码后可以正确调用聊天功能的API
- ✅ 不再使用Jitsi服务器地址作为API入口

### 未加密二维码
- ✅ URL现在指向聊天页面的房间入口
- ✅ 扫码后直接进入聊天页面的房间
- ✅ 不再使用后台管理系统的URL

## 📝 相关文件

- `/opt/mop/app/api/v1/qrcode.py` - 二维码生成API
  - `get_room_qrcode()` - 获取房间二维码（JSON响应）
  - `get_room_qrcode_image()` - 获取房间二维码图片（PNG响应）

## 🔧 修复的函数

1. **`get_room_qrcode()`**:
   - ✅ 修复了加密二维码的 `api_url` 生成逻辑
   - ✅ 修复了未加密二维码的 URL 生成逻辑

2. **`get_room_qrcode_image()`**:
   - ✅ 修复了加密二维码的 `api_url` 生成逻辑
   - ✅ 修复了未加密二维码的 URL 生成逻辑

## ✅ 验证建议

1. **测试加密二维码**:
   - 从后台管理系统生成房间二维码
   - 检查二维码中的 `api_url` 是否为 `https://log.chat5202ol.xyz/api/v1`
   - APP扫码后是否能正确调用API

2. **测试未加密二维码**:
   - 从后台管理系统生成房间二维码（未加密模式）
   - 检查二维码URL是否为 `https://log.chat5202ol.xyz/room/{room_id}?jwt=...&server=...`
   - 扫码后是否能正确进入聊天页面的房间

3. **测试从聊天页面生成**:
   - 从聊天页面生成房间二维码
   - 检查是否使用聊天页面的域名
