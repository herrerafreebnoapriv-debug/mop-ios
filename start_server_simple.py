"""
简单的服务器启动脚本
"""
import uvicorn
from app.core.config import settings

if __name__ == "__main__":
    print("=" * 60)
    print("Starting MOP FastAPI Server")
    print("=" * 60)
    print(f"Host: {settings.HOST}")
    print(f"Port: {settings.PORT}")
    print(f"Debug: {settings.DEBUG}")
    print("=" * 60)
    print("\nAccess URLs:")
    print(f"  - API Docs: http://{settings.HOST}:{settings.PORT}/docs")
    print(f"  - Demo Page: http://{settings.HOST}:{settings.PORT}/demo")
    print(f"  - Health Check: http://{settings.HOST}:{settings.PORT}/health")
    print("\nPress Ctrl+C to stop the server")
    print("=" * 60)
    print()
    
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=False,  # 禁用reload以避免模块缓存问题
        log_level=settings.LOG_LEVEL.lower()
    )
