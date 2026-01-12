"""
Favicon 随机选择 API
每次请求随机返回一个 favicon
"""

from fastapi import APIRouter
from fastapi.responses import FileResponse
import random
import os
from pathlib import Path

router = APIRouter()

# Favicon 文件目录
# 从 app/api/v1/favicon.py 到项目根目录: ../../../
BASE_DIR = Path(__file__).parent.parent.parent.parent
FAVICON_DIR = BASE_DIR / "static" / "favicons"
ICON_DIR = BASE_DIR / "static" / "icons"


def get_favicon_files():
    """获取所有 favicon 文件"""
    favicons = []
    if FAVICON_DIR.exists():
        # 优先查找包含 fav 的文件
        for ext in ['.ico', '.png', '.svg', '.jpg', '.jpeg']:
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*{ext}")))
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*.{ext.lstrip('.')}")))
        
        # 如果没找到包含 fav 的文件，则查找目录中的所有图片文件
        if not favicons:
            for ext in ['.ico', '.png', '.svg', '.jpg', '.jpeg']:
                favicons.extend(list(FAVICON_DIR.glob(f"*{ext}")))
    return favicons


def get_icon_files():
    """获取所有图标文件（用于应用图标）"""
    icons = []
    if ICON_DIR.exists():
        # 查找所有包含 ico 的文件
        for ext in ['.png', '.ico', '.svg']:
            icons.extend(list(ICON_DIR.glob(f"*ico*{ext}")))
    return icons


@router.get("/favicon.ico")
async def get_random_favicon():
    """
    随机返回一个 favicon
    
    如果 favicons 目录中有文件，随机选择一个
    否则返回默认图标
    """
    favicons = get_favicon_files()
    
    if favicons:
        # 随机选择一个 favicon
        selected = random.choice(favicons)
        return FileResponse(
            selected,
            media_type="image/x-icon" if selected.suffix == '.ico' else f"image/{selected.suffix.lstrip('.')}"
        )
    else:
        # 如果没有 favicon，从图标中选择一个小的作为默认
        icons = get_icon_files()
        if icons:
            # 选择文件大小最小的（通常是 favicon 尺寸）
            selected = min(icons, key=lambda f: f.stat().st_size)
            return FileResponse(
                selected,
                media_type="image/png"
            )
        else:
            # 返回 404 或默认图标
            from fastapi import HTTPException
            raise HTTPException(status_code=404, detail="Favicon not found")


@router.get("/favicon/{filename}")
async def get_specific_favicon(filename: str):
    """获取指定的 favicon 文件"""
    favicon_path = FAVICON_DIR / filename
    if favicon_path.exists() and favicon_path.is_file():
        return FileResponse(favicon_path)
    else:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Favicon not found")
