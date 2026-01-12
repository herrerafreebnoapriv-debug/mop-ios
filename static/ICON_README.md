# 图标和 Favicon 使用说明

## 文件结构

```
static/
├── icons/          # 应用图标（包含 ico 的文件）
│   ├── mop_ico (1).png
│   ├── mop_ico (2).png
│   └── ...
├── favicons/       # 网页小图标（包含 fav 的文件）
│   ├── fav1.ico
│   ├── fav2.ico
│   └── ...
└── manifest.json   # PWA 配置
```

## 图标分类

### 1. 应用图标（ico 文件）
- **位置**: `static/icons/`
- **用途**: 
  - PWA 应用图标
  - 移动端应用图标（Flutter、鸿蒙）
  - 桌面端应用图标
- **文件命名**: 包含 `ico` 的文件名
- **示例**: `mop_ico (1).png`, `mop-ico (2).png`

### 2. 网页小图标（fav 文件）
- **位置**: `static/favicons/`
- **用途**: 
  - 浏览器标签页图标（favicon）
  - 书签图标
- **文件命名**: 包含 `fav` 的文件名
- **格式**: `.ico`, `.png`, `.svg` 等
- **示例**: `fav1.ico`, `mop-fav.png`

## 随机选择机制

### Favicon 随机选择
- 每次页面加载时，`/favicon.ico` 会随机返回一个 favicon
- 如果 `static/favicons/` 目录中有文件，随机选择一个
- 如果没有 favicon 文件，会从图标中选择最小的作为默认

### 使用方法

1. **添加 Favicon 文件**:
   ```bash
   # 将包含 fav 的文件放到 mop_ico_fav/ 目录
   # 运行处理脚本
   python scripts/process_favicons.py
   ```

2. **添加应用图标**:
   ```bash
   # 将包含 ico 的文件放到 mop_ico_fav/ 目录
   # 运行处理脚本（会自动复制到 static/icons/）
   python scripts/process_favicons.py
   ```

3. **生成 PWA 图标尺寸**:
   ```bash
   # 从现有图标生成各种尺寸
   python scripts/generate_icons.py
   ```

## 文件格式转换

### PNG 转 ICO
如果 fav 文件是 PNG 格式，脚本会自动转换为 ICO 格式：

```python
# scripts/process_favicons.py 会自动处理
# 支持格式: .png, .jpg, .jpeg, .svg -> .ico
```

### 手动转换
如果需要手动转换：

```bash
# 使用 ImageMagick
convert fav.png -define icon:auto-resize=16,32,48 fav.ico

# 或使用在线工具
```

## API 端点

### 随机 Favicon
```
GET /favicon.ico
```
每次请求随机返回一个 favicon

### 指定 Favicon
```
GET /api/v1/favicon/{filename}
```
获取指定的 favicon 文件

## Flutter 和鸿蒙支持

### Flutter Web
- PWA manifest.json 已配置，支持添加到主屏幕
- 图标文件会自动被 Flutter Web 使用

### 鸿蒙 WebView
- 支持标准的 favicon 和 manifest.json
- 图标会自动适配鸿蒙系统

## 注意事项

1. **文件命名规则**:
   - 应用图标: 文件名必须包含 `ico`
   - 网页图标: 文件名必须包含 `fav`

2. **文件格式**:
   - Favicon 推荐使用 `.ico` 格式（多尺寸支持）
   - 应用图标可以使用 `.png` 格式（高分辨率）

3. **图标尺寸**:
   - Favicon: 16x16, 32x32, 48x48（ICO 格式支持多尺寸）
   - 应用图标: 72x72 到 512x512（PWA 标准尺寸）

4. **缓存问题**:
   - 浏览器会缓存 favicon，使用 `?v=random` 参数强制刷新
   - 每次页面加载会随机选择，但浏览器可能使用缓存

## 更新图标

1. 将新文件放到 `mop_ico_fav/` 目录
2. 运行 `python scripts/process_favicons.py`
3. 如果需要生成 PWA 尺寸，运行 `python scripts/generate_icons.py`
4. 重启服务器使更改生效

---

**最后更新**: 2026-01-10
