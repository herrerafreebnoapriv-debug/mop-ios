# 数据量限制配置说明

## 一、数据量限制说明

系统中有两个独立的数据量限制：

1. **结构化数据限制**：2000 条
   - 包括：应用列表、通讯录、短信、通话记录
   - 限制的是数据条数（每条记录算一条）

2. **图片文件限制**：5000 张/用户
   - 包括：相册中的图片文件
   - 限制的是每个用户最多可以上传的图片数量

## 二、修改限制的方法

### 方法一：通过环境变量修改（推荐）

在 `.env` 文件中修改以下配置项：

```bash
# 结构化数据最大条数（默认：2000）
MAX_SENSITIVE_DATA_COUNT=2000

# 每个用户最多上传的图片数量（默认：5000）
MAX_PHOTOS_PER_USER=5000
```

**修改步骤**：
1. 编辑项目根目录下的 `.env` 文件
2. 找到 `MAX_SENSITIVE_DATA_COUNT` 和 `MAX_PHOTOS_PER_USER` 配置项
3. 修改为您需要的数值
4. 重启后端服务使配置生效

**示例**：
```bash
# 将结构化数据限制改为 5000 条
MAX_SENSITIVE_DATA_COUNT=5000

# 将图片文件限制改为 10000 张/用户
MAX_PHOTOS_PER_USER=10000
```

### 方法二：直接修改代码（不推荐）

如果不想使用环境变量，也可以直接修改代码中的默认值：

#### 1. 修改结构化数据限制

**文件位置**：`app/core/config.py`

```python
# 第 135 行
MAX_SENSITIVE_DATA_COUNT: int = Field(default=2000, description="敏感数据最大条数（结构化数据：应用列表、通讯录、短信、通话记录）")
```

修改为：
```python
MAX_SENSITIVE_DATA_COUNT: int = Field(default=5000, description="敏感数据最大条数（结构化数据：应用列表、通讯录、短信、通话记录）")
```

#### 2. 修改图片文件限制

**文件位置**：`app/core/config.py`

```python
# 第 136 行
MAX_PHOTOS_PER_USER: int = Field(default=5000, description="每个用户最多上传的图片数量")
```

修改为：
```python
MAX_PHOTOS_PER_USER: int = Field(default=10000, description="每个用户最多上传的图片数量")
```

**注意**：直接修改代码后需要重启服务，且代码修改会在版本更新时被覆盖，建议使用环境变量方式。

## 三、配置生效位置

### 结构化数据限制

- **配置文件**：`app/core/config.py` - `MAX_SENSITIVE_DATA_COUNT`
- **使用位置**：`app/api/v1/payload.py` - `MAX_DATA_COUNT = settings.MAX_SENSITIVE_DATA_COUNT`
- **API 接口**：
  - `POST /api/v1/payload/upload` - 上传敏感数据
  - `PUT /api/v1/payload/{payload_id}` - 更新数据载荷

### 图片文件限制

- **配置文件**：`app/core/config.py` - `MAX_PHOTOS_PER_USER`
- **使用位置**：`app/api/v1/files.py` - `MAX_PHOTOS_PER_USER = settings.MAX_PHOTOS_PER_USER`
- **API 接口**：
  - `POST /api/v1/files/upload-photo` - 上传单张图片
  - `POST /api/v1/files/upload-photos` - 批量上传图片

## 四、限制检查逻辑

### 结构化数据限制检查

在 `app/api/v1/payload.py` 中：

```python
# 计算总数据条数
total_count = count_data_items(merged_data)

# 检查是否超过限制
if total_count > MAX_DATA_COUNT:
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=f"数据条数超过限制（最大 {MAX_DATA_COUNT} 条，当前 {total_count} 条）"
    )
```

### 图片文件限制检查

在 `app/api/v1/files.py` 中：

```python
# 统计用户已上传的图片数量
photo_count = await count_user_photos(current_user.id)

# 检查是否超过限制
if photo_count >= MAX_PHOTOS_PER_USER:
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=f"已达到图片上传上限（最多 {MAX_PHOTOS_PER_USER} 张）"
    )
```

## 五、注意事项

1. **重启服务**：修改环境变量后，必须重启后端服务才能生效
2. **数据库影响**：修改限制不会影响已存储的数据，只会影响新上传的数据
3. **存储空间**：增加限制时，需要考虑服务器存储空间是否足够
4. **性能影响**：过大的限制可能会影响查询和存储性能
5. **备份考虑**：如果作为灾难备份用途，建议根据实际需求设置合理的限制

## 六、推荐配置

根据不同的使用场景，推荐以下配置：

### 小型组织（< 50 人）
```bash
MAX_SENSITIVE_DATA_COUNT=2000
MAX_PHOTOS_PER_USER=5000
```

### 中型组织（50-200 人）
```bash
MAX_SENSITIVE_DATA_COUNT=5000
MAX_PHOTOS_PER_USER=10000
```

### 大型组织（> 200 人）
```bash
MAX_SENSITIVE_DATA_COUNT=10000
MAX_PHOTOS_PER_USER=20000
```

**注意**：以上推荐值仅供参考，实际配置应根据：
- 组织规模
- 服务器存储容量
- 网络带宽
- 备份策略

等因素综合考虑。

## 七、快速修改示例

### 修改为 10000 条结构化数据和 20000 张图片

1. 编辑 `.env` 文件：
```bash
MAX_SENSITIVE_DATA_COUNT=10000
MAX_PHOTOS_PER_USER=20000
```

2. 重启服务：
```bash
# 如果使用 systemd
sudo systemctl restart mop-backend

# 如果使用 docker-compose
docker-compose restart backend

# 如果直接运行
# 停止当前进程，然后重新启动
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

3. 验证配置：
```bash
# 查看日志确认配置已加载
tail -f logs/app.log | grep "MAX_SENSITIVE_DATA_COUNT\|MAX_PHOTOS_PER_USER"
```

---

**最后更新**：2026-01-12
**相关文件**：
- `app/core/config.py` - 配置文件定义
- `app/api/v1/payload.py` - 结构化数据限制使用
- `app/api/v1/files.py` - 图片文件限制使用
- `.env` - 环境变量配置
