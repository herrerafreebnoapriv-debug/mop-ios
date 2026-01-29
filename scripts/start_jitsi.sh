#!/bin/bash
# Jitsi Meet 启动脚本（使用 docker run，绕过 docker-compose 兼容性问题）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo "Jitsi Meet 服务启动脚本"
echo "=========================================="

# 检查 jitsi.env 文件
if [ ! -f "jitsi.env" ]; then
    echo "❌ jitsi.env 文件不存在，请先创建配置文件"
    exit 1
fi

# 加载环境变量
source jitsi.env

# 创建网络（如果不存在）
echo ""
echo "1. 检查 Docker 网络..."
docker network create jitsi_meet 2>/dev/null || echo "网络已存在"

# 创建配置目录
echo ""
echo "2. 检查配置目录..."
sudo mkdir -p /opt/jitsi-meet-cfg/{web,prosody,jvb,jicofo}
sudo chown -R 1000:1000 /opt/jitsi-meet-cfg

# 检查容器是否已存在
echo ""
echo "3. 检查现有容器..."

if docker ps -a --format '{{.Names}}' | grep -q "^jitsi_prosody$"; then
    echo "   发现已存在的容器，先停止并删除..."
    docker stop jitsi_prosody jitsi_jvb jitsi_jicofo jitsi_web 2>/dev/null || true
    docker rm jitsi_prosody jitsi_jvb jitsi_jicofo jitsi_web 2>/dev/null || true
fi

# 启动 Prosody
echo ""
echo "4. 启动 jitsi_prosody..."
docker run -d \
    --log-driver none \
    --name jitsi_prosody \
    --restart unless-stopped \
    --network jitsi_meet \
    -v /opt/jitsi-meet-cfg/prosody:/config:Z \
    -e AUTH_TYPE=jwt \
    -e ENABLE_AUTH=1 \
    -e ENABLE_GUESTS=0 \
    -e XMPP_DOMAIN=meet.jitsi \
    -e XMPP_AUTH_DOMAIN=auth.meet.jitsi \
    -e XMPP_GUEST_DOMAIN=guest.meet.jitsi \
    -e XMPP_MUC_DOMAIN=muc.meet.jitsi \
    -e XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi \
    -e XMPP_RECORDER_DOMAIN=recorder.meet.jitsi \
    -e JICOFO_COMPONENT_SECRET="$JITSI_JICOFO_COMPONENT_SECRET" \
    -e JICOFO_AUTH_USER="$JITSI_JICOFO_AUTH_USER" \
    -e JICOFO_AUTH_PASSWORD="$JITSI_JICOFO_AUTH_PASSWORD" \
    -e JVB_AUTH_USER="$JITSI_JVB_AUTH_USER" \
    -e JVB_AUTH_PASSWORD="$JITSI_JVB_AUTH_PASSWORD" \
    -e JWT_APP_ID="$JITSI_JWT_APP_ID" \
    -e JWT_APP_SECRET="$JITSI_JWT_APP_SECRET" \
    -e JWT_ACCEPTED_ISSUERS="$JITSI_JWT_ACCEPTED_ISSUERS" \
    -e JWT_ACCEPTED_AUDIENCES="$JITSI_JWT_ACCEPTED_AUDIENCES" \
    -e JWT_ALLOW_EMPTY=false \
    -e JWT_AUTH_TYPE=token \
    -e JWT_TOKEN_AUTH_MODULE=token_verification \
    -e LOG_LEVEL="${JITSI_LOG_LEVEL:-ERROR}" \
    -e TZ=Asia/Shanghai \
    jitsi/prosody:stable

# 启动 JVB
echo ""
echo "5. 启动 jitsi_jvb..."
docker run -d \
    --log-driver none \
    --name jitsi_jvb \
    --restart unless-stopped \
    --network jitsi_meet \
    -p "${JITSI_JVB_PORT:-10000}:10000/udp" \
    -p "${JITSI_JVB_TCP_PORT:-4443}:4443/tcp" \
    -v /opt/jitsi-meet-cfg/jvb:/config:Z \
    -e XMPP_AUTH_DOMAIN=auth.meet.jitsi \
    -e XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi \
    -e XMPP_SERVER=jitsi_prosody \
    -e JVB_AUTH_USER="$JITSI_JVB_AUTH_USER" \
    -e JVB_AUTH_PASSWORD="$JITSI_JVB_AUTH_PASSWORD" \
    -e JVB_BREWERY_MUC=jvbbrewery \
    -e JVB_PORT=10000 \
    -e JVB_TCP_PORT=4443 \
    -e JVB_STUN_SERVERS="${JITSI_JVB_STUN_SERVERS:-}" \
    -e JVB_ENABLE_APIS=rest,xmpp \
    -e LOG_LEVEL="${JITSI_LOG_LEVEL:-ERROR}" \
    -e TZ=Asia/Shanghai \
    jitsi/jvb:stable

