"""
通知API模块
实现通知查询、标记已读等功能
"""

from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, desc
from sqlalchemy.orm import selectinload
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.permissions import check_user_not_disabled
from app.db.session import get_db
from app.db.models import User, Notification
from app.api.v1.auth import get_current_user
from loguru import logger

router = APIRouter()


# ==================== 请求/响应模型 ====================

class NotificationResponse(BaseModel):
    """通知响应模型"""
    id: int
    type: str
    title: str
    content: Optional[str] = None
    related_user_id: Optional[int] = None
    related_resource_id: Optional[int] = None
    related_resource_type: Optional[str] = None
    is_read: bool
    read_at: Optional[datetime] = None
    created_at: datetime
    related_user_nickname: Optional[str] = None
    
    class Config:
        from_attributes = True


class NotificationListResponse(BaseModel):
    """通知列表响应模型"""
    notifications: List[NotificationResponse]
    total: int
    unread_count: int


class MarkReadRequest(BaseModel):
    """标记已读请求模型"""
    notification_ids: List[int] = Field(..., description="通知ID列表")


# ==================== API 路由 ====================

@router.get("/list", response_model=NotificationListResponse)
async def get_notifications(
    is_read: Optional[bool] = Query(None, description="筛选已读/未读状态"),
    type_filter: Optional[str] = Query(None, description="筛选通知类型"),
    limit: int = Query(50, ge=1, le=100, description="返回数量"),
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取通知列表
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 构建查询条件
    conditions = [Notification.user_id == current_user.id]
    
    if is_read is not None:
        conditions.append(Notification.is_read == is_read)
    
    if type_filter:
        conditions.append(Notification.type == type_filter)
    
    # 查询通知
    query = select(Notification).where(and_(*conditions)).options(
        selectinload(Notification.related_user)
    ).order_by(desc(Notification.created_at)).limit(limit)
    
    result = await db.execute(query)
    notifications = result.scalars().all()
    
    # 查询未读数量
    unread_query = select(func.count(Notification.id)).where(
        and_(
            Notification.user_id == current_user.id,
            Notification.is_read == False
        )
    )
    unread_result = await db.execute(unread_query)
    unread_count = unread_result.scalar() or 0
    
    # 转换为响应模型
    notification_list = []
    for notif in notifications:
        notification_list.append(NotificationResponse(
            id=notif.id,
            type=notif.type,
            title=notif.title,
            content=notif.content,
            related_user_id=notif.related_user_id,
            related_resource_id=notif.related_resource_id,
            related_resource_type=notif.related_resource_type,
            is_read=notif.is_read,
            read_at=notif.read_at,
            created_at=notif.created_at,
            related_user_nickname=notif.related_user.nickname if notif.related_user else None
        ))
    
    return NotificationListResponse(
        notifications=notification_list,
        total=len(notification_list),
        unread_count=unread_count
    )


@router.put("/mark-read", status_code=status.HTTP_200_OK)
async def mark_notifications_read(
    request_data: MarkReadRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    标记通知为已读
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 批量更新通知已读状态
    # 确保使用不带时区的 datetime（数据库字段是 TIMESTAMP WITHOUT TIME ZONE）
    # 使用 datetime.utcnow() 直接获取不带时区的 UTC 时间，避免时区转换问题
    now = datetime.utcnow()  # 直接返回 naive datetime，无时区信息
    
    result = await db.execute(
        select(Notification).where(
            Notification.id.in_(request_data.notification_ids),
            Notification.user_id == current_user.id,
            Notification.is_read == False
        )
    )
    notifications = result.scalars().all()
    
    updated_count = 0
    for notif in notifications:
        notif.is_read = True
        notif.read_at = now  # 使用不带时区的 datetime
        updated_count += 1
    
    await db.commit()
    
    return {"message": f"已标记 {updated_count} 条通知为已读", "updated_count": updated_count}


@router.delete("/{notification_id}", status_code=status.HTTP_200_OK)
async def delete_notification(
    notification_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除通知
    """
    lang = current_user.language or get_language_from_request(request)
    check_user_not_disabled(current_user, lang)
    
    # 查找通知
    result = await db.execute(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == current_user.id
        )
    )
    notification = result.scalar_one_or_none()
    
    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("notifications.not_found", lang)
        )
    
    await db.delete(notification)
    await db.commit()
    
    return {"message": i18n.get("notifications.deleted", lang)}
