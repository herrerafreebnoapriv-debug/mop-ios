"""
管理员API
超级管理员专用功能：房主管理、用户管理、操作日志查看
"""

from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import selectinload
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.permissions import (
    is_super_admin, check_user_not_disabled,
    filter_visible_users, ROLE_ROOM_OWNER, SUPER_ADMIN_USERNAME
)
from app.core.operation_log import log_operation
from app.core.security import get_password_hash
from app.db.session import get_db
from app.db.models import User, Room, OperationLog, SystemConfig
from app.api.v1.auth import get_current_user
from loguru import logger

router = APIRouter()


# ==================== 请求/响应模型 ====================

class RoomOwnerCreate(BaseModel):
    """创建房主请求模型"""
    phone: str = Field(..., description="手机号")
    username: Optional[str] = Field(None, max_length=100, description="用户名")
    password: str = Field(..., min_length=6, description="密码")
    nickname: Optional[str] = Field(None, max_length=100, description="昵称")
    max_rooms: Optional[int] = Field(None, ge=1, description="最大可创建房间数（None表示无限制）")
    default_max_occupants: int = Field(3, ge=1, le=100, description="房间默认最大人数上限")


class RoomOwnerUpdate(BaseModel):
    """更新房主请求模型"""
    max_rooms: Optional[int] = Field(None, ge=1, description="最大可创建房间数（None表示无限制）")
    default_max_occupants: Optional[int] = Field(None, ge=1, le=100, description="房间默认最大人数上限")
    is_disabled: Optional[bool] = Field(None, description="是否禁用")


class UserResponse(BaseModel):
    """用户响应模型"""
    id: int
    phone: str
    username: Optional[str]
    nickname: Optional[str]
    role: str
    max_rooms: Optional[int]
    default_max_occupants: Optional[int]
    is_disabled: bool
    created_at: str
    updated_at: str
    
    class Config:
        from_attributes = True


class OperationLogResponse(BaseModel):
    """操作日志响应模型"""
    id: int
    user_id: Optional[int]
    username: Optional[str]
    operation_type: str
    resource_type: str
    resource_id: Optional[int]
    resource_name: Optional[str]
    operation_detail: Optional[str]
    ip_address: Optional[str]
    user_agent: Optional[str]
    created_at: str
    
    class Config:
        from_attributes = True


# ==================== 权限检查 ====================

def require_super_admin(current_user: User):
    """要求超级管理员权限"""
    if not is_super_admin(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="仅超级管理员可访问"
        )


# ==================== API 路由 ====================

class SystemStatsResponse(BaseModel):
    """系统统计响应模型"""
    total_users: int = Field(..., description="总用户数")
    online_users: int = Field(..., description="在线用户数")
    total_devices: int = Field(..., description="总设备数")
    total_rooms: int = Field(..., description="总房间数")
    active_rooms: int = Field(..., description="活跃房间数")
    total_invitations: int = Field(..., description="总邀请码数")
    active_invitations: int = Field(..., description="有效邀请码数")


@router.get("/stats", response_model=SystemStatsResponse)
async def get_system_stats(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取系统统计信息（仅超级管理员）
    
    返回用户数、设备数、房间数等统计信息
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 统计用户数
    from sqlalchemy import func
    total_users_result = await db.execute(select(func.count(User.id)))
    total_users = total_users_result.scalar() or 0
    
    # 统计在线用户数
    online_users_result = await db.execute(
        select(func.count(User.id)).where(User.is_online == True)
    )
    online_users = online_users_result.scalar() or 0
    
    # 统计设备数
    from app.db.models import UserDevice
    total_devices_result = await db.execute(select(func.count(UserDevice.id)))
    total_devices = total_devices_result.scalar() or 0
    
    # 统计房间数
    from app.db.models import Room
    total_rooms_result = await db.execute(select(func.count(Room.id)))
    total_rooms = total_rooms_result.scalar() or 0
    
    # 统计活跃房间数
    active_rooms_result = await db.execute(
        select(func.count(Room.id)).where(Room.is_active == True)
    )
    active_rooms = active_rooms_result.scalar() or 0
    
    # 统计邀请码数
    from app.db.models import InvitationCode
    total_invitations_result = await db.execute(select(func.count(InvitationCode.id)))
    total_invitations = total_invitations_result.scalar() or 0
    
    # 统计有效邀请码数
    active_invitations_result = await db.execute(
        select(func.count(InvitationCode.id)).where(
            and_(
                InvitationCode.is_active == True,
                InvitationCode.is_revoked == False
            )
        )
    )
    active_invitations = active_invitations_result.scalar() or 0
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="system_stats",
        request=request
    )
    await db.commit()
    
    return SystemStatsResponse(
        total_users=total_users,
        online_users=online_users,
        total_devices=total_devices,
        total_rooms=total_rooms,
        active_rooms=active_rooms,
        total_invitations=total_invitations,
        active_invitations=active_invitations
    )


