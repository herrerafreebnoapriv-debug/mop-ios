"""
Jitsi 房间 API
包含房间创建、查询、更新、加入和参与者管理功能
根据 Spec.txt：必须通过后端签发的 JWT 进行房门授权，实现强管控
"""

from datetime import datetime, timezone
from typing import List, Optional
import uuid
import hashlib
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, desc
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.security import create_jitsi_token
from app.core.config import settings
from loguru import logger
from app.core.permissions import (
    is_super_admin, is_room_owner, check_user_not_disabled,
    check_room_ownership, check_room_creation_limit,
    filter_visible_rooms, ROLE_ROOM_OWNER
)
from app.core.operation_log import log_operation
from app.db.session import get_db
from app.db.models import User, Room, RoomParticipant, QRCodeScan, Call
from app.api.v1.auth import get_current_user

router = APIRouter()


# ==================== 房间ID生成工具函数 ====================

def generate_hex8_room_id() -> str:
    """
    生成8位16进制房间ID
    格式：r-{8位16进制}
    示例：r-a1b2c3d4
    
    使用加密安全的随机数生成器，确保不可预测
    """
    import secrets
    # 生成4字节随机数，转换为8位16进制
    hex8 = secrets.token_hex(4)  # 4字节 = 8位16进制
    return f"r-{hex8}"


async def generate_unique_room_id(db: AsyncSession, max_retries: int = 10) -> str:
    """
    生成唯一的房间ID（带碰撞检测）
    
    Args:
        db: 数据库会话
        max_retries: 最大重试次数
    
    Returns:
        唯一的房间ID
    """
    for _ in range(max_retries):
        room_id = generate_hex8_room_id()
        
        # 检查是否已存在
        result = await db.execute(
            select(Room).where(Room.room_id == room_id)
        )
        existing_room = result.scalar_one_or_none()
        
        if not existing_room:
            return room_id
    
    # 如果多次重试后仍然冲突，使用UUID作为后备方案
    return f"r-{uuid.uuid4().hex[:8]}"


def validate_room_id_format(room_id: str) -> bool:
    """
    验证房间ID格式
    
    支持的格式：
    1. 8位16进制格式：r-{8位16进制}（推荐）
    2. 其他格式（向后兼容）
    
    Args:
        room_id: 房间ID
    
    Returns:
        是否为有效格式
    """
    if not room_id or len(room_id) < 3:
        return False
    
    # 8位16进制格式：r-{8位16进制}
    if room_id.startswith("r-") and len(room_id) == 10:
        hex_part = room_id[2:]
        try:
            int(hex_part, 16)
            return True
        except ValueError:
            return False
    
    # 其他格式（向后兼容，不验证具体格式）
    return True  # 允许其他自定义格式


# ==================== 请求/响应模型 ====================

class RoomCreate(BaseModel):
    """房间创建请求模型"""
    room_name: Optional[str] = Field(None, max_length=200, description="房间名称")
    max_occupants: Optional[int] = Field(None, ge=1, le=100, description="最大在线人数（默认10）")
    room_id: Optional[str] = Field(None, max_length=100, description="自定义房间ID（可选，默认自动生成）")


class RoomUpdate(BaseModel):
    """房间更新请求模型"""
    room_name: Optional[str] = Field(None, max_length=200, description="房间名称")
    max_occupants: Optional[int] = Field(None, ge=1, le=100, description="最大在线人数")
    is_active: Optional[bool] = Field(None, description="是否激活")


class RoomResponse(BaseModel):
    """房间响应模型"""
    id: int
    room_id: str
    room_name: Optional[str]
    created_by: int
    max_occupants: int
    is_active: bool
    participant_count: int
    created_at: str
    updated_at: str
    
    class Config:
        from_attributes = True


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


class ParticipantResponse(BaseModel):
    """参与者响应模型"""
    id: int
    user_id: int
    display_name: Optional[str]
    is_moderator: bool
    joined_at: str
    left_at: Optional[str]
    is_active: bool
    user_nickname: Optional[str]
    
    class Config:
        from_attributes = True


# ==================== API 路由 ====================

