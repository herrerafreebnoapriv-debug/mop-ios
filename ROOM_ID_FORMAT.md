# 房间ID格式说明

## 简化格式

### 格式规范
```
r-{10位数字}{1位校验位}
```

**示例**:
- `r-1234567890x`
- `r-9876543210a`
- `r-6224633525f`

### 格式说明
- **前缀**: `r-`（固定）
- **数字部分**: 10位随机数字（0-9）
- **校验位**: 1位十六进制字符（0-9a-f），由SHA256哈希计算得出

### 长度
- **总长度**: 13字符（`r-` + 10位数字 + 1位校验位）
- **相比原始格式**: 减少约35%（原始格式约20字符）

## 生成逻辑

```python
def generate_short_room_id() -> str:
    # 生成10位随机数字
    digits = ''.join([str(random.randint(0, 9)) for _ in range(10)])
    
    # 计算校验位（SHA256的最后一位）
    hash_obj = hashlib.sha256(f"room_{digits}".encode())
    checksum = hash_obj.hexdigest()[-1]
    
    return f"r-{digits}{checksum}"
```

## 验证逻辑

```python
def validate_room_id_format(room_id: str) -> bool:
    # 1. 检查前缀
    if not room_id.startswith("r-"):
        return False
    
    # 2. 检查长度（11字符：10位数字 + 1位校验位）
    id_part = room_id[2:]
    if len(id_part) != 11:
        return False
    
    # 3. 检查前10位是否为数字
    if not id_part[:10].isdigit():
        return False
    
    # 4. 验证校验位
    digits = id_part[:10]
    expected_checksum = hashlib.sha256(f"room_{digits}".encode()).hexdigest()[-1]
    return id_part[10] == expected_checksum
```

## 二维码数据量影响

### 对比

| 格式 | 房间ID长度 | 加密后长度 | 减少 |
|------|-----------|-----------|------|
| 原始格式 | 20字符 | 432字符 | - |
| 简化格式 | 13字符 | 428字符 | 4字符 (0.9%) |

### 当前状态
- **简化后长度**: 428字符
- **目标**: ≤271字符（版本10）
- **差距**: 157字符

**注意**: 虽然简化了房间ID格式，但由于RSA-2048签名本身就有344字符，仍无法降到271字符以下。

## 向后兼容

- ✅ 支持用户自定义房间ID（保持原格式）
- ✅ 自动生成时使用简化格式
- ✅ 验证函数可以识别两种格式

## 使用示例

### 自动生成（简化格式）
```python
# 创建房间时不提供room_id，自动生成简化格式
POST /api/v1/rooms/create
{
    "room_name": "我的房间",
    "max_occupants": 10
}
# 返回: {"room_id": "r-1234567890x"}
```

### 自定义房间ID（支持原格式）
```python
# 用户可以提供自定义房间ID
POST /api/v1/rooms/create
{
    "room_id": "my-custom-room",
    "room_name": "自定义房间"
}
# 返回: {"room_id": "my-custom-room"}
```

---

**最后更新**: 2026-01-10
