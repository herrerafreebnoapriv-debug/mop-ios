@echo off
chcp 65001 >nul
echo ========================================
echo MOP 系统 - 启动服务器并运行测试
echo ========================================
echo.
echo [步骤 1] 启动 FastAPI 服务器...
echo 功能：启动后端API服务器，监听8000端口
echo.
start "FastAPI服务器" cmd /k "python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload"
echo.
echo [信息] 服务器正在新窗口中启动，等待10秒让服务器完全启动...
timeout /t 10 /nobreak >nul
echo.
echo [步骤 2] 运行API测试脚本...
echo 功能：测试新实现的3个API模块（用户管理、邀请码管理、后台管理）
echo.
python scripts/test_new_apis_zh.py
echo.
echo ========================================
echo 测试完成！
echo ========================================
echo.
echo 提示：
echo   - 服务器在新窗口中运行，可以看到实时日志
echo   - 可以访问 http://127.0.0.1:8000/docs 查看API文档
echo   - 按任意键关闭此窗口（服务器窗口会继续运行）
pause >nul