@router.post("/room-owners", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_room_owner(
    owner_data: RoomOwnerCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    创建房主（仅超级管理员）
    
    超级管理员可以创建房主，并设置房主可拥有的房间数和房间人数上限
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 检查手机号是否已存在
    result = await db.execute(
        select(User).where(User.phone == owner_data.phone)
    )
    existing_user = result.scalar_one_or_none()
    
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("user.phone_exists", lang=lang)
        )
    
    # 创建房主用户
    new_owner = User(
        phone=owner_data.phone,
        username=owner_data.username,
        password_hash=get_password_hash(owner_data.password),
        nickname=owner_data.nickname,
        role=ROLE_ROOM_OWNER,
        max_rooms=owner_data.max_rooms,
        default_max_occupants=owner_data.default_max_occupants,
        is_disabled=False,
        language="en_US"
    )
    
    db.add(new_owner)
    await db.commit()
    await db.refresh(new_owner)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="create",
        resource_type="user",
        resource_id=new_owner.id,
        resource_name=new_owner.username or new_owner.phone,
        operation_detail={
            "role": ROLE_ROOM_OWNER,
            "max_rooms": owner_data.max_rooms,
            "default_max_occupants": owner_data.default_max_occupants
        },
        request=request
    )
    await db.commit()
    
    return UserResponse(
        id=new_owner.id,
        phone=new_owner.phone,
        username=new_owner.username,
        nickname=new_owner.nickname,
        role=new_owner.role or "user",
        max_rooms=new_owner.max_rooms,
        default_max_occupants=new_owner.default_max_occupants or 3,
        is_disabled=new_owner.is_disabled or False,
        created_at=new_owner.created_at.isoformat(),
        updated_at=new_owner.updated_at.isoformat()
    )


