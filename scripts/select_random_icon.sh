#!/bin/bash
# 随机选择图标脚本
# 用于去 Jitsi 化，随机替换图标和 favicon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

ICON_DIR="$PROJECT_DIR/mop_ico_fav"
JIT_LOGO_DIR="$ICON_DIR/jit_logo"

# 函数：随机选择文件
select_random_file() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo ""
        return
    fi
    
    # 使用数组存储文件路径，正确处理包含空格和特殊字符的文件名
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.svg" -o -name "*.ico" \) -print0 | sort -z)
    
    if [ ${#files[@]} -eq 0 ]; then
        echo ""
        return
    fi
    
    local random_index=$((RANDOM % ${#files[@]}))
    echo "${files[$random_index]}"
}

# 选择首页左上角 logo（从 jit_logo 目录）
LOGO_FILE=$(select_random_file "$JIT_LOGO_DIR")
if [ -n "$LOGO_FILE" ]; then
    echo "选择的首页 Logo: $LOGO_FILE"
    cp "$LOGO_FILE" "$ICON_DIR/selected_logo.png"
else
    echo "警告: 未找到 jit_logo 目录下的图标"
fi

# 选择 favicon（从主目录的方形图标）
FAVICON_FILE=$(select_random_file "$ICON_DIR")
if [ -n "$FAVICON_FILE" ] && [ "$FAVICON_FILE" != "$LOGO_FILE" ]; then
    echo "选择的 Favicon: $FAVICON_FILE"
    cp "$FAVICON_FILE" "$ICON_DIR/selected_favicon.png"
else
    # 如果和 logo 相同，再选一次
    FAVICON_FILE=$(select_random_file "$ICON_DIR")
    if [ -n "$FAVICON_FILE" ]; then
        echo "选择的 Favicon: $FAVICON_FILE"
        cp "$FAVICON_FILE" "$ICON_DIR/selected_favicon.png"
    fi
fi

echo ""
echo "✅ 图标选择完成"
echo "  Logo: $ICON_DIR/selected_logo.png"
echo "  Favicon: $ICON_DIR/selected_favicon.png"
