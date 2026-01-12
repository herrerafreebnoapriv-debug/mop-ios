# 二维码数据结构说明

## 优化后的数据结构

### 加密前的实际结构（优化后）

```json
{
  "r": "test-room-1234567890",  // room_id (短键名)
  "t": 1768085155               // timestamp (短键名)
}
```

**说明**:
- 使用短键名 `r` 代替 `room_id`，`t` 代替 `timestamp`
- **省略了 `api_url`**，因为它是固定的后端配置，可以从 `settings.JITSI_SERVER_URL` 读取
- JSON 紧凑格式（无空格）：43 字符

### 加密后的结构

```
Base64编码的字符串，格式：
base64(json_data + "|" + base64(signature))

实际内容示例：
eyJyIjoidGVzdC1yb29tLTEyMzQ1Njc4OTAiLCJ0IjoxNzY4MDg1MTUwfXxQd0NaYzJHaWVlbmhhMjVqYXE4RWU5V1ZHM2k1akd2...
```

**长度**: 约 520 字符（优化前 588 字符，减少 60 字符，约 10.3%）

### 解密后的结构（自动扩展）

```json
{
  "room_id": "test-room-1234567890",
  "timestamp": 1768085155,
  "api_url": "https://meet.jit.si"  // 从配置自动添加
}
```

## 键名映射

| 短键名 | 完整键名 | 说明 |
|--------|---------|------|
| `u` | `api_url` | API 服务器地址（通常省略） |
| `r` | `room_id` | 房间ID |
| `t` | `timestamp` | 时间戳 |
| `e` | `expires_at` | 过期时间（可选） |

## 优化效果

### 数据量对比

| 项目 | 优化前 | 优化后 | 减少 |
|------|--------|--------|------|
| JSON字符串 | 94 字符 | 43 字符 | 51 字符 (54.3%) |
| 加密后Base64 | 588 字符 | 520 字符 | 68 字符 (11.6%) |
| 二维码版本 | 版本15 | 版本15 | - |

### 优化措施

1. **使用短键名**: `room_id` → `r`，`timestamp` → `t`
2. **省略固定字段**: `api_url` 从后端配置读取，不包含在二维码中
3. **紧凑JSON格式**: 无空格，最小化数据量
4. **自动扩展**: 解密时自动将短键名扩展为完整键名

## 二维码版本

- **当前数据长度**: 520 字符
- **所需版本**: 版本15（Level H 容错）
- **最大容量**: 559 字符
- **密度**: 仍较密集，但比优化前改善约11%

## 使用示例

### 生成二维码

```python
from app.core.security import rsa_encrypt

data = {
    "r": "room-123",  # room_id
    "t": 1768085155   # timestamp
}

encrypted = rsa_encrypt(data, use_short_keys=True)
# 返回: Base64编码的加密字符串（约520字符）
```

### 验证二维码

```python
from app.core.security import rsa_decrypt
from app.core.config import settings

decrypted = rsa_decrypt(encrypted, expand_short_keys=True)
# 返回: {"room_id": "room-123", "timestamp": 1768085155}

# 自动添加api_url
if "api_url" not in decrypted:
    decrypted["api_url"] = settings.JITSI_SERVER_URL
```

## 注意事项

1. **向后兼容**: 旧格式（完整键名）仍然支持，会自动扩展
2. **api_url处理**: 如果二维码中没有 `api_url`，系统会自动从配置读取
3. **安全性**: RSA-2048 签名长度固定（约344字符），无法进一步优化
4. **扫描性能**: 虽然仍需要版本15，但数据量减少使二维码更易扫描

---

**最后更新**: 2026-01-10
