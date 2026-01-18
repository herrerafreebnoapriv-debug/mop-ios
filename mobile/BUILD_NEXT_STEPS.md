# 构建恢复指南

## 快速恢复步骤

### 1. 检查当前状态
```bash
cd /opt/mop/mobile
flutter doctor -v
```

### 2. 修复缺少 namespace 的插件

#### 修复 telephony 插件
```bash
# 查找 telephony 插件的 package
TELEPHONY_DIR=$(find ~/.pub-cache/hosted/pub.dev -type d -name "telephony-0.2.0" 2>/dev/null | head -1)
TELEPHONY_MANIFEST="$TELEPHONY_DIR/android/src/main/AndroidManifest.xml"
PACKAGE=$(grep -o 'package="[^"]*"' "$TELEPHONY_MANIFEST" 2>/dev/null | cut -d'"' -f2)

# 添加 namespace 到 build.gradle
if [ -n "$PACKAGE" ] && [ -f "$TELEPHONY_DIR/android/build.gradle" ]; then
    sed -i "/android {/a\    namespace \"$PACKAGE\"" "$TELEPHONY_DIR/android/build.gradle"
    echo "已为 telephony 添加 namespace: $PACKAGE"
fi
```

#### 检查其他缺少 namespace 的插件
```bash
cd /opt/mop/mobile
flutter build apk --release --target-platform android-arm64 2>&1 | grep -i "namespace not specified" | head -10
```

### 3. 重新构建
```bash
cd /opt/mop/mobile
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### 4. 监控构建进度
```bash
# 在另一个终端监控
watch -n 30 'ps aux | grep gradle | grep -v grep; echo ""; find /opt/mop/mobile/build/app/intermediates -name "*.dex" 2>/dev/null | wc -l; ls /opt/mop/mobile/build/app/outputs/flutter-apk/*.apk 2>/dev/null | wc -l'
```

## 已应用的优化配置

所有配置已按照 Jitsi SDK 11.6.0 官方要求完成：
- ✅ Java 17
- ✅ Desugaring 启用
- ✅ MultiDex 启用
- ✅ minSdkVersion 26
- ✅ AGP 8.0.2
- ✅ Gradle 8.0
- ✅ 内存优化（6GB）

## 预计构建时间

- **首次构建**: 15-25 分钟（包含依赖下载）
- **后续构建**: 5-10 分钟（使用缓存）

## 构建输出位置

成功构建后，APK 文件位于：
```
/opt/mop/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```
