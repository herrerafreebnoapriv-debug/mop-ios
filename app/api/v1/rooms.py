"""
Jitsi 房间加入 API
视频通话和共享功能交由Jitsi自行处理，后端仅负责签发JWT token用于授权
根据 Spec.txt：必须通过后端签发的 JWT 进行房门授权，实现强管控
"""

from datetime import datetime, timezone
from typing import Optional
import hashlib
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.security import create_jitsi_token
from app.core.config import settings
from loguru import logger
from app.core.permissions import check_user_not_disabled
from app.db.session import get_db
from app.db.models import User, QRCodeScan
from app.api.v1.auth import get_current_user

router = APIRouter()


# ==================== 请求/响应模型 ====================

class RoomJoin(BaseModel):
    """加入房间请求模型"""
    display_name: Optional[str] = Field(None, max_length=100, description="显示名称")
    is_moderator: bool = Field(False, description="是否为主持人")
    encrypted_data: Optional[str] = Field(None, description="二维码加密数据（用于扫码加入）")
    plain_qrcode_data: Optional[str] = Field(None, description="未加密二维码数据（用于游客扫码加入）")


class RoomJoinResponse(BaseModel):
    """加入房间响应模型"""
    room_id: str
    jitsi_token: str
    jitsi_server_url: str
    room_url: str


# ==================== API 路由 ====================

