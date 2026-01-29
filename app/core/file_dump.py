"""
文件转储模块
实现大文件的服务器端转储功能，避免 Socket.io 消息过大
"""

import base64
import uuid
from pathlib import Path
from typing import Optional, Dict
from datetime import datetime, timezone
from loguru import logger

# Socket.io 消息大小阈值（超过此值将触发文件转储）
MESSAGE_SIZE_THRESHOLD = 4 * 1024 * 1024  # 4MB


async def dump_large_file_to_storage(
    base64_data_uri: str,
    sender_id: int,
    message_type: str,
    file_name: Optional[str] = None
) -> Optional[Dict]:
    """
    将大文件的 base64 数据 URI 转储到服务器存储
    
    Args:
        base64_data_uri: base64 数据 URI (格式: data:image/png;base64,xxxxx)
        sender_id: 发送者用户ID
        message_type: 消息类型 (image/audio/video/file)
    
    Returns:
        包含 file_id, file_url, file_name, file_size 的字典，失败返回 None
    """
    try:
        # 解析 base64 数据 URI
        if not base64_data_uri.startswith('data:'):
            logger.warning(f"不是有效的 base64 数据 URI: {base64_data_uri[:100]}...")
            return None
        
        # 提取 MIME 类型和 base64 数据
        comma_index = base64_data_uri.index(',')
        header = base64_data_uri[:comma_index]
        base64_string = base64_data_uri[comma_index + 1:]
        
        # 解析 MIME 类型与扩展名：一律按原始文件名扩展名，无预设允许列表，减少维护与资源消耗
        mime_type = 'application/octet-stream'
        file_ext = '.bin'
        if ';base64' in header:
            mime_part = header.split(';')[0]
            mime_type = mime_part.replace('data:', '')
        if file_name and '.' in file_name:
            file_ext = Path(file_name).suffix.lower()
        
        # 解码 base64 数据
        try:
            file_bytes = base64.b64decode(base64_string)
            file_size = len(file_bytes)
        except Exception as e:
            logger.error(f"Base64 解码失败: {e}")
            return None
        
        # 确定文件类型
        # 支持 'voice' 作为 'audio' 的别名
        normalized_type = 'audio' if message_type == 'voice' else message_type
        
        if normalized_type not in ['image', 'audio', 'video', 'file']:
            if mime_type.startswith('image/'):
                file_type = 'image'
            elif mime_type.startswith('audio/'):
                file_type = 'audio'
            elif mime_type.startswith('video/'):
                file_type = 'video'
            else:
                # 对于未知类型，统一使用 'file' 而不是 'document'，确保前端能正确显示
                file_type = 'file'
        else:
            file_type = normalized_type
        
        # 生成唯一文件名
        stored_filename = f"{uuid.uuid4()}{file_ext}"
        
        # 确定存储目录（使用绝对路径）
        # 获取项目根目录（从 app/core/file_dump.py 向上三级到项目根 /opt/mop）
        PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
        upload_base_dir = (PROJECT_ROOT / "uploads").resolve()
        if file_type == 'image':
            file_dir = upload_base_dir / "images" / str(sender_id)
        elif file_type == 'audio':
            file_dir = upload_base_dir / "audio" / str(sender_id)
        elif file_type == 'video':
            file_dir = upload_base_dir / "videos" / str(sender_id)
        else:
            file_dir = upload_base_dir / "files" / str(sender_id)
        
        file_dir.mkdir(parents=True, exist_ok=True)
        file_path = file_dir / stored_filename
        
        # 保存文件
        with open(file_path, 'wb') as f:
            f.write(file_bytes)
        
        # 生成文件访问 URL（使用查询参数避免路径参数点号问题）
        from urllib.parse import quote
        file_url = f"/api/v1/files/download?file_type={quote(file_type)}&stored_filename={quote(stored_filename)}"
        
        # 保存文件记录到数据库
        from app.db.session import get_db
        from app.db.models import File as FileModel
        from sqlalchemy import select
        
        file_id = None
        async for session in get_db():
            try:
                db_file = FileModel(
                    uploader_id=sender_id,
                    filename=file_name or stored_filename,  # 原始文件名
                    stored_filename=stored_filename,
                    file_path=str(file_path.relative_to(upload_base_dir)),
                    file_url=file_url,
                    file_type=file_type,
                    mime_type=mime_type,
                    file_size=file_size,
                    created_at=datetime.now(timezone.utc).replace(tzinfo=None)
                )
                session.add(db_file)
                await session.commit()
                await session.refresh(db_file)
                file_id = db_file.id
                logger.info(f"文件已转储到数据库: ID={file_id}, path={file_path}")
                break
            except Exception as db_error:
                await session.rollback()
                logger.error(f"保存文件记录到数据库失败: {db_error}", exc_info=True)
                # 即使数据库保存失败，也返回文件信息（文件已保存到磁盘）
        
        return {
            'file_id': file_id,
            'file_url': file_url,
            'file_name': file_name or stored_filename,  # 使用原始文件名（如果提供）
            'file_size': file_size,
            'mime_type': mime_type
        }
        
    except Exception as e:
        logger.error(f"转储文件失败: {e}", exc_info=True)
        return None
