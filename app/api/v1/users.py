"""
用户管理 API
包含用户查询、更新、删除等功能
"""

from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, and_, func
from pydantic import BaseModel, Field, EmailStr

from app.core.i18n import i18n, get_language_from_request
from app.db.session import get_db
from app.db.models import User
from app.api.v1.auth import get_current_user
from app.core.security import get_password_hash, verify_password

router = APIRouter()


# ==================== 请求/响应模型 ====================

class UserUpdate(BaseModel):
    """用户更新请求模型"""
    username: Optional[str] = Field(None, min_length=3, max_length=100)
    nickname: Optional[str] = Field(None, max_length=100)
    password: Optional[str] = Field(None, min_length=6, max_length=72, description="新密码（修改密码时必须提供旧密码）")
    language: Optional[str] = Field(None, max_length=10, description="语言偏好")
    old_password: Optional[str] = Field(None, description="旧密码（修改密码时必需）")


class UserResponse(BaseModel):
    """用户信息响应模型"""
    id: int
    phone: str
    username: Optional[str]
    nickname: Optional[str]
    is_online: bool
    is_admin: bool
    role: Optional[str] = None
    is_disabled: Optional[bool] = False
    language: Optional[str] = None
    first_used_at: Optional[str] = None
    last_active_at: Optional[str] = None
    created_at: str

    class Config:
        from_attributes = True


class UserListResponse(BaseModel):
    """用户列表响应模型"""
    total: int
    users: List[UserResponse]


class PasswordChange(BaseModel):
    """密码修改请求模型"""
    old_password: str = Field(..., description="旧密码")
    new_password: str = Field(..., min_length=6, max_length=72, description="新密码")


# ==================== 辅助函数 ====================

async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """要求管理员权限"""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("common.forbidden", current_user.language or "zh_TW")
        )
    return current_user


# ==================== API 路由 ====================

