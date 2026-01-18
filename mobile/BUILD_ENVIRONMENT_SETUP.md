# 移动端编译环境准备指南

## 编译优先级

1. **远程机（Linux）** - 最高优先级 ✅
2. **本机 Win10 专业版** - 次优先级
3. **网上打包平台** - 备选方案
4. **其他方案** - 最后选择

## 方案一：远程机编译（推荐）

### 环境要求

#### Linux 服务器要求
- **操作系统：** Ubuntu 20.04+ / CentOS 7+ / Debian 10+
- **CPU：** 4核以上（推荐8核）
- **内存：** 8GB以上（推荐16GB）
- **磁盘：** 50GB以上可用空间
- **网络：** 稳定的互联网连接

### 安装步骤

#### 1. 安装 Flutter SDK

```bash
# 下载 Flutter SDK
cd /opt
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.16.0-stable.tar.xz
tar xf flutter_linux_3.16.0-stable.tar.xz

# 添加到 PATH
echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# 验证安装
flutter --version
flutter doctor
```

#### 2. 安装 Android 编译环境

```bash
# 安装 Java JDK 17（Android Gradle 需要）
sudo apt update
sudo apt install -y openjdk-17-jdk

# 设置 JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证 Java
java -version
javac -version

# 安装 Android SDK（通过 Flutter）
flutter doctor --android-licenses
```

#### 3. 配置 Android 签名（可选，用于发布）

```bash
# 生成签名密钥
cd /opt/mop/mobile/android/app
keytool -genkey -v -keystore mop-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mop-key \
  -storepass YOUR_KEYSTORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD

# 创建 key.properties 文件
cat > /opt/mop/mobile/android/key.properties << EOF
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=mop-key
storeFile=/opt/mop/mobile/android/app/mop-release-key.jks
EOF
```

#### 4. 配置 build.gradle 支持签名

更新 `/opt/mop/mobile/android/app/build.gradle`：

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... 其他配置 ...
    
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }
    
    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig signingConfigs.release
            } else {
                signingConfig signingConfigs.debug
            }
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### 编译 APK

#### 编译 Release APK

```bash
cd /opt/mop/mobile

# 获取依赖
flutter pub get

# 清理构建
flutter clean

# 编译 APK（仅 armv7 和 arm64）
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --split-per-abi

# APK 输出位置
# build/app/outputs/flutter-apk/app-release.apk (合并版本)
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (armv7)
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (arm64)
```

#### 编译 App Bundle（用于 Google Play）

```bash
flutter build appbundle --release \
  --target-platform android-arm,android-arm64
```

### iOS 编译（需要 macOS）

**注意：** iOS 编译必须在 macOS 系统上进行，Linux 无法直接编译 IPA。

如果远程机是 macOS：

```bash
# 安装 Xcode Command Line Tools
xcode-select --install

# 安装 CocoaPods
sudo gem install cocoapods

# 安装 iOS 依赖
cd /opt/mop/mobile/ios
pod install

# 编译 IPA
cd /opt/mop/mobile
flutter build ipa --release
```

## 方案二：本机 Win10 专业版编译

### 环境要求

- **操作系统：** Windows 10 专业版或更高
- **内存：** 8GB以上
- **磁盘：** 50GB以上可用空间

### 安装步骤

#### 1. 安装 Flutter SDK

```powershell
# 下载 Flutter SDK
# 从 https://flutter.dev/docs/get-started/install/windows 下载
# 解压到 C:\flutter

# 添加到 PATH
# 系统环境变量 -> Path -> 添加 C:\flutter\bin

# 验证安装
flutter --version
flutter doctor
```

#### 2. 安装 Android Studio

1. 下载并安装 Android Studio
2. 安装 Android SDK（API Level 34）
3. 安装 Android SDK Command-line Tools
4. 配置 ANDROID_HOME 环境变量

