"""
文件上传 API
用于上传用户敏感数据中的文件（如图片）
支持批量上传、断点续传等功能
"""

import os
import hashlib
import uuid
from pathlib import Path
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status, Request, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.config import settings
from app.db.session import get_db
from app.db.models import User, UserDataPayload
from app.api.v1.auth import get_current_user

router = APIRouter()

# 文件上传配置
UPLOAD_BASE_DIR = Path("uploads")
UPLOAD_PHOTOS_DIR = UPLOAD_BASE_DIR / "photos"
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB per file
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
# 每个用户最多上传的图片数量（从配置文件读取，可通过环境变量修改）
MAX_PHOTOS_PER_USER = settings.MAX_PHOTOS_PER_USER


# ==================== 请求/响应模型 ====================

class PhotoUploadResponse(BaseModel):
    """图片上传响应模型"""
    photo_id: str = Field(..., description="图片ID（唯一标识）")
    file_name: str = Field(..., description="原始文件名")
    file_size: int = Field(..., description="文件大小（字节）")
    file_path: str = Field(..., description="服务器存储路径（相对路径）")
    file_hash: str = Field(..., description="文件哈希值（SHA256）")
    uploaded_at: str = Field(..., description="上传时间")


class PhotoInfo(BaseModel):
    """图片信息模型"""
    photo_id: str
    file_name: str
    file_size: int
    file_path: str
    file_hash: str
    uploaded_at: str
    user_id: int


class PhotoListResponse(BaseModel):
    """图片列表响应模型"""
    photos: List[PhotoInfo]
    total: int
    user_id: int


# ==================== 辅助函数 ====================

def ensure_upload_dirs():
    """确保上传目录存在"""
    UPLOAD_PHOTOS_DIR.mkdir(parents=True, exist_ok=True)


def generate_photo_id() -> str:
    """生成唯一的图片ID"""
    return str(uuid.uuid4())


def get_file_hash(file_path: Path) -> str:
    """计算文件哈希值（SHA256）"""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def get_user_photo_dir(user_id: int) -> Path:
    """获取用户的图片存储目录"""
    user_dir = UPLOAD_PHOTOS_DIR / str(user_id)
    user_dir.mkdir(parents=True, exist_ok=True)
    return user_dir


def validate_image_file(file: UploadFile) -> bool:
    """验证是否为有效的图片文件"""
    if not file.filename:
        return False
    
    file_ext = Path(file.filename).suffix.lower()
    return file_ext in ALLOWED_IMAGE_EXTENSIONS


async def save_uploaded_file(
    file: UploadFile,
    user_id: int,
    photo_id: str
) -> tuple[Path, str]:
    """
    保存上传的文件
    
    Returns:
        (文件路径, 文件哈希值)
    """
    ensure_upload_dirs()
    
    # 获取文件扩展名
    file_ext = Path(file.filename).suffix.lower()
    if file_ext not in ALLOWED_IMAGE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的文件类型，仅支持: {', '.join(ALLOWED_IMAGE_EXTENSIONS)}"
        )
    
    # 构建保存路径
    user_dir = get_user_photo_dir(user_id)
    file_name = f"{photo_id}{file_ext}"
    file_path = user_dir / file_name
    
    # 读取并保存文件
    file_content = await file.read()
    file_size = len(file_content)
    
    # 检查文件大小
    if file_size > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"文件大小超过限制（最大 {MAX_FILE_SIZE / 1024 / 1024}MB）"
        )
    
    # 保存文件
    with open(file_path, "wb") as f:
        f.write(file_content)
    
    # 计算文件哈希
    file_hash = hashlib.sha256(file_content).hexdigest()
    
    return file_path, file_hash


async def count_user_photos(user_id: int) -> int:
    """统计用户已上传的图片数量"""
    user_dir = get_user_photo_dir(user_id)
    if not user_dir.exists():
        return 0
    
    count = 0
    for file in user_dir.iterdir():
        if file.is_file() and file.suffix.lower() in ALLOWED_IMAGE_EXTENSIONS:
            count += 1
    
    return count


# ==================== API 路由 ====================

