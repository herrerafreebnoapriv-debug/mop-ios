#!/bin/bash
# 清理 Jitsi 所有日志，并确保重启后持久化不写日志
# 使用方式：./scripts/clear_jitsi_logs.sh [--restart]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
JITSI_CONFIG_DIR="${JITSI_CONFIG_DIR:-/opt/jitsi-meet-cfg}"
DO_RESTART=false
[ "${1:-}" = "--restart" ] && DO_RESTART=true

echo "=========================================="
echo "清理 Jitsi 日志并固化禁用配置"
echo "=========================================="

# 1. 删除配置目录下所有 .log 文件
echo ""
echo "1. 删除 $JITSI_CONFIG_DIR 下所有 .log 文件..."
find "$JITSI_CONFIG_DIR" -type f -name "*.log" 2>/dev/null | while read -r f; do
    rm -f "$f" && echo "   已删除: $f" || true
done
echo "   ✅ 完成"

# 2. 注入 JVB/Jicofo 日志禁用配置（持久化）
echo ""
echo "2. 注入 JVB/Jicofo 日志禁用配置..."
for conf in jvb jicofo; do
    SRC="$PROJECT_DIR/docker/jitsi/custom/logging-${conf}.properties"
    DST="$JITSI_CONFIG_DIR/${conf}/logging.properties"
    if [ -f "$SRC" ] && [ -d "$JITSI_CONFIG_DIR/$conf" ]; then
        cp "$SRC" "$DST" 2>/dev/null && echo "   ✅ ${conf}/logging.properties 已更新" || true
    fi
done

# 3. 若使用 docker-compose，可清理容器日志并重启（需 --restart）
if [ "$DO_RESTART" = true ]; then
    echo ""
    echo "3. 重启 Jitsi（应用 log-driver none 与 LOG_LEVEL）..."
    if [ -f "docker-compose.jitsi.yml" ] && [ -f "jitsi.env" ]; then
        docker compose -f docker-compose.jitsi.yml --env-file jitsi.env down 2>/dev/null || true
        docker compose -f docker-compose.jitsi.yml --env-file jitsi.env up -d 2>/dev/null || true
        echo "   ✅ Jitsi 已重启"
    else
        echo "   ⚠️  未找到 docker-compose.jitsi.yml 或 jitsi.env，跳过重启"
    fi
else
    echo ""
    echo "3. 跳过重启。若需重启以应用 log-driver none，请执行："
    echo "   $0 --restart"
fi

echo ""
echo "=========================================="
echo "✅ 清理完成。重启后禁用日志配置将持久生效。"
echo "=========================================="
