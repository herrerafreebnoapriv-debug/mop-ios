#!/bin/bash
# Flutter APK 自动化构建脚本
# 功能：自动递增版本号、清理缓存、构建 APK
# 规则：每次修改后都必须清理缓存并递增版本号再构建

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PUBSPEC_FILE="pubspec.yaml"
BUILD_TYPE="${1:-release}"

echo "=========================================="
echo "Flutter APK 自动化构建"
echo "=========================================="
echo ""

# 1. 读取当前版本号
if [ ! -f "$PUBSPEC_FILE" ]; then
    echo "❌ 错误: 找不到 $PUBSPEC_FILE"
    exit 1
fi

CURRENT_VERSION=$(grep "^version:" "$PUBSPEC_FILE" | sed 's/version: //' | tr -d ' ')
VERSION_NAME=$(echo "$CURRENT_VERSION" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT_VERSION" | cut -d'+' -f2)

if [ -z "$BUILD_NUMBER" ]; then
    echo "❌ 错误: 版本号格式不正确，应为 'versionName+buildNumber' 格式"
    exit 1
fi

echo "当前版本: $CURRENT_VERSION"
echo "  版本名称: $VERSION_NAME"
echo "  构建号: $BUILD_NUMBER"
echo ""

# 2. 递增构建号
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="${VERSION_NAME}+${NEW_BUILD_NUMBER}"

echo "📝 更新版本号: $CURRENT_VERSION → $NEW_VERSION"
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_FILE"
echo "✅ 版本号已更新"
echo ""

# 3. 清理构建缓存
echo "🧹 清理 Flutter 构建缓存..."
flutter clean
echo "✅ Flutter 缓存已清理"
echo ""

# 4. 清理 Android 构建目录
echo "🧹 清理 Android 构建目录..."
rm -rf android/app/build android/build android/.gradle 2>/dev/null || true
echo "✅ Android 构建目录已清理"
echo ""

# 5. 获取依赖
echo "📦 获取 Flutter 依赖..."
flutter pub get
echo "✅ 依赖已获取"
echo ""

# 6. 构建 APK
echo "🔨 开始构建 APK ($BUILD_TYPE)..."
echo ""

if [ "$BUILD_TYPE" = "release" ]; then
    flutter build apk --release
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
elif [ "$BUILD_TYPE" = "debug" ]; then
    flutter build apk --debug
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
else
    echo "❌ 错误: 不支持的构建类型 '$BUILD_TYPE'，支持: release, debug"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ 构建完成！"
echo "=========================================="
echo ""
echo "APK 路径: $APK_PATH"
echo "版本号: $NEW_VERSION"
echo ""

# 显示 APK 信息并创建下载链接
if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo "APK 大小: $APK_SIZE"
    echo ""
    
    # 7. 创建下载目录并复制 APK（带版本号和时间戳）
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    DOWNLOAD_DIR="$PROJECT_ROOT/static/apk"
    mkdir -p "$DOWNLOAD_DIR"
    
    # 生成时间戳（格式：YYYYMMDD-HHMMSS）
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    # 清理版本名称中的特殊字符（用于文件名）
    VERSION_CLEAN=$(echo "$VERSION_NAME" | sed 's/[^a-zA-Z0-9.-]/-/g')
    # 生成文件名：mop-app-v{version}-{buildNumber}-{timestamp}.apk
    APK_FILENAME="mop-app-v${VERSION_CLEAN}+${NEW_BUILD_NUMBER}-${TIMESTAMP}.apk"
    APK_DOWNLOAD_PATH="$DOWNLOAD_DIR/$APK_FILENAME"
    
    # 复制 APK 到下载目录
    echo "📦 复制 APK 到下载目录..."
    cp "$APK_PATH" "$APK_DOWNLOAD_PATH"
    echo "✅ APK 已复制到: $APK_DOWNLOAD_PATH"
    echo ""
    
    # 生成下载链接（尝试检测服务器配置）
    # 默认使用 static 目录对应的 URL 路径
    DOWNLOAD_URL="https://api.chat5202ol.xyz/static/apk/$APK_FILENAME"
    # 备用链接（如果使用不同的域名）
    DOWNLOAD_URL_ALT="https://app.chat5202ol.xyz/static/apk/$APK_FILENAME"
    
    echo "=========================================="
    echo "📥 下载链接"
    echo "=========================================="
    echo ""
    echo "文件名: $APK_FILENAME"
    echo "版本: $NEW_VERSION"
    echo "构建时间: $(date +"%Y-%m-%d %H:%M:%S")"
    echo ""
    echo "下载链接:"
    echo "  🔗 $DOWNLOAD_URL"
    echo "  🔗 $DOWNLOAD_URL_ALT"
    echo ""
    echo "本地路径:"
    echo "  📁 $APK_DOWNLOAD_PATH"
    echo ""
    echo "安装命令:"
    echo "  adb install -r $APK_PATH"
    echo ""
    echo "或通过下载链接直接在设备上下载安装"
    echo ""
    
    # 保存构建信息到文件
    BUILD_INFO_FILE="$DOWNLOAD_DIR/latest-build-info.txt"
    cat > "$BUILD_INFO_FILE" <<EOF
构建时间: $(date +"%Y-%m-%d %H:%M:%S")
版本号: $NEW_VERSION
文件名: $APK_FILENAME
APK 大小: $APK_SIZE
下载链接: $DOWNLOAD_URL
备用链接: $DOWNLOAD_URL_ALT
本地路径: $APK_DOWNLOAD_PATH
EOF
    echo "📝 构建信息已保存到: $BUILD_INFO_FILE"
else
    echo "⚠️  警告: APK 文件未找到: $APK_PATH"
fi
