#!/bin/bash
# 保存 Jitsi Docker 镜像到本地
# 用于离线部署，不依赖网络环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

IMAGES_DIR="$PROJECT_DIR/docker/images"
JITSI_IMAGES=(
    "jitsi/web:latest"
    "jitsi/prosody:latest"
    "jitsi/jvb:latest"
    "jitsi/jicofo:latest"
)

echo "=========================================="
echo "保存 Jitsi Docker 镜像到本地"
echo "=========================================="

# 创建镜像目录
mkdir -p "$IMAGES_DIR"
echo "✅ 镜像目录已创建: $IMAGES_DIR"

# 拉取并保存镜像
for image in "${JITSI_IMAGES[@]}"; do
    echo ""
    echo "处理镜像: $image"
    
    # 拉取镜像
    echo "  拉取镜像..."
    docker pull "$image"
    
    # 生成文件名（替换 : 为 -）
    filename=$(echo "$image" | sed 's/:/-/g' | sed 's/\//_/g').tar
    filepath="$IMAGES_DIR/$filename"
    
    # 保存镜像
    echo "  保存镜像到: $filepath"
    docker save "$image" -o "$filepath"
    
    # 压缩镜像（可选，节省空间）
    echo "  压缩镜像..."
    gzip -f "$filepath"
    
    echo "  ✅ 完成: ${filepath}.gz"
done

echo ""
echo "=========================================="
echo "✅ 所有镜像已保存完成！"
echo "=========================================="
echo ""
echo "镜像文件位置: $IMAGES_DIR"
echo ""
echo "镜像列表:"
ls -lh "$IMAGES_DIR"/*.tar.gz 2>/dev/null || echo "  无镜像文件"
echo ""
echo "下一步："
echo "1. 将这些镜像文件打包到项目中"
echo "2. 使用 scripts/load_jitsi_images.sh 加载镜像"
echo ""
