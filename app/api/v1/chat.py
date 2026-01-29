"""
聊天API模块
实现消息历史查询、会话管理等功能
"""

from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_, desc
from sqlalchemy.orm import selectinload
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.permissions import is_super_admin, check_user_not_disabled
from app.core.operation_log import log_operation
from app.db.session import get_db
from app.db.models import User, Message, Room, RoomParticipant, File
from app.api.v1.auth import get_current_user
from loguru import logger

router = APIRouter()


# ==================== 请求/响应模型 ====================

class MessageResponse(BaseModel):
    """消息响应模型"""
    id: int
    sender_id: int
    receiver_id: Optional[int] = None
    room_id: Optional[int] = None
    message: str
    message_type: str
    is_read: bool
    read_at: Optional[datetime] = None
    created_at: datetime
    sender_nickname: Optional[str] = None
    receiver_nickname: Optional[str] = None
    room_name: Optional[str] = None
    # 文件相关字段（图片/文件消息）
    file_id: Optional[int] = None
    file_url: Optional[str] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    duration: Optional[int] = None  # 语音/视频时长（秒）
    extra_data: Optional[dict] = None  # 扩展数据，如 call_invitation（视频通话邀请，供前端显示接受/拒绝按钮）
    
    class Config:
        from_attributes = True


class MessageListResponse(BaseModel):
    """消息列表响应模型"""
    total: int
    messages: List[MessageResponse]
    page: int
    limit: int


class MessageSinceResponse(BaseModel):
    """增量消息响应模型（按最后消息ID之后拉取）"""
    messages: List[MessageResponse]
    last_message_id: Optional[int] = Field(None, description="本次返回的最大消息ID，供下次增量使用")


class ConversationResponse(BaseModel):
    """会话响应模型"""
    user_id: Optional[int] = None
    room_id: Optional[int] = None
    user_nickname: Optional[str] = None
    room_name: Optional[str] = None
    last_message: Optional[str] = None
    last_message_time: Optional[datetime] = None
    unread_count: int = 0


class ConversationListResponse(BaseModel):
    """会话列表响应模型"""
    conversations: List[ConversationResponse]


class MarkReadRequest(BaseModel):
    """标记已读请求模型"""
    message_ids: List[int] = Field(..., description="消息ID列表")


class SendMessageRequest(BaseModel):
    """发送消息请求模型"""
    receiver_id: Optional[int] = Field(None, description="接收者用户ID（点对点消息）")
    room_id: Optional[int] = Field(None, description="房间ID（房间群聊消息）")
    message: Optional[str] = Field(None, max_length=5000, description="消息内容（文本消息必需，文件消息可选）")
    message_type: str = Field("text", description="消息类型：text/image/file/audio/system")
    file_id: Optional[int] = Field(None, description="文件ID（语音/通用文件时使用 files 表）")
    file_url: Optional[str] = Field(None, max_length=500, description="文件URL（图片等 HTTP 上传后直接提供）")
    file_name: Optional[str] = Field(None, max_length=255, description="文件名（与 file_url 配合）")


# ==================== API 路由 ====================

