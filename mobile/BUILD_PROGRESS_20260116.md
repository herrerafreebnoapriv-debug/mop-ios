# Android APK 构建进度记录

**日期**: 2026-01-16  
**状态**: ✅ 构建成功 - 所有插件问题已修复

## ✅ 已完成的工作

### 1. 跳过 geolocator 模块
- ✅ 在 `pubspec.yaml` 中注释了 `geolocator` 和 `geocoding` 依赖
- ✅ 注释了 `dependency_overrides` 中的 `geolocator_android`
- ✅ 保留代码和注释，便于后期补全

### 2. 应用 Jitsi SDK 11.6.0 官方要求配置
- ✅ **Java 版本**: 升级到 Java 17（`sourceCompatibility` 和 `targetCompatibility` 均为 `VERSION_17`）
- ✅ **Kotlin JVM Target**: 更新为 `jvmTarget = '17'`
- ✅ **启用核心库脱糖**: `coreLibraryDesugaringEnabled true`
- ✅ **添加 desugaring 依赖**: `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'`
- ✅ **MultiDex**: 已启用 `multiDexEnabled true` 和 `androidx.multidex:multidex:2.0.1`
- ✅ **minSdkVersion**: 更新为 26（Jitsi SDK 硬性要求）
- ✅ **targetSdkVersion**: 34（对应 Android 14）
- ✅ **compileSdkVersion**: 34
- ✅ **ABI 过滤**: 添加了 `ndk { abiFilters 'armeabi-v7a', 'arm64-v8a' }`
- ✅ **移除 splits 配置**: 避免与 ndk abiFilters 冲突

### 3. Gradle 配置优化
- ✅ **AGP 版本**: 升级到 8.0.2（Jitsi SDK 要求 8.1.0+，但 8.0.2 更兼容旧插件）
- ✅ **Gradle 版本**: 升级到 8.0
- ✅ **JVM 内存**: 增加到 6GB（`-Xmx6144M`）
- ✅ **Metaspace**: 增加到 1GB（`-XX:MaxMetaspaceSize=1024m`）
- ✅ **GC 优化**: 使用 G1GC（`-XX:+UseG1GC`）
- ✅ **构建配置**: 禁用并行构建和缓存以避免并发问题（`org.gradle.parallel=false`, `org.gradle.caching=false`）
- ✅ **工作线程**: 限制为 2（`org.gradle.workers.max=2`）

### 4. 插件配置修复（2026-01-16 完成）
- ✅ **qr_code_scanner**: 
  - 已添加 `namespace "net.touchcapture.qr.flutterqr"`
  - 修复 JVM 目标版本不一致：Java 和 Kotlin 统一为 17
- ✅ **telephony**: 
  - 已有 namespace `"com.shounakmulay.telephony"`
  - 修复 JVM 目标版本：从 1.8 升级到 17

### 5. 原生库冲突解决（2026-01-16 完成）
- ✅ **libc++_shared.so 冲突**: 
  - 在 `android/app/build.gradle` 中添加 `packaging` 配置
  - 使用 `pickFirst` 策略解决多个库提供相同原生库的问题
  - 支持所有 ABI：armeabi-v7a, arm64-v8a, x86, x86_64

## ✅ 构建成功验证

### 构建结果
- ✅ **Debug APK**: 构建成功（437MB）
  - 构建时间：约 21 秒
  - 位置：`build/app/outputs/flutter-apk/app-debug.apk`
- ✅ **Release APK**: 构建成功（93.1MB）
  - 构建时间：约 208 秒（3分28秒）
  - 位置：`build/app/outputs/flutter-apk/app-release.apk`

### 已知警告（不影响构建）
- ⚠️ Kotlin 版本兼容性警告：部分插件使用旧版本 Kotlin 编译，但运行时兼容
- ⚠️ Proguard 配置警告：部分规则未匹配，不影响功能

### 2. 系统资源检查
- ✅ 内存充足：15GB 总内存，7.5GB 可用
- ✅ 磁盘空间充足：355GB 可用
- ✅ CPU：10 核心

## 📋 当前配置摘要

### Android 配置 (`android/app/build.gradle`)
- **minSdkVersion**: 26（Jitsi SDK 硬性要求）
- **targetSdkVersion**: 34
- **compileSdkVersion**: 34
- **Java 版本**: 17（`sourceCompatibility` 和 `targetCompatibility`）
- **Kotlin JVM Target**: 17
- **核心库脱糖**: 已启用
- **MultiDex**: 已启用
- **ABI 过滤**: armeabi-v7a, arm64-v8a