@router.get("/", response_model=List[RoomResponse])
async def list_rooms(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0, description="跳过记录数"),
    limit: int = Query(100, ge=1, le=100, description="返回记录数")
):
    """
    获取房间列表
    
    超级管理员：可以看到所有房间
    房主：只能看到自己创建的房间
    普通用户：只能看到自己创建的房间
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="room",
        request=request
    )
    
    # 根据权限过滤房间
    visible_rooms = await filter_visible_rooms(current_user, db)
    
    # 应用分页
    paginated_rooms = visible_rooms[skip:skip + limit]
    
    # 为每个房间统计参与者数量
    room_responses = []
    for room in paginated_rooms:
        participant_count_result = await db.execute(
            select(func.count(RoomParticipant.id)).where(
                and_(
                    RoomParticipant.__table__.c.room_id == room.id,
                    RoomParticipant.__table__.c.is_active == True
                )
            )
        )
        participant_count = participant_count_result.scalar() or 0
        
        room_responses.append(RoomResponse(
            id=room.id,
            room_id=room.room_id,
            room_name=room.room_name,
            created_by=room.created_by,
            max_occupants=room.max_occupants,
            is_active=room.is_active,
            participant_count=participant_count,
            created_at=room.created_at.isoformat(),
            updated_at=room.updated_at.isoformat()
        ))
    
    await db.commit()  # 提交操作日志
    
    return room_responses


@router.post("/create", response_model=RoomResponse, status_code=status.HTTP_201_CREATED)
async def create_room(
    room_data: RoomCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    创建房间
    
    超级管理员：无限制
    房主：检查房间数限制和人数上限（默认3）
    普通用户：不允许创建房间
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查用户是否可以创建房间
    await check_room_creation_limit(current_user, db, lang)
    
    # 生成房间ID（如果未提供）
    if room_data.room_id:
        room_id = room_data.room_id
        if not validate_room_id_format(room_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("room.invalid_id_format", lang=lang, room_id=room_id)
            )
    else:
        room_id = await generate_unique_room_id(db)
    
    # 检查房间ID是否已存在
    result = await db.execute(
        select(Room).where(Room.room_id == room_id)
    )
    existing_room = result.scalar_one_or_none()
    
    if existing_room:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("room.id_exists", lang=lang, room_id=room_id)
        )
    
    # 确定房间最大人数上限
    if is_room_owner(current_user) and current_user.default_max_occupants:
        default_max_occupants = current_user.default_max_occupants
    else:
        default_max_occupants = settings.JITSI_ROOM_MAX_OCCUPANTS
    
    max_occupants = room_data.max_occupants or default_max_occupants
    
    # 房主不能超过默认人数上限
    if is_room_owner(current_user) and current_user.default_max_occupants:
        if max_occupants > current_user.default_max_occupants:
            max_occupants = current_user.default_max_occupants
    
    # 创建房间
    new_room = Room(
        room_id=room_id,
        room_name=room_data.room_name,
        created_by=current_user.id,
        max_occupants=max_occupants,
        is_active=True
    )
    
    db.add(new_room)
    await db.commit()
    await db.refresh(new_room)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="create",
        resource_type="room",
        resource_id=new_room.id,
        resource_name=new_room.room_name or new_room.room_id,
        operation_detail={"room_id": new_room.room_id, "max_occupants": max_occupants},
        request=request
    )
    await db.commit()
    
    return RoomResponse(
        id=new_room.id,
        room_id=new_room.room_id,
        room_name=new_room.room_name,
        created_by=new_room.created_by,
        max_occupants=new_room.max_occupants,
        is_active=new_room.is_active,
        participant_count=0,
        created_at=new_room.created_at.isoformat(),
        updated_at=new_room.updated_at.isoformat()
    )


@router.get("/{room_id}", response_model=RoomResponse)
async def get_room(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取房间信息
    
    超级管理员：可以查看所有房间
    房主：只能查看自己创建的房间
    """
    lang = get_language_from_request(request)
    if current_user:
        lang = current_user.language or lang
    
    check_user_not_disabled(current_user, lang)
    
    # 检查权限并获取房间
    room = await check_room_ownership(room_id, current_user, db, lang)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="room",
        resource_id=room.id,
        resource_name=room.room_name or room.room_id,
        request=request
    )
    
    # 统计当前活跃参与者数量
    participant_count_result = await db.execute(
        select(func.count(RoomParticipant.id)).where(
            and_(
                RoomParticipant.__table__.c.room_id == room.id,
                RoomParticipant.__table__.c.is_active == True
            )
        )
    )
    participant_count = participant_count_result.scalar() or 0
    
    await db.commit()  # 提交操作日志
    
    return RoomResponse(
        id=room.id,
        room_id=room.room_id,
        room_name=room.room_name,
        created_by=room.created_by,
        max_occupants=room.max_occupants,
        is_active=room.is_active,
        participant_count=participant_count,
        created_at=room.created_at.isoformat(),
        updated_at=room.updated_at.isoformat()
    )


