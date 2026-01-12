#!/bin/bash
# 启动 MOP 后端服务器脚本

cd /opt/mop

# 检查是否已经运行
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "服务器已经在运行中"
    ps aux | grep uvicorn | grep -v grep
    exit 0
fi

# 启动服务器
echo "正在启动 MOP 后端服务器..."
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/mop_server.log 2>&1 &

# 等待启动
sleep 3

# 检查是否启动成功
if pgrep -f "uvicorn app.main:app" > /dev/null; then
    echo "✅ 服务器启动成功"
    echo "PID: $(pgrep -f 'uvicorn app.main:app')"
    echo "日志文件: /tmp/mop_server.log"
    echo "健康检查: http://127.0.0.1:8000/health"
else
    echo "❌ 服务器启动失败，请查看日志: /tmp/mop_server.log"
    tail -20 /tmp/mop_server.log
    exit 1
fi
