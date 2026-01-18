"""
FastAPI 主应用入口
初始化 FastAPI 应用、中间件、路由和生命周期事件
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, FileResponse
from loguru import logger
import sys
from pathlib import Path

from app.core.config import settings
from app.db.session import db
from app.core.socketio import socketio_app, sio, start_heartbeat_monitor

# 调试：打印CORS配置
logger.info(f"CORS允许的源: {settings.cors_origins_list}")


# 配置日志
def setup_logging():
    """配置应用日志"""
    logger.remove()  # 移除默认处理器
    logger.add(
        sys.stdout,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        level=settings.LOG_LEVEL,
        colorize=True
    )
    logger.add(
        settings.LOG_FILE,
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} - {message}",
        level=settings.LOG_LEVEL,
        rotation="10 MB",
        retention="7 days",
        compression="zip"
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    应用生命周期管理
    启动时初始化数据库，关闭时清理资源
    """
    # 启动时执行
    logger.info(f"启动 {settings.APP_NAME} v{settings.APP_VERSION}")
    logger.info(f"环境: {'开发' if settings.DEBUG else '生产'}")
    
    # 初始化数据库（异步）
    try:
        await db.initialize()
        logger.info("数据库连接已初始化")
    except Exception as e:
        logger.warning(f"数据库初始化失败（可能未配置）: {e}")
        # 不抛出异常，允许应用启动（数据库可能未配置）
        logger.info("应用将在数据库未配置的情况下运行，某些功能可能不可用")
    
    # 启动 Socket.io 心跳监测
    try:
        start_heartbeat_monitor()
        logger.info("Socket.io 心跳监测已启动")
    except Exception as e:
        logger.error(f"启动 Socket.io 心跳监测失败: {e}")
    
    yield
    
    # 关闭时执行
    logger.info("正在关闭应用...")
    try:
        await db.close()
        logger.info("数据库连接已关闭")
    except Exception as e:
        logger.error(f"关闭数据库连接时出错: {e}")


# 创建 FastAPI 应用实例
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="MOP 后端 API - 私有化管控通讯系统",
    docs_url="/docs" if settings.DEBUG else None,  # 生产环境关闭 Swagger UI
    redoc_url="/redoc" if settings.DEBUG else None,  # 生产环境关闭 ReDoc
    openapi_url="/openapi.json" if settings.DEBUG else None,  # 生产环境关闭 OpenAPI Schema
    lifespan=lifespan
)

# 配置 CORS 中间件
# 使用 allow_origins 从配置中读取，如果没有配置则使用默认值
cors_origins = settings.cors_origins_list
if not cors_origins:
    # 默认值
    cors_origins = [
        "https://www.chat5202ol.xyz",      # 主域名：后台管理系统
        "https://chat5202ol.xyz",          # 主域名（备用）
        "https://log.chat5202ol.xyz",      # log域名：即时通讯
        "https://app.chat5202ol.xyz",      # 移动端应用
        "https://api.chat5202ol.xyz",      # API服务域名
        "http://localhost:3000",
        "http://localhost:8080",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:8000",
    ]

logger.info(f"配置 CORS 允许的源: {cors_origins}")

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=[
        "accept",
        "accept-language",
        "Accept-Language",
        "authorization",
        "Authorization",
        "content-type",
        "Content-Type",
        "x-requested-with",
        "X-Requested-With",
    ],
    expose_headers=["*"],
)


# 全局异常处理
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc):
    """全局异常处理器"""
    from app.core.i18n import get_language_from_request, i18n
    
    lang = get_language_from_request(request)
    try:
        logger.error(f"未处理的异常: {repr(exc)}", exc_info=True)
    except Exception:
        logger.error("未处理的异常", exc_info=True)
    
    return JSONResponse(
        status_code=500,
        content={
            "error": i18n.get("common.internal_error", lang),
            "detail": str(exc) if settings.DEBUG else i18n.get("common.internal_error", lang)
        }
    )


# 健康检查端点
@app.get("/health", tags=["系统"])
async def health_check(request: Request):
    """
    健康检查端点
    用于监控系统状态
    """
    from app.core.i18n import get_language_from_request, i18n
    
    lang = get_language_from_request(request)
    app_name = i18n.get("app.name", lang)
    
    return {
        "status": "healthy",
        "app_name": app_name,
        "version": settings.APP_VERSION,
        "environment": "development" if settings.DEBUG else "production"
    }


# 根路径
@app.get("/", tags=["系统"])
async def root(request: Request):
    """根路径"""
    from app.core.i18n import get_language_from_request, i18n
    
    lang = get_language_from_request(request)
    app_name = i18n.get("app.name", lang)
    
    return {
        "message": i18n.get("common.welcome", lang, app_name=app_name),
        "version": settings.APP_VERSION,
        "docs": "/docs" if settings.DEBUG else i18n.get("common.docs_disabled", lang)
    }