@router.put("/{room_id}/max_occupants", response_model=RoomResponse)
async def update_room_max_occupants(
    room_id: str,
    max_occupants: int = Query(..., ge=1, le=100, description="最大在线人数"),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    设置房间最大人数
    
    超级管理员：可以设置任何房间
    房主：只能设置自己的房间，且不能超过默认人数上限（默认3）
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查权限并获取房间
    room = await check_room_ownership(room_id, current_user, db, lang)
    
    # 房主不能超过默认人数上限
    if is_room_owner(current_user) and current_user.default_max_occupants:
        if max_occupants > current_user.default_max_occupants:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("room.max_occupants_exceeded", lang=lang, max=current_user.default_max_occupants)
            )
    
    old_max_occupants = room.max_occupants
    
    # 更新最大人数
    room.max_occupants = max_occupants
    
    await db.commit()
    await db.refresh(room)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="room",
        resource_id=room.id,
        resource_name=room.room_name or room.room_id,
        operation_detail={"field": "max_occupants", "old_value": old_max_occupants, "new_value": max_occupants},
        request=request
    )
    await db.commit()
    
    # 统计当前活跃参与者数量
    participant_count_result = await db.execute(
        select(func.count(RoomParticipant.id)).where(
            and_(
                RoomParticipant.__table__.c.room_id == room.id,
                RoomParticipant.__table__.c.is_active == True
            )
        )
    )
    participant_count = participant_count_result.scalar() or 0
    
    return RoomResponse(
        id=room.id,
        room_id=room.room_id,
        room_name=room.room_name,
        created_by=room.created_by,
        max_occupants=room.max_occupants,
        is_active=room.is_active,
        participant_count=participant_count,
        created_at=room.created_at.isoformat(),
        updated_at=room.updated_at.isoformat()
    )