@router.get("/room-owners", response_model=List[UserResponse])
async def list_room_owners(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=100)
):
    """
    获取房主列表（仅超级管理员）
    
    超级管理员可以查看所有房主
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查询所有房主（排除超级管理员自己）
    result = await db.execute(
        select(User)
        .where(
            and_(
                User.role == ROLE_ROOM_OWNER,
                User.username != SUPER_ADMIN_USERNAME
            )
        )
        .order_by(User.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    owners = result.scalars().all()
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="user",
        operation_detail={"filter": "room_owners"},
        request=request
    )
    await db.commit()
    
    return [
        UserResponse(
            id=owner.id,
            phone=owner.phone,
            username=owner.username,
            nickname=owner.nickname,
            role=owner.role or "user",
            max_rooms=owner.max_rooms,
            default_max_occupants=owner.default_max_occupants or 3,
            is_disabled=owner.is_disabled or False,
            created_at=owner.created_at.isoformat(),
            updated_at=owner.updated_at.isoformat()
        )
        for owner in owners
    ]


@router.put("/room-owners/{owner_id}", response_model=UserResponse)
async def update_room_owner(
    owner_id: int,
    owner_data: RoomOwnerUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新房主信息（仅超级管理员）
    
    可以设置房主可拥有的房间数和房间人数上限，禁用房主
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查找房主
    result = await db.execute(
        select(User).where(
            and_(
                User.id == owner_id,
                User.role == ROLE_ROOM_OWNER
            )
        )
    )
    owner = result.scalar_one_or_none()
    
    if not owner:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("user.not_found", lang=lang)
        )
    
    # 记录更新前的值
    old_values = {
        "max_rooms": owner.max_rooms,
        "default_max_occupants": owner.default_max_occupants,
        "is_disabled": owner.is_disabled
    }
    
    # 更新字段
    if owner_data.max_rooms is not None:
        owner.max_rooms = owner_data.max_rooms
    if owner_data.default_max_occupants is not None:
        owner.default_max_occupants = owner_data.default_max_occupants
    if owner_data.is_disabled is not None:
        owner.is_disabled = owner_data.is_disabled
    
    await db.commit()
    await db.refresh(owner)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="user",
        resource_id=owner.id,
        resource_name=owner.username or owner.phone,
        operation_detail={
            "old_values": old_values,
            "new_values": {
                "max_rooms": owner.max_rooms,
                "default_max_occupants": owner.default_max_occupants,
                "is_disabled": owner.is_disabled
            }
        },
        request=request
    )
    await db.commit()
    
    return UserResponse(
        id=owner.id,
        phone=owner.phone,
        username=owner.username,
        nickname=owner.nickname,
        role=owner.role or "user",
        max_rooms=owner.max_rooms,
        default_max_occupants=owner.default_max_occupants or 3,
        is_disabled=owner.is_disabled or False,
        created_at=owner.created_at.isoformat(),
        updated_at=owner.updated_at.isoformat()
    )


@router.put("/users/{user_id}/disable", response_model=UserResponse)
async def toggle_user_status(
    user_id: int,
    is_disabled: bool = Query(..., description="是否禁用（True=禁用，False=启用）"),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    切换用户状态（禁用/启用）（仅超级管理员）
    
    超级管理员可以禁用/启用任何用户（包括房主），但不能操作自己和超级管理员
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 不能操作自己
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="不能操作自己的账户状态"
        )
    
    # 查找用户
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("user.not_found", lang=lang)
        )
    
    # 不能禁用超级管理员
    if is_super_admin(user) and is_disabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="不能禁用超级管理员"
        )
    
    user.is_disabled = is_disabled
    await db.commit()
    await db.refresh(user)
    
    # 记录操作日志
    action = "disable" if is_disabled else "enable"
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="user",
        resource_id=user.id,
        resource_name=user.username or user.phone,
        operation_detail={"action": action},
        request=request
    )
    await db.commit()
    
    return UserResponse(
        id=user.id,
        phone=user.phone,
        username=user.username,
        nickname=user.nickname,
        role=user.role or "user",
        max_rooms=user.max_rooms,
        default_max_occupants=user.default_max_occupants or 3,
        is_disabled=user.is_disabled or False,
        created_at=user.created_at.isoformat(),
        updated_at=user.updated_at.isoformat()
    )


@router.put("/rooms/{room_id}/disable", response_model=dict)
async def disable_room(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    禁用房间（仅超级管理员）
    
    超级管理员可以禁用任何房间
    """
    require_super_admin(current_user)
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
    
    room.is_active = False
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
        operation_detail={"action": "disable"},
        request=request
    )
    await db.commit()
    
    return {"message": "房间已禁用", "room_id": room_id}


