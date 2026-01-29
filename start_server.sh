#!/bin/bash
# 启动/重启 MOP 后端服务器脚本
# 用法: bash /opt/mop/start_server.sh [restart]

cd /opt/mop

# 如果传入 restart 参数，先停止现有进程
if [ "$1" = "restart" ]; then
    if pgrep -f "uvicorn app.main:app" > /dev/null; then
        echo "正在停止现有服务器..."
        pkill -f "uvicorn app.main:app"
        sleep 2
        
        # 确保进程已停止
        if pgrep -f "uvicorn app.main:app" > /dev/null; then
            echo "强制停止服务器..."
            killall -9 uvicorn 2>/dev/null
            sleep 1
        fi
    fi
fi

# 检查是否已经运行（非重启模式下）
if [ "$1" != "restart" ] && pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "服务器已经在运行中"
    ps aux | grep uvicorn | grep -v grep
    echo ""
    echo "如需重启，请使用: bash /opt/mop/start_server.sh restart"
    exit 0
fi

# 启动服务器
if [ "$1" = "restart" ]; then
    echo "正在重启 MOP 后端服务器..."
else
    echo "正在启动 MOP 后端服务器..."
fi
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > /var/log/mop-backend.log 2>&1 &

# 等待启动
sleep 3

# 检查是否启动成功
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "✅ 服务器启动成功"
    echo "PID: $(pgrep -f 'uvicorn app.main:app')"
    echo "日志文件: /var/log/mop-backend.log"
    echo "健康检查: http://127.0.0.1:8000/"
else
    echo "❌ 服务器启动失败，请查看日志: /var/log/mop-backend.log"
    tail -20 /var/log/mop-backend.log
    exit 1
fi
