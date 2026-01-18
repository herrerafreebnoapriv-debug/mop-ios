#!/bin/bash
# 编译环境检查脚本

echo "=========================================="
echo "MOP 移动端编译环境检查"
echo "=========================================="
echo ""

# 检查 Flutter
echo "[1/5] 检查 Flutter..."
if command -v flutter &> /dev/null; then
    FLUTTER_VERSION=$(flutter --version | head -n 1)
    echo "  ✓ Flutter 已安装: $FLUTTER_VERSION"
    flutter doctor | grep -E "(✓|✗|!|•)" | head -20
else
    echo "  ✗ Flutter 未安装"
    echo "    安装方法: https://flutter.dev/docs/get-started/install/linux"
fi
echo ""

# 检查 Java
echo "[2/5] 检查 Java..."
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    echo "  ✓ Java 已安装: $JAVA_VERSION"
    echo "  JAVA_HOME: ${JAVA_HOME:-未设置}"
else
    echo "  ✗ Java 未安装"
    echo "    安装方法: sudo apt install openjdk-17-jdk"
fi
echo ""

# 检查 Android SDK
echo "[3/5] 检查 Android SDK..."
if [ -n "$ANDROID_HOME" ]; then
    echo "  ✓ ANDROID_HOME: $ANDROID_HOME"
    if [ -d "$ANDROID_HOME" ]; then
        echo "  ✓ Android SDK 目录存在"
    else
        echo "  ✗ Android SDK 目录不存在"
    fi
else
    echo "  ! ANDROID_HOME 未设置"
    echo "    可能通过 Flutter 自动管理"
fi
echo ""

# 检查项目配置
echo "[4/5] 检查项目配置..."
PROJECT_DIR="/opt/mop/mobile"
if [ -f "$PROJECT_DIR/pubspec.yaml" ]; then
    echo "  ✓ 项目目录存在"
    if [ -f "$PROJECT_DIR/android/key.properties" ]; then
        echo "  ✓ 签名配置存在"
    else
        echo "  ! 签名配置不存在（将使用 debug 签名）"
    fi
else
    echo "  ✗ 项目目录不存在: $PROJECT_DIR"
fi
echo ""

# 检查磁盘空间
echo "[5/5] 检查磁盘空间..."
AVAILABLE_SPACE=$(df -h /opt | tail -1 | awk '{print $4}')
echo "  /opt 可用空间: $AVAILABLE_SPACE"
if [ -d "/opt/mop/mobile" ]; then
    PROJECT_SIZE=$(du -sh /opt/mop/mobile 2>/dev/null | cut -f1)
    echo "  项目大小: $PROJECT_SIZE"
fi
echo ""

echo "=========================================="
echo "检查完成"
echo "=========================================="