@router.delete("/rooms/{room_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_room(
    room_id: str,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除房间（仅超级管理员）
    
    超级管理员可以删除任何房间
    """
    require_super_admin(current_user)
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


@router.get("/operation-logs", response_model=List[OperationLogResponse])
async def list_operation_logs(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    operation_type: Optional[str] = Query(None, description="操作类型：create/read/update/delete"),
    resource_type: Optional[str] = Query(None, description="资源类型：user/room/device等"),
    user_id: Optional[int] = Query(None, description="操作用户ID")
):
    """
    获取操作日志列表（仅超级管理员）
    
    记录所有增删改查操作的时间和IP
    """
    require_super_admin(current_user)
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建查询条件
    conditions = []
    if operation_type:
        conditions.append(OperationLog.operation_type == operation_type)
    if resource_type:
        conditions.append(OperationLog.resource_type == resource_type)
    if user_id:
        conditions.append(OperationLog.user_id == user_id)
    
    # 查询操作日志
    query = select(OperationLog)
    if conditions:
        query = query.where(and_(*conditions))
    query = query.order_by(OperationLog.created_at.desc()).offset(skip).limit(limit)
    
    result = await db.execute(query)
    logs = result.scalars().all()
    
    # 记录操作日志（查看日志本身）
    await log_operation(
        db=db,
        user=current_user,
        operation_type="read",
        resource_type="operation_log",
        operation_detail={"filters": {"operation_type": operation_type, "resource_type": resource_type, "user_id": user_id}},
        request=request
    )
    await db.commit()
    
    return [
        OperationLogResponse(
            id=log.id,
            user_id=log.user_id,
            username=log.username,
            operation_type=log.operation_type,
            resource_type=log.resource_type,
            resource_id=log.resource_id,
            resource_name=log.resource_name,
            operation_detail=log.operation_detail,
            ip_address=log.ip_address,
            user_agent=log.user_agent,
            created_at=log.created_at.isoformat()
        )
        for log in logs
    ]


# ==================== 系统配置管理 ====================

class SystemConfigResponse(BaseModel):
    """系统配置响应模型"""
    config_key: str
    config_value: str
    description: Optional[str] = None


class SystemConfigUpdate(BaseModel):
    """系统配置更新请求模型"""
    config_value: str = Field(..., description="配置值")


class SystemConfigListResponse(BaseModel):
    """系统配置列表响应模型"""
    configs: List[SystemConfigResponse]


@router.get("/system-configs", response_model=SystemConfigListResponse)
async def get_system_configs(
    request: Request,
    current_user = Depends(is_super_admin),  # 移除类型注解以修复 FastAPI 错误
    db: AsyncSession = Depends(get_db)
):
    """
    获取系统配置列表（仅超级管理员）
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(SystemConfig))
    configs = result.scalars().all()
    
    return {
        "configs": [
            {
                "config_key": c.config_key,
                "config_value": c.config_value or "",
                "description": c.description
            }
            for c in configs
        ]
    }


@router.put("/system-configs/{config_key}", response_model=SystemConfigResponse)
async def update_system_config(
    config_key: str,
    config_data: SystemConfigUpdate,
    request: Request,
    current_user = Depends(is_super_admin),  # 移除类型注解以修复 FastAPI 错误
    db: AsyncSession = Depends(get_db)
):
    """
    更新系统配置（仅超级管理员）
    
    特殊处理：二维码配置互斥逻辑
    - 启用加密二维码时，自动禁用未加密二维码
    - 启用未加密二维码时，自动禁用加密二维码
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(SystemConfig).where(SystemConfig.config_key == config_key))
    config = result.scalar_one_or_none()
    
    if not config:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("common.not_found", lang) or f"配置项 {config_key} 不存在"
        )
    
    # 二维码配置互斥逻辑
    if config_key == 'qrcode.encrypted_enabled' and config_data.config_value.lower() == 'true':
        # 启用加密二维码时，禁用未加密二维码
        plain_config_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.plain_enabled')
        )
        plain_config = plain_config_result.scalar_one_or_none()
        if plain_config and plain_config.config_value.lower() == 'true':
            plain_config.config_value = 'false'
            plain_config.updated_at = datetime.now()
            await db.commit()
            logger.info(f"自动禁用未加密二维码配置（因为启用了加密二维码）")
    elif config_key == 'qrcode.plain_enabled' and config_data.config_value.lower() == 'true':
        # 启用未加密二维码时，禁用加密二维码
        encrypted_config_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.encrypted_enabled')
        )
        encrypted_config = encrypted_config_result.scalar_one_or_none()
        if encrypted_config and encrypted_config.config_value.lower() == 'true':
            encrypted_config.config_value = 'false'
            encrypted_config.updated_at = datetime.now()
            await db.commit()
            logger.info(f"自动禁用加密二维码配置（因为启用了未加密二维码）")
    
    # 更新配置值
    config.config_value = config_data.config_value
    config.updated_at = datetime.now()
    await db.commit()
    await db.refresh(config)
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="system_config",
        resource_id=config.id,
        resource_name=config_key,
        operation_detail={"config_value": config_data.config_value},
        request=request
    )
    await db.commit()
    
    return {
        "config_key": config.config_key,
        "config_value": config.config_value or "",
        "description": config.description
    }
