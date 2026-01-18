# Flutter APK 构建规则

## 📋 核心规则

**每次修改代码后，构建 APK 前必须：**
1. ✅ **清理构建缓存** - 确保使用最新代码
2. ✅ **递增版本号** - 确保 Android 系统识别为新版本
3. ✅ **重新构建** - 使用新版本号生成 APK

## 🚀 使用方法

### 方法 1: 使用自动化脚本（推荐）

```bash
cd /opt/mop/mobile

# 构建 Release APK（推荐）
./build_apk.sh release

# 构建 Debug APK
./build_apk.sh debug
```

脚本会自动执行：
- ✅ 读取当前版本号
- ✅ 自动递增构建号（versionCode）
- ✅ 清理 Flutter 构建缓存
- ✅ 清理 Android 构建目录
- ✅ 获取依赖
- ✅ 构建 APK
- ✅ 显示 APK 路径和安装命令

### 方法 2: 手动构建

如果需要手动构建，请按以下步骤操作：

```bash
cd /opt/mop/mobile

# 1. 更新 pubspec.yaml 中的版本号
# 格式: version: 1.0.0-test+N
# 例如: 1.0.0-test+1 → 1.0.0-test+2

# 2. 清理构建缓存
flutter clean
rm -rf android/app/build android/build android/.gradle

# 3. 获取依赖
flutter pub get

# 4. 构建 APK
flutter build apk --release
```

## 📝 版本号格式说明

Flutter 版本号格式：`versionName+buildNumber`

- **versionName**: 显示给用户的版本名称（如 `1.0.0-test`）
- **buildNumber**: 构建号，对应 Android 的 `versionCode`（必须递增）

示例：
```yaml
version: 1.0.0-test+1  # 版本名称: 1.0.0-test, 构建号: 1
version: 1.0.0-test+2  # 版本名称: 1.0.0-test, 构建号: 2
version: 1.0.1+1       # 版本名称: 1.0.1, 构建号: 1
```

## ⚠️ 重要提示

1. **版本号必须递增**: 如果 `versionCode` 相同或更小，Android 不会识别为新版本，安装后仍会显示旧版。

2. **必须清理缓存**: 未清理缓存可能导致构建使用旧的版本信息或代码。

3. **构建类型**:
   - `release`: 生产环境发布版本（已签名、已优化）
   - `debug`: 开发调试版本（未签名、包含调试信息）

## 📦 APK 位置

构建完成后，APK 文件位于两个位置：

1. **原始构建文件**:
   - **Release**: `build/app/outputs/flutter-apk/app-release.apk`
   - **Debug**: `build/app/outputs/flutter-apk/app-debug.apk`

2. **下载目录（带版本号和时间戳）**:
   - **路径**: `../static/apk/`
   - **文件名格式**: `mop-app-v{版本号}+{构建号}-{时间戳}.apk`
   - **示例**: `mop-app-v1.0.0-test+3-20260117-123045.apk`

## 🔧 安装 APK

### 方法 1: 通过下载链接（推荐）

构建完成后，脚本会自动生成下载链接，可以直接在浏览器或设备上下载：

```
https://api.chat5202ol.xyz/static/apk/mop-app-v{版本号}+{构建号}-{时间戳}.apk
https://app.chat5202ol.xyz/static/apk/mop-app-v{版本号}+{构建号}-{时间戳}.apk
```

### 方法 2: 通过 ADB 安装

```bash
# 安装原始构建文件
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 或安装下载目录中的文件
adb install -r ../static/apk/mop-app-v*.apk
```

### 方法 3: 直接复制到设备

将 APK 文件复制到设备后手动安装。

## 📥 下载链接功能

每次构建完成后，脚本会自动：

1. ✅ **复制 APK 到下载目录** (`static/apk/`)
2. ✅ **生成带版本号和时间戳的文件名**
3. ✅ **显示下载链接**（可直接在浏览器中打开）
4. ✅ **保存构建信息** (`static/apk/latest-build-info.txt`)

### 文件名格式

```
mop-app-v{版本名称}+{构建号}-{时间戳}.apk

示例：
mop-app-v1.0.0-test+3-20260117-123045.apk
```

### 查看最新构建信息

```bash
cat ../static/apk/latest-build-info.txt
```

该文件包含：
- 构建时间
- 版本号
- 文件名
- APK 大小
- 下载链接
- 本地路径

## ❓ 常见问题

### Q: 为什么安装后仍是旧版？

**A:** 可能的原因：
1. `versionCode` 未递增 - 检查 `pubspec.yaml` 中的版本号
2. 构建缓存未清理 - 运行 `flutter clean` 并清理 Android 构建目录
3. 签名不同 - 如果签名不一致，可能需要先卸载旧版本

### Q: 如何查看当前版本号？

**A:** 
```bash
cd /opt/mop/mobile
grep "^version:" pubspec.yaml
```

### Q: 版本号应该递增多少？

**A:** 每次构建至少递增 1。如果跳过了多个版本，可以一次性递增更大的数值（如 +10）。

## 📚 相关文档

- `BUILD_README.md` - 详细构建文档
- `BUILD_QUICK_START.md` - 快速开始指南
- `SIGNING_SETUP_COMPLETE.md` - 签名配置说明