```powershell
# 设置环境变量
$env:ANDROID_HOME = "C:\Users\YourName\AppData\Local\Android\Sdk"
$env:PATH += ";$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\tools"
```

#### 3. 安装 Visual Studio（用于 Windows 编译，可选）

如果需要编译 Windows 版本。

#### 4. 配置签名

同远程机方案，在 `mobile/android/` 目录下创建 `key.properties`。

### 编译命令

```powershell
cd C:\path\to\mop\mobile

# 获取依赖
flutter pub get

# 编译 APK
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

## 方案三：网上打包平台

### 推荐平台

1. **Codemagic** - https://codemagic.io
   - 支持 Flutter
   - 免费额度有限
   - 需要 GitHub/GitLab 仓库

2. **AppCircle** - https://appcircle.io
   - 支持 Flutter
   - 有免费计划

3. **Bitrise** - https://www.bitrise.io
   - 支持 Flutter
   - 有免费计划

### 使用步骤（以 Codemagic 为例）

1. 注册账号并连接 Git 仓库
2. 创建新的应用配置
3. 选择 Flutter 工作流
4. 配置构建脚本
5. 设置签名密钥
6. 触发构建

## 编译脚本

### 远程机编译脚本

创建 `/opt/mop/scripts/build_apk.sh`：

```bash
#!/bin/bash
# APK 编译脚本

set -e

PROJECT_DIR="/opt/mop/mobile"
OUTPUT_DIR="/opt/mop/build_output"

echo "开始编译 APK..."

cd "$PROJECT_DIR"

# 清理
echo "清理构建文件..."
flutter clean

# 获取依赖
echo "获取依赖..."
flutter pub get

# 编译 APK
echo "编译 Release APK..."
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --split-per-abi

# 复制到输出目录
mkdir -p "$OUTPUT_DIR"
cp build/app/outputs/flutter-apk/app-*-release.apk "$OUTPUT_DIR/"

echo "编译完成！"
echo "APK 文件位置："
ls -lh "$OUTPUT_DIR"/*.apk
```

### Windows 编译脚本

创建 `build_apk.bat`：

```batch
@echo off
set PROJECT_DIR=%~dp0mobile
set OUTPUT_DIR=%~dp0build_output

echo 开始编译 APK...

cd /d "%PROJECT_DIR%"

flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
copy build\app\outputs\flutter-apk\app-*-release.apk "%OUTPUT_DIR%\"

echo 编译完成！
pause
```

## 检查清单

### 编译前检查

- [ ] Flutter SDK 已安装并配置
- [ ] Android SDK 已安装
- [ ] Java JDK 已安装（17+）
- [ ] 项目依赖已获取（`flutter pub get`）
- [ ] 签名密钥已配置（发布版本）
- [ ] 网络连接正常（下载依赖）

### 编译后检查

- [ ] APK 文件已生成
- [ ] APK 文件大小合理（通常 20-50MB）
- [ ] 可以安装到测试设备
- [ ] 应用可以正常启动
- [ ] 功能测试通过

## 常见问题

### 问题 1：Flutter 未找到

**解决：**
```bash
# 检查 PATH
echo $PATH | grep flutter

# 重新加载环境变量
source ~/.bashrc

# 或手动添加
export PATH="$PATH:/opt/flutter/bin"
```

### 问题 2：Android SDK 未找到

**解决：**
```bash
# 通过 Flutter 安装 Android SDK
flutter doctor --android-licenses

# 或手动设置 ANDROID_HOME
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools"
```

### 问题 3：编译失败 - 依赖问题

**解决：**
```bash
# 清理并重新获取依赖
flutter clean
flutter pub get
flutter pub upgrade
```

### 问题 4：签名错误

**解决：**
- 检查 `key.properties` 文件路径
- 检查密钥文件权限
- 验证密钥密码正确

## 下一步

1. 选择编译方案（推荐远程机）
2. 准备编译环境
3. 运行编译脚本
4. 测试生成的 APK
5. 配置 CI/CD（可选）
