#!/bin/bash
# 快速测试进入 Jitsi 房间的脚本

set -e

API_BASE="http://89.223.95.18:8000"
JITSI_SERVER="http://89.223.95.18:8080"

echo "=========================================="
echo "Jitsi 房间加入测试脚本"
echo "=========================================="
echo ""

# 检查参数
if [ $# -lt 2 ]; then
    echo "用法: $0 <username> <password> [room_id]"
    echo ""
    echo "示例:"
    echo "  $0 testuser testpass                    # 创建新房间并加入"
    echo "  $0 testuser testpass r-a1b2c3d4        # 加入指定房间"
    exit 1
fi

USERNAME=$1
PASSWORD=$2
ROOM_ID=$3

echo "1. 登录获取访问令牌..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ 登录失败，请检查用户名和密码"
    echo "响应: $LOGIN_RESPONSE"
    exit 1
fi

echo "✅ 登录成功"
echo ""

# 如果没有提供房间ID，创建新房间
if [ -z "$ROOM_ID" ]; then
    echo "2. 创建新房间..."
    CREATE_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/rooms/create" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"room_name":"测试房间","max_occupants":10}')
    
    ROOM_ID=$(echo "$CREATE_RESPONSE" | grep -o '"room_id":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$ROOM_ID" ]; then
        echo "❌ 创建房间失败"
        echo "响应: $CREATE_RESPONSE"
        exit 1
    fi
    
    echo "✅ 房间创建成功: $ROOM_ID"
    echo ""
else
    echo "2. 使用指定房间: $ROOM_ID"
    echo ""
fi

# 加入房间
echo "3. 加入房间获取 Jitsi JWT Token..."
JOIN_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/rooms/$ROOM_ID/join" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"display_name":"测试用户"}')

JITSI_TOKEN=$(echo "$JOIN_RESPONSE" | grep -o '"jitsi_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$JITSI_TOKEN" ]; then
    echo "❌ 加入房间失败"
    echo "响应: $JOIN_RESPONSE"
    exit 1
fi

echo "✅ 成功获取 Jitsi JWT Token"
echo ""

# 构建房间 URL
ROOM_URL="$API_BASE/room/$ROOM_ID?jwt=$JITSI_TOKEN&server=$JITSI_SERVER"

echo "=========================================="
echo "✅ 房间准备就绪！"
echo "=========================================="
echo ""
echo "房间ID: $ROOM_ID"
echo "Jitsi 服务器: $JITSI_SERVER"
echo ""
echo "📱 房间访问 URL:"
echo "$ROOM_URL"
echo ""
echo "💡 提示:"
echo "1. 复制上面的 URL 到浏览器打开"
echo "2. 或者使用以下命令在浏览器中打开:"
echo "   xdg-open \"$ROOM_URL\" 2>/dev/null || echo '请手动复制 URL 到浏览器'"
echo ""
echo "🔍 查看房间信息:"
echo "   curl -H \"Authorization: Bearer $ACCESS_TOKEN\" $API_BASE/api/v1/rooms/$ROOM_ID"
echo ""
