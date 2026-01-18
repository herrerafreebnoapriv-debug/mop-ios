# Android APK 构建 - 下一步操作指南

## 📋 当前状态

### ✅ 已完成
- Android SDK 环境配置完成
- Gradle 配置完成（AGP 7.4.2, Gradle 7.6, Kotlin 2.0.21）
- 所有 Flutter 代码编译错误已修复
- SDK 版本：minSdkVersion 24, targetSdkVersion 34
- 插件修复：call_log, contacts_service, geolocator_android (namespace)

### ⚠️ 当前问题
- **geolocator_android 构建失败**（暂时跳过，保留依赖）

## 🚀 在新窗口继续构建

### 方案 A：暂时移除 geolocator 使用（推荐，快速完成构建）

```bash
cd /opt/mop/mobile

# 1. 暂时注释掉 geolocator 相关代码（如果存在）
# 2. 保留 pubspec.yaml 中的依赖声明

# 3. 构建 APK
export ANDROID_HOME=~/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
flutter build apk --release --target-platform android-arm64 --no-shrink --no-tree-shake-icons
```

### 方案 B：继续修复 geolocator 问题

1. 尝试更新 geolocator 到最新版本
2. 检查 Google Play Services 依赖冲突
3. 考虑使用替代定位库

## 📝 关键配置

### SDK 版本
- minSdkVersion: **24**
- targetSdkVersion: **34**
- compileSdkVersion: **34**

### 构建工具
- Gradle: 7.6
- AGP: 7.4.2
- Kotlin: 2.0.21

### 环境变量
```bash
export ANDROID_HOME=~/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
```

## 📂 重要文件位置

- 构建配置：`/opt/mop/mobile/android/app/build.gradle`
- 项目配置：`/opt/mop/mobile/android/build.gradle`
- 依赖配置：`/opt/mop/mobile/pubspec.yaml`
- 进度文档：`/opt/mop/ANDROID_BUILD_PROGRESS.md`

## 🔍 调试命令

```bash
# 清理构建
cd /opt/mop/mobile && flutter clean

# 检查环境
flutter doctor -v

# 查看详细错误
cd /opt/mop/mobile/android && ./gradlew assembleRelease --stacktrace
```