@router.post("/join-guest", response_model=RoomJoinResponse)
async def join_room_as_guest(
    join_data: RoomJoin,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    游客加入房间（通过未加密二维码，公开端点，无需登录）
    
    用于未加密二维码的游客扫码加入，无需先登录
    游客不能成为主持人
    """
    lang = get_language_from_request(request)
    
    # 必须提供未加密二维码数据
    if not join_data.plain_qrcode_data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.invalid", lang=lang) or "缺少二维码数据"
        )
    
    # 解析未加密二维码数据（支持URL格式或JSON格式）
    import json
    from urllib.parse import urlparse
    
    room_id = None
    
    # 先尝试作为URL解析（新格式：明文链接带token）
    if join_data.plain_qrcode_data.startswith("http://") or join_data.plain_qrcode_data.startswith("https://"):
        try:
            parsed_url = urlparse(join_data.plain_qrcode_data)
            # 从URL路径中提取房间ID，格式：/room/{room_id}
            path_parts = parsed_url.path.strip('/').split('/')
            if len(path_parts) >= 2 and path_parts[0] == 'room':
                room_id = path_parts[1]
        except Exception as e:
            logger.warning(f"解析URL格式二维码失败: {e}")
    
    # 如果不是URL格式或解析失败，尝试JSON格式（向后兼容）
    if not room_id:
        try:
            qr_data = json.loads(join_data.plain_qrcode_data)
            room_id = qr_data.get("room_id")
        except Exception as e:
            logger.warning(f"解析JSON格式二维码失败: {e}")
    
    if not room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.invalid", lang=lang) or "二维码数据格式错误：无法解析房间ID"
        )
    
    # 检查二维码扫描次数（使用 plain_qrcode_data 的哈希）
    from app.api.v1.qrcode import calculate_encrypted_data_hash
    plain_data_hash = calculate_encrypted_data_hash(join_data.plain_qrcode_data)
    qr_scan_result = await db.execute(
        select(QRCodeScan).where(
            QRCodeScan.encrypted_data_hash == plain_data_hash,
            QRCodeScan.qrcode_type == 'plain'
        )
    )
    qr_scan = qr_scan_result.scalar_one_or_none()
    
    if qr_scan and qr_scan.is_expired:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.expired", lang=lang) or "二维码已失效"
        )
    
    # 更新二维码扫描次数（如果有限制）
    if qr_scan and qr_scan.max_scans > 0:
        qr_scan.scan_count += 1
        if qr_scan.scan_count >= qr_scan.max_scans:
            qr_scan.is_expired = True
        await db.commit()
    
    # 生成临时用户标识和JWT Token
    temp_user_id = int(hashlib.sha256(plain_data_hash.encode()).hexdigest()[:8], 16) % 1000000
    user_name = join_data.display_name or f"游客{temp_user_id % 10000}"
    
    # 生成 Jitsi JWT Token（游客不能成为主持人）
    jitsi_token = create_jitsi_token(
        room_id=room_id,
        user_id=temp_user_id,
        user_name=user_name,
        is_moderator=False,  # 游客不能成为主持人
        expires_in_minutes=60
    )
    
    # 验证 JWT token 中的 moderator 字段
    import jwt
    try:
        decoded_token = jwt.decode(jitsi_token, options={"verify_signature": False})
        moderator_status = decoded_token.get("context", {}).get("user", {}).get("moderator", True)
        if moderator_status:
            logger.warning(f"警告：游客 JWT token 中的 moderator 字段为 True，这不应该发生！房间ID: {room_id}")
        else:
            logger.info(f"✓ 确认：游客 JWT token 中 moderator=False，房间ID: {room_id}, 用户: {user_name}")
    except Exception as e:
        logger.error(f"解析 JWT token 失败: {e}")
    
    # 构建房间 URL
    from urllib.parse import urlencode
    base_url = str(request.base_url).rstrip('/')
    room_url = f"{base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
    
    return RoomJoinResponse(
        room_id=room_id,
        jitsi_token=jitsi_token,
        jitsi_server_url=settings.JITSI_SERVER_URL,
        room_url=room_url
    )


@router.post("/join-by-qrcode", response_model=RoomJoinResponse)
async def join_room_by_qrcode(
    join_data: RoomJoin,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    通过二维码加入房间（公开端点，无需登录）
    
    支持两种二维码格式：
    1. 加密二维码：使用 encrypted_data（需要客户端解密）
    2. 未加密二维码：使用 plain_qrcode_data（JSON格式）
    
    用于网页版扫码直接加入房间，无需先登录
    根据 Spec.txt：支持 PC 浏览器端免插件访问
    游客不能成为主持人
    """
    lang = get_language_from_request(request)
    import json
    
    # 验证二维码并获取房间ID
    from app.api.v1.qrcode import calculate_encrypted_data_hash
    from app.core.security import rsa_decrypt
    
    data = None
    qrcode_type = 'encrypted'
    qrcode_data = None
    
    # 判断是加密还是未加密二维码
    if join_data.plain_qrcode_data:
        # 未加密二维码（支持URL格式或JSON格式）
        from urllib.parse import urlparse
        
        qrcode_type = 'plain'
        qrcode_data = join_data.plain_qrcode_data
        
        # 先尝试作为URL解析（新格式：明文链接带token）
        if join_data.plain_qrcode_data.startswith("http://") or join_data.plain_qrcode_data.startswith("https://"):
            try:
                parsed_url = urlparse(join_data.plain_qrcode_data)
                # 从URL路径中提取房间ID，格式：/room/{room_id}
                path_parts = parsed_url.path.strip('/').split('/')
                if len(path_parts) >= 2 and path_parts[0] == 'room':
                    room_id_from_url = path_parts[1]
                    # 构造数据字典以兼容后续逻辑
                    data = {"room_id": room_id_from_url}
                else:
                    raise ValueError("URL中未找到房间ID")
            except Exception as e:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=i18n.t("qrcode.invalid", lang=lang) or f"URL格式二维码解析失败: {str(e)}"
                )
        else:
            # 尝试JSON格式（向后兼容）
            try:
                data = json.loads(join_data.plain_qrcode_data)
            except Exception as e:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=i18n.t("qrcode.invalid", lang=lang) or "未加密二维码数据格式错误（既不是URL也不是JSON）"
                )
    elif join_data.encrypted_data:
        # 加密二维码
        try:
            data = rsa_decrypt(join_data.encrypted_data, expand_short_keys=True, decompress=True)
            qrcode_type = 'encrypted'
            qrcode_data = join_data.encrypted_data
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("qrcode.invalid", lang=lang) or "加密二维码解密失败"
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.invalid", lang=lang) or "缺少二维码数据"
        )
    
    room_id = data.get("room_id")
    if not room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.invalid", lang=lang) or "二维码中缺少房间ID"
        )
    
    # 检查二维码扫描次数
    encrypted_data_hash = calculate_encrypted_data_hash(qrcode_data)
    qr_scan_result = await db.execute(
        select(QRCodeScan).where(
            QRCodeScan.encrypted_data_hash == encrypted_data_hash,
            QRCodeScan.qrcode_type == qrcode_type
        )
    )
    qr_scan = qr_scan_result.scalar_one_or_none()
    
    if qr_scan and qr_scan.is_expired:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.expired", lang=lang) or "二维码已失效"
        )
    
    # 去除后台房间功能，视频通话和共享功能交由Jitsi自行处理
    # 不再检查或创建数据库中的房间记录，直接基于room_id生成JWT token
    
    # 更新二维码扫描次数（max_scans=0表示不限制）
    if qr_scan and qr_scan.max_scans > 0:
        qr_scan.scan_count += 1
        if qr_scan.scan_count >= qr_scan.max_scans:
            qr_scan.is_expired = True
        await db.commit()
    
    # 生成临时用户标识和JWT Token
    # 基于二维码数据生成临时用户标识
    temp_user_id = int(hashlib.sha256(encrypted_data_hash.encode()).hexdigest()[:8], 16) % 1000000
    user_name = join_data.display_name or f"访客{temp_user_id % 10000}"
    
    # 生成 Jitsi JWT Token（游客不能成为主持人）
    jitsi_token = create_jitsi_token(
        room_id=room_id,
        user_id=temp_user_id,
        user_name=user_name,
        is_moderator=False,  # 扫码加入的用户（包括游客）不能成为主持人
        expires_in_minutes=60
    )
    
    # 验证 JWT token 中的 moderator 字段
    import jwt
    try:
        decoded_token = jwt.decode(jitsi_token, options={"verify_signature": False})
        moderator_status = decoded_token.get("context", {}).get("user", {}).get("moderator", True)
        if moderator_status:
            logger.warning(f"警告：扫码加入用户 JWT token 中的 moderator 字段为 True，这不应该发生！房间ID: {room_id}")
        else:
            logger.info(f"✓ 确认：扫码加入用户 JWT token 中 moderator=False，房间ID: {room_id}, 用户: {user_name}, 二维码类型: {qrcode_type}")
    except Exception as e:
        logger.error(f"解析 JWT token 失败: {e}")
    
    # 构建房间 URL（指向后端系统的 /room 页面，而不是直接访问 Jitsi）
    from urllib.parse import urlencode
    base_url = str(request.base_url).rstrip('/')
    room_url = f"{base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
    
    return RoomJoinResponse(
        room_id=room_id,
        jitsi_token=jitsi_token,
        jitsi_server_url=settings.JITSI_SERVER_URL,
        room_url=room_url
    )


