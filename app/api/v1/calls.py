"""
通话记录 API
包含通话记录的创建、查询、统计功能
"""

from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_, desc
from sqlalchemy.orm import selectinload
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.permissions import check_user_not_disabled
from app.db.session import get_db
from app.db.models import User, Call, Room, RoomParticipant
from app.api.v1.auth import get_current_user
from loguru import logger

router = APIRouter()


# ==================== 请求/响应模型 ====================

class CallResponse(BaseModel):
    """通话记录响应模型"""
    id: int
    call_type: str
    call_status: str
    caller_id: int
    callee_id: Optional[int]
    room_id: Optional[int]
    jitsi_room_id: str
    start_time: Optional[str]
    end_time: Optional[str]
    duration: Optional[int]
    created_at: str
    caller_nickname: Optional[str] = None
    callee_nickname: Optional[str] = None
    room_name: Optional[str] = None
    
    class Config:
        from_attributes = True


class CallCreate(BaseModel):
    """创建通话记录请求模型"""
    call_type: str = Field(..., description="通话类型：video/audio")
    call_status: str = Field(default="initiated", description="通话状态：initiated/ringing/connected/ended/rejected/missed")
    callee_id: Optional[int] = Field(None, description="接收者用户ID（点对点通话）")
    room_id: Optional[int] = Field(None, description="房间ID（房间通话）")
    jitsi_room_id: str = Field(..., description="Jitsi房间ID")


class CallUpdate(BaseModel):
    """更新通话记录请求模型"""
    call_status: Optional[str] = Field(None, description="通话状态")
    start_time: Optional[datetime] = Field(None, description="通话开始时间")
    end_time: Optional[datetime] = Field(None, description="通话结束时间")
    duration: Optional[int] = Field(None, description="通话时长（秒）")


class CallStatsResponse(BaseModel):
    """通话统计响应模型"""
    total_calls: int
    total_duration: int  # 总时长（秒）
    video_calls: int
    audio_calls: int
    connected_calls: int
    missed_calls: int


# ==================== API 路由 ====================

@router.post("/", response_model=CallResponse, status_code=status.HTTP_201_CREATED)
async def create_call(
    call_data: CallCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    创建通话记录
    
    当用户加入房间时，自动创建通话记录
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 验证房间是否存在（如果提供了房间ID）
    if call_data.room_id:
        room_result = await db.execute(
            select(Room).where(Room.id == call_data.room_id)
        )
        room = room_result.scalar_one_or_none()
        if not room:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=i18n.t("room.not_found", lang=lang)
            )
    
    # 创建通话记录
    new_call = Call(
        call_type=call_data.call_type,
        call_status=call_data.call_status,
        caller_id=current_user.id,
        callee_id=call_data.callee_id,
        room_id=call_data.room_id,
        jitsi_room_id=call_data.jitsi_room_id,
        start_time=datetime.utcnow() if call_data.call_status == "connected" else None,
        created_at=datetime.utcnow()
    )
    
    db.add(new_call)
    await db.commit()
    await db.refresh(new_call)
    
    # 加载关联数据
    await db.refresh(new_call, ["caller", "callee", "room"])
    
    return CallResponse(
        id=new_call.id,
        call_type=new_call.call_type,
        call_status=new_call.call_status,
        caller_id=new_call.caller_id,
        callee_id=new_call.callee_id,
        room_id=new_call.room_id,
        jitsi_room_id=new_call.jitsi_room_id,
        start_time=new_call.start_time.isoformat() if new_call.start_time else None,
        end_time=new_call.end_time.isoformat() if new_call.end_time else None,
        duration=new_call.duration,
        created_at=new_call.created_at.isoformat(),
        caller_nickname=new_call.caller.nickname if new_call.caller else None,
        callee_nickname=new_call.callee.nickname if new_call.callee else None,
        room_name=new_call.room.room_name if new_call.room else None,
    )


