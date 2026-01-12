# 服务器重启通知

**日期**: 2026-01-10  
**原因**: 应用8位16进制房间ID新格式

## 已完成的更改

1. ✅ 更新房间ID生成逻辑为8位16进制格式
2. ✅ 实现碰撞检测和重试机制
3. ✅ 添加格式验证函数
4. ✅ 更新多语言支持
5. ✅ **服务器已重启，新代码已生效**

## 新房间ID格式

**格式**: `r-{8位16进制}`  
**示例**: `r-a1b2c3d4`, `r-12345678`, `r-e80f9057`  
**长度**: 10字符

## 验证

### 测试生成
```bash
cd /opt/mop
python3 -c "from app.api.v1.rooms import generate_hex8_room_id; [print(generate_hex8_room_id()) for _ in range(5)]"
```

### 预期输出
```
r-be7441cb
r-203948d5
r-7dd8cbf4
r-a1b2c3d4
r-12345678
```

## 使用说明

### 自动生成（推荐）
创建房间时不提供 `room_id`，系统会自动生成8位16进制格式：
```json
POST /api/v1/rooms/create
{
    "room_name": "我的房间",
    "max_occupants": 10
}
```

### 自定义房间ID（向后兼容）
用户仍可以提供自定义房间ID，支持旧格式：
```json
POST /api/v1/rooms/create
{
    "room_id": "my-custom-room",
    "room_name": "自定义房间"
}
```

## 注意事项

1. ✅ 旧格式房间ID继续有效，无需迁移
2. ✅ 新创建的房间自动使用新格式
3. ✅ 碰撞检测确保ID唯一性
4. ✅ 最多重试10次生成唯一ID

---

**服务器状态**: ✅ 已重启并运行  
**新功能**: ✅ 已生效
