#!/bin/bash
# 使用 Chrome 测试 WebRTC（允许 HTTP）

CHROME_PATH=""
if [ -f "/usr/bin/google-chrome" ]; then
    CHROME_PATH="/usr/bin/google-chrome"
elif [ -f "/usr/bin/chromium-browser" ]; then
    CHROME_PATH="/usr/bin/chromium-browser"
elif [ -f "/usr/bin/chromium" ]; then
    CHROME_PATH="/usr/bin/chromium"
fi

if [ -z "$CHROME_PATH" ]; then
    echo "❌ 未找到 Chrome/Chromium"
    echo ""
    echo "请手动使用以下命令启动 Chrome："
    echo "  google-chrome --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir=/tmp/chrome_jitsi_test"
    exit 1
fi

if [ -z "$1" ]; then
    echo "用法: $0 <房间URL>"
    echo ""
    echo "示例:"
    echo "  $0 'http://89.223.95.18:8000/room/r-test123?jwt=TOKEN&server=http://89.223.95.18:8080'"
    exit 1
fi

echo "🚀 启动 Chrome（允许 HTTP WebRTC）..."
echo "访问: $1"
echo ""

$CHROME_PATH \
  --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 \
  --user-data-dir=/tmp/chrome_jitsi_test \
  "$1"
