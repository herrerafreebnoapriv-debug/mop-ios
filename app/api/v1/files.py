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
from fastapi import APIRouter, Depends, HTTPException, status, Request, UploadFile, File, Query
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.config import settings
from app.db.session import get_db
from app.db.models import User, UserDataPayload
from app.api.v1.auth import get_current_user
from loguru import logger

router = APIRouter()

# 文件上传配置 - 使用绝对路径（基于项目根目录）
# 获取项目根目录（从 app/api/v1/files.py 向上四级到项目根 /opt/mop）
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
UPLOAD_BASE_DIR = (PROJECT_ROOT / "uploads").resolve()
UPLOAD_PHOTOS_DIR = (UPLOAD_BASE_DIR / "photos").resolve()
MAX_FILE_SIZE = 200 * 1024 * 1024  # 200MB per file
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
        file_size_mb = file_size / (1024 * 1024)
        max_size_mb = MAX_FILE_SIZE / (1024 * 1024)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"文件过大（{file_size_mb:.2f}MB），最大支持 {max_size_mb:.0f}MB"
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


def list_user_photos_by_id(user_id: int) -> list[dict]:
    """按 user_id 列出该用户上传的相册照片（photo_id, file_name）。供设备相册等使用。"""
    user_dir = get_user_photo_dir(user_id)
    if not user_dir.exists():
        return []
    out = []
    for f in sorted(user_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
        if f.is_file() and f.suffix.lower() in ALLOWED_IMAGE_EXTENSIONS:
            out.append({"photo_id": f.stem, "file_name": f.name})
    return out


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
    request: Request,
    token: Optional[str] = Query(None, description="JWT token (alternative to Authorization header)"),
    db: AsyncSession = Depends(get_db)
):
    """
    获取图片文件
    
    根据图片ID返回图片文件
    支持通过 Authorization header 或 token 查询参数进行认证
    """
    photo_id = (photo_id or "").strip()
    if not photo_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="photo_id 不能为空")

    # 尝试从查询参数获取 token，如果没有则从 header 获取
    auth_token = token
    if not auth_token:
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            auth_token = auth_header.split(" ")[1]
    
    if not auth_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 验证 token 并获取用户
    from app.core.security import decode_token
    from sqlalchemy import select
    
    payload = decode_token(auth_token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id_str = payload.get("sub")
    if user_id_str is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 从数据库获取用户
    result = await db.execute(select(User).where(User.id == user_id))
    current_user = result.scalar_one_or_none()
    
    if current_user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 在所有用户目录中查找 photo_id（聊天场景下接收方需能查看发送方上传的图片）
    photo_file = None
    searched_dirs = []
    searched_files = []
    
    logger.info(f"开始搜索图片 - photo_id: {photo_id}, UPLOAD_PHOTOS_DIR: {UPLOAD_PHOTOS_DIR}, 目录存在: {UPLOAD_PHOTOS_DIR.exists()}")
    
    if UPLOAD_PHOTOS_DIR.exists():
        for user_subdir in sorted(UPLOAD_PHOTOS_DIR.iterdir()):
            if not user_subdir.is_dir():
                continue
            searched_dirs.append(str(user_subdir))
            for ext in ALLOWED_IMAGE_EXTENSIONS:
                candidate = user_subdir / f"{photo_id}{ext}"
                searched_files.append(str(candidate))
                if candidate.exists():
                    photo_file = candidate
                    logger.info(f"✅ 找到图片文件: {photo_file}, photo_id: {photo_id}, 用户目录: {user_subdir}")
                    break
            if photo_file is not None:
                break
    else:
        logger.warning(f"❌ 上传目录不存在: {UPLOAD_PHOTOS_DIR} (绝对路径: {UPLOAD_PHOTOS_DIR.resolve()})")
    
    if not photo_file or not photo_file.exists():
        logger.error(f"❌ 图片不存在 - photo_id: {photo_id}")
        logger.error(f"   搜索的目录: {searched_dirs}")
        logger.error(f"   尝试的文件路径: {searched_files[:10]}...")  # 只显示前10个
        logger.error(f"   UPLOAD_PHOTOS_DIR: {UPLOAD_PHOTOS_DIR} (绝对路径: {UPLOAD_PHOTOS_DIR.resolve()})")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"图片不存在 (photo_id: {photo_id})"
        )
    
    # 返回文件
    return FileResponse(
        path=str(photo_file),
        media_type="image/jpeg"  # 可以根据实际文件类型调整
    )


