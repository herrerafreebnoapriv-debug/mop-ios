# 移动端编译完整指南

## 目录

1. [环境准备](#环境准备)
2. [编译步骤](#编译步骤)
3. [签名配置](#签名配置)
4. [常见问题](#常见问题)
5. [优化建议](#优化建议)

## 环境准备

### 方案优先级

1. **远程机（Linux）** ⭐ 最高优先级
2. **本机 Win10 专业版**
3. **网上打包平台**
4. **其他方案**

### 远程机环境准备

#### 系统要求

- **操作系统：** Ubuntu 20.04+ / CentOS 7+ / Debian 10+
- **CPU：** 4核以上（推荐8核）
- **内存：** 8GB以上（推荐16GB）
- **磁盘：** 50GB以上可用空间

#### 安装步骤

##### 1. 安装 Flutter SDK

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

##### 2. 安装 Java JDK 17

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y openjdk-17-jdk

# CentOS/RHEL
sudo yum install -y java-17-openjdk-devel

# 设置 JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc
echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证
java -version
javac -version
```

##### 3. 安装 Android SDK（通过 Flutter）

```bash
# Flutter 会自动下载 Android SDK
flutter doctor --android-licenses

# 接受所有许可证
yes | flutter doctor --android-licenses
```

##### 4. 检查环境

```bash
# 运行环境检查脚本
cd /opt/mop/mobile
./ENVIRONMENT_CHECK.sh

# 或手动检查
flutter doctor -v
```

### Windows 10 环境准备

#### 安装步骤

##### 1. 安装 Flutter SDK

1. 下载 Flutter SDK：https://flutter.dev/docs/get-started/install/windows
2. 解压到 `C:\flutter`
3. 添加到系统 PATH：`C:\flutter\bin`
4. 验证：`flutter --version`

##### 2. 安装 Android Studio

1. 下载并安装 Android Studio
2. 安装 Android SDK（API Level 34）
3. 安装 Android SDK Command-line Tools
4. 设置环境变量：
   - `ANDROID_HOME=C:\Users\YourName\AppData\Local\Android\Sdk`
   - 添加到 PATH：`%ANDROID_HOME%\platform-tools` 和 `%ANDROID_HOME%\tools`

##### 3. 安装 Java JDK 17

1. 下载 JDK 17：https://adoptium.net/
2. 安装并设置 `JAVA_HOME`

## 编译步骤

### 远程机编译（推荐）

#### 使用编译脚本

```bash
cd /opt/mop

# Release 版本（所有架构）
./scripts/build_apk.sh release all

# Release 版本（仅 arm64）
./scripts/build_apk.sh release arm64

# Debug 版本
./scripts/build_apk.sh debug all
```

#### 手动编译

```bash
cd /opt/mop/mobile

# 1. 清理
flutter clean

# 2. 获取依赖
flutter pub get

# 3. 编译 APK
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --split-per-abi

# 4. 查看输出
ls -lh build/app/outputs/flutter-apk/
```

### Windows 10 编译

#### 使用编译脚本

```batch
cd C:\path\to\mop

REM Release 版本
scripts\build_apk.bat release all

REM Debug 版本
scripts\build_apk.bat debug all
```

#### 手动编译

```batch
cd mobile

flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
```

### 编译 App Bundle（用于 Google Play）

```bash
cd /opt/mop/mobile
flutter build appbundle --release \
  --target-platform android-arm,android-arm64
```

输出：`build/app/outputs/bundle/release/app-release.aab`

## 签名配置

### 生成签名密钥

```bash
cd /opt/mop/mobile/android/app

# 生成密钥库
keytool -genkey -v -keystore mop-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mop-key \
  -storepass YOUR_KEYSTORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD \
  -dname "CN=MOP, OU=Development, O=MOP, L=City, ST=State, C=CN"
```

### 创建 key.properties

```bash
cat > /opt/mop/mobile/android/key.properties << EOF
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=mop-key
storeFile=app/mop-release-key.jks
EOF
```

**注意：** `storeFile` 路径是相对于 `android/` 目录的。

### 验证签名

```bash
# 检查 APK 签名
jarsigner -verify -verbose -certs build/app/outputs/flutter-apk/app-release.apk

# 查看签名信息
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## 输出文件说明

### APK 文件位置

编译完成后，APK 文件位于：

```
build/app/outputs/flutter-apk/
├── app-release.apk              # 合并版本（包含所有架构）
├── app-armeabi-v7a-release.apk # armv7 版本（约 20-30MB）
└── app-arm64-v8a-release.apk   # arm64 版本（约 20-30MB）
```

### 文件大小参考

- **Debug APK：** 50-80MB
- **Release APK（单个架构）：** 20-35MB
- **Release APK（合并）：** 40-70MB
- **App Bundle：** 20-30MB

## 常见问题

### 问题 1：Flutter 未找到

**症状：**
```
flutter: command not found
```

**解决：**
```bash
# 检查 PATH
echo $PATH | grep flutter

# 添加到 PATH
export PATH="$PATH:/opt/flutter/bin"
source ~/.bashrc

# 验证
flutter --version
```

### 问题 2：Android SDK 未找到

**症状：**
```
Android SDK not found
```

**解决：**
```bash
# 通过 Flutter 安装
flutter doctor --android-licenses

# 或手动设置
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools"
```

### 问题 3：Java 版本不兼容

**症状：**
```
Unsupported class file major version
```

**解决：**
```bash
# 检查 Java 版本（需要 17+）
java -version

# 安装 Java 17
sudo apt install openjdk-17-jdk

# 设置 JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

### 问题 4：依赖获取失败

**症状：**
```
Failed to get dependencies
```

**解决：**
```bash
# 清理并重试
flutter clean
flutter pub cache repair
flutter pub get

# 如果网络问题，使用镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get
```

### 问题 5：编译失败 - 内存不足

**症状：**
```
Out of memory error
```

**解决：**
```bash
# 增加 Gradle 内存
cat >> /opt/mop/mobile/android/gradle.properties << EOF
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m
EOF

# 或使用 swap
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 问题 6：签名错误

**症状：**
```
Signing config not found
```

**解决：**
- 检查 `key.properties` 文件路径
- 检查密钥文件权限
- 验证密钥密码正确
- 如果不需要签名，使用 debug 签名

## 优化建议

### 1. 减小 APK 大小

```gradle
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

### 2. 启用代码混淆

已配置 `proguard-rules.pro`，确保重要类不被混淆。

### 3. 分离架构

使用 `--split-per-abi` 生成单独的 APK，减小单个文件大小。

### 4. 使用 App Bundle

Google Play 推荐使用 AAB 格式，可以进一步减小下载大小。

### 5. 优化资源

- 压缩图片资源
- 移除未使用的资源
- 使用 WebP 格式图片

## 测试安装

### 安装到设备

```bash
# 通过 ADB 安装
adb install build/app/outputs/flutter-apk/app-release.apk

# 或直接传输到设备安装
```

### 验证功能

1. 应用可以正常启动
2. 登录功能正常
3. 权限申请正常
4. 数据收集功能正常
5. Socket.io 连接正常

## 下一步

1. ✅ 环境准备完成
2. ✅ 编译 APK 成功
3. ⬜ 测试 APK 功能
4. ⬜ 配置 CI/CD（可选）
5. ⬜ 发布到应用商店（可选）

## 相关文档

- `BUILD_ENVIRONMENT_SETUP.md` - 详细环境准备
- `BUILD_QUICK_START.md` - 快速开始指南
- `ENVIRONMENT_CHECK.sh` - 环境检查脚本
