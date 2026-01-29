#!/bin/bash
# 重启 MOP 后端服务器脚本
# 用法: bash /opt/mop/restart_server.sh

cd /opt/mop

echo "正在重启 MOP 后端服务器..."

# 停止现有进程
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
else
    echo "未发现运行中的服务器"
fi

# 启动服务器
echo "正在启动新服务器..."
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > /var/log/mop-backend.log 2>&1 &

# 等待启动
sleep 3

# 检查是否启动成功
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "✅ 服务器重启成功"
    echo "PID: $(pgrep -f 'uvicorn app.main:app')"
    echo "日志文件: /var/log/mop-backend.log"
    echo "健康检查: http://127.0.0.1:8000/"
    
    # 显示最后几行日志
    echo ""
    echo "最近日志:"
    tail -10 /var/log/mop-backend.log
else
    echo "❌ 服务器启动失败，请查看日志: /var/log/mop-backend.log"
    tail -20 /var/log/mop-backend.log
    exit 1
fi
