# 移动端编译快速开始

## 快速编译命令

### 远程机（Linux）

```bash
# 使用编译脚本（推荐）
cd /opt/mop
./scripts/build_apk.sh release all

# 或手动编译
cd /opt/mop/mobile
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

### Windows 10

```batch
REM 使用编译脚本
cd C:\path\to\mop
scripts\build_apk.bat release all

REM 或手动编译
cd mobile
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

## 输出文件位置

编译完成后，APK 文件位于：

- **合并版本：** `build/app/outputs/flutter-apk/app-release.apk`
- **armv7 版本：** `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- **arm64 版本：** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

## 环境检查

### 快速检查命令

```bash
# 检查 Flutter
flutter --version
flutter doctor

# 检查 Java
java -version

# 检查 Android SDK
flutter doctor --android-licenses
```

## 常见问题快速解决

### Flutter 未找到
```bash
export PATH="$PATH:/opt/flutter/bin"
source ~/.bashrc
```

### 依赖问题
```bash
cd /opt/mop/mobile
flutter clean
flutter pub get
flutter pub upgrade
```

### 编译失败
```bash
# 查看详细错误
flutter build apk --release --verbose

# 清理后重试
flutter clean
flutter pub get
flutter build apk --release
```
