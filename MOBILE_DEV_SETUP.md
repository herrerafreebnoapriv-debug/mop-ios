# 移动端开发工具准备指南

## 📱 开发目标平台

- **iOS**: iPhone/iPad (仅 arm64 真机架构)
- **Android**: 手机/平板 (仅 armv7 和 arm64 架构)

---

## 🪟 Windows 10 专业版开发环境准备

### ⚠️ 重要说明

**Windows 10 专业版无法直接开发 iOS 应用**，因为：
- iOS 开发需要 **Xcode**，而 Xcode 只能在 **macOS** 上运行
- 即使使用虚拟机，也无法满足 iOS 真机调试和发布的需求

### 解决方案

#### 方案 1：使用 macOS 设备（推荐）
- **MacBook Pro/Air** 或 **iMac**
- 安装 **Xcode** 和 **Flutter**
- 可以同时开发 iOS 和 Android

#### 方案 2：Windows + macOS 虚拟机（不推荐）
- 使用 **VMware** 或 **Parallels Desktop** 安装 macOS
- 性能较差，无法真机调试
- 仅适合学习，不适合实际开发

#### 方案 3：Windows 仅开发 Android（可行）
- Windows 10 可以完整支持 Android 开发
- iOS 部分需要 Mac 设备或云 Mac 服务

---

## 🛠️ Windows 10 专业版 - Android 开发工具

### 1. 必需软件