# 启动 Jicofo
echo ""
echo "6. 启动 jitsi_jicofo..."
docker run -d \
    --log-driver none \
    --name jitsi_jicofo \
    --restart unless-stopped \
    --network jitsi_meet \
    -v /opt/jitsi-meet-cfg/jicofo:/config:Z \
    -e ENABLE_AUTH=1 \
    -e XMPP_DOMAIN=meet.jitsi \
    -e XMPP_AUTH_DOMAIN=auth.meet.jitsi \
    -e XMPP_INTERNAL_MUC_DOMAIN=internal-muc.meet.jitsi \
    -e XMPP_SERVER=jitsi_prosody \
    -e JICOFO_COMPONENT_SECRET="$JITSI_JICOFO_COMPONENT_SECRET" \
    -e JICOFO_AUTH_USER="$JITSI_JICOFO_AUTH_USER" \
    -e JICOFO_AUTH_PASSWORD="$JITSI_JICOFO_AUTH_PASSWORD" \
    -e JVB_BREWERY_MUC=jvbbrewery \
    -e HOST=meet.jitsi \
    -e XMPP_MUC_DOMAIN=muc.meet.jitsi \
    -e ENABLE_SCTP=0 \
    -e LOG_LEVEL="${JITSI_LOG_LEVEL:-ERROR}" \
    -e TZ=Asia/Shanghai \
    jitsi/jicofo:stable

# 启动 Web
echo ""
echo "7. 启动 jitsi_web..."
# 如果启用了 Let's Encrypt，需要监听 80/443 端口
if [ "${JITSI_ENABLE_LETSENCRYPT:-0}" = "1" ] && [ "${JITSI_DISABLE_HTTPS:-1}" = "0" ]; then
    echo "   启用 HTTPS 和 Let's Encrypt，监听 80/443 端口"
    HTTP_PORT="${JITSI_HTTP_PORT:-80}"
    HTTPS_PORT="${JITSI_HTTPS_PORT:-443}"
else
    echo "   使用 HTTP，监听 ${JITSI_HTTP_PORT:-8080}/${JITSI_HTTPS_PORT:-8443} 端口"
    HTTP_PORT="${JITSI_HTTP_PORT:-8080}"
    HTTPS_PORT="${JITSI_HTTPS_PORT:-8443}"
fi

# 获取 Prosody 容器 IP（用于 hosts 解析）
PROSODY_IP=$(docker inspect jitsi_prosody --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || echo "172.19.0.2")

docker run -d \
    --log-driver none \
    --name jitsi_web \
    --restart unless-stopped \
    --network jitsi_meet \
    --add-host "jitsi_prosody:${PROSODY_IP}" \
    --add-host "meet.jitsi:${PROSODY_IP}" \
    --add-host "xmpp.meet.jitsi:${PROSODY_IP}" \
    --add-host "muc.meet.jitsi:${PROSODY_IP}" \
    --add-host "auth.meet.jitsi:${PROSODY_IP}" \
    -p "${HTTP_PORT}:80" \
    -p "${HTTPS_PORT}:443" \
    -v /opt/jitsi-meet-cfg/web:/config:Z \
    -e ENABLE_AUTH="${JITSI_ENABLE_AUTH:-1}" \
    -e ENABLE_GUESTS="${JITSI_ENABLE_GUESTS:-0}" \
    -e ENABLE_LETSENCRYPT="${JITSI_ENABLE_LETSENCRYPT:-0}" \
    -e ENABLE_HTTP_REDIRECT="${JITSI_ENABLE_HTTP_REDIRECT:-0}" \
    -e ENABLE_TRANSCRIPTIONS="${JITSI_ENABLE_TRANSCRIPTIONS:-0}" \
    -e DISABLE_HTTPS="${JITSI_DISABLE_HTTPS:-1}" \
    -e LETSENCRYPT_DOMAIN="${JITSI_LETSENCRYPT_DOMAIN:-}" \
    -e LETSENCRYPT_EMAIL="${JITSI_LETSENCRYPT_EMAIL:-}" \
    -e JICOFO_AUTH_USER="$JITSI_JICOFO_AUTH_USER" \
    -e PUBLIC_URL="$JITSI_PUBLIC_URL" \
    -e TZ=Asia/Shanghai \
    jitsi/web:stable

echo ""
echo "=========================================="
echo "✅ Jitsi Meet 服务启动完成！"
echo "=========================================="
echo ""
echo "服务状态："
docker ps --filter "name=jitsi" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# 执行去品牌化和去除外链
echo "8. 执行去品牌化和去除外链..."
if [ -f "$SCRIPT_DIR/customize_jitsi.sh" ]; then
    "$SCRIPT_DIR/customize_jitsi.sh"
else
    echo "   ⚠️  自定义脚本不存在，跳过"
fi

echo ""
echo "访问地址: $JITSI_PUBLIC_URL"
echo ""
echo "查看日志："
echo "  docker logs -f jitsi_web"
echo "  docker logs -f jitsi_prosody"
echo "  docker logs -f jitsi_jvb"
echo "  docker logs -f jitsi_jicofo"
echo ""
echo "停止服务："
echo "  docker stop jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody"
echo "  docker rm jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody"
echo ""
