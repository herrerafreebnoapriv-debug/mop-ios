"""
好友管理API模块
实现好友查找、添加、列表等功能
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
from app.db.models import User, Friendship, Notification
from app.api.v1.auth import get_current_user
from app.core.socketio import sio, connected_users, send_notification
from loguru import logger

router = APIRouter()


# ==================== 请求/响应模型 ====================

class FriendResponse(BaseModel):
    """好友响应模型"""
    user_id: int
    nickname: Optional[str] = None
    username: Optional[str] = None
    phone: Optional[str] = None
    is_online: bool = False
    status: str  # pending/accepted/blocked
    note: Optional[str] = None  # 备注
    created_at: datetime
    
    class Config:
        from_attributes = True


class FriendListResponse(BaseModel):
    """好友列表响应模型"""
    friends: List[FriendResponse]
    total: int


class SearchUserRequest(BaseModel):
    """搜索用户请求模型"""
    keyword: str = Field(..., min_length=1, max_length=100, description="搜索关键词（手机号或用户名，精确匹配）")


class AddFriendRequest(BaseModel):
    """添加好友请求模型"""
    friend_id: int = Field(..., description="要添加的好友ID")


class UpdateFriendshipRequest(BaseModel):
    """更新好友关系请求模型"""
    friend_id: int = Field(..., description="好友ID")
    status: str = Field(..., description="状态：accepted（接受）/blocked（屏蔽）")
    note: Optional[str] = Field(None, max_length=200, description="备注（可选）")


# ==================== API 路由 ====================

@router.get("/search", response_model=List[FriendResponse])
async def search_users(
    keyword: str = Query(..., min_length=1, max_length=100, description="搜索关键词（手机号或用户名，精确匹配）"),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    搜索用户（用于添加好友）
    
    隐私优化：仅支持通过手机号或用户名精确搜索，不支持模糊搜索和昵称搜索
    这样可以保护用户隐私，避免通过部分信息就能搜索到用户
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建搜索条件：仅支持手机号或用户名精确匹配（大小写不敏感）
    # 移除昵称搜索和模糊搜索，保护用户隐私
    # 使用 lower() 进行大小写不敏感匹配，但仍然是精确匹配（不是模糊搜索）
    keyword_lower = keyword.lower().strip()
    conditions = [
        or_(
            User.phone == keyword,  # 手机号精确匹配（保持原样，手机号通常不区分大小写）
            func.lower(User.username) == keyword_lower  # 用户名精确匹配（大小写不敏感）
        ),
        User.id != current_user.id,  # 排除自己
        User.is_disabled == False  # 排除禁用的用户
    ]
    
    # 查询用户（精确匹配，最多返回1个结果）
    result = await db.execute(
        select(User).where(and_(*conditions)).limit(1)
    )
    users = result.scalars().all()
    
    # 转换为响应模型
    user_list = []
    for user in users:
        # 检查是否已经是好友
        friendship_result = await db.execute(
            select(Friendship).where(
                or_(
                    and_(Friendship.user_id == current_user.id, Friendship.friend_id == user.id),
                    and_(Friendship.user_id == user.id, Friendship.friend_id == current_user.id)
                )
            )
        )
        friendship = friendship_result.scalar_one_or_none()
        
        status_str = "none"
        if friendship:
            status_str = friendship.status
        
        user_list.append(FriendResponse(
            user_id=user.id,
            nickname=user.nickname,
            username=user.username,
            phone=user.phone if is_super_admin(current_user) else None,  # 普通用户不显示手机号
            is_online=user.is_online or False,
            status=status_str,
            note=None,  # 搜索时没有备注
            created_at=user.created_at
        ))
    
    return user_list


@router.post("/add", status_code=status.HTTP_201_CREATED)
async def add_friend(
    request_data: AddFriendRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    发送好友请求
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 不能添加自己
    if request_data.friend_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("friends.cannot_add_self", lang)
        )
    
    # 检查目标用户是否存在
    friend_result = await db.execute(
        select(User).where(User.id == request_data.friend_id)
    )
    friend = friend_result.scalar_one_or_none()
    
    if not friend:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("user.not_found", lang)
        )
    
    if friend.is_disabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("friends.user_disabled", lang)
        )
    
    # 检查是否已经存在好友关系
    existing_result = await db.execute(
        select(Friendship).where(
            or_(
                and_(Friendship.user_id == current_user.id, Friendship.friend_id == request_data.friend_id),
                and_(Friendship.user_id == request_data.friend_id, Friendship.friend_id == current_user.id)
            )
        )
    )
    existing = existing_result.scalar_one_or_none()
    
    if existing:
        if existing.status == "accepted":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("friends.already_friends", lang)
            )
        elif existing.status == "blocked":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=i18n.get("friends.blocked", lang)
            )
        elif existing.status == "pending":
            if existing.user_id == current_user.id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=i18n.get("friends.request_already_sent", lang)
                )
            else:
                # 对方已发送请求，直接接受
                existing.status = "accepted"
                existing.updated_at = datetime.utcnow()
                await db.commit()
                
                # 创建通知
                notification = Notification(
                    user_id=request_data.friend_id,
                    type="friend_request",
                    title=i18n.get("friends.request_accepted", lang),
                    content=f"{current_user.nickname or current_user.username} 已接受您的好友请求",
                    related_user_id=current_user.id,
                    is_read=False
                )
                db.add(notification)
                await db.commit()
                
                # 通过 Socket.io 发送实时通知
                await send_notification(request_data.friend_id, {
                    "id": notification.id,
                    "type": "friend_request",
                    "title": notification.title,
                    "content": notification.content,
                    "related_user_id": current_user.id,
                    "created_at": notification.created_at.isoformat()
                })
                
                return {"message": i18n.get("friends.request_accepted", lang), "status": "accepted"}
    
    # 创建新的好友请求
    friendship = Friendship(
        user_id=current_user.id,
        friend_id=request_data.friend_id,
        status="pending"
    )
    db.add(friendship)
    await db.commit()
    await db.refresh(friendship)
    
    # 创建通知
    notification = Notification(
        user_id=request_data.friend_id,
        type="friend_request",
        title=i18n.get("friends.new_request", lang),
        content=f"{current_user.nickname or current_user.username} 想添加您为好友",
        related_user_id=current_user.id,
        is_read=False
    )
    db.add(notification)
    await db.commit()
    await db.refresh(notification)
    
    # 通过 Socket.io 发送实时通知
    await send_notification(request_data.friend_id, {
        "id": notification.id,
        "type": "friend_request",
        "title": notification.title,
        "content": notification.content,
        "related_user_id": current_user.id,
        "created_at": notification.created_at.isoformat()
    })
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="create",
        resource_type="friendships",
        resource_id=friendship.id,
        operation_detail={"friend_id": request_data.friend_id},
        request=request
    )
    await db.commit()
    
    return {"message": i18n.get("friends.request_sent", lang), "friendship_id": friendship.id}


@router.get("/list", response_model=FriendListResponse)
async def get_friends(
    status_filter: Optional[str] = Query(None, description="状态筛选：pending/accepted/blocked"),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取好友列表
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建查询条件
    conditions = [
        or_(
            Friendship.user_id == current_user.id,
            Friendship.friend_id == current_user.id
        )
    ]
    
    if status_filter:
        conditions.append(Friendship.status == status_filter)
    
    # 查询好友关系
    result = await db.execute(
        select(Friendship).where(and_(*conditions))
        .options(selectinload(Friendship.user), selectinload(Friendship.friend))
    )
    friendships = result.scalars().all()
    
    # 转换为响应模型
    friends_list = []
    for friendship in friendships:
        # 确定好友用户（不是当前用户的那个）
        friend_user = friendship.friend if friendship.user_id == current_user.id else friendship.user
        
        friends_list.append(FriendResponse(
            user_id=friend_user.id,
            nickname=friend_user.nickname,
            username=friend_user.username,
            phone=friend_user.phone if is_super_admin(current_user) else None,
            is_online=friend_user.is_online or False,
            status=friendship.status,
            note=friendship.note,
            created_at=friendship.created_at
        ))
    
    return FriendListResponse(friends=friends_list, total=len(friends_list))


@router.put("/update", status_code=status.HTTP_200_OK)
async def update_friendship(
    request_data: UpdateFriendshipRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新好友关系（接受/屏蔽好友请求）
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    if request_data.status not in ["accepted", "blocked"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("friends.invalid_status", lang)
        )
    
    # 查找好友关系（必须是对方发送的请求）
    friendship_result = await db.execute(
        select(Friendship).where(
            Friendship.user_id == request_data.friend_id,
            Friendship.friend_id == current_user.id,
            Friendship.status == "pending"
        )
    )
    friendship = friendship_result.scalar_one_or_none()
    
    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("friends.request_not_found", lang)
        )
    
    # 更新状态和备注
    friendship.status = request_data.status
    if request_data.note is not None:
        friendship.note = request_data.note
    friendship.updated_at = datetime.utcnow()
    await db.commit()
    
    # 创建通知
    if request_data.status == "accepted":
        notification = Notification(
            user_id=request_data.friend_id,
            type="friend_request",
            title=i18n.get("friends.request_accepted", lang),
            content=f"{current_user.nickname or current_user.username} 已接受您的好友请求",
            related_user_id=current_user.id,
            is_read=False
        )
        db.add(notification)
        await db.commit()
        await db.refresh(notification)
        
        # 通过 Socket.io 发送实时通知
        await send_notification(request_data.friend_id, {
            "id": notification.id,
            "type": "friend_request",
            "title": notification.title,
            "content": notification.content,
            "related_user_id": current_user.id,
            "created_at": notification.created_at.isoformat()
        })
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="update",
        resource_type="friendships",
        resource_id=friendship.id,
        operation_detail={"friend_id": request_data.friend_id, "status": request_data.status},
        request=request
    )
    await db.commit()
    
    return {"message": i18n.get(f"friends.{request_data.status}_success", lang)}


@router.delete("/remove/{friend_id}", status_code=status.HTTP_200_OK)
async def remove_friend(
    friend_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除好友关系
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查找好友关系
    friendship_result = await db.execute(
        select(Friendship).where(
            or_(
                and_(Friendship.user_id == current_user.id, Friendship.friend_id == friend_id),
                and_(Friendship.user_id == friend_id, Friendship.friend_id == current_user.id)
            )
        )
    )
    friendship = friendship_result.scalar_one_or_none()
    
    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("friends.not_found", lang)
        )
    
    await db.delete(friendship)
    await db.commit()
    
    # 记录操作日志
    await log_operation(
        db=db,
        user=current_user,
        operation_type="delete",
        resource_type="friendships",
        resource_id=friendship.id,
        operation_detail={"friend_id": friend_id},
        request=request
    )
    await db.commit()
    
    return {"message": i18n.get("friends.removed", lang)}