@router.get("/messages", response_model=MessageListResponse)
async def get_messages(
    request: Request,
    page: int = Query(1, ge=1, description="页码"),
    limit: int = Query(50, ge=1, le=100, description="每页数量"),
    user_id: Optional[int] = Query(None, description="筛选用户ID（点对点消息）"),
    room_id: Optional[int] = Query(None, description="筛选房间ID（房间群聊）"),
    start_time: Optional[datetime] = Query(None, description="开始时间"),
    end_time: Optional[datetime] = Query(None, description="结束时间"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取消息列表
    
    超级管理员：可以查看所有消息
    普通用户：只能查看与自己相关的消息（发送或接收）
    """
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建查询条件
    conditions = []
    
    # 权限控制：普通用户只能查看与自己相关的消息
    if not is_super_admin(current_user):
        # 普通用户：只能查看自己发送或接收的消息
        conditions.append(
            or_(
                Message.sender_id == current_user.id,
                Message.receiver_id == current_user.id,
                # 房间消息：检查用户是否是房间参与者
                and_(
                    Message.room_id.isnot(None),
                    Message.room_id.in_(
                        select(Room.id).join(RoomParticipant).where(
                            RoomParticipant.user_id == current_user.id
                        )
                    )
                )
            )
        )
    
    if user_id:
        # 点对点消息：发送者或接收者是指定用户
        if is_super_admin(current_user):
            # 管理员可以查看任意用户的消息
            conditions.append(
                or_(
                    Message.sender_id == user_id,
                    Message.receiver_id == user_id
                )
            )
        else:
            # 普通用户只能查看与自己的对话
            conditions.append(
                and_(
                    or_(
                        Message.sender_id == user_id,
                        Message.receiver_id == user_id
                    ),
                    or_(
                        Message.sender_id == current_user.id,
                        Message.receiver_id == current_user.id
                    )
                )
            )
    
    if room_id:
        # 房间群聊消息
        if is_super_admin(current_user):
            # 管理员可以查看任意房间的消息
            conditions.append(Message.room_id == room_id)
        else:
            # 普通用户只能查看自己参与的房间
            conditions.append(
                and_(
                    Message.room_id == room_id,
                    Message.room_id.in_(
                        select(Room.id).join(RoomParticipant).where(
                            RoomParticipant.user_id == current_user.id
                        )
                    )
                )
            )
    
    if start_time:
        conditions.append(Message.created_at >= start_time)
    
    if end_time:
        conditions.append(Message.created_at <= end_time)
    
    # 查询总数
    count_query = select(func.count(Message.id))
    if conditions:
        count_query = count_query.where(and_(*conditions))
    
    total_result = await db.execute(count_query)
    total = total_result.scalar() or 0
    
    # 查询消息列表（带关联）
    query = select(Message).options(
        selectinload(Message.sender),
        selectinload(Message.receiver),
        selectinload(Message.room)
    ).order_by(desc(Message.created_at))
    
    if conditions:
        query = query.where(and_(*conditions))
    
    # 分页
    offset = (page - 1) * limit
    query = query.offset(offset).limit(limit)
    
    result = await db.execute(query)
    messages = result.scalars().all()
    
    # 转换为响应模型
    message_list = []
    for msg in messages:
        message_list.append(MessageResponse(
            id=msg.id,
            sender_id=msg.sender_id,
            receiver_id=msg.receiver_id,
            room_id=msg.room_id,
            message=msg.message,
            message_type=msg.message_type,
            is_read=msg.is_read,
            read_at=msg.read_at,
            created_at=msg.created_at,
            sender_nickname=msg.sender.nickname if msg.sender else None,
            receiver_nickname=msg.receiver.nickname if msg.receiver else None,
            room_name=msg.room.room_name if msg.room else None,
            # 文件相关字段（如果存在）
            file_id=getattr(msg, 'file_id', None),
            file_url=getattr(msg, 'file_url', None),
            file_name=getattr(msg, 'file_name', None),
            file_size=getattr(msg, 'file_size', None),
            duration=getattr(msg, 'duration', None),
            extra_data=getattr(msg, 'extra_data', None),
        ))
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="messages",
        request=request
    )
    await db.commit()
    
    return MessageListResponse(
        total=total,
        messages=message_list,
        page=page,
        limit=limit
    )


@router.get("/messages/since", response_model=MessageSinceResponse)
async def get_messages_since(
    request: Request,
    last_message_id: int = Query(0, ge=0, description="最后一条已同步的消息ID（0表示从头开始）"),
    user_id: Optional[int] = Query(None, description="点对点会话对方用户ID"),
    room_id: Optional[int] = Query(None, description="房间ID（群聊）"),
    limit: int = Query(200, ge=1, le=500, description="最多返回的消息数量"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    增量获取消息列表（用于离线消息补偿）

    - 必须指定 user_id（点对点）或 room_id（群聊）之一
    - 只返回 ID 大于 last_message_id 的消息，按时间正序（旧到新）
    - 普通用户只能获取与自己相关的消息
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)

    if not user_id and not room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="必须指定 user_id 或 room_id",
        )

    if user_id and room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="不能同时指定 user_id 和 room_id",
        )

    conditions = [Message.id > last_message_id]

    # 点对点会话
    if user_id:
        if is_super_admin(current_user):
            # 超级管理员：拉取与指定 user_id 相关的消息
            conditions.append(
                or_(
                    and_(
                        Message.sender_id == current_user.id,
                        Message.receiver_id == user_id,
                    ),
                    and_(
                        Message.sender_id == user_id,
                        Message.receiver_id == current_user.id,
                    ),
                )
            )
        else:
            # 普通用户：只能拉取“自己 <-> 对方”的消息
            conditions.append(
                and_(
                    Message.room_id.is_(None),
                    or_(
                        and_(
                            Message.sender_id == current_user.id,
                            Message.receiver_id == user_id,
                        ),
                        and_(
                            Message.sender_id == user_id,
                            Message.receiver_id == current_user.id,
                        ),
                    ),
                )
            )

    # 房间会话
    if room_id:
        if is_super_admin(current_user):
            conditions.append(Message.room_id == room_id)
        else:
            # 普通用户：只能拉取自己参与的房间
            conditions.append(
                and_(
                    Message.room_id == room_id,
                    Message.room_id.in_(
                        select(Room.id)
                        .join(RoomParticipant)
                        .where(
                            RoomParticipant.user_id == current_user.id,
                            RoomParticipant.is_active == True,
                        )
                    ),
                )
            )

    query = (
        select(Message)
        .options(
            selectinload(Message.sender),
            selectinload(Message.receiver),
            selectinload(Message.room),
        )
        .where(and_(*conditions))
        .order_by(Message.created_at.asc(), Message.id.asc())
        .limit(limit)
    )

    result = await db.execute(query)
    messages = result.scalars().all()

    response_messages: List[MessageResponse] = []
    max_id = last_message_id
    for msg in messages:
        if msg.id > max_id:
            max_id = msg.id
        response_messages.append(
            MessageResponse(
                id=msg.id,
                sender_id=msg.sender_id,
                receiver_id=msg.receiver_id,
                room_id=msg.room_id,
                message=msg.message,
                message_type=msg.message_type,
                is_read=msg.is_read,
                read_at=msg.read_at,
                created_at=msg.created_at,
                sender_nickname=msg.sender.nickname if msg.sender else None,
                receiver_nickname=msg.receiver.nickname
                if msg.receiver
                else None,
                room_name=msg.room.room_name if msg.room else None,
                file_id=getattr(msg, "file_id", None),
                file_url=getattr(msg, "file_url", None),
                file_name=getattr(msg, "file_name", None),
                file_size=getattr(msg, "file_size", None),
                duration=getattr(msg, "duration", None),
                extra_data=getattr(msg, "extra_data", None),
            )
        )

    # 不记录操作日志，作为高频补偿接口保持轻量
    return MessageSinceResponse(messages=response_messages, last_message_id=max_id)


@router.get("/messages/{message_id}", response_model=MessageResponse)
async def get_message(
    message_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取单条消息详情（仅超级管理员）
    """
    if not is_super_admin(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="仅超级管理员可访问"
        )
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    result = await db.execute(
        select(Message).options(
            selectinload(Message.sender),
            selectinload(Message.receiver),
            selectinload(Message.room)
        ).where(Message.id == message_id)
    )
    message = result.scalar_one_or_none()
    
    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("common.not_found", lang)
        )
    
    return MessageResponse(
        id=message.id,
        sender_id=message.sender_id,
        receiver_id=message.receiver_id,
        room_id=message.room_id,
        message=message.message,
        message_type=message.message_type,
        is_read=message.is_read,
        read_at=message.read_at,
        created_at=message.created_at,
        sender_nickname=message.sender.nickname if message.sender else None,
        receiver_nickname=message.receiver.nickname if message.receiver else None,
        room_name=message.room.room_name if message.room else None,
        file_id=getattr(message, 'file_id', None),
        file_url=getattr(message, 'file_url', None),
        file_name=getattr(message, 'file_name', None),
        file_size=getattr(message, 'file_size', None),
        duration=getattr(message, 'duration', None),
        extra_data=getattr(message, 'extra_data', None),
    )


@router.post("/messages", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    request_data: SendMessageRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    发送消息
    
    支持点对点消息（receiver_id）和房间群聊（room_id）
    普通用户只能发送给自己参与的房间或与其他用户的点对点消息
    """
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 验证参数：必须指定 receiver_id 或 room_id 之一，但不能同时指定
    if not request_data.receiver_id and not request_data.room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("chat.must_specify_receiver_or_room", lang)
        )
    
    if request_data.receiver_id and request_data.room_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("chat.cannot_specify_both", lang)
        )
    
    # 权限验证
    if request_data.receiver_id:
        # 点对点消息：不能发送给自己
        if request_data.receiver_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("chat.cannot_send_to_self", lang)
            )
        
        # 验证接收者是否存在
        receiver_result = await db.execute(
            select(User).where(User.id == request_data.receiver_id)
        )
        receiver = receiver_result.scalar_one_or_none()
        
        if not receiver:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=i18n.get("user.not_found", lang)
            )
        
        # 普通用户不能发送给禁用的用户
        if not is_super_admin(current_user) and receiver.is_disabled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=i18n.get("chat.receiver_disabled", lang)
            )
    
    elif request_data.room_id:
        # 房间群聊：验证用户是否是房间参与者
        room_result = await db.execute(
            select(Room).where(Room.id == request_data.room_id)
        )
        room = room_result.scalar_one_or_none()
        
        if not room:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=i18n.get("room.not_found", lang)
            )
        
        # 超级管理员可以发送到任意房间，普通用户需要验证参与者身份
        if not is_super_admin(current_user):
            participant_result = await db.execute(
                select(RoomParticipant).where(
                    RoomParticipant.room_id == request_data.room_id,
                    RoomParticipant.user_id == current_user.id,
                    RoomParticipant.is_active == True
                )
            )
            participant = participant_result.scalar_one_or_none()
            
            if not participant:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=i18n.get("room.not_participant", lang)
                )
    
    # 解析文件信息：file_id 查 files 表；图片等可仅传 file_url + file_name
    file_info = None
    if request_data.file_id:
        fr = await db.execute(select(File).where(File.id == request_data.file_id))
        f = fr.scalar_one_or_none()
        if f and f.uploader_id == current_user.id:
            file_info = f

    now = datetime.utcnow()
    message_content = request_data.message or ""
    if file_info:
        message_content = message_content or file_info.file_url
    elif request_data.file_url and request_data.message_type in ("image", "audio", "video", "file"):
        message_content = message_content or request_data.file_url

    file_id_val = file_info.id if file_info else None
    file_url_val = file_info.file_url if file_info else (request_data.file_url or None)
    file_name_val = file_info.filename if file_info else (request_data.file_name or None)
    file_size_val = file_info.file_size if file_info else None
    duration_val = file_info.duration if file_info else None

    db_message = Message(
        sender_id=current_user.id,
        receiver_id=request_data.receiver_id,
        room_id=request_data.room_id,
        message=message_content,
        message_type=request_data.message_type,
        is_read=False,
        created_at=now,
        file_id=file_id_val,
        file_url=file_url_val,
        file_name=file_name_val,
        file_size=file_size_val,
        duration=duration_val,
    )
    
    db.add(db_message)
    await db.commit()
    await db.refresh(db_message)
    
    # 加载关联数据
    await db.refresh(db_message, ["sender", "receiver", "room"])
    
    # 通过 Socket.io 实时推送消息
    try:
        from app.core.socketio import sio, connected_users
        from datetime import timezone as tz
        
        if request_data.receiver_id:
            # 点对点消息：发送给接收者
            if request_data.receiver_id in connected_users:
                message_data = {
                    'id': db_message.id,
                    'sender_id': current_user.id,
                    'sender_nickname': current_user.nickname,
                    'receiver_id': request_data.receiver_id,
                    'message': message_content,
                    'message_type': request_data.message_type,
                    'is_read': False,
                    'created_at': now.isoformat()
                }
                if file_info:
                    message_data['file_id'] = file_info.id
                    message_data['file_url'] = file_info.file_url
                    message_data['file_name'] = file_info.filename
                    message_data['file_size'] = file_info.file_size
                    if file_info.duration:
                        message_data['duration'] = file_info.duration
                    if file_info.width and file_info.height:
                        message_data['width'] = file_info.width
                        message_data['height'] = file_info.height
                elif file_url_val:
                    message_data['file_url'] = file_url_val
                    if file_name_val:
                        message_data['file_name'] = file_name_val
                    if file_size_val is not None:
                        message_data['file_size'] = file_size_val
                    if duration_val is not None:
                        message_data['duration'] = duration_val

                await sio.emit('message', message_data, room=f"user_{request_data.receiver_id}")
        elif request_data.room_id:
            # 房间群聊：发送给所有参与者
            participants_result = await db.execute(
                select(RoomParticipant).where(
                    RoomParticipant.room_id == request_data.room_id,
                    RoomParticipant.is_active == True
                )
            )
            participants = participants_result.scalars().all()
            
            for participant in participants:
                if participant.user_id in connected_users:
                    message_data = {
                        'id': db_message.id,
                        'sender_id': current_user.id,
                        'sender_nickname': current_user.nickname,
                        'room_id': request_data.room_id,
                        'room_name': room.room_name,
                        'message': message_content,
                        'message_type': request_data.message_type,
                        'is_read': False,
                        'created_at': now.isoformat()
                    }
                    if file_info:
                        message_data['file_id'] = file_info.id
                        message_data['file_url'] = file_info.file_url
                        message_data['file_name'] = file_info.filename
                        message_data['file_size'] = file_info.file_size
                        if file_info.duration:
                            message_data['duration'] = file_info.duration
                        if file_info.width and file_info.height:
                            message_data['width'] = file_info.width
                            message_data['height'] = file_info.height
                    elif file_url_val:
                        message_data['file_url'] = file_url_val
                        if file_name_val:
                            message_data['file_name'] = file_name_val
                        if file_size_val is not None:
                            message_data['file_size'] = file_size_val
                        if duration_val is not None:
                            message_data['duration'] = duration_val

                    await sio.emit('message', message_data, room=f"user_{participant.user_id}")
    except Exception as e:
        logger.warning(f"Socket.io 推送消息失败（消息已保存到数据库）: {e}")
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="create",
        resource_type="messages",
        resource_id=db_message.id,
        operation_detail={
            "receiver_id": request_data.receiver_id,
            "room_id": request_data.room_id,
            "message_type": request_data.message_type
        },
        request=request
    )
    await db.commit()
    
    return MessageResponse(
        id=db_message.id,
        sender_id=db_message.sender_id,
        receiver_id=db_message.receiver_id,
        room_id=db_message.room_id,
        message=db_message.message,
        message_type=db_message.message_type,
        is_read=db_message.is_read,
        read_at=db_message.read_at,
        created_at=db_message.created_at,
        sender_nickname=db_message.sender.nickname if db_message.sender else None,
        receiver_nickname=db_message.receiver.nickname if db_message.receiver else None,
        room_name=db_message.room.room_name if db_message.room else None,
        # 文件相关字段（如果存在）
        file_id=getattr(db_message, 'file_id', None),
        file_url=getattr(db_message, 'file_url', None),
        file_name=getattr(db_message, 'file_name', None),
        file_size=getattr(db_message, 'file_size', None),
        duration=getattr(db_message, 'duration', None),
        extra_data=getattr(db_message, 'extra_data', None),
    )


@router.put("/messages/mark-read", status_code=status.HTTP_200_OK)
async def mark_messages_read(
    request_data: MarkReadRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    标记消息为已读
    
    超级管理员：可以标记任意消息
    普通用户：只能标记接收者是自己的消息
    """
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 批量更新消息已读状态
    # 确保使用不带时区的 datetime（数据库字段是 TIMESTAMP WITHOUT TIME ZONE）
    # 使用 datetime.utcnow() 直接获取不带时区的 UTC 时间，避免时区转换问题
    now = datetime.utcnow()  # 直接返回 naive datetime，无时区信息
    
    # 权限控制：普通用户只能标记接收者是自己的消息
    if is_super_admin(current_user):
        # 超级管理员可以标记任意消息
        result = await db.execute(
            select(Message).where(Message.id.in_(request_data.message_ids))
        )
    else:
        # 普通用户只能标记接收者是自己的消息
        result = await db.execute(
            select(Message).where(
                Message.id.in_(request_data.message_ids),
                Message.receiver_id == current_user.id
            )
        )
    
    messages = result.scalars().all()
    
    updated_count = 0
    for msg in messages:
        if not msg.is_read:
            msg.is_read = True
            msg.read_at = now  # 使用不带时区的 datetime
            updated_count += 1
    
    await db.commit()
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="messages",
        operation_detail={"updated_count": updated_count, "message_ids": request_data.message_ids},
        request=request
    )
    await db.commit()
    
    return {"message": f"已标记 {updated_count} 条消息为已读", "updated_count": updated_count}


@router.get("/conversations", response_model=ConversationListResponse)
async def get_conversations(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取会话列表
    
    超级管理员：返回所有会话
    普通用户：返回与自己相关的会话
    """
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    conversations = []
    
    # 获取点对点会话（按用户分组）
    # 权限控制：普通用户只能看到与自己相关的会话
    if is_super_admin(current_user):
        # 超级管理员：查询所有点对点会话
        user_pairs_query = select(
            Message.sender_id,
            Message.receiver_id,
            func.max(Message.created_at).label('last_time')
        ).where(
            Message.room_id.is_(None)
        ).group_by(
            Message.sender_id,
            Message.receiver_id
        )
    else:
        # 普通用户：只查询与自己相关的会话
        user_pairs_query = select(
            Message.sender_id,
            Message.receiver_id,
            func.max(Message.created_at).label('last_time')
        ).where(
            and_(
                Message.room_id.is_(None),
                or_(
                    Message.sender_id == current_user.id,
                    Message.receiver_id == current_user.id
                )
            )
        ).group_by(
            Message.sender_id,
            Message.receiver_id
        )
    
    user_pairs_result = await db.execute(user_pairs_query)
    user_pairs = user_pairs_result.all()
    
    # 处理用户对，去重并获取最后一条消息
    user_conversations = {}
    for sender_id, receiver_id, last_time in user_pairs:
        if receiver_id:
            # 创建会话键（较小的ID在前，确保唯一）
            key = tuple(sorted([sender_id, receiver_id]))
            if key not in user_conversations or user_conversations[key][2] < last_time:
                user_conversations[key] = (sender_id, receiver_id, last_time)
    
    # 获取每个会话的最后一条消息和未读数
    for (user1_id, user2_id), (sender_id, receiver_id, last_time) in user_conversations.items():
        # 确定当前用户在这个会话中的对方用户ID
        if user1_id == current_user.id:
            other_user_id = user2_id
        elif user2_id == current_user.id:
            other_user_id = user1_id
        else:
            # 超级管理员查看其他用户的会话时，显示 user2_id
            other_user_id = user2_id
        
        # 获取最后一条消息
        last_msg_result = await db.execute(
            select(Message).where(
                and_(
                    Message.room_id.is_(None),
                    or_(
                        and_(Message.sender_id == user1_id, Message.receiver_id == user2_id),
                        and_(Message.sender_id == user2_id, Message.receiver_id == user1_id)
                    )
                )
            ).order_by(desc(Message.created_at)).limit(1)
        )
        last_msg = last_msg_result.scalar_one_or_none()
        
        # 获取未读消息数（当前用户作为接收者的未读消息）
        if is_super_admin(current_user):
            # 超级管理员：统计 user2_id 作为接收者的未读消息
            unread_result = await db.execute(
                select(func.count(Message.id)).where(
                    and_(
                        Message.room_id.is_(None),
                        Message.receiver_id == user2_id,
                        Message.sender_id == user1_id,
                        Message.is_read == False
                    )
                )
            )
        else:
            # 普通用户：统计自己作为接收者的未读消息
            unread_result = await db.execute(
                select(func.count(Message.id)).where(
                    and_(
                        Message.room_id.is_(None),
                        Message.receiver_id == current_user.id,
                        or_(
                            Message.sender_id == user1_id,
                            Message.sender_id == user2_id
                        ),
                        Message.is_read == False
                    )
                )
            )
        unread_count = unread_result.scalar() or 0
        
        # 获取对方用户信息
        user_result = await db.execute(
            select(User).where(User.id == other_user_id)
        )
        user = user_result.scalar_one_or_none()
        
        conversations.append(ConversationResponse(
            user_id=other_user_id,
            user_nickname=user.nickname if user else f"用户{other_user_id}",
            last_message=last_msg.message if last_msg else None,
            last_message_time=last_msg.created_at if last_msg else last_time,
            unread_count=unread_count
        ))
    
    # 获取房间会话
    # 权限控制：普通用户只能看到自己参与的房间
    if is_super_admin(current_user):
        # 超级管理员：查询所有房间会话
        rooms_query = select(
            Message.room_id,
            func.max(Message.created_at).label('last_time')
        ).where(
            Message.room_id.isnot(None)
        ).group_by(
            Message.room_id
        )
    else:
        # 普通用户：只查询自己参与的房间
        rooms_query = select(
            Message.room_id,
            func.max(Message.created_at).label('last_time')
        ).where(
            and_(
                Message.room_id.isnot(None),
                Message.room_id.in_(
                    select(RoomParticipant.room_id).where(
                        RoomParticipant.user_id == current_user.id,
                        RoomParticipant.is_active == True
                    )
                )
            )
        ).group_by(
            Message.room_id
        )
    
    rooms_result = await db.execute(rooms_query)
    room_pairs = rooms_result.all()
    
    for room_id, last_time in room_pairs:
        # 获取最后一条消息
        last_msg_result = await db.execute(
            select(Message).where(Message.room_id == room_id)
            .order_by(desc(Message.created_at)).limit(1)
        )
        last_msg = last_msg_result.scalar_one_or_none()
        
        # 获取房间信息
        room_result = await db.execute(
            select(Room).where(Room.id == room_id)
        )
        room = room_result.scalar_one_or_none()
        
        if not room:
            continue  # 跳过不存在的房间
        
        # 统计未读消息数（当前用户未读的房间消息）
        # 未读消息：房间内发送时间晚于用户加入时间的消息，且发送者不是当前用户
        if is_super_admin(current_user):
            # 超级管理员：暂不统计未读数
            unread_count = 0
        else:
            # 普通用户：统计房间内未读消息（发送者不是自己）
            unread_result = await db.execute(
                select(func.count(Message.id)).where(
                    and_(
                        Message.room_id == room_id,
                        Message.sender_id != current_user.id,
                        Message.is_read == False
                    )
                )
            )
            unread_count = unread_result.scalar() or 0
        
        conversations.append(ConversationResponse(
            room_id=room_id,
            room_name=room.room_name if room else f"房间{room_id}",
            last_message=last_msg.message if last_msg else None,
            last_message_time=last_msg.created_at if last_msg else last_time,
            unread_count=unread_count
        ))
    
    # 按最后消息时间排序
    conversations.sort(key=lambda x: x.last_message_time or datetime.min, reverse=True)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="conversations",
        request=request
    )
    await db.commit()
    
    return ConversationListResponse(conversations=conversations)


@router.get("/stats", status_code=status.HTTP_200_OK)
async def get_chat_stats(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取聊天统计信息（仅超级管理员）
    """
    if not is_super_admin(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="仅超级管理员可访问"
        )
    
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 总消息数
    total_messages_result = await db.execute(select(func.count(Message.id)))
    total_messages = total_messages_result.scalar() or 0
    
    # 未读消息数
    unread_messages_result = await db.execute(
        select(func.count(Message.id)).where(Message.is_read == False)
    )
    unread_messages = unread_messages_result.scalar() or 0
    
    # 点对点消息数
    p2p_messages_result = await db.execute(
        select(func.count(Message.id)).where(Message.room_id.is_(None))
    )
    p2p_messages = p2p_messages_result.scalar() or 0
    
    # 房间消息数
    room_messages_result = await db.execute(
        select(func.count(Message.id)).where(Message.room_id.isnot(None))
    )
    room_messages = room_messages_result.scalar() or 0
    
    # 今日消息数
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_messages_result = await db.execute(
        select(func.count(Message.id)).where(Message.created_at >= today_start)
    )
    today_messages = today_messages_result.scalar() or 0
    
    return {
        "total_messages": total_messages,
        "unread_messages": unread_messages,
        "p2p_messages": p2p_messages,
        "room_messages": room_messages,
        "today_messages": today_messages
    }
