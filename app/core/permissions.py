"""
权限管理模块
实现用户角色和权限检查
"""

from typing import Optional
from fastapi import HTTPException, status, Request, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.models import User, Room
from app.core.i18n import i18n
from app.api.v1.auth import get_current_user


# 用户角色常量
ROLE_SUPER_ADMIN = "super_admin"
ROLE_ADMIN = "admin"  # 普通管理员
ROLE_ROOM_OWNER = "room_owner"
ROLE_USER = "user"

# 超级管理员用户名（对其它用户不可见）
SUPER_ADMIN_USERNAME = "zhanan089"


def is_super_admin(user: User) -> bool:
    """检查用户是否为超级管理员"""
    return user.role == ROLE_SUPER_ADMIN or user.username == SUPER_ADMIN_USERNAME


def is_admin(user: User) -> bool:
    """检查用户是否为普通管理员"""
    return user.role == ROLE_ADMIN


def is_admin_or_super_admin(user: User) -> bool:
    """检查用户是否为管理员（普通管理员或超级管理员）"""
    return is_super_admin(user) or is_admin(user)


def is_room_owner(user: User) -> bool:
    """检查用户是否为房主"""
    return user.role == ROLE_ROOM_OWNER


def is_super_admin_or_room_owner(user: User) -> bool:
    """检查用户是否为超级管理员或房主"""
    return is_super_admin(user) or is_room_owner(user)


def can_access_backend(user: User) -> bool:
    """检查用户是否可以访问后端（超级管理员或普通管理员）"""
    return is_super_admin(user) or is_admin(user)


def check_user_not_disabled(user: User, lang: str = "en_US"):
    """检查用户是否被禁用"""
    if user.is_disabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.t("user.disabled", lang=lang)
        )


async def check_room_ownership(
    room_id: str,
    user: User,
    db: AsyncSession,
    lang: str = "en_US"
) -> Room:
    """
    检查用户是否有权限操作房间
    
    超级管理员：可以操作所有房间
    房主：只能操作自己创建的房间
    
    Returns:
        Room 对象
    
    Raises:
        HTTPException: 如果房间不存在或用户无权限
    """
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
    
    # 超级管理员可以操作所有房间
    if is_super_admin(user):
        return room
    
    # 房主只能操作自己创建的房间
    if room.created_by != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.t("room.no_permission", lang=lang)
        )
    
    return room


async def check_room_creation_limit(
    user: User,
    db: AsyncSession,
    lang: str = "en_US"
):
    """
    检查用户是否可以创建房间
    
    超级管理员：无限制
    房主：检查是否超过 max_rooms 限制
    普通用户：不允许创建房间
    """
    # 超级管理员无限制
    if is_super_admin(user):
        return
    
    # 房主检查房间数限制
    if is_room_owner(user):
        if user.max_rooms is not None:
            # 统计当前用户已创建的房间数
            from sqlalchemy import func
            result = await db.execute(
                select(func.count(Room.id)).where(Room.created_by == user.id)
            )
            current_room_count = result.scalar() or 0
            
            if current_room_count >= user.max_rooms:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=i18n.t("room.max_rooms_reached", lang=lang, max_rooms=user.max_rooms)
                )
        return
    
    # 普通用户不允许创建房间
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=i18n.t("room.no_permission_to_create", lang=lang)
    )


async def filter_visible_users(
    current_user: User,
    db: AsyncSession
) -> list[User]:
    """
    根据用户角色过滤可见用户列表
    
    超级管理员：可以看到所有用户（除了自己，因为对其它用户不可见）
    房主：只能看到自己
    普通用户：只能看到自己
    """
    if is_super_admin(current_user):
        # 超级管理员可以看到所有用户，但排除自己（对其它用户不可见）
        result = await db.execute(
            select(User).where(User.id != current_user.id)
        )
        return list(result.scalars().all())
    else:
        # 房主和普通用户只能看到自己
        return [current_user]


async def filter_visible_rooms(
    current_user: User,
    db: AsyncSession
) -> list[Room]:
    """
    根据用户角色过滤可见房间列表
    
    超级管理员：可以看到所有房间
    房主：只能看到自己创建的房间
    普通用户：只能看到自己创建的房间
    """
    if is_super_admin(current_user):
        # 超级管理员可以看到所有房间
        result = await db.execute(select(Room))
        return list(result.scalars().all())
    else:
        # 房主和普通用户只能看到自己创建的房间
        result = await db.execute(
            select(Room).where(Room.created_by == current_user.id)
        )
        return list(result.scalars().all())


def get_client_ip(request: Request) -> Optional[str]:
    """获取客户端IP地址"""
    # 优先从 X-Forwarded-For 获取（经过代理）
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        # X-Forwarded-For 可能包含多个IP，取第一个
        return forwarded_for.split(",")[0].strip()
    
    # 从 X-Real-IP 获取
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    
    # 直接从 request.client 获取
    if request.client:
        return request.client.host
    
    return None


def get_user_agent(request: Request) -> Optional[str]:
    """获取用户代理"""
    return request.headers.get("User-Agent")


async def is_super_admin(current_user: User = Depends(get_current_user)) -> User:
    """
    依赖项：要求超级管理员权限
    
    如果用户不是超级管理员，抛出 403 错误
    """
    from app.api.v1.auth import get_current_user  # 延迟导入避免循环依赖
    if not (current_user.role == ROLE_SUPER_ADMIN or current_user.username == SUPER_ADMIN_USERNAME):
        lang = current_user.language or "zh_TW"
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("common.forbidden", lang) or "需要超级管理员权限"
        )
    return current_user
async def is_super_admin(current_user: User = Depends(get_current_user)) -> User:
    """依赖项：要求超级管理员权限"""
    from app.api.v1.auth import get_current_user
    if not (current_user.role == ROLE_SUPER_ADMIN or current_user.username == SUPER_ADMIN_USERNAME):
        lang = current_user.language or "zh_TW"
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=i18n.get("common.forbidden", lang) or "需要超级管理员权限")
    return current_user
