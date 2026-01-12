#!/bin/bash
# 从本地加载 Jitsi Docker 镜像
# 用于离线部署，不依赖网络环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

IMAGES_DIR="$PROJECT_DIR/docker/images"

echo "=========================================="
echo "从本地加载 Jitsi Docker 镜像"
echo "=========================================="

# 检查镜像目录
if [ ! -d "$IMAGES_DIR" ]; then
    echo "❌ 镜像目录不存在: $IMAGES_DIR"
    exit 1
fi

# 查找所有镜像文件
IMAGE_FILES=$(find "$IMAGES_DIR" -name "*.tar.gz" -o -name "*.tar" 2>/dev/null | sort)

if [ -z "$IMAGE_FILES" ]; then
    echo "❌ 未找到镜像文件，请先运行 scripts/save_jitsi_images.sh"
    exit 1
fi

# 加载镜像
for image_file in $IMAGE_FILES; do
    echo ""
    echo "加载镜像: $(basename $image_file)"
    
    # 如果是压缩文件，先解压
    if [[ "$image_file" == *.gz ]]; then
        echo "  解压镜像..."
        gunzip -c "$image_file" | docker load
    else
        echo "  加载镜像..."
        docker load -i "$image_file"
    fi
    
    echo "  ✅ 完成"
done

echo ""
echo "=========================================="
echo "✅ 所有镜像已加载完成！"
echo "=========================================="
echo ""
echo "验证镜像："
docker images | grep jitsi || echo "  未找到 jitsi 镜像"
echo ""