@router.put("/me", response_model=UserResponse)
async def update_current_user(
    user_data: UserUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新当前用户信息
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 更新字段
    update_data = user_data.model_dump(exclude_unset=True)
    
    # 如果更新用户名，检查是否已存在
    if "username" in update_data and update_data["username"]:
        result = await db.execute(
            select(User).where(
                User.username == update_data["username"],
                User.id != current_user.id
            )
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("auth.register.username_exists", lang)
            )
    
    # 如果更新密码，需要哈希
    if "password" in update_data:
        update_data["password_hash"] = get_password_hash(update_data.pop("password"))
    
    # 更新字段
    for field, value in update_data.items():
        if hasattr(current_user, field):
            setattr(current_user, field, value)
    
    # updated_at 会通过事件监听器自动更新
    await db.commit()
    await db.refresh(current_user)
    
    return {
        "id": current_user.id,
        "phone": current_user.phone,
        "username": current_user.username,
        "nickname": current_user.nickname,
        "is_online": current_user.is_online,
        "is_admin": current_user.is_admin,
        "language": current_user.language,
        "first_used_at": current_user.first_used_at.isoformat() if current_user.first_used_at else None,
        "last_active_at": current_user.last_active_at.isoformat() if current_user.last_active_at else None,
        "created_at": current_user.created_at.isoformat()
    }


@router.post("/me/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    password_data: PasswordChange,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    修改当前用户密码
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 验证旧密码
    if not verify_password(password_data.old_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("auth.login.failed", lang)
        )
    
    # 更新密码
    current_user.password_hash = get_password_hash(password_data.new_password)
    # updated_at 会通过事件监听器自动更新
    await db.commit()
    
    return None


@router.get("/", response_model=UserListResponse)
async def get_users(
    request: Request,
    skip: int = Query(0, ge=0, description="跳过记录数"),
    limit: int = Query(100, ge=1, le=1000, description="返回记录数"),
    search: Optional[str] = Query(None, description="搜索关键词（手机号、用户名）"),
    is_online: Optional[bool] = Query(None, description="筛选在线状态"),
    is_admin: Optional[bool] = Query(None, description="筛选管理员"),
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    获取用户列表（仅管理员）
    
    支持分页、搜索和筛选
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 构建查询
    query = select(User)
    conditions = []
    
    # 搜索条件
    if search:
        conditions.append(
            or_(
                User.phone.ilike(f"%{search}%"),
                User.username.ilike(f"%{search}%"),
                User.nickname.ilike(f"%{search}%")
            )
        )
    
    # 筛选条件
    if is_online is not None:
        conditions.append(User.is_online == is_online)
    
    if is_admin is not None:
        conditions.append(User.is_admin == is_admin)
    
    if conditions:
        query = query.where(and_(*conditions))
    
    # 获取总数
    count_query = select(func.count()).select_from(User)
    if conditions:
        count_query = count_query.where(and_(*conditions))
    total_result = await db.execute(count_query)
    total = total_result.scalar()
    
    # 分页查询
    query = query.order_by(User.created_at.desc()).offset(skip).limit(limit)
    result = await db.execute(query)
    users = result.scalars().all()
    
    return {
        "total": total,
        "users": [
            {
                "id": u.id,
                "phone": u.phone,
                "username": u.username,
                "nickname": u.nickname,
                "is_online": u.is_online or False,
                "is_admin": u.is_admin or False,
                "role": u.role or "user",
                "is_disabled": u.is_disabled or False,
                "language": u.language,
                "first_used_at": u.first_used_at.isoformat() if u.first_used_at else None,
                "last_active_at": u.last_active_at.isoformat() if u.last_active_at else None,
                "created_at": u.created_at.isoformat()
            }
            for u in users
        ]
    }


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    获取指定用户信息（仅管理员）
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("user.not_found", lang)
        )
    
    return {
        "id": user.id,
        "phone": user.phone,
        "username": user.username,
        "nickname": user.nickname,
        "is_online": user.is_online or False,
        "is_admin": user.is_admin or False,
        "role": user.role or "user",
        "is_disabled": user.is_disabled or False,
        "language": user.language,
        "first_used_at": user.first_used_at.isoformat() if user.first_used_at else None,
        "last_active_at": user.last_active_at.isoformat() if user.last_active_at else None,
        "created_at": user.created_at.isoformat()
    }


@router.put("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: int,
    user_data: UserUpdate,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    更新指定用户信息（仅管理员）
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("user.not_found", lang)
        )
    
    # 更新字段
    update_data = user_data.model_dump(exclude_unset=True)
    
    # 如果更新用户名，检查是否已存在
    if "username" in update_data and update_data["username"]:
        result = await db.execute(
            select(User).where(
                User.username == update_data["username"],
                User.id != user_id
            )
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("auth.register.username_exists", lang)
            )
    
    # 如果更新密码，所有用户都需要验证旧密码（安全性要求）
    if "password" in update_data:
        # 所有用户修改密码都需要提供旧密码
        if "old_password" not in update_data or not update_data.get("old_password"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("auth.password.old_required", lang) or "修改密码需要提供旧密码"
            )
        # 验证旧密码
        if not verify_password(update_data["old_password"], user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("auth.login.failed", lang) or "旧密码错误"
            )
        # 移除旧密码字段
        update_data.pop("old_password")
        # 设置新密码哈希
        update_data["password_hash"] = get_password_hash(update_data.pop("password"))
    
    # 更新字段
    for field, value in update_data.items():
        if hasattr(user, field):
            setattr(user, field, value)
    
    user.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    await db.commit()
    await db.refresh(user)
    
    return {
        "id": user.id,
        "phone": user.phone,
        "username": user.username,
        "nickname": user.nickname,
        "is_online": user.is_online or False,
        "is_admin": user.is_admin or False,
        "role": user.role or "user",
        "is_disabled": user.is_disabled or False,
        "language": user.language,
        "first_used_at": user.first_used_at.isoformat() if user.first_used_at else None,
        "last_active_at": user.last_active_at.isoformat() if user.last_active_at else None,
        "created_at": user.created_at.isoformat()
    }


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    删除指定用户（仅管理员）
    
    注意：不能删除自己
    """
    lang = current_user.language or get_language_from_request(request)
    
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("user.cannot_delete_self", lang)
        )
    
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("user.not_found", lang)
        )
    
    await db.delete(user)
    await db.commit()
    
    return None
