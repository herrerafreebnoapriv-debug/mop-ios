# APK 签名状态说明

**日期**: 2026-01-16  
**状态**: ✅ APK 已签名（使用 Debug 签名）

## 📋 当前签名状态

### Debug APK
- ✅ **已签名**: 使用 Android Debug 签名
- 🔑 **密钥**: `~/.android/debug.keystore`（Flutter 默认）
- 📦 **文件**: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK
- ✅ **已签名**: 使用 Android Debug 签名（因为未配置 release 签名）
- 🔑 **密钥**: `~/.android/debug.keystore`（与 debug 相同）
- 📦 **文件**: `build/app/outputs/flutter-apk/app-release.apk`
- ⚠️ **注意**: Release APK 目前使用 debug 签名，**不适合发布到生产环境**

## 🔍 签名配置检查

### 当前配置 (`android/app/build.gradle`)

```gradle
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
            signingConfig signingConfigs.debug  // ⚠️ 当前使用 debug 签名
        }
    }
}
```

### 检查结果
- ❌ `android/key.properties` 文件不存在
- ✅ `~/.android/debug.keystore` 存在（默认 debug 密钥）
- ⚠️ Release APK 因此回退到使用 debug 签名

## 🚀 如何创建正式签名（Release 签名）

### 步骤 1: 生成签名密钥

```bash
cd /opt/mop/mobile/android
keytool -genkey -v -keystore release.keystore -alias mop-release -keyalg RSA -keysize 2048 -validity 10000
```

**参数说明**:
- `-keystore release.keystore`: 密钥库文件名
- `-alias mop-release`: 密钥别名
- `-keyalg RSA`: 使用 RSA 算法
- `-keysize 2048`: 密钥长度 2048 位
- `-validity 10000`: 有效期 10000 天（约 27 年）

**交互提示**:
- 输入密钥库密码（请妥善保管）
- 输入密钥密码（可以与密钥库密码相同）
- 输入姓名、组织等信息

### 步骤 2: 创建签名配置文件

创建 `android/key.properties` 文件：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=mop-release
storeFile=release.keystore
```

**⚠️ 安全提示**:
- 不要将 `key.properties` 提交到 Git
- 将 `key.properties` 添加到 `.gitignore`
- 将 `release.keystore` 添加到 `.gitignore`
- 妥善保管密钥库文件和密码

### 步骤 3: 更新 .gitignore

确保以下文件已添加到 `.gitignore`:

```
android/key.properties
android/release.keystore
android/*.keystore
```

### 步骤 4: 重新构建 Release APK

```bash
cd /opt/mop/mobile
flutter build apk --release
```

构建完成后，Release APK 将使用正式签名。

## 🔐 Debug 签名 vs Release 签名

### Debug 签名
- ✅ 用于开发和测试
- ✅ 自动生成，无需配置
- ❌ **不能用于生产环境发布**
- ❌ Google Play 不接受 debug 签名的 APK
- ❌ 其他应用商店也不接受

### Release 签名
- ✅ 用于生产环境发布
- ✅ 可以上传到 Google Play 和其他应用商店
- ✅ 用户可以正常安装和更新
- ⚠️ 需要妥善保管密钥（丢失后无法更新应用）

## 📝 验证签名

### 方法 1: 使用 jarsigner（检查 JAR 签名）
```bash
jarsigner -verify -verbose -certs app-release.apk
```

### 方法 2: 使用 apksigner（检查 APK 签名，推荐）
```bash
# 需要 Android SDK Build Tools
apksigner verify --print-certs app-release.apk
```

### 方法 3: 检查签名信息
```bash
# 列出 APK 中的签名文件
unzip -l app-release.apk | grep META-INF
```

## ⚠️ 重要提示

1. **当前状态**: Release APK 使用 debug 签名，**仅用于测试**
2. **生产发布**: 必须创建并配置 release 签名
3. **密钥安全**: 一旦创建 release 签名，请妥善保管密钥库文件和密码
4. **密钥丢失**: 如果丢失 release 签名密钥，将无法更新已发布的应用

## 🔄 下一步操作

1. ✅ 创建 release 签名密钥库
2. ✅ 创建 `key.properties` 配置文件
3. ✅ 更新 `.gitignore` 排除敏感文件
4. ✅ 重新构建 Release APK
5. ✅ 验证签名是否正确

## 📚 参考文档

- [Android 应用签名](https://developer.android.com/studio/publish/app-signing)
- [Flutter 应用签名](https://docs.flutter.dev/deployment/android#signing-the-app)
