#!/usr/bin/env python3
"""
最小化 Favicon 测试服务器
只测试 favicon 功能，不依赖数据库
"""

from fastapi import FastAPI
from fastapi.responses import FileResponse
from pathlib import Path
import random

app = FastAPI(title="Favicon Test Server")

# Favicon 文件目录
BASE_DIR = Path(__file__).parent
FAVICON_DIR = BASE_DIR / "static" / "favicons"
ICON_DIR = BASE_DIR / "static" / "icons"


def get_favicon_files():
    """获取所有 favicon 文件"""
    favicons = []
    if FAVICON_DIR.exists():
        for ext in ['.ico', '.png', '.svg', '.jpg', '.jpeg']:
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*{ext}")))
    return favicons


def get_icon_files():
    """获取所有图标文件"""
    icons = []
    if ICON_DIR.exists():
        for ext in ['.png', '.ico', '.svg']:
            icons.extend(list(ICON_DIR.glob(f"*ico*{ext}")))
    return icons


@app.get("/favicon.ico")
async def get_random_favicon():
    """随机返回一个 favicon"""
    favicons = get_favicon_files()
    
    if favicons:
        selected = random.choice(favicons)
        return FileResponse(
            selected,
            media_type="image/x-icon" if selected.suffix == '.ico' else f"image/{selected.suffix.lstrip('.')}"
        )
    else:
        icons = get_icon_files()
        if icons:
            selected = min(icons, key=lambda f: f.stat().st_size)
            return FileResponse(selected, media_type="image/png")
        else:
            from fastapi import HTTPException
            raise HTTPException(status_code=404, detail="Favicon not found")


@app.get("/health")
async def health():
    """健康检查"""
    return {"status": "healthy", "service": "favicon-test"}


if __name__ == "__main__":
    import uvicorn
    print("=" * 60)
    print("启动 Favicon 测试服务器")
    print("=" * 60)
    print(f"Favicon 目录: {FAVICON_DIR} (存在: {FAVICON_DIR.exists()})")
    print(f"Icon 目录: {ICON_DIR} (存在: {ICON_DIR.exists()})")
    print(f"找到 {len(get_favicon_files())} 个 favicon 文件")
    print(f"找到 {len(get_icon_files())} 个图标文件")
    print("=" * 60)
    print("\n访问地址:")
    print("  - Favicon: http://127.0.0.1:8000/favicon.ico")
    print("  - Health: http://127.0.0.1:8000/health")
    print("\n按 Ctrl+C 停止服务器")
    print("=" * 60)
    print()
    
    uvicorn.run(app, host="127.0.0.1", port=8000)
