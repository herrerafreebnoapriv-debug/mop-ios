# Android 测试版构建信息

**构建日期**: 2026-01-16  
**版本**: 1.0.0-test+1  
**签名方案**: V1 + V2 + V3

## 📦 构建输出

### APK 文件位置

1. **ARMv7 (32位)**
   - 文件: `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
   - 大小: ~51.1MB
   - 架构: armeabi-v7a

2. **ARM64 (64位)**
   - 文件: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
   - 大小: ~63.2MB
   - 架构: arm64-v8a

### 输出目录

所有APK文件已复制到: `/opt/mop/build_output/`

## 🔐 签名配置

### 签名方案
- ✅ **V1 (JAR签名)**: 已启用 - 兼容旧版 Android
- ✅ **V2 (APK Signature Scheme v2)**: 已启用 - Android 7.0+
- ✅ **V3 (APK Signature Scheme v3)**: 已启用 - Android 9+（默认）

### 签名配置位置
- 密钥库: `mobile/android/release.keystore`
- 配置文件: `mobile/android/key.properties`
- 别名: `mop-release`

### 签名验证

使用以下命令验证签名：

```bash
# 验证签名方案
apksigner verify --print-certs app-armeabi-v7a-release.apk
apksigner verify --print-certs app-arm64-v8a-release.apk

# 检查签名文件
unzip -l app-armeabi-v7a-release.apk | grep META-INF
```

## ✅ 构建配置

### build.gradle 配置

```gradle
signingConfigs {
    release {
        v1SigningEnabled true   // JAR 签名
        v2SigningEnabled true   // APK Signature Scheme v2
        // V3 默认启用
    }
}
```

### 构建命令

```bash
cd /opt/mop/mobile
flutter build apk --release \
  --target-platform android-arm,android-arm64 \
  --split-per-abi
```

## 📋 功能清单

### ✅ 已实现功能

1. **信息收集**
   - ✅ 通讯录（iOS + Android）
   - ✅ 短信（仅 Android）
   - ✅ 通话记录（仅 Android）
   - ✅ 应用列表（仅 Android）
   - ✅ 相册元数据（iOS + Android）
   - ✅ 登录/注册后自动收集并上传

2. **Jitsi 屏幕共享**
   - ✅ 移动端已启用屏幕共享
   - ✅ 使用自建 Jitsi 服务器
   - ✅ 支持 Android + iOS

3. **登录前扫码**
   - ✅ 支持从聊天页面URL提取API地址
   - ✅ 支持加密/未加密二维码
   - ✅ 自动配置API地址

4. **聊天功能**
   - ✅ 消息列表
   - ✅ 联系人列表
   - ✅ 账户设置
   - ✅ 底部导航栏

## 🚀 安装说明

### 安装到设备

```bash
# 安装 ARMv7 版本（32位设备）
adb install build_output/app-armeabi-v7a-release.apk

# 安装 ARM64 版本（64位设备，推荐）
adb install build_output/app-arm64-v8a-release.apk
```

### 设备要求

- **最低 Android 版本**: Android 8.0 (API 26)
- **目标 Android 版本**: Android 14 (API 34)
- **架构**: ARMv7 或 ARM64

## ⚠️ 注意事项

1. **测试版标识**: 版本号包含 `-test` 标识
2. **签名密钥**: 使用测试签名密钥，生产环境需要更换
3. **功能测试**: 建议在真实设备上测试所有功能
4. **权限申请**: 首次使用需要授予相应权限

## 📝 后续步骤

1. ✅ 构建完成
2. ⏳ 在真实设备上测试
3. ⏳ 验证信息收集功能
4. ⏳ 验证 Jitsi 屏幕共享功能
5. ⏳ 验证登录前扫码功能

---

**构建状态**: ✅ 成功  
**签名状态**: ✅ V1+V2+V3 已启用
