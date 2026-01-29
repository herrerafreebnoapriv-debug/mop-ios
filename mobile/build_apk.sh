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

# 1.5 检查 release 签名配置（避免打出未正确签名的 APK）
KEY_PROPERTIES="$SCRIPT_DIR/android/key.properties"
KEYSTORE_REL=$(grep -E "^storeFile=" "$KEY_PROPERTIES" 2>/dev/null | cut -d= -f2)
KEYSTORE_PATH=""
if [ -f "$KEY_PROPERTIES" ] && [ -n "$KEYSTORE_REL" ]; then
    KEYSTORE_PATH="$SCRIPT_DIR/android/$KEYSTORE_REL"
    if [ -f "$KEYSTORE_PATH" ]; then
        echo "✅ 签名配置: $KEY_PROPERTIES -> $KEYSTORE_REL"
    else
        echo "⚠️  警告: key.properties 指向的 keystore 不存在: $KEYSTORE_PATH"
        echo "   Release 将使用 debug 签名。若安装报「损坏」请配置正确 keystore 后重建。"
    fi
else
    echo "⚠️  警告: 未找到 android/key.properties 或 storeFile，Release 将使用 debug 签名"
fi
echo ""

# 2. 递增版本号（如 1.0.28 -> 1.0.29）与构建号
MAJOR=$(echo "$VERSION_NAME" | cut -d. -f1)
MINOR=$(echo "$VERSION_NAME" | cut -d. -f2)
PATCH=$(echo "$VERSION_NAME" | cut -d. -f3)
PATCH=$((PATCH + 1))
NEW_VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="${NEW_VERSION_NAME}+${NEW_BUILD_NUMBER}"

echo "📝 更新版本号: $CURRENT_VERSION → $NEW_VERSION"
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC_FILE"
echo "✅ 版本号已更新（APK 将输出为 mop-app-v${NEW_VERSION_NAME}.apk）"
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
    
    # 生成文件名：仅版本号，如 mop-app-v1.0.29.apk
    APK_FILENAME="mop-app-v${NEW_VERSION_NAME}.apk"
    APK_DOWNLOAD_PATH="$DOWNLOAD_DIR/$APK_FILENAME"
    
    # 复制 APK 到下载目录
    echo "📦 复制 APK 到下载目录..."
    cp "$APK_PATH" "$APK_DOWNLOAD_PATH"
    echo "✅ APK 已复制到: $APK_DOWNLOAD_PATH"
    echo ""
    
    # 生成 SHA256 校验和（用于验证下载是否损坏）
    if command -v sha256sum >/dev/null 2>&1; then
        APK_SHA256=$(sha256sum "$APK_DOWNLOAD_PATH" | cut -d' ' -f1)
        echo "SHA256: $APK_SHA256"
        echo "$APK_SHA256  $APK_FILENAME" > "$DOWNLOAD_DIR/${APK_FILENAME}.sha256"
        echo "✅ 校验和已保存: $DOWNLOAD_DIR/${APK_FILENAME}.sha256"
        echo ""
    fi
    
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
    {
        echo "构建时间: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "版本号: $NEW_VERSION"
        echo "文件名: $APK_FILENAME"
        echo "APK 大小: $APK_SIZE"
        echo "下载链接: $DOWNLOAD_URL"
        echo "备用链接: $DOWNLOAD_URL_ALT"
        echo "本地路径: $APK_DOWNLOAD_PATH"
        [ -n "$APK_SHA256" ] && echo "SHA256: $APK_SHA256"
    } > "$BUILD_INFO_FILE"
    echo "📝 构建信息已保存到: $BUILD_INFO_FILE"
else
    echo "⚠️  警告: APK 文件未找到: $APK_PATH"
fi