#### Java Development Kit (JDK)
- **版本**: JDK 17 或更高
- **下载**: [Oracle JDK](https://www.oracle.com/java/technologies/downloads/) 或 [OpenJDK](https://adoptium.net/)
- **安装**: 下载 Windows x64 安装包，安装后配置环境变量

```bash
# 验证安装
java -version
javac -version
```

#### Android Studio
- **版本**: 最新稳定版（推荐 2023.3+）
- **下载**: [Android Studio 官网](https://developer.android.com/studio)
- **安装**: 
  1. 下载安装包（约 1GB）
  2. 运行安装程序，选择 Standard 安装
  3. 安装 Android SDK、Android SDK Platform、Android Virtual Device

**配置环境变量**:
```bash
# 添加到系统环境变量
ANDROID_HOME = C:\Users\YourName\AppData\Local\Android\Sdk
Path += %ANDROID_HOME%\platform-tools
Path += %ANDROID_HOME%\tools
Path += %ANDROID_HOME%\tools\bin
```

#### Flutter SDK
- **版本**: 最新稳定版（推荐 3.16+）
- **下载**: [Flutter 官网](https://flutter.dev/docs/get-started/install/windows)
- **安装步骤**:
  1. 下载 Flutter SDK ZIP 文件
  2. 解压到 `C:\src\flutter`（或任意路径，避免空格和特殊字符）
  3. 添加到系统 PATH: `C:\src\flutter\bin`

```bash
# 验证安装
flutter doctor
```

#### Git
- **版本**: 最新版
- **下载**: [Git 官网](https://git-scm.com/download/win)
- **安装**: 使用默认选项安装

#### Visual Studio Code（推荐）
- **下载**: [VS Code 官网](https://code.visualstudio.com/)
- **必需扩展**:
  - Flutter
  - Dart
  - Android iOS Emulator

#### Android 设备（真机调试）
- **选项 1**: 使用 Android 手机/平板
  - 开启开发者选项
  - 启用 USB 调试
  - 连接电脑后授权调试
- **选项 2**: 使用 Android 模拟器
  - 在 Android Studio 中创建 AVD（Android Virtual Device）
  - 选择 arm64 架构的模拟器（如 Pixel 5）

---

### 2. 环境配置检查

运行以下命令检查环境：

```bash
# 检查 Flutter 环境
flutter doctor

# 应该看到：
# ✓ Flutter (Channel stable, version x.x.x)
# ✓ Android toolchain - develop for Android devices
# ✓ Android Studio (version x.x.x)
# ✓ VS Code (version x.x.x)
# ✓ Connected device (Android 设备或模拟器)
```

---

## 🍎 macOS - iOS 开发工具（必需）

### 1. 必需软件

#### Xcode
- **版本**: 最新稳定版（推荐 15.0+）
- **下载**: [Mac App Store](https://apps.apple.com/app/xcode/id497799835)
- **安装**: 
  1. 从 App Store 下载（约 12GB）
  2. 打开 Xcode，接受许可协议
  3. 安装额外组件（Command Line Tools）

```bash
# 验证安装
xcode-select --version
```

#### CocoaPods（iOS 依赖管理）
```bash
# 安装 CocoaPods
sudo gem install cocoapods

# 验证
pod --version
```

#### Flutter SDK（macOS 版）
- **下载**: [Flutter 官网 macOS 版](https://flutter.dev/docs/get-started/install/macos)
- **安装**: 解压到 `/Users/YourName/flutter` 或任意路径

```bash
# 添加到 PATH（在 ~/.zshrc 或 ~/.bash_profile）
export PATH="$PATH:/Users/YourName/flutter/bin"

# 验证
flutter doctor
```

#### Android Studio（macOS 版，用于 Android 开发）
- 与 Windows 版本相同，但下载 macOS 版本

#### Visual Studio Code（macOS 版）
- 下载 macOS 版本

---

### 2. iOS 真机调试配置

#### Apple Developer 账号
- **免费账号**: 可以真机调试，但证书有效期 7 天
- **付费账号** ($99/年): 可以发布到 App Store，证书有效期 1 年
- **注册**: [Apple Developer](https://developer.apple.com/)

#### 配置步骤
1. 在 Xcode 中登录 Apple ID
2. 连接 iPhone/iPad 到 Mac
3. 在设备上信任电脑
4. 在 Xcode 中选择设备作为运行目标

---

## 📦 Flutter 项目依赖

### pubspec.yaml 必需依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Socket.io 客户端
  socket_io_client: ^2.0.3
  
  # HTTP 请求
  http: ^1.1.0
  
  # 本地存储
  shared_preferences: ^2.2.2
  
  # 二维码扫描
  qr_code_scanner: ^1.0.1
  
  # 国际化
  flutter_localizations:
    sdk: flutter
  intl: ^0.18.1
  
  # 权限管理
  permission_handler: ^11.0.1
  
  # 位置服务
  geolocator: ^10.1.0
  
  # 设备信息
  device_info_plus: ^9.1.0
  
  # 加密
  crypto: ^3.0.3
  
  # JWT 解析
  jwt_decoder: ^2.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## 🔧 开发工具清单总结

### Windows 10 专业版（Android 开发）

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| JDK | 17+ | Java 开发环境 |
| Android Studio | 最新稳定版 | Android 开发 IDE |
| Flutter SDK | 3.16+ | Flutter 框架 |
| Git | 最新版 | 版本控制 |
| VS Code | 最新版 | 代码编辑器（可选） |
| Android 设备/模拟器 | - | 真机调试 |

### macOS（iOS + Android 开发）

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| Xcode | 15.0+ | iOS 开发 IDE（必需） |
| CocoaPods | 最新版 | iOS 依赖管理 |
| Flutter SDK | 3.16+ | Flutter 框架 |
| Android Studio | 最新稳定版 | Android 开发（可选） |
| VS Code | 最新版 | 代码编辑器（可选） |
| Apple Developer 账号 | - | iOS 真机调试/发布 |

---

## 📝 下一步操作

### 1. 选择开发方案
- **仅 Android**: 在 Windows 10 上安装 Android 开发工具
- **iOS + Android**: 使用 macOS 设备（MacBook/iMac）

### 2. 安装工具
按照上述清单逐一安装和配置

### 3. 验证环境
运行 `flutter doctor` 检查所有工具是否正确安装

### 4. 创建 Flutter 项目
```bash
flutter create mop_mobile
cd mop_mobile
flutter pub get
```

### 5. 配置项目
- 添加依赖到 `pubspec.yaml`
- 配置 Android/iOS 权限
- 设置应用图标和启动画面

---

## ⚠️ 重要提醒

1. **iOS 开发必须在 macOS 上进行**，Windows 无法直接开发 iOS
2. **架构限制**: 
   - Android: 仅支持 armv7 和 arm64（排除 x86）
   - iOS: 仅支持 arm64 真机（排除模拟器）
3. **真机调试**: 
   - Android: 需要开启 USB 调试
   - iOS: 需要 Apple Developer 账号（免费账号也可）
4. **网络要求**: 
   - 需要访问 Google 服务（Android SDK 下载）
   - 需要访问 Apple 服务（iOS 开发）

---

## 📞 技术支持

如遇到安装问题，请检查：
1. 系统版本是否符合要求
2. 网络连接是否正常
3. 环境变量是否正确配置
4. 磁盘空间是否充足（至少 20GB 可用空间）

---

**文档版本**: v1.0  
**最后更新**: 2026-01-12  
**适用系统**: Windows 10 专业版 / macOS