@router.put("/{room_id}", response_model=RoomResponse)
async def update_room(
    room_id: str,
    room_data: RoomUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新房间信息
    
    超级管理员：可以更新任何房间
    房主：只能更新自己创建的房间
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查权限并获取房间
    room = await check_room_ownership(room_id, current_user, db, lang)
    
    # 更新字段
    if room_data.room_name is not None:
        room.room_name = room_data.room_name
    if room_data.max_occupants is not None:
        # 房主不能超过默认人数上限
        if is_room_owner(current_user) and current_user.default_max_occupants:
            if room_data.max_occupants > current_user.default_max_occupants:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=i18n.t("room.max_occupants_exceeded", lang=lang, max=current_user.default_max_occupants)
                )
        room.max_occupants = room_data.max_occupants
    if room_data.is_active is not None:
        room.is_active = room_data.is_active
    
    await db.commit()
    await db.refresh(room)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="room",
        resource_id=room.id,
        resource_name=room.room_name or room.room_id,
        operation_detail={"room_data": room_data.dict(exclude_unset=True)},
        request=request
    )
    await db.commit()
    
    # 统计当前活跃参与者数量
    participant_count_result = await db.execute(
        select(func.count(RoomParticipant.id)).where(
            and_(
                RoomParticipant.__table__.c.room_id == room.id,
                RoomParticipant.__table__.c.is_active == True
            )
        )
    )
    participant_count = participant_count_result.scalar() or 0
    
    return RoomResponse(
        id=room.id,
        room_id=room.room_id,
        room_name=room.room_name,
        created_by=room.created_by,
        max_occupants=room.max_occupants,
        is_active=room.is_active,
        participant_count=participant_count,
        created_at=room.created_at.isoformat(),
        updated_at=room.updated_at.isoformat()
    )


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
    from urllib.parse import urlparse, parse_qs
    
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
    
    # 查找房间
    result = await db.execute(
        select(Room).where(Room.room_id == room_id)
    )
    room = result.scalar_one_or_none()
    
    if not room:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("room.not_found", lang=lang)
        )
    
    if not room.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("room.inactive", lang=lang)
        )
    
    # 更新二维码扫描次数（如果有限制）
    if qr_scan and qr_scan.max_scans > 0:
        qr_scan.scan_count += 1
        if qr_scan.scan_count >= qr_scan.max_scans:
            qr_scan.is_expired = True
        await db.commit()
    
    # 生成临时用户标识和JWT Token
    import hashlib
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
    
    # 查找房间
    result = await db.execute(
        select(Room).where(Room.room_id == room_id)
    )
    room = result.scalar_one_or_none()
    
    if not room:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("room.not_found", lang=lang)
        )
    
    if not room.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("room.inactive", lang=lang) or "房间已关闭"
        )
    
    # 更新二维码扫描次数（max_scans=0表示不限制）
    if qr_scan and qr_scan.max_scans > 0:
        qr_scan.scan_count += 1
        if qr_scan.scan_count >= qr_scan.max_scans:
            qr_scan.is_expired = True
        await db.commit()
    
    # 生成临时用户标识和JWT Token
    import hashlib
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
    
    # 查找房间
    result = await db.execute(
        select(Room).where(Room.room_id == room_id)
    )
    room = result.scalar_one_or_none()
    
    if not room:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("room.not_found", lang=lang)
        )
    
    if not room.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("room.inactive", lang=lang)
        )
    
    # 检查房间是否已满
    participant_count_result = await db.execute(
        select(func.count(RoomParticipant.id)).where(
            and_(
                RoomParticipant.__table__.c.room_id == room.id,
                RoomParticipant.__table__.c.is_active == True
            )
        )
    )
    participant_count = participant_count_result.scalar() or 0
    
    if participant_count >= room.max_occupants:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("room.full", lang=lang, max_occupants=room.max_occupants)
        )
    
    # 检查是否已经是参与者
    existing_participant_result = await db.execute(
        select(RoomParticipant).where(
            and_(
                RoomParticipant.__table__.c.room_id == room.id,
                RoomParticipant.__table__.c.user_id == current_user.id,
                RoomParticipant.__table__.c.is_active == True
            )
        )
    )
    existing_participant = existing_participant_result.scalar_one_or_none()
    
    if existing_participant:
        # 更新参与者信息
        existing_participant.display_name = join_data.display_name or current_user.nickname
        existing_participant.is_moderator = join_data.is_moderator if room.created_by == current_user.id else existing_participant.is_moderator
    else:
        # 创建新的参与者记录
        is_moderator = join_data.is_moderator and (room.created_by == current_user.id)
        
        new_participant = RoomParticipant(
            room_id=room.id,
            user_id=current_user.id,
            display_name=join_data.display_name or current_user.nickname,
            is_moderator=is_moderator,
            is_active=True
        )
        db.add(new_participant)
    
    await db.commit()
    
    # 生成 Jitsi JWT Token
    user_name = join_data.display_name or current_user.nickname or current_user.username or current_user.phone
    is_moderator = join_data.is_moderator and (room.created_by == current_user.id)
    
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
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="room",
        resource_id=room.id,
        resource_name=room.room_name or room.room_id,
        operation_detail={"action": "join"},
        request=request
    )
    
    # 创建通话记录（如果不存在）
    # 检查是否已有该用户在该房间的活跃通话记录
    existing_call_result = await db.execute(
        select(Call).where(
            and_(
                Call.room_id == room.id,
                Call.caller_id == current_user.id,
                Call.call_status.in_(["initiated", "ringing", "connected"])
            )
        ).order_by(desc(Call.created_at))
    )
    existing_call = existing_call_result.scalar_one_or_none()
    
    if not existing_call:
        # 创建新的通话记录
        new_call = Call(
            call_type="video",  # 默认视频通话
            call_status="connected",  # 加入房间时状态为已连接
            caller_id=current_user.id,
            callee_id=None,  # 房间通话没有特定接收者
            room_id=room.id,
            jitsi_room_id=room_id,
            start_time=datetime.utcnow(),
            created_at=datetime.utcnow()
        )
        db.add(new_call)
    
    await db.commit()
    
    return RoomJoinResponse(
        room_id=room_id,
        jitsi_token=jitsi_token,
        jitsi_server_url=settings.JITSI_SERVER_URL,
        room_url=room_url
    )


