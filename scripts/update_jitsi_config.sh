#!/bin/bash
# 更新 Jitsi 配置文件，加载自定义配置和资源

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

JITSI_CONFIG_DIR="${JITSI_CONFIG_DIR:-/opt/jitsi-meet-cfg}"
WEB_CONFIG_DIR="$JITSI_CONFIG_DIR/web"

echo "=========================================="
echo "更新 Jitsi 配置文件"
echo "=========================================="

# 1. 更新 interface_config.js，引用自定义配置
echo ""
echo "1. 更新 interface_config.js..."
if [ -f "$WEB_CONFIG_DIR/interface_config.js" ]; then
    # 备份原配置
    cp "$WEB_CONFIG_DIR/interface_config.js" "$WEB_CONFIG_DIR/interface_config.js.backup"
    
    # 在文件末尾添加自定义配置引用
    cat >> "$WEB_CONFIG_DIR/interface_config.js" << 'EOF'

// 加载自定义配置（去品牌化和去外链）
if (typeof window !== 'undefined' && window.location) {
    var customConfigScript = document.createElement('script');
    customConfigScript.src = '/custom/interface_config.js';
    customConfigScript.onload = function() {
        // 合并自定义配置
        if (typeof interfaceConfig !== 'undefined') {
            Object.assign(window.interfaceConfig || {}, interfaceConfig);
        }
    };
    document.head.appendChild(customConfigScript);
}
EOF
    echo "✅ interface_config.js 已更新"
else
    echo "⚠️  interface_config.js 不存在，将在容器启动时自动生成"
fi

# 2. 更新 config.js，引用自定义配置
echo ""
echo "2. 更新 config.js..."
if [ -f "$WEB_CONFIG_DIR/config.js" ]; then
    # 备份原配置
    cp "$WEB_CONFIG_DIR/config.js" "$WEB_CONFIG_DIR/config.js.backup"
    
    # 在文件末尾添加自定义配置引用
    cat >> "$WEB_CONFIG_DIR/config.js" << 'EOF'

// 加载自定义配置（去除外链）
if (typeof window !== 'undefined' && window.location) {
    var customConfigScript = document.createElement('script');
    customConfigScript.src = '/custom/config.js';
    customConfigScript.onload = function() {
        // 合并自定义配置
        if (typeof config !== 'undefined') {
            Object.assign(window.config || {}, config);
        }
    };
    document.head.appendChild(customConfigScript);
}
EOF
    echo "✅ config.js 已更新"
else
    echo "⚠️  config.js 不存在，将在容器启动时自动生成"
fi

# 3. 创建 favicon.ico 链接
echo ""
echo "3. 创建 favicon 链接..."
if [ -f "$WEB_CONFIG_DIR/custom/favicon.png" ]; then
    # 转换为 favicon.ico（如果需要）
    # 这里直接使用 PNG，现代浏览器支持 PNG favicon
    cp "$WEB_CONFIG_DIR/custom/favicon.png" "$WEB_CONFIG_DIR/favicon.png" 2>/dev/null || true
    echo "✅ Favicon 已复制"
fi

# 4. 设置权限
echo ""
echo "4. 设置文件权限..."
chown -R 1000:1000 "$WEB_CONFIG_DIR" 2>/dev/null || sudo chown -R 1000:1000 "$WEB_CONFIG_DIR"

echo ""
echo "=========================================="
echo "✅ 配置文件更新完成！"
echo "=========================================="
echo ""
echo "注意：需要重启 Jitsi Web 容器以应用配置"
echo ""