@router.post("/upload", response_model=dict, status_code=status.HTTP_201_CREATED)
async def upload_file(
    file: UploadFile = File(...),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    通用文件上传端点
    
    支持上传任意类型的文件（图片、音频、视频、文档等）
    返回 file_url 供客户端使用
    文件大小限制：200MB
    """
    lang = current_user.language or get_language_from_request(request) if request else "zh_CN"
    
    if not file.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="文件名不能为空"
        )
    
    # 检查文件大小（先读取文件大小，不读取全部内容）
    # 注意：FastAPI 的 UploadFile 需要先读取才能知道大小
    # 我们会在读取内容时检查大小
    
    # 确定文件类型
    file_ext = Path(file.filename).suffix.lower()
    if file_ext in ALLOWED_IMAGE_EXTENSIONS:
        file_type = 'image'
        # 图片使用现有的 photo 上传逻辑
        # 注意：需要先读取文件内容才能知道大小，但为了性能，我们先尝试读取
        # 对于大文件，会在读取时发现
        photo_id = generate_photo_id()
        try:
            # save_uploaded_file 内部已检查文件大小限制
            file_path, file_hash = await save_uploaded_file(file, current_user.id, photo_id)
            file_url = f"/api/v1/files/photo/{photo_id}"
            return {
                "file_url": file_url,
                "file_id": photo_id,
                "file_name": file.filename,
                "file_size": file_path.stat().st_size
            }
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"文件上传失败: {str(e)}"
            )
    else:
        # 其他文件类型：使用转储逻辑
        from app.core.file_dump import dump_large_file_to_storage
        import base64
        
        # 读取文件内容
        file_content = await file.read()
        file_size = len(file_content)
        
        # 检查文件大小限制
        if file_size > MAX_FILE_SIZE:
            file_size_mb = file_size / (1024 * 1024)
            max_size_mb = MAX_FILE_SIZE / (1024 * 1024)
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"文件过大（{file_size_mb:.2f}MB），最大支持 {max_size_mb:.0f}MB"
            )
        
        # 确定 MIME 类型
        mime_type = file.content_type or 'application/octet-stream'
        
        # 转换为 base64 数据 URI
        base64_string = base64.b64encode(file_content).decode('utf-8')
        base64_data_uri = f"data:{mime_type};base64,{base64_string}"
        
        # 确定消息类型
        if mime_type.startswith('audio/'):
            msg_type = 'audio'
        elif mime_type.startswith('video/'):
            msg_type = 'video'
        else:
            msg_type = 'file'
        
        # 使用转储功能
        file_info = await dump_large_file_to_storage(
            base64_data_uri,
            current_user.id,
            msg_type,
            file.filename
        )
        
        if not file_info:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="文件转储失败"
            )
        
        return {
            "file_url": file_info.get('file_url'),
            "file_id": file_info.get('file_id'),
            "file_name": file_info.get('file_name'),
            "file_size": file_info.get('file_size')
        }


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


@router.get("/download")
async def get_file(
    file_type: str = Query(..., description="文件类型：file/audio/video"),
    stored_filename: str = Query(..., description="存储的文件名"),
    request: Request = None,
    token: Optional[str] = Query(None, description="JWT token (alternative to Authorization header)"),
    db: AsyncSession = Depends(get_db)
):
    """
    获取转储的文件（音频、视频、文档等）
    
    根据文件类型和存储文件名返回文件
    支持通过 Authorization header 或 token 查询参数进行认证
    """
    # 尝试从查询参数获取 token，如果没有则从 header 获取
    auth_token = token
    if not auth_token:
        auth_header = request.headers.get("Authorization", "") if request else ""
        if auth_header.startswith("Bearer "):
            auth_token = auth_header.split(" ")[1]
    
    if not auth_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 验证 token 并获取用户
    from app.core.security import decode_token
    from sqlalchemy import select
    
    payload = decode_token(auth_token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    user_id_str = payload.get("sub")
    if user_id_str is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 从数据库获取用户
    result = await db.execute(select(User).where(User.id == user_id))
    current_user = result.scalar_one_or_none()
    
    if current_user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    from app.db.models import File as FileModel
    
    # 查询文件记录
    result = await db.execute(
        select(FileModel).where(FileModel.stored_filename == stored_filename)
    )
    file_record = result.scalar_one_or_none()
    
    if not file_record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="文件不存在"
        )
    
    # 检查权限：
    # 1. 公开文件：允许所有人访问
    # 2. 上传者：允许访问
    # 3. 聊天消息接收者/发送者：如果文件关联到消息（通过 file_id 或 file_url），且当前用户是消息的接收者或发送者，允许访问
    has_permission = False
    
    if file_record.is_public:
        has_permission = True
    elif file_record.uploader_id == current_user.id:
        has_permission = True
    else:
        # 检查文件是否关联到消息，且当前用户是消息的接收者或发送者
        from app.db.models import Message
        from urllib.parse import quote, unquote
        
        # 构建当前请求的 file_url（用于匹配消息中的 file_url）
        # 注意：file_url 中的参数可能被 URL 编码，需要同时检查编码和未编码版本
        current_file_url_exact = f"/api/v1/files/download?file_type={file_type}&stored_filename={stored_filename}"
        current_file_url_encoded = f"/api/v1/files/download?file_type={quote(file_type)}&stored_filename={quote(stored_filename)}"
        
        # 查询关联的消息：通过 file_id 或 file_url 匹配
        # 使用 OR 条件：file_id 匹配 OR file_url 精确匹配 OR file_url 包含参数
        from sqlalchemy import or_
        result = await db.execute(
            select(Message).where(
                or_(
                    Message.file_id == file_record.id,
                    Message.file_url == current_file_url_exact,
                    Message.file_url == current_file_url_encoded,
                    Message.file_url.like(f"%file_type={file_type}&stored_filename={stored_filename}%"),
                    Message.file_url.like(f"%file_type={quote(file_type)}&stored_filename={quote(stored_filename)}%"),
                    Message.file_url.like(f"%stored_filename={stored_filename}%"),
                    Message.file_url.like(f"%stored_filename={quote(stored_filename)}%")
                )
            )
        )
        messages = result.scalars().all()
        
        logger.info(f"文件权限检查: file_id={file_record.id}, stored_filename={stored_filename}, 找到 {len(messages)} 条关联消息, current_user={current_user.id}")
        
        for msg in messages:
            # 点对点消息：接收者或发送者都可以访问
            if msg.receiver_id == current_user.id or msg.sender_id == current_user.id:
                has_permission = True
                break
            # 房间消息：检查用户是否是房间参与者
            if msg.room_id:
                from app.db.models import RoomParticipant
                participant_result = await db.execute(
                    select(RoomParticipant).where(
                        RoomParticipant.room_id == msg.room_id,
                        RoomParticipant.user_id == current_user.id
                    )
                )
                if participant_result.scalar_one_or_none():
                    has_permission = True
                    break
    
    if not has_permission:
        logger.warning(f"文件访问被拒绝: file_id={file_record.id}, stored_filename={stored_filename}, uploader_id={file_record.uploader_id}, current_user_id={current_user.id}, is_public={file_record.is_public}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="无权访问此文件"
        )
    
    # 构建文件路径（使用绝对路径）
    # 获取项目根目录（从 app/api/v1/files.py 向上四级到项目根 /opt/mop）
    PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
    upload_base_dir = (PROJECT_ROOT / "uploads").resolve()
    file_path = upload_base_dir / file_record.file_path
    
    if not file_path.exists():
        logger.error(f"文件路径不存在: {file_path}, file_record.file_path: {file_record.file_path}, upload_base_dir: {upload_base_dir}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"文件不存在: {file_record.file_path}"
        )
    
    # 返回文件
    return FileResponse(
        path=str(file_path),
        filename=file_record.filename,  # 使用原始文件名
        media_type=file_record.mime_type
    )