@router.get("/{room_id}/participants", response_model=List[ParticipantResponse])
async def get_room_participants(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取房间参与者
    
    获取指定房间的所有参与者列表
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查权限并获取房间
    room = await check_room_ownership(room_id, current_user, db, lang)
    
    # 获取参与者列表（包含用户信息）
    participants_result = await db.execute(
        select(RoomParticipant, User).join(
            User, RoomParticipant.__table__.c.user_id == User.id
        ).where(
            RoomParticipant.__table__.c.room_id == room.id,
            RoomParticipant.__table__.c.is_active == True
        ).order_by(RoomParticipant.__table__.c.joined_at)
    )
    participants_data = participants_result.all()
    
    participants = []
    for participant, user in participants_data:
        participants.append(ParticipantResponse(
            id=participant.id,
            user_id=participant.user_id,
            display_name=participant.display_name,
            is_moderator=participant.is_moderator,
            joined_at=participant.joined_at.isoformat(),
            left_at=participant.left_at.isoformat() if participant.left_at else None,
            is_active=participant.is_active,
            user_nickname=user.nickname
        ))
    
    return participants


@router.post("/{room_id}/leave", status_code=status.HTTP_200_OK)
async def leave_room(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    离开房间
    
    更新参与者状态并更新通话记录
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查找房间
    result = await db.execute(
        select(Room).where(Room.room_id == room_id)
    )
    room = result.scalar_one_or_none()
    
    if not room:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("room.not_found", lang=lang)
        )
    
    # 查找参与者记录
    participant_result = await db.execute(
        select(RoomParticipant).where(
            and_(
                RoomParticipant.room_id == room.id,
                RoomParticipant.user_id == current_user.id,
                RoomParticipant.is_active == True
            )
        )
    )
    participant = participant_result.scalar_one_or_none()
    
    if participant:
        # 更新参与者状态
        participant.is_active = False
        participant.left_at = datetime.utcnow()
    
    # 更新通话记录
    call_result = await db.execute(
        select(Call).where(
            and_(
                Call.room_id == room.id,
                Call.caller_id == current_user.id,
                Call.call_status.in_(["initiated", "ringing", "connected"])
            )
        ).order_by(desc(Call.created_at))
    )
    call = call_result.scalar_one_or_none()
    
    if call:
        # 更新通话记录
        call.call_status = "ended"
        call.end_time = datetime.utcnow()
        if call.start_time:
            duration_delta = call.end_time - call.start_time
            call.duration = int(duration_delta.total_seconds())
    
    await db.commit()
    
    return {"message": "已离开房间", "room_id": room_id}


@router.delete("/{room_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_room(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除房间
    
    房主可以删除自己创建的房间
    超级管理员可以删除任何房间（通过 /admin/rooms/{room_id}）
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查权限并获取房间
    room = await check_room_ownership(room_id, current_user, db, lang)
    
    room_name = room.room_name or room.room_id
    room_id_for_log = room.id
    
    # 删除房间（级联删除参与者）
    await db.delete(room)
    await db.commit()
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="delete",
        resource_type="room",
        resource_id=room_id_for_log,
        resource_name=room_name,
        request=request
    )
    await db.commit()
