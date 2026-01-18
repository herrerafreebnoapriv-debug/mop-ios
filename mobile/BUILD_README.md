# 移动端编译打包指南

## 📋 快速开始

### 方案优先级

1. **远程机（Linux）** ⭐ 最高优先级
2. **本机 Win10 专业版**
3. **网上打包平台**
4. **其他方案**

## 🚀 远程机编译（推荐）

### 一键安装环境

```bash
# 运行环境安装脚本
cd /opt/mop
./scripts/setup_build_environment.sh
```

### 检查环境

```bash
# 运行环境检查脚本
cd /opt/mop/mobile
./ENVIRONMENT_CHECK.sh
```

### 编译 APK

```bash
# 使用编译脚本（推荐）
cd /opt/mop
./scripts/build_apk.sh release all

# APK 输出位置
ls -lh build_output/
```

## 💻 Windows 10 编译

### 环境准备

1. 安装 Flutter SDK
2. 安装 Android Studio
3. 安装 Java JDK 17

详细步骤见：`BUILD_ENVIRONMENT_SETUP.md`

### 编译命令

```batch
cd C:\path\to\mop
scripts\build_apk.bat release all
```

## 📱 iOS 编译说明

**重要：** iOS 编译必须在 macOS 系统上进行，Linux 和 Windows 无法直接编译 IPA。

### 如果远程机是 macOS

```bash
# 安装 Xcode Command Line Tools
xcode-select --install

# 安装 CocoaPods
sudo gem install cocoapods

# 安装依赖
cd /opt/mop/mobile/ios
pod install

# 编译 IPA
cd /opt/mop/mobile
flutter build ipa --release
```

### 如果远程机是 Linux/Windows

需要使用以下方案之一：
1. 使用 macOS 远程机
2. 使用网上打包平台（如 Codemagic）
3. 使用本机 macOS（如果有）

## 📦 输出文件

### APK 文件

编译完成后，APK 文件位于：

- **合并版本：** `build/app/outputs/flutter-apk/app-release.apk`
- **armv7 版本：** `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- **arm64 版本：** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### App Bundle（用于 Google Play）

```bash
flutter build appbundle --release
```

输出：`build/app/outputs/bundle/release/app-release.aab`

## 🔐 签名配置

### 生成签名密钥

```bash
cd /opt/mop/mobile/android/app
keytool -genkey -v -keystore mop-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mop-key \
  -storepass YOUR_PASSWORD \
  -keypass YOUR_PASSWORD
```

### 创建 key.properties

```bash
cat > /opt/mop/mobile/android/key.properties << EOF
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=mop-key
storeFile=app/mop-release-key.jks
EOF
```

## ✅ 编译检查清单

### 编译前

- [ ] Flutter SDK 已安装
- [ ] Java JDK 17 已安装
- [ ] Android SDK 已配置
- [ ] 项目依赖已获取（`flutter pub get`）
- [ ] 签名密钥已配置（发布版本）

### 编译后

- [ ] APK 文件已生成
- [ ] APK 文件大小合理（20-50MB）
- [ ] 可以安装到测试设备
- [ ] 应用可以正常启动

## 📚 相关文档

- `BUILD_ENVIRONMENT_SETUP.md` - 详细环境准备指南
- `BUILD_COMPLETE_GUIDE.md` - 完整编译指南
- `BUILD_QUICK_START.md` - 快速开始指南

## 🆘 常见问题

### Flutter 未找到
```bash
export PATH="$PATH:/opt/flutter/bin"
source ~/.bashrc
```

### 依赖获取失败
```bash
flutter clean
flutter pub get
```

### 编译失败
```bash
# 查看详细错误
flutter build apk --release --verbose
```

更多问题请参考：`BUILD_COMPLETE_GUIDE.md`
