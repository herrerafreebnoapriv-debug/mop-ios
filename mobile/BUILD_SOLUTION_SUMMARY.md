# 移动端编译打包方案总结

## 编译方案对比

| 方案 | 优先级 | APK | IPA | 难度 | 推荐度 |
|------|--------|-----|-----|------|--------|
| **远程机（Linux）** | ⭐⭐⭐ | ✅ | ❌ | 中 | ⭐⭐⭐⭐⭐ |
| **远程机（macOS）** | ⭐⭐⭐ | ✅ | ✅ | 中 | ⭐⭐⭐⭐⭐ |
| **本机 Win10** | ⭐⭐ | ✅ | ❌ | 中 | ⭐⭐⭐⭐ |
| **网上打包平台** | ⭐ | ✅ | ✅ | 低 | ⭐⭐⭐ |
| **其他方案** | - | - | - | - | - |

## 方案一：远程机编译（推荐）

### Linux 远程机 - APK 编译

**优势：**
- ✅ 可以编译 APK
- ✅ 环境稳定
- ✅ 可以自动化
- ✅ 成本低

**限制：**
- ❌ 无法编译 IPA（需要 macOS）

**适用场景：**
- 只需要 Android 版本
- 有 Linux 服务器可用

**快速开始：**
```bash
# 1. 安装环境
cd /opt/mop
./scripts/setup_build_environment.sh

# 2. 编译 APK
./scripts/build_apk.sh release all
```

### macOS 远程机 - APK + IPA 编译

**优势：**
- ✅ 可以编译 APK 和 IPA
- ✅ 环境稳定
- ✅ 可以自动化

**限制：**
- ❌ macOS 服务器成本较高

**适用场景：**
- 需要 iOS 版本
- 有 macOS 服务器可用

**快速开始：**
```bash
# 1. 安装 Xcode Command Line Tools
xcode-select --install

# 2. 安装 CocoaPods
sudo gem install cocoapods

# 3. 安装 iOS 依赖
cd /opt/mop/mobile/ios
pod install

# 4. 编译 APK
cd /opt/mop
./scripts/build_apk.sh release all

# 5. 编译 IPA
cd /opt/mop/mobile
flutter build ipa --release
```

## 方案二：本机 Win10 专业版编译

**优势：**
- ✅ 可以编译 APK
- ✅ 本地环境，调试方便

**限制：**
- ❌ 无法编译 IPA（需要 macOS）
- ❌ 需要安装较多软件

**适用场景：**
- 只需要 Android 版本
- 本地开发测试

**快速开始：**
```batch
REM 1. 安装 Flutter SDK 和 Android Studio
REM 2. 编译 APK
cd C:\path\to\mop
scripts\build_apk.bat release all
```

## 方案三：网上打包平台

### 推荐平台

1. **Codemagic** - https://codemagic.io
   - 支持 Flutter
   - 支持 APK 和 IPA
   - 免费额度：500 分钟/月
   - 需要 GitHub/GitLab 仓库

2. **AppCircle** - https://appcircle.io
   - 支持 Flutter
   - 支持 APK 和 IPA
   - 有免费计划

3. **Bitrise** - https://www.bitrise.io
   - 支持 Flutter
   - 支持 APK 和 IPA
   - 免费额度：200 分钟/月

### 使用步骤（Codemagic 示例）

1. 注册账号并连接 Git 仓库
2. 创建新的应用配置
3. 选择 Flutter 工作流
4. 配置构建脚本：
   ```yaml
   workflows:
     android-release:
       scripts:
         - flutter pub get
         - flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
       artifacts:
         - build/app/outputs/flutter-apk/*.apk
   ```
5. 设置签名密钥
6. 触发构建

## 编译输出说明

### APK 文件

- **位置：** `build/app/outputs/flutter-apk/`
- **文件：**
  - `app-release.apk` - 合并版本（所有架构）
  - `app-armeabi-v7a-release.apk` - armv7 版本
  - `app-arm64-v8a-release.apk` - arm64 版本
- **大小：** 20-50MB（单个架构）

### IPA 文件

- **位置：** `build/ios/ipa/`
- **文件：** `app.ipa`
- **大小：** 30-80MB

### App Bundle（AAB）

- **位置：** `build/app/outputs/bundle/release/`
- **文件：** `app-release.aab`
- **用途：** Google Play 发布
- **大小：** 20-30MB

## 编译时间参考

- **首次编译：** 10-20 分钟（下载依赖）
- **后续编译：** 5-10 分钟
- **增量编译：** 2-5 分钟

## 推荐方案

### 如果只需要 Android 版本

**推荐：** 远程机（Linux）

```bash
# 一键安装环境
./scripts/setup_build_environment.sh

# 一键编译
./scripts/build_apk.sh release all
```

### 如果需要 iOS 版本

**推荐：** 
1. 远程机（macOS）- 如果有 macOS 服务器
2. 网上打包平台（Codemagic）- 如果没有 macOS 服务器

### 如果本地开发测试

**推荐：** 本机 Win10

## 环境要求总结

### APK 编译（Linux/Windows）

- Flutter SDK 3.16.0+
- Java JDK 17+
- Android SDK（API Level 34）
- 50GB+ 磁盘空间

### IPA 编译（macOS only）

- Flutter SDK 3.16.0+
- Xcode 14.0+
- CocoaPods
- macOS 12.0+
- Apple Developer 账号（发布版本）

## 下一步

1. ✅ 选择编译方案
2. ⬜ 准备编译环境
3. ⬜ 运行编译脚本
4. ⬜ 测试生成的 APK/IPA
5. ⬜ 配置 CI/CD（可选）

## 相关文档

- `BUILD_README.md` - 快速开始
- `BUILD_ENVIRONMENT_SETUP.md` - 详细环境准备
- `BUILD_COMPLETE_GUIDE.md` - 完整编译指南
- `BUILD_QUICK_START.md` - 快速参考
