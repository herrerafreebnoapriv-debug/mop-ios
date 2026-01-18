#!/bin/bash
# MOP 移动端编译环境一键安装脚本
# 适用于 Ubuntu/Debian/CentOS

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    log_info "检测到操作系统: $OS $OS_VERSION"
}

# 安装 Flutter
install_flutter() {
    log_step "安装 Flutter SDK..."
    
    FLUTTER_DIR="/opt/flutter"
    
    if [ -d "$FLUTTER_DIR" ]; then
        log_warn "Flutter 已安装在 $FLUTTER_DIR"
        read -p "是否重新安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过 Flutter 安装"
            return
        fi
        sudo rm -rf "$FLUTTER_DIR"
    fi
    
    log_info "下载 Flutter SDK..."
    cd /tmp
    wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.16.0-stable.tar.xz
    
    log_info "解压 Flutter SDK..."
    sudo tar xf flutter_linux_3.16.0-stable.tar.xz -C /opt/
    sudo chown -R $USER:$USER "$FLUTTER_DIR"
    
    # 添加到 PATH
    if ! grep -q "flutter/bin" ~/.bashrc; then
        echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc
        log_info "已添加到 PATH"
    fi
    
    export PATH="$PATH:/opt/flutter/bin"
    
    # 验证安装
    flutter --version
    log_info "Flutter 安装完成"
    
    # 清理
    rm -f /tmp/flutter_linux_3.16.0-stable.tar.xz
}

# 安装 Java
install_java() {
    log_step "安装 Java JDK 17..."
    
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -n 1)
        log_warn "Java 已安装: $JAVA_VERSION"
        read -p "是否重新安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "跳过 Java 安装"
            return
        fi
    fi
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt update
        sudo apt install -y openjdk-17-jdk
        JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        sudo yum install -y java-17-openjdk-devel
        JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
    else
        log_error "不支持的操作系统: $OS"
        exit 1
    fi
    
    # 设置 JAVA_HOME
    if ! grep -q "JAVA_HOME" ~/.bashrc; then
        echo "export JAVA_HOME=$JAVA_HOME" >> ~/.bashrc
        echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.bashrc
        log_info "已设置 JAVA_HOME"
    fi
    
    export JAVA_HOME=$JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
    
    # 验证
    java -version
    javac -version
    log_info "Java 安装完成"
}

# 安装 Android SDK（通过 Flutter）
setup_android_sdk() {
    log_step "配置 Android SDK..."
    
    log_info "Flutter 会自动下载 Android SDK"
    log_info "接受 Android 许可证..."
    
    # 接受许可证
    yes | flutter doctor --android-licenses 2>/dev/null || {
        log_warn "许可证接受可能需要交互，请稍后手动运行: flutter doctor --android-licenses"
    }
    
    log_info "Android SDK 配置完成"
}

# 安装其他依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt update
        sudo apt install -y \
            curl \
            wget \
            unzip \
            git \
            xz-utils \
            zip \
            libglu1-mesa
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        sudo yum install -y \
            curl \
            wget \
            unzip \
            git \
            xz \
            zip \
            mesa-libGLU
    fi
    
    log_info "系统依赖安装完成"
}

# 运行 Flutter Doctor
run_flutter_doctor() {
    log_step "运行 Flutter Doctor 检查..."
    
    flutter doctor -v
    
    log_info "环境检查完成"
    log_warn "如果看到 ✗ 标记，请根据提示修复问题"
}

# 主函数
main() {
    echo "=========================================="
    echo "MOP 移动端编译环境一键安装脚本"
    echo "=========================================="
    echo ""
    
    # 检查 root 权限（部分操作需要）
    if [ "$EUID" -eq 0 ]; then
        log_error "请不要使用 root 用户运行此脚本"
        exit 1
    fi
    
    # 检测操作系统
    detect_os
    
    # 安装依赖
    install_dependencies
    
    # 安装 Flutter
    install_flutter
    
    # 安装 Java
    install_java
    
    # 配置 Android SDK
    setup_android_sdk
    
    # 运行检查
    run_flutter_doctor
    
    echo ""
    log_info "=========================================="
    log_info "安装完成！"
    log_info "=========================================="
    log_info "请运行以下命令使环境变量生效："
    log_info "  source ~/.bashrc"
    log_info ""
    log_info "或重新登录终端"
    log_info ""
    log_info "然后可以运行编译脚本："
    log_info "  cd /opt/mop"
    log_info "  ./scripts/build_apk.sh release all"
    echo ""
}

# 运行主函数
main
