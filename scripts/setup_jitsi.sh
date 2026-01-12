#!/bin/bash
# Jitsi Meet Docker 部署脚本
# 用于快速部署和配置 Jitsi Meet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo "Jitsi Meet Docker 部署脚本"
echo "=========================================="

# 1. 检查 Docker 和 Docker Compose
echo ""
echo "1. 检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose 未安装，请先安装 Docker Compose"
    exit 1
fi

echo "✅ Docker 环境检查通过"

# 2. 创建配置目录
echo ""
echo "2. 创建配置目录..."
JITSI_CONFIG_DIR="${JITSI_CONFIG_DIR:-/opt/jitsi-meet-cfg}"
sudo mkdir -p "$JITSI_CONFIG_DIR"/{web,prosody,jvb,jicofo}
sudo chown -R 1000:1000 "$JITSI_CONFIG_DIR"
echo "✅ 配置目录已创建: $JITSI_CONFIG_DIR"

# 3. 检查环境变量文件
echo ""
echo "3. 检查环境变量配置..."
if [ ! -f "jitsi.env" ]; then
    echo "⚠️  jitsi.env 文件不存在，从示例文件创建..."
    if [ -f "jitsi.env.example" ]; then
        cp jitsi.env.example jitsi.env
        echo "✅ 已创建 jitsi.env，请编辑配置："
        echo "   - JITSI_PUBLIC_URL: Jitsi 公共访问地址"
        echo "   - JITSI_JWT_APP_ID: 必须与后端 .env 中的 JITSI_APP_ID 一致"
        echo "   - JITSI_JWT_APP_SECRET: 必须与后端 .env 中的 JITSI_APP_SECRET 一致"
        echo ""
        echo "⚠️  请先编辑 jitsi.env 文件，然后重新运行此脚本"
        exit 1
    else
        echo "❌ jitsi.env.example 文件不存在"
        exit 1
    fi
else
    echo "✅ jitsi.env 文件存在"
fi

# 4. 生成随机密码（如果未设置）
echo ""
echo "4. 生成认证密码..."
source jitsi.env 2>/dev/null || true

if [ -z "$JITSI_JICOFO_COMPONENT_SECRET" ] || [ "$JITSI_JICOFO_COMPONENT_SECRET" = "\$(openssl rand -hex 16)" ]; then
    JITSI_JICOFO_COMPONENT_SECRET=$(openssl rand -hex 16)
    echo "JITSI_JICOFO_COMPONENT_SECRET=$JITSI_JICOFO_COMPONENT_SECRET" >> jitsi.env
    echo "✅ 已生成 JICOFO_COMPONENT_SECRET"
fi

if [ -z "$JITSI_JICOFO_AUTH_PASSWORD" ] || [ "$JITSI_JICOFO_AUTH_PASSWORD" = "\$(openssl rand -hex 16)" ]; then
    JITSI_JICOFO_AUTH_PASSWORD=$(openssl rand -hex 16)
    echo "JITSI_JICOFO_AUTH_PASSWORD=$JITSI_JICOFO_AUTH_PASSWORD" >> jitsi.env
    echo "✅ 已生成 JICOFO_AUTH_PASSWORD"
fi

if [ -z "$JITSI_JVB_AUTH_PASSWORD" ] || [ "$JITSI_JVB_AUTH_PASSWORD" = "\$(openssl rand -hex 16)" ]; then
    JITSI_JVB_AUTH_PASSWORD=$(openssl rand -hex 16)
    echo "JITSI_JVB_AUTH_PASSWORD=$JITSI_JVB_AUTH_PASSWORD" >> jitsi.env
    echo "✅ 已生成 JVB_AUTH_PASSWORD"
fi

# 5. 检查必要的配置
echo ""
echo "5. 验证配置..."
source jitsi.env

if [ -z "$JITSI_PUBLIC_URL" ] || [ "$JITSI_PUBLIC_URL" = "http://localhost:8080" ]; then
    echo "⚠️  警告: JITSI_PUBLIC_URL 使用默认值，生产环境请修改"
fi

if [ -z "$JITSI_JWT_APP_ID" ] || [ "$JITSI_JWT_APP_ID" = "your_jitsi_app_id" ]; then
    echo "❌ 错误: JITSI_JWT_APP_ID 未配置"
    echo "   请编辑 jitsi.env 文件，设置 JITSI_JWT_APP_ID"
    exit 1
fi

if [ -z "$JITSI_JWT_APP_SECRET" ] || [ "$JITSI_JWT_APP_SECRET" = "your_jitsi_app_secret_for_jwt_signing" ]; then
    echo "❌ 错误: JITSI_JWT_APP_SECRET 未配置"
    echo "   请编辑 jitsi.env 文件，设置 JITSI_JWT_APP_SECRET"
    exit 1
fi

echo "✅ 配置验证通过"

# 6. 拉取 Docker 镜像
echo ""
echo "6. 拉取 Docker 镜像..."
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env pull || docker compose -f docker-compose.jitsi.yml --env-file jitsi.env pull
echo "✅ 镜像拉取完成"

# 7. 启动服务
echo ""
echo "7. 启动 Jitsi Meet 服务..."
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d || docker compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d

echo ""
echo "=========================================="
echo "✅ Jitsi Meet 部署完成！"
echo "=========================================="
echo ""
echo "服务状态："
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env ps || docker compose -f docker-compose.jitsi.yml --env-file jitsi.env ps

echo ""
echo "访问地址: $JITSI_PUBLIC_URL"
echo ""
echo "下一步："
echo "1. 确保后端 .env 中的 JITSI_SERVER_URL 与 JITSI_PUBLIC_URL 一致"
echo "2. 确保后端 .env 中的 JITSI_APP_ID 和 JITSI_APP_SECRET 与 jitsi.env 一致"
echo "3. 测试房间连接：访问 $JITSI_PUBLIC_URL/test-room"
echo ""
echo "查看日志："
echo "  docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f"
echo ""
echo "停止服务："
echo "  docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env down"
echo ""