### Gradle 配置
- **AGP**: 8.0.2
- **Gradle**: 8.0
- **Kotlin**: 2.0.21

### 依赖配置
- **MultiDex**: `androidx.multidex:multidex:2.0.1`
- **Desugaring**: `com.android.tools:desugar_jdk_libs:2.0.4`
- **geolocator**: 已注释（保留以便后期补全）

## 📝 下一步操作

### 立即需要做的（优先级：高）
1. **修复 telephony 插件的 namespace**
   - 查找 telephony 插件的 AndroidManifest.xml 获取 package
   - 在插件的 build.gradle 中添加 namespace

2. **检查其他缺少 namespace 的插件**
   - 运行构建，查看所有缺少 namespace 的插件列表
   - 逐个修复或创建自动化脚本

3. **继续构建并监控**
   - 修复所有 namespace 问题后重新构建
   - 监控构建进度和耗时

### 备选方案（如果 namespace 修复太复杂）
1. **回退到 AGP 7.4.2**
   - 保留其他 Jitsi SDK 要求的配置（Java 17、desugaring 等）
   - 测试是否可以在 AGP 7.4.2 下成功构建

2. **创建插件 namespace 补丁脚本**
   - 自动检测所有缺少 namespace 的插件
   - 从 AndroidManifest.xml 读取 package
   - 自动添加到 build.gradle

## 🔗 相关文件

- `/opt/mop/mobile/android/app/build.gradle` - 主应用配置
- `/opt/mop/mobile/android/build.gradle` - 项目级配置
- `/opt/mop/mobile/android/gradle.properties` - Gradle 属性
- `/opt/mop/mobile/android/gradle/wrapper/gradle-wrapper.properties` - Gradle wrapper 配置
- `/opt/mop/mobile/pubspec.yaml` - Flutter 依赖配置

## 📌 关键配置变更记录

### 1. Java 版本升级（Jitsi SDK 要求）
```gradle
compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
    coreLibraryDesugaringEnabled true
}
kotlinOptions {
    jvmTarget = '17'
}
```

### 2. Desugaring 配置
```gradle
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'
}
```

### 3. ABI 过滤
```gradle
defaultConfig {
    ndk {
        abiFilters 'armeabi-v7a', 'arm64-v8a'
    }
}
```

### 4. Gradle 内存优化
```properties
org.gradle.jvmargs=-Xmx6144M -XX:MaxMetaspaceSize=1024m -XX:+HeapDumpOnOutOfMemoryError -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Dfile.encoding=UTF-8
```

## ⏱️ 构建耗时统计

- **首次完整构建尝试**: 约 47 分钟（卡在依赖库 DEX 处理）
- **Debug 构建**: 约 21 秒（修复后）
- **Release 构建**: 约 208 秒（3分28秒）
- **预计完整构建时间**: 3-5 分钟（Release 模式，包含优化）

## 🎯 已解决的问题

### 1. JVM 目标版本不一致
**问题**: `qr_code_scanner` 插件 Java 编译使用 1.8，Kotlin 编译使用 17
**解决**: 统一升级到 Java 17，添加 `compileOptions` 和 `kotlinOptions` 配置

### 2. 原生库冲突
**问题**: 多个库提供相同的 `libc++_shared.so` 文件
**解决**: 在 `packaging` 块中使用 `pickFirst` 策略

### 3. 插件 JVM 版本不统一
**问题**: `telephony` 插件使用 JVM 1.8
**解决**: 升级到 JVM 17，保持与主应用一致

## 📝 修复文件清单

1. `/root/.pub-cache/hosted/pub.dev/qr_code_scanner-1.0.1/android/build.gradle`
   - 添加 `compileOptions` 和 `kotlinOptions` 配置
   - Java 版本从 1.8 升级到 17

2. `/root/.pub-cache/hosted/pub.dev/telephony-0.2.0/android/build.gradle`
   - 添加 `compileOptions` 配置
   - Kotlin JVM 目标从 1.8 升级到 17

3. `/opt/mop/mobile/android/app/build.gradle`
   - 添加 `packaging` 配置解决原生库冲突
