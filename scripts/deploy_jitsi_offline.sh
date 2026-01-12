#!/bin/bash
# Jitsi Meet 离线一键部署脚本
# 完全离线部署，不依赖任何网络环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "=========================================="
echo "Jitsi Meet 离线一键部署"
echo "=========================================="

# 1. 检查 Docker
echo ""
echo "1. 检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    exit 1
fi
echo "✅ Docker 已安装"

# 2. 加载本地镜像
echo ""
echo "2. 加载本地 Docker 镜像..."
if [ -f "scripts/load_jitsi_images.sh" ]; then
    bash scripts/load_jitsi_images.sh
else
    echo "⚠️  镜像加载脚本不存在，跳过（如果镜像已存在则不影响）"
fi

# 3. 创建配置目录
echo ""
echo "3. 创建配置目录..."
JITSI_CONFIG_DIR="${JITSI_CONFIG_DIR:-/opt/jitsi-meet-cfg}"
sudo mkdir -p "$JITSI_CONFIG_DIR"/{web,prosody,jvb,jicofo}
sudo chown -R 1000:1000 "$JITSI_CONFIG_DIR"
echo "✅ 配置目录已创建: $JITSI_CONFIG_DIR"

# 4. 检查环境变量
echo ""
echo "4. 检查环境变量配置..."
if [ ! -f "jitsi.env" ]; then
    if [ -f "jitsi.env.example" ]; then
        echo "⚠️  jitsi.env 不存在，从示例文件创建..."
        cp jitsi.env.example jitsi.env
        
        # 生成随机密码
        echo "生成随机密码..."
        JICOFO_SECRET=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)
        JICOFO_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)
        JVB_PASSWORD=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)
        
        cat >> jitsi.env <<EOF

# 自动生成的密码（首次部署）
JITSI_JICOFO_COMPONENT_SECRET=$JICOFO_SECRET
JITSI_JICOFO_AUTH_PASSWORD=$JICOFO_PASSWORD
JITSI_JVB_AUTH_PASSWORD=$JVB_PASSWORD
EOF
        
        echo "✅ 已创建 jitsi.env"
        echo "⚠️  请编辑 jitsi.env 设置以下配置："
        echo "   - JITSI_PUBLIC_URL: Jitsi 访问地址"
        echo "   - JITSI_JWT_APP_ID: JWT App ID（与后端一致）"
        echo "   - JITSI_JWT_APP_SECRET: JWT App Secret（与后端一致）"
        echo ""
        read -p "按 Enter 继续（或 Ctrl+C 退出编辑配置）..."
    else
        echo "❌ jitsi.env.example 不存在"
        exit 1
    fi
fi

# 5. 验证配置
echo ""
echo "5. 验证配置..."
source jitsi.env 2>/dev/null || true

if [ -z "$JITSI_JWT_APP_ID" ] || [ "$JITSI_JWT_APP_ID" = "your_jitsi_app_id" ]; then
    echo "⚠️  警告: JITSI_JWT_APP_ID 未配置，请编辑 jitsi.env"
fi

if [ -z "$JITSI_JWT_APP_SECRET" ] || [ "$JITSI_JWT_APP_SECRET" = "your_jitsi_app_secret_for_jwt_signing" ]; then
    echo "⚠️  警告: JITSI_JWT_APP_SECRET 未配置，请编辑 jitsi.env"
fi

# 6. 启动服务
echo ""
echo "6. 启动 Jitsi Meet 服务..."
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d || docker compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d

# 7. 等待服务启动
echo ""
echo "7. 等待服务启动..."
sleep 5

# 8. 检查服务状态
echo ""
echo "8. 检查服务状态..."
docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env ps || docker compose -f docker-compose.jitsi.yml --env-file jitsi.env ps

echo ""
echo "=========================================="
echo "✅ Jitsi Meet 部署完成！"
echo "=========================================="
echo ""
echo "访问地址: ${JITSI_PUBLIC_URL:-未配置}"
echo ""
echo "服务管理："
echo "  查看日志: docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env logs -f"
echo "  停止服务: docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env down"
echo "  重启服务: docker-compose -f docker-compose.jitsi.yml --env-file jitsi.env restart"
echo ""
