#!/bin/bash
# MOP 移动端 APK 编译脚本
# 版本: mop-v0115-0530
# 注意：仅构建 arm64-v8a（64位）架构，不再构建 arm v7a（32位）

set -e

# 配置
PROJECT_DIR="/opt/mop/mobile"
OUTPUT_DIR="/opt/mop/build_output"
BUILD_TYPE="${1:-release}"  # release 或 debug
TARGET_ARCH="${2:-arm64}"   # arm64 (仅支持 64 位架构，不再构建 arm v7a)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Flutter
check_flutter() {
    log_info "检查 Flutter 环境..."
    if ! command -v flutter &> /dev/null; then
        log_error "Flutter 未安装或未在 PATH 中"
        log_info "请安装 Flutter SDK: https://flutter.dev/docs/get-started/install/linux"
        exit 1
    fi
    
    FLUTTER_VERSION=$(flutter --version | head -n 1)
    log_info "Flutter 版本: $FLUTTER_VERSION"
    
    # 运行 flutter doctor
    log_info "检查 Flutter 环境配置..."
    flutter doctor
}

# 检查 Java
check_java() {
    log_info "检查 Java 环境..."
    if ! command -v java &> /dev/null; then
        log_error "Java 未安装"
        log_info "请安装 Java JDK 17: sudo apt install openjdk-17-jdk"
        exit 1
    fi
    
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    log_info "Java 版本: $JAVA_VERSION"
}

# 准备构建环境
prepare_build() {
    log_info "准备构建环境..."
    
    cd "$PROJECT_DIR"
    
    # 检查项目目录
    if [ ! -f "pubspec.yaml" ]; then
        log_error "未找到 pubspec.yaml，请检查项目目录"
        exit 1
    fi
    
    # 清理旧的构建
    log_info "清理旧的构建文件..."
    flutter clean
    
    # 获取依赖
    log_info "获取项目依赖..."
    flutter pub get
    
    # 检查依赖
    if [ $? -ne 0 ]; then
        log_error "依赖获取失败"
        exit 1
    fi
    
    log_info "依赖获取完成"
}

# 构建 APK
build_apk() {
    log_info "开始构建 APK (类型: $BUILD_TYPE, 架构: $TARGET_ARCH)..."
    
    cd "$PROJECT_DIR"
    
    # 确定目标平台（仅支持 arm64，不再构建 arm v7a）
    if [ "$TARGET_ARCH" = "arm64" ]; then
        TARGET_PLATFORM="android-arm64"
        SPLIT_FLAG=""
    else
        log_warn "不支持的架构: $TARGET_ARCH，使用默认架构 arm64"
        TARGET_PLATFORM="android-arm64"
        SPLIT_FLAG=""
    fi
    
    # 构建命令
    if [ "$BUILD_TYPE" = "release" ]; then
        log_info "构建 Release APK..."
        flutter build apk --release \
            --target-platform "$TARGET_PLATFORM" \
            $SPLIT_FLAG
    elif [ "$BUILD_TYPE" = "debug" ]; then
        log_info "构建 Debug APK..."
        flutter build apk --debug \
            --target-platform "$TARGET_PLATFORM" \
            $SPLIT_FLAG
    else
        log_error "不支持的构建类型: $BUILD_TYPE"
        exit 1
    fi
    
    if [ $? -ne 0 ]; then
        log_error "APK 构建失败"
        exit 1
    fi
    
    log_info "APK 构建完成"
}

# 复制输出文件
copy_output() {
    log_info "复制输出文件..."
    
    mkdir -p "$OUTPUT_DIR"
    
    # 复制 APK 文件
    if [ "$TARGET_ARCH" = "all" ]; then
        cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-armeabi-v7a-$BUILD_TYPE.apk" "$OUTPUT_DIR/" 2>/dev/null || true
        cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-$BUILD_TYPE.apk" "$OUTPUT_DIR/" 2>/dev/null || true
    fi
    
    cp "$PROJECT_DIR/build/app/outputs/flutter-apk/app-$BUILD_TYPE.apk" "$OUTPUT_DIR/" 2>/dev/null || true
    
    log_info "输出文件已复制到: $OUTPUT_DIR"
}

# 显示构建信息
show_build_info() {
    log_info "构建信息："
    echo "  项目目录: $PROJECT_DIR"
    echo "  输出目录: $OUTPUT_DIR"
    echo "  构建类型: $BUILD_TYPE"
    echo "  目标架构: $TARGET_ARCH"
    echo ""
    
    if [ -d "$OUTPUT_DIR" ]; then
        log_info "生成的 APK 文件："
        ls -lh "$OUTPUT_DIR"/*.apk 2>/dev/null || log_warn "未找到 APK 文件"
    fi
}

# 主函数
main() {
    log_info "=========================================="
    log_info "MOP 移动端 APK 编译脚本"
    log_info "版本: mop-v0115-0530"
    log_info "=========================================="
    echo ""
    
    # 检查环境
    check_flutter
    check_java
    
    # 准备构建
    prepare_build
    
    # 构建 APK
    build_apk
    
    # 复制输出
    copy_output
    
    # 显示信息
    show_build_info
    
    log_info "=========================================="
    log_info "构建完成！"
    log_info "=========================================="
}

# 运行主函数
main