# 导入路由
from app.api.v1 import router as api_v1_router
app.include_router(api_v1_router, prefix=settings.API_V1_PREFIX)

# Favicon 路由（根路径，浏览器会自动请求）
@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    """随机返回 favicon"""
    from app.api.v1.favicon import get_random_favicon
    return await get_random_favicon()

# 挂载 Socket.io 应用
# Socket.io 路径：/socket.io/
app.mount("/socket.io", socketio_app)

# 静态文件服务（用于演示页面）
static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
    
    @app.get("/demo", tags=["演示"])
    async def i18n_demo():
        """多语言演示页面"""
        demo_file = static_dir / "i18n_demo.html"
        if demo_file.exists():
            return FileResponse(demo_file)
        return {"error": "Demo page not found"}
    
    @app.get("/login", tags=["认证"])
    async def login_page():
        """登录页面"""
        login_file = static_dir / "login.html"
        if login_file.exists():
            return FileResponse(login_file)
        return {"error": "Login page not found"}
    
    @app.get("/login.html", tags=["认证"])
    async def login_html_page():
        """登录页面（HTML文件路径）"""
        login_file = static_dir / "login.html"
        if login_file.exists():
            return FileResponse(login_file)
        return {"error": "Login page not found"}
    
    @app.get("/register", tags=["认证"])
    async def register_page():
        """注册页面"""
        register_file = static_dir / "register.html"
        if register_file.exists():
            return FileResponse(register_file)
        return {"error": "Register page not found"}
    
    @app.get("/register.html", tags=["认证"])
    async def register_html_page():
        """注册页面（HTML文件路径）"""
        register_file = static_dir / "register.html"
        if register_file.exists():
            return FileResponse(register_file)
        return {"error": "Register page not found"}
    
    @app.get("/dashboard", tags=["应用"])
    async def dashboard_page():
        """主控制台页面"""
        dashboard_file = static_dir / "dashboard.html"
        if dashboard_file.exists():
            return FileResponse(dashboard_file)
        return {"error": "Dashboard page not found"}
    
    @app.get("/room/{room_id}", tags=["应用"])
    async def room_page(room_id: str, jwt: str = None, server: str = None):
        """Jitsi 视频通话房间页面"""
        room_file = static_dir / "room.html"
        if room_file.exists():
            return FileResponse(room_file)
        return {"error": "Room page not found"}
    
    @app.get("/scan-join", tags=["应用"])
    async def scan_join_page():
        """扫码加入房间页面"""
        scan_join_file = static_dir / "scan_join.html"
        if scan_join_file.exists():
            return FileResponse(scan_join_file)
        return {"error": "Scan join page not found"}
    
    @app.get("/chat", tags=["应用"])
    async def chat_page():
        """聊天页面"""
        chat_file = static_dir / "chat.html"
        if chat_file.exists():
            return FileResponse(chat_file)
        return {"error": "Chat page not found"}
    
    @app.get("/test_user_info", tags=["测试"])
    async def test_user_info_page():
        """测试用户信息 API 页面"""
        test_file = static_dir / "test_user_info.html"
        if test_file.exists():
            return FileResponse(test_file)
        return {"error": "Test page not found"}
    
    @app.get("/test_user_info.html", tags=["测试"])
    async def test_user_info_page_html():
        """测试用户信息 API 页面（带 .html 后缀）"""
        test_file = static_dir / "test_user_info.html"
        if test_file.exists():
            return FileResponse(test_file)
        return {"error": "Test page not found"}
    
    # APK 下载端点
    @app.get("/download/apk", tags=["下载"])
    async def download_apk():
        """下载 Android APK 文件（arm64-v8a 架构）"""
        apk_file = static_dir / "mop-app-arm64-v8a-release.apk"
        if apk_file.exists():
            return FileResponse(
                path=str(apk_file),
                media_type="application/vnd.android.package-archive",
                filename="mop-app-arm64-v8a-release.apk",
                headers={
                    "Content-Disposition": "attachment; filename=mop-app-arm64-v8a-release.apk"
                }
            )
        return {"error": "APK file not found"}
    
    @app.get("/download/apk/info", tags=["下载"])
    async def apk_info():
        """获取 APK 文件信息"""
        apk_file = static_dir / "mop-app-arm64-v8a-release.apk"
        if apk_file.exists():
            import os
            stat = os.stat(apk_file)
            return {
                "filename": "mop-app-arm64-v8a-release.apk",
                "size": stat.st_size,
                "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "architecture": "arm64-v8a",
                "build_type": "release",
                "download_url": "/download/apk",
                "static_url": "/static/mop-app-arm64-v8a-release.apk",
                "modified_time": stat.st_mtime
            }
        return {"error": "APK file not found"}


if __name__ == "__main__":
    import uvicorn
    
    setup_logging()
    
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower()
    )
