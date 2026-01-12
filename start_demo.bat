@echo off
chcp 65001 >nul
echo ========================================
echo MOP - 多语言演示页面启动脚本
echo ========================================
echo.
echo 正在启动 FastAPI 服务器...
echo.
echo 启动后，请在浏览器中访问：
echo   http://127.0.0.1:8000/demo
echo.
echo 或者访问 Swagger UI：
echo   http://127.0.0.1:8000/docs
echo.
echo 按 Ctrl+C 停止服务器
echo ========================================
echo.

python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload

pause