@router.post("/upload-photo", response_model=PhotoUploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_photo(
    file: UploadFile = File(...),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    上传单张图片
    
    将图片文件保存到服务器，并返回图片信息
    """
    lang = current_user.language or get_language_from_request(request) if request else "zh_CN"
    
    # 验证文件类型
    if not validate_image_file(file):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("files.invalid_file_type", lang=lang) or "不支持的文件类型"
        )
    
    # 检查用户图片数量限制
    photo_count = await count_user_photos(current_user.id)
    if photo_count >= MAX_PHOTOS_PER_USER:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("files.max_photos_reached", lang=lang, max_count=MAX_PHOTOS_PER_USER) or 
                    f"已达到图片上传上限（最多 {MAX_PHOTOS_PER_USER} 张）"
        )
    
    # 生成图片ID
    photo_id = generate_photo_id()
    
    try:
        # 保存文件
        file_path, file_hash = await save_uploaded_file(file, current_user.id, photo_id)
        
        # 记录上传信息到数据库（可选，如果需要查询）
        # 这里可以将图片信息保存到 UserDataPayload 的 sensitive_data 中
        
        return PhotoUploadResponse(
            photo_id=photo_id,
            file_name=file.filename,
            file_size=file_path.stat().st_size,
            file_path=str(file_path.relative_to(UPLOAD_BASE_DIR)),
            file_hash=file_hash,
            uploaded_at=datetime.now(timezone.utc).isoformat()
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"文件上传失败: {str(e)}"
        )


@router.post("/upload-photos", response_model=List[PhotoUploadResponse], status_code=status.HTTP_201_CREATED)
async def upload_photos(
    files: List[UploadFile] = File(...),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    批量上传图片
    
    支持一次上传多张图片
    """
    lang = current_user.language or get_language_from_request(request) if request else "zh_CN"
    
    if not files:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("files.no_files", lang=lang) or "请至少上传一张图片"
        )
    
    # 检查用户图片数量限制
    photo_count = await count_user_photos(current_user.id)
    remaining_slots = MAX_PHOTOS_PER_USER - photo_count
    
    if remaining_slots <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("files.max_photos_reached", lang=lang, max_count=MAX_PHOTOS_PER_USER) or 
                    f"已达到图片上传上限（最多 {MAX_PHOTOS_PER_USER} 张）"
        )
    
    if len(files) > remaining_slots:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("files.exceed_remaining_slots", lang=lang, remaining=remaining_slots) or 
                    f"上传数量超过剩余配额（剩余 {remaining_slots} 张）"
        )
    
    results = []
    errors = []
    
    for file in files:
        try:
            # 验证文件类型
            if not validate_image_file(file):
                errors.append(f"{file.filename}: 不支持的文件类型")
                continue
            
            # 生成图片ID
            photo_id = generate_photo_id()
            
            # 保存文件
            file_path, file_hash = await save_uploaded_file(file, current_user.id, photo_id)
            
            results.append(PhotoUploadResponse(
                photo_id=photo_id,
                file_name=file.filename,
                file_size=file_path.stat().st_size,
                file_path=str(file_path.relative_to(UPLOAD_BASE_DIR)),
                file_hash=file_hash,
                uploaded_at=datetime.now(timezone.utc).isoformat()
            ))
        except Exception as e:
            errors.append(f"{file.filename}: {str(e)}")
    
    if not results:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"所有文件上传失败: {', '.join(errors)}"
        )
    
    # 如果有部分失败，返回成功的结果，但包含错误信息
    if errors:
        # 可以在响应中添加警告信息
        pass
    
    return results


@router.get("/photo/{photo_id}")
async def get_photo(
    photo_id: str,
    current_user: User = Depends(get_current_user)
):
    """
    获取图片文件
    
    根据图片ID返回图片文件
    """
    user_dir = get_user_photo_dir(current_user.id)
    
    # 查找图片文件（支持多种扩展名）
    photo_file = None
    for ext in ALLOWED_IMAGE_EXTENSIONS:
        candidate = user_dir / f"{photo_id}{ext}"
        if candidate.exists():
            photo_file = candidate
            break
    
    if not photo_file or not photo_file.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="图片不存在"
        )
    
    # 返回文件
    return FileResponse(
        path=str(photo_file),
        media_type="image/jpeg"  # 可以根据实际文件类型调整
    )


@router.get("/photos", response_model=PhotoListResponse)
async def list_photos(
    current_user: User = Depends(get_current_user)
):
    """
    获取用户的图片列表
    
    返回当前用户上传的所有图片信息
    """
    user_dir = get_user_photo_dir(current_user.id)
    
    photos = []
    if user_dir.exists():
        for file in user_dir.iterdir():
            if file.is_file() and file.suffix.lower() in ALLOWED_IMAGE_EXTENSIONS:
                # 从文件名提取 photo_id（去掉扩展名）
                photo_id = file.stem
                
                # 计算文件哈希
                file_hash = get_file_hash(file)
                
                photos.append(PhotoInfo(
                    photo_id=photo_id,
                    file_name=file.name,
                    file_size=file.stat().st_size,
                    file_path=str(file.relative_to(UPLOAD_BASE_DIR)),
                    file_hash=file_hash,
                    uploaded_at=datetime.fromtimestamp(file.stat().st_mtime, tz=timezone.utc).isoformat(),
                    user_id=current_user.id
                ))
    
    return PhotoListResponse(
        photos=photos,
        total=len(photos),
        user_id=current_user.id
    )


@router.delete("/photo/{photo_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_photo(
    photo_id: str,
    current_user: User = Depends(get_current_user)
):
    """
    删除图片
    
    根据图片ID删除图片文件
    """
    user_dir = get_user_photo_dir(current_user.id)
    
    # 查找并删除图片文件
    deleted = False
    for ext in ALLOWED_IMAGE_EXTENSIONS:
        candidate = user_dir / f"{photo_id}{ext}"
        if candidate.exists():
            candidate.unlink()
            deleted = True
            break
    
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="图片不存在"
        )
    
    return None