@router.post("/{room_id}/join", response_model=RoomJoinResponse)
async def join_room(
    room_id: str,
    join_data: RoomJoin,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    加入房间（返回 JWT）
    
    根据 Spec.txt：必须通过后端签发的 JWT 进行房门授权，实现强管控
    返回 Jitsi JWT Token 和房间 URL
    
    去除后台房间功能，视频通话和共享功能交由Jitsi自行处理
    不再检查或创建数据库中的房间记录，直接基于room_id生成JWT token
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 如果提供了二维码数据，检查二维码是否已失效
    if join_data.encrypted_data:
        from app.api.v1.qrcode import calculate_encrypted_data_hash
        
        encrypted_data_hash = calculate_encrypted_data_hash(join_data.encrypted_data)
        qr_scan_result = await db.execute(
            select(QRCodeScan).where(QRCodeScan.encrypted_data_hash == encrypted_data_hash)
        )
        qr_scan = qr_scan_result.scalar_one_or_none()
        
        if qr_scan and qr_scan.is_expired:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("qrcode.expired", lang=lang)
            )
        
        # 更新二维码扫描次数
        if qr_scan:
            qr_scan.scan_count += 1
            if qr_scan.scan_count >= qr_scan.max_scans:
                qr_scan.is_expired = True
            await db.commit()
    
    # 去除后台房间功能，视频通话和共享功能交由Jitsi自行处理
    # 不再检查或创建数据库中的房间记录，直接基于room_id生成JWT token
    # 房间人数限制和参与者管理由Jitsi自行处理
    
    # 生成 Jitsi JWT Token
    user_name = join_data.display_name or current_user.nickname or current_user.username or current_user.phone
    
    # 已登录用户可以通过 is_moderator 参数控制是否为主持人
    # 但为了安全，这里默认不是主持人，只有在特殊情况下才允许
    is_moderator = join_data.is_moderator if join_data.is_moderator else False
    
    jitsi_token = create_jitsi_token(
        room_id=room_id,
        user_id=current_user.id,
        user_name=user_name,
        is_moderator=is_moderator,
        expires_in_minutes=60  # Jitsi token 有效期 1 小时
    )
    
    # 构建房间 URL（指向后端系统的 /room 页面，而不是直接访问 Jitsi）
    from urllib.parse import urlencode
    base_url = str(request.base_url).rstrip('/')
    room_url = f"{base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
    
    logger.info(f"✓ 用户 {current_user.id} ({user_name}) 加入房间 {room_id}")
    
    return RoomJoinResponse(
        room_id=room_id,
        jitsi_token=jitsi_token,
        jitsi_server_url=settings.JITSI_SERVER_URL,
        room_url=room_url
    )