@router.get("/", response_model=List[CallResponse])
async def get_calls(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0, description="跳过记录数"),
    limit: int = Query(100, ge=1, le=100, description="返回记录数"),
    call_type: Optional[str] = Query(None, description="过滤通话类型：video/audio"),
    call_status: Optional[str] = Query(None, description="过滤通话状态"),
):
    """
    获取通话记录列表
    
    用户可以查看自己作为发起者或接收者的通话记录
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建查询条件：用户是发起者或接收者
    conditions = [
        or_(
            Call.caller_id == current_user.id,
            Call.callee_id == current_user.id
        )
    ]
    
    # 添加过滤条件
    if call_type:
        conditions.append(Call.call_type == call_type)
    if call_status:
        conditions.append(Call.call_status == call_status)
    
    # 执行查询
    query = select(Call).where(
        and_(*conditions)
    ).order_by(desc(Call.created_at)).offset(skip).limit(limit)
    
    result = await db.execute(query.options(
        selectinload(Call.caller),
        selectinload(Call.callee),
        selectinload(Call.room)
    ))
    calls = result.scalars().all()
    
    # 构建响应
    call_responses = []
    for call in calls:
        call_responses.append(CallResponse(
            id=call.id,
            call_type=call.call_type,
            call_status=call.call_status,
            caller_id=call.caller_id,
            callee_id=call.callee_id,
            room_id=call.room_id,
            jitsi_room_id=call.jitsi_room_id,
            start_time=call.start_time.isoformat() if call.start_time else None,
            end_time=call.end_time.isoformat() if call.end_time else None,
            duration=call.duration,
            created_at=call.created_at.isoformat(),
            caller_nickname=call.caller.nickname if call.caller else None,
            callee_nickname=call.callee.nickname if call.callee else None,
            room_name=call.room.room_name if call.room else None,
        ))
    
    return call_responses


@router.get("/{call_id}", response_model=CallResponse)
async def get_call(
    call_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取通话记录详情
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查询通话记录
    result = await db.execute(
        select(Call).where(Call.id == call_id).options(
            selectinload(Call.caller),
            selectinload(Call.callee),
            selectinload(Call.room)
        )
    )
    call = result.scalar_one_or_none()
    
    if not call:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("call.not_found", lang=lang) or "通话记录不存在"
        )
    
    # 检查权限：用户必须是发起者或接收者
    if call.caller_id != current_user.id and call.callee_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.t("call.access_denied", lang=lang) or "无权访问此通话记录"
        )
    
    return CallResponse(
        id=call.id,
        call_type=call.call_type,
        call_status=call.call_status,
        caller_id=call.caller_id,
        callee_id=call.callee_id,
        room_id=call.room_id,
        jitsi_room_id=call.jitsi_room_id,
        start_time=call.start_time.isoformat() if call.start_time else None,
        end_time=call.end_time.isoformat() if call.end_time else None,
        duration=call.duration,
        created_at=call.created_at.isoformat(),
        caller_nickname=call.caller.nickname if call.caller else None,
        callee_nickname=call.callee.nickname if call.callee else None,
        room_name=call.room.room_name if call.room else None,
    )


@router.put("/{call_id}", response_model=CallResponse)
async def update_call(
    call_id: int,
    call_data: CallUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新通话记录
    
    用于更新通话状态、开始时间、结束时间和时长
    通常在用户离开房间时调用
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查询通话记录
    result = await db.execute(select(Call).where(Call.id == call_id))
    call = result.scalar_one_or_none()
    
    if not call:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("call.not_found", lang=lang) or "通话记录不存在"
        )
    
    # 检查权限：用户必须是发起者或接收者
    if call.caller_id != current_user.id and call.callee_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.t("call.access_denied", lang=lang) or "无权访问此通话记录"
        )
    
    # 更新字段
    if call_data.call_status is not None:
        call.call_status = call_data.call_status
    if call_data.start_time is not None:
        call.start_time = call_data.start_time
    if call_data.end_time is not None:
        call.end_time = call_data.end_time
    if call_data.duration is not None:
        call.duration = call_data.duration
    elif call.start_time and call.end_time:
        # 自动计算时长
        duration_delta = call.end_time - call.start_time
        call.duration = int(duration_delta.total_seconds())
    
    await db.commit()
    await db.refresh(call)
    
    # 加载关联数据
    await db.refresh(call, ["caller", "callee", "room"])
    
    return CallResponse(
        id=call.id,
        call_type=call.call_type,
        call_status=call.call_status,
        caller_id=call.caller_id,
        callee_id=call.callee_id,
        room_id=call.room_id,
        jitsi_room_id=call.jitsi_room_id,
        start_time=call.start_time.isoformat() if call.start_time else None,
        end_time=call.end_time.isoformat() if call.end_time else None,
        duration=call.duration,
        created_at=call.created_at.isoformat(),
        caller_nickname=call.caller.nickname if call.caller else None,
        callee_nickname=call.callee.nickname if call.callee else None,
        room_name=call.room.room_name if call.room else None,
    )


@router.get("/stats/summary", response_model=CallStatsResponse)
async def get_call_stats(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取通话统计信息
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查询条件：用户是发起者或接收者
    base_condition = or_(
        Call.caller_id == current_user.id,
        Call.callee_id == current_user.id
    )
    
    # 总通话数
    total_result = await db.execute(
        select(func.count(Call.id)).where(base_condition)
    )
    total_calls = total_result.scalar() or 0
    
    # 视频通话数
    video_result = await db.execute(
        select(func.count(Call.id)).where(
            and_(base_condition, Call.call_type == "video")
        )
    )
    video_calls = video_result.scalar() or 0
    
    # 音频通话数
    audio_result = await db.execute(
        select(func.count(Call.id)).where(
            and_(base_condition, Call.call_type == "audio")
        )
    )
    audio_calls = audio_result.scalar() or 0
    
    # 已接通通话数
    connected_result = await db.execute(
        select(func.count(Call.id)).where(
            and_(base_condition, Call.call_status == "connected")
        )
    )
    connected_calls = connected_result.scalar() or 0
    
    # 未接通话数
    missed_result = await db.execute(
        select(func.count(Call.id)).where(
            and_(base_condition, Call.call_status == "missed")
        )
    )
    missed_calls = missed_result.scalar() or 0
    
    # 总时长
    duration_result = await db.execute(
        select(func.sum(Call.duration)).where(
            and_(base_condition, Call.duration.isnot(None))
        )
    )
    total_duration = int(duration_result.scalar() or 0)
    
    return CallStatsResponse(
        total_calls=total_calls,
        total_duration=total_duration,
        video_calls=video_calls,
        audio_calls=audio_calls,
        connected_calls=connected_calls,
        missed_calls=missed_calls,
    )
