"""
文件上传API模块
支持图片、语音条、视频等文件上传
"""

import os
import uuid
import hashlib
from pathlib import Path
from typing import Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Request, UploadFile, File, Form
from fastapi.responses import FileResponse as FastAPIFileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.permissions import check_user_not_disabled
from app.core.operation_log import log_operation
from app.db.session import get_db
from app.db.models import User, File as FileModel, Message
from app.api.v1.auth import get_current_user
from app.core.socketio import sio, connected_users
from loguru import logger

router = APIRouter()

# 文件上传配置
UPLOAD_DIR = Path("/opt/mop/uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# 允许的文件类型
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
ALLOWED_AUDIO_TYPES = {"audio/mpeg", "audio/mp3", "audio/wav", "audio/ogg", "audio/aac", "audio/m4a"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/webm", "video/ogg"}
ALLOWED_DOCUMENT_TYPES = {"application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"}

# 文件大小限制（字节）
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB
MAX_AUDIO_SIZE = 20 * 1024 * 1024  # 20MB


class FileUploadResponse(BaseModel):
    """文件响应模型"""
    id: int
    filename: str
    file_url: str
    file_type: str
    file_size: int
    duration: Optional[int] = None
    width: Optional[int] = None
    height: Optional[int] = None
    created_at: datetime


def get_file_type(mime_type: str) -> str:
    """根据 MIME 类型判断文件类型"""
    if mime_type in ALLOWED_IMAGE_TYPES:
        return "image"
    elif mime_type in ALLOWED_AUDIO_TYPES:
        return "audio"
    elif mime_type in ALLOWED_VIDEO_TYPES:
        return "video"
    elif mime_type in ALLOWED_DOCUMENT_TYPES:
        return "document"
    else:
        return "other"


def generate_stored_filename(original_filename: str, user_id: int) -> str:
    """生成存储文件名"""
    ext = Path(original_filename).suffix
    unique_id = uuid.uuid4().hex[:8]
    timestamp = int(datetime.utcnow().timestamp())
    return f"{user_id}_{timestamp}_{unique_id}{ext}"


@router.post("/upload", response_model=FileUploadResponse, status_code=status.HTTP_201_CREATED)
async def upload_file(
    file: UploadFile = File(...),
    is_public: bool = Form(False),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    上传文件（图片、语音条、视频等）
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 验证文件类型
    file_type = get_file_type(file.content_type)
    if file_type == "other":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("files.invalid_type", lang)
        )
    
    # 验证文件大小
    content = await file.read()
    file_size = len(content)
    
    max_size = MAX_FILE_SIZE
    if file_type == "image":
        max_size = MAX_IMAGE_SIZE
    elif file_type == "audio":
        max_size = MAX_AUDIO_SIZE
    
    if file_size > max_size:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("files.too_large", lang).format(max_size=max_size // (1024 * 1024))
        )
    
    # 生成存储文件名和路径
    stored_filename = generate_stored_filename(file.filename, current_user.id)
    file_path = UPLOAD_DIR / stored_filename
    
    # 保存文件
    try:
        with open(file_path, "wb") as f:
            f.write(content)
    except Exception as e:
        logger.error(f"保存文件失败: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=i18n.get("files.upload_failed", lang)
        )
    
    # 生成文件URL
    base_url = str(request.base_url).rstrip("/")
    file_url = f"{base_url}/api/v1/files/{stored_filename}"
    
    # 获取文件元数据（如果需要）
    duration = None
    width = None
    height = None
    
    # TODO: 使用第三方库获取图片/视频/音频的元数据
    # 例如：Pillow 用于图片，mutagen 用于音频等
    
    # 保存文件记录到数据库
    db_file = FileModel(
        uploader_id=current_user.id,
        filename=file.filename,
        stored_filename=stored_filename,
        file_path=str(file_path),
        file_url=file_url,
        file_type=file_type,
        mime_type=file.content_type,
        file_size=file_size,
        duration=duration,
        width=width,
        height=height,
        is_public=is_public
    )
    db.add(db_file)
    await db.commit()
    await db.refresh(db_file)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="create",
        resource_type="files",
        resource_id=db_file.id,
        operation_detail={"filename": file.filename, "file_type": file_type},
        request=request
    )
    await db.commit()
    
    return FileUploadResponse(
        id=db_file.id,
        filename=db_file.filename,
        file_url=db_file.file_url,
        file_type=db_file.file_type,
        file_size=db_file.file_size,
        duration=db_file.duration,
        width=db_file.width,
        height=db_file.height,
        created_at=db_file.created_at
    )


@router.get("/{stored_filename}")
async def get_file(
    stored_filename: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取文件（下载或查看）
    """
    # 查询文件记录
    result = await db.execute(
        select(FileModel).where(FileModel.stored_filename == stored_filename)
    )
    db_file = result.scalar_one_or_none()
    
    if not db_file:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found"
        )
    
    # 权限检查：公开文件或上传者可以访问
    if not db_file.is_public and db_file.uploader_id != current_user.id:
        # 检查是否是好友发送的文件
        from app.db.models import Friendship
        friendship_result = await db.execute(
            select(Friendship).where(
                or_(
                    and_(Friendship.user_id == current_user.id, Friendship.friend_id == db_file.uploader_id),
                    and_(Friendship.user_id == db_file.uploader_id, Friendship.friend_id == current_user.id)
                ),
                Friendship.status == "accepted"
            )
        )
        friendship = friendship_result.scalar_one_or_none()
        
        if not friendship:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied"
            )
    
    # 返回文件
    file_path = Path(db_file.file_path)
    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found on disk"
        )
    
    return FastAPIFileResponse(
        path=file_path,
        filename=db_file.filename,
        media_type=db_file.mime_type
    )
