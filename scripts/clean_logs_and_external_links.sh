#!/bin/bash
# 清理所有 console.log/console.warn 等日志输出，并移除硬编码外链 URL
# 保留关键错误（console.error for critical errors）

set -e
cd /opt/mop/static

echo "=========================================="
echo "清理日志输出和硬编码外链"
echo "=========================================="

# 1. 清理 console.log（调试日志）
echo ""
echo "1. 清理 console.log（调试日志）..."
find . -name "*.js" -type f ! -name "socket.io.min.js" ! -name "*.min.js" -exec sed -i '/console\.log(/d' {} \;
echo "   ✅ console.log 已清理"

# 2. 清理 console.warn（警告日志）
echo ""
echo "2. 清理 console.warn（警告日志）..."
find . -name "*.js" -type f ! -name "socket.io.min.js" ! -name "*.min.js" -exec sed -i '/console\.warn(/d' {} \;
echo "   ✅ console.warn 已清理"

# 3. 清理 console.debug/console.info
echo ""
echo "3. 清理 console.debug/console.info..."
find . -name "*.js" -type f ! -name "socket.io.min.js" ! -name "*.min.js" -exec sed -i '/console\.debug(/d; /console\.info(/d' {} \;
echo "   ✅ console.debug/info 已清理"

# 4. 移除硬编码的 api.chat5202ol.xyz 外链
echo ""
echo "4. 移除硬编码外链 URL（api.chat5202ol.xyz）..."

for file in dashboard.html login.html register.html devices.html test_api.html; do
    if [ -f "$file" ] && grep -q "https://api.chat5202ol.xyz" "$file" 2>/dev/null; then
        sed -i 's|https://api\.chat5202ol\.xyz/api/v1|/api/v1|g' "$file"
        echo "   ✅ $file 已修复"
    fi
done

echo ""
echo "=========================================="
echo "✅ 清理完成"
echo "=========================================="
