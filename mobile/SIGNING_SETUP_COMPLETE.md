# APK 签名配置完成

**日期**: 2026-01-16  
**状态**: ✅ 签名配置已完成，Release APK 已使用正式签名

## ✅ 已完成的配置

### 1. 签名密钥库
- **文件**: `android/release.keystore`
- **别名**: `mop-release`
- **算法**: RSA 2048 位
- **有效期**: 10000 天（约 27 年）
- **证书信息**:
  - CN: MOP App
  - OU: Development
  - O: MOP
  - L: Beijing
  - ST: Beijing
  - C: CN

### 2. 签名配置文件
- **文件**: `android/key.properties`
- **内容**:
  ```properties
  storePassword=mop123456
  keyPassword=mop123456
  keyAlias=mop-release
  storeFile=release.keystore
  ```

### 3. 构建配置更新
- ✅ 更新了 `android/app/build.gradle` 中的签名配置路径
- ✅ 修复了密钥库文件路径解析问题

### 4. Git 忽略配置
- ✅ 更新了 `.gitignore`，排除敏感文件：
  - `android/key.properties`
  - `android/*.keystore`
  - `android/*.jks`

## 📦 构建结果

### Release APK
- ✅ **状态**: 构建成功
- 📦 **大小**: 93.1MB
- 🔑 **签名**: 使用正式 release 签名
- 📍 **位置**: `build/app/outputs/flutter-apk/app-release.apk`

### Debug APK
- ✅ **状态**: 构建成功（使用 debug 签名）
- 📦 **大小**: 437MB
- 📍 **位置**: `build/app/outputs/flutter-apk/app-debug.apk`

## 🔐 签名信息

### 密钥库信息
- **存储密码**: `mop123456`
- **密钥密码**: `mop123456`
- **密钥别名**: `mop-release`

### ⚠️ 重要安全提示

1. **密码安全**:
   - 当前使用的是测试密码 `mop123456`
   - **生产环境请使用强密码**
   - 建议密码长度至少 16 位，包含大小写字母、数字和特殊字符

2. **密钥库备份**:
   - 请务必备份 `android/release.keystore` 文件
   - 如果丢失密钥库，将无法更新已发布的应用
   - 建议将密钥库存储在安全的位置（加密存储）

3. **密码管理**:
   - 不要将密码提交到 Git
   - 考虑使用环境变量或密钥管理服务
   - 团队成员需要知道密码时，使用安全的方式传递

## 🚀 使用方法

### 构建 Release APK
```bash
cd /opt/mop/mobile
flutter build apk --release
```

### 构建 Debug APK
```bash
cd /opt/mop/mobile
flutter build apk --debug
```

### 验证签名
```bash
# 使用 jarsigner 验证（检查 JAR 签名）
jarsigner -verify -verbose -certs build/app/outputs/flutter-apk/app-release.apk

# 使用 apksigner 验证（推荐，需要 Android SDK）
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## 📝 配置说明

### build.gradle 签名配置
```gradle
signingConfigs {
    release {
        if (keystorePropertiesFile.exists()) {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            def keystorePath = keystorePropertiesFile.getParentFile()
            storeFile file("${keystorePath}/${keystoreProperties['storeFile']}")
            storePassword keystoreProperties['storePassword']
        }
    }
}
```

### key.properties 路径
- 文件位置: `android/key.properties`
- build.gradle 查找路径: `rootProject.file('../key.properties')`
- 密钥库路径: 相对于 `key.properties` 文件所在目录

## ✅ 验证清单

- [x] 签名密钥库已创建
- [x] key.properties 配置文件已创建
- [x] build.gradle 签名配置已更新
- [x] .gitignore 已更新（排除敏感文件）
- [x] Release APK 构建成功
- [x] APK 已使用正式签名

## 🔄 后续操作建议

1. **生产环境准备**:
   - 生成新的密钥库（使用强密码）
   - 更新 `key.properties` 中的密码
   - 备份密钥库到安全位置

2. **团队协作**:
   - 将密钥库和密码安全地分发给团队成员
   - 考虑使用密钥管理服务（如 AWS Secrets Manager、HashiCorp Vault）

3. **CI/CD 集成**:
   - 在 CI/CD 系统中配置签名密钥
   - 使用环境变量存储密码
   - 确保密钥库文件安全存储

## 📚 相关文档

- [Android 应用签名](https://developer.android.com/studio/publish/app-signing)
- [Flutter 应用签名](https://docs.flutter.dev/deployment/android#signing-the-app)
- `/opt/mop/mobile/APK_SIGNING_STATUS.md` - 签名状态说明文档
