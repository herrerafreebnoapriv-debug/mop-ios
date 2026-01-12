"""
邀请码管理 API
包含邀请码创建、查询、撤回等功能
支持一人一码/一人多码，支持撤回
"""

import secrets
import string
from datetime import datetime, timezone, timedelta
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.db.session import get_db
from app.db.models import User, InvitationCode
from app.api.v1.auth import get_current_user
from app.api.v1.users import require_admin

router = APIRouter()


# ==================== 请求/响应模型 ====================

class InvitationCodeCreate(BaseModel):
    """创建邀请码请求模型"""
    code: Optional[str] = Field(None, max_length=50, description="自定义邀请码（可选，不提供则自动生成）")
    max_uses: int = Field(1, ge=1, le=1000, description="最大使用次数（1=一人一码，>1=一人多码）")
    expires_at: Optional[datetime] = Field(None, description="过期时间（可选）")


class InvitationCodeResponse(BaseModel):
    """邀请码响应模型"""
    id: int
    code: str
    created_by: Optional[int]
    max_uses: int
    used_count: int
    is_active: bool
    is_revoked: bool
    created_at: str
    revoked_at: Optional[str]
    expires_at: Optional[str]

    class Config:
        from_attributes = True


class InvitationCodeListResponse(BaseModel):
    """邀请码列表响应模型"""
    total: int
    codes: List[InvitationCodeResponse]


class InvitationCodeVerify(BaseModel):
    """邀请码验证请求模型"""
    code: str = Field(..., max_length=50, description="邀请码")


class InvitationCodeVerifyResponse(BaseModel):
    """邀请码验证响应模型"""
    valid: bool
    code: str
    message: str
    max_uses: Optional[int] = None
    used_count: Optional[int] = None
    expires_at: Optional[str] = None


# ==================== 辅助函数 ====================

def generate_invitation_code(length: int = 12) -> str:
    """
    生成随机邀请码
    
    Args:
        length: 邀请码长度
    
    Returns:
        随机邀请码字符串
    """
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


# ==================== API 路由 ====================

@router.post("/create", response_model=InvitationCodeResponse, status_code=status.HTTP_201_CREATED)
async def create_invitation_code(
    code_data: InvitationCodeCreate,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    创建邀请码（仅管理员）
    
    支持自定义邀请码或自动生成
    支持设置最大使用次数（一人一码/一人多码）
    支持设置过期时间
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 确定邀请码
    if code_data.code:
        # 使用自定义邀请码
        code = code_data.code.upper().strip()
        # 检查是否已存在
        result = await db.execute(
            select(InvitationCode).where(InvitationCode.code == code)
        )
        if result.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("invitation.code_exists", lang, code=code)
            )
    else:
        # 自动生成邀请码
        code = generate_invitation_code()
        # 确保唯一性
        max_attempts = 10
        for _ in range(max_attempts):
            result = await db.execute(
                select(InvitationCode).where(InvitationCode.code == code)
            )
            if result.scalar_one_or_none() is None:
                break
            code = generate_invitation_code()
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=i18n.get("invitation.generate_failed", lang)
            )
    
    # 创建邀请码
    new_code = InvitationCode(
        code=code,
        created_by=current_user.id,
        max_uses=code_data.max_uses,
        used_count=0,
        is_active=True,
        is_revoked=False,
        expires_at=code_data.expires_at
    )
    
    db.add(new_code)
    await db.commit()
    await db.refresh(new_code)
    
    # 安全访问 revoked_at 字段（兼容旧数据库）
    revoked_at = getattr(new_code, 'revoked_at', None)
    
    return {
        "id": new_code.id,
        "code": new_code.code,
        "created_by": new_code.created_by,
        "max_uses": new_code.max_uses,
        "used_count": new_code.used_count,
        "is_active": new_code.is_active,
        "is_revoked": new_code.is_revoked,
        "created_at": new_code.created_at.isoformat(),
        "revoked_at": revoked_at.isoformat() if revoked_at else None,
        "expires_at": new_code.expires_at.isoformat() if new_code.expires_at else None
    }


@router.get("/", response_model=InvitationCodeListResponse)
async def get_invitation_codes(
    request: Request,
    skip: int = Query(0, ge=0, description="跳过记录数"),
    limit: int = Query(100, ge=1, le=1000, description="返回记录数"),
    code: Optional[str] = Query(None, description="搜索邀请码"),
    is_active: Optional[bool] = Query(None, description="筛选激活状态"),
    is_revoked: Optional[bool] = Query(None, description="筛选撤回状态"),
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    获取邀请码列表（仅管理员）
    
    支持分页、搜索和筛选
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 构建查询
    query = select(InvitationCode)
    conditions = []
    
    # 搜索条件
    if code:
        conditions.append(InvitationCode.code.ilike(f"%{code}%"))
    
    # 筛选条件
    if is_active is not None:
        conditions.append(InvitationCode.is_active == is_active)
    
    if is_revoked is not None:
        conditions.append(InvitationCode.is_revoked == is_revoked)
    
    if conditions:
        query = query.where(and_(*conditions))
    
    # 获取总数
    count_query = select(func.count()).select_from(InvitationCode)
    if conditions:
        count_query = count_query.where(and_(*conditions))
    total_result = await db.execute(count_query)
    total = total_result.scalar()
    
    # 分页查询
    query = query.order_by(InvitationCode.created_at.desc()).offset(skip).limit(limit)
    result = await db.execute(query)
    codes = result.scalars().all()
    
    # 安全访问 revoked_at 字段（兼容旧数据库）
    def get_revoked_at(code):
        revoked_at = getattr(code, 'revoked_at', None)
        return revoked_at.isoformat() if revoked_at else None
    
    return {
        "total": total,
        "codes": [
            {
                "id": c.id,
                "code": c.code,
                "created_by": c.created_by,
                "max_uses": c.max_uses,
                "used_count": c.used_count,
                "is_active": c.is_active,
                "is_revoked": c.is_revoked,
                "created_at": c.created_at.isoformat(),
                "revoked_at": get_revoked_at(c),
                "expires_at": c.expires_at.isoformat() if c.expires_at else None
            }
            for c in codes
        ]
    }


@router.delete("/{code_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_invitation_code(
    code_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    删除邀请码（仅管理员）
    
    永久删除邀请码，此操作不可恢复
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(InvitationCode).where(InvitationCode.id == code_id))
    code = result.scalar_one_or_none()
    
    if code is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("invitation.not_found", lang)
        )
    
    # 删除邀请码
    await db.delete(code)
    await db.commit()
    
    return None


@router.get("/{code_id}", response_model=InvitationCodeResponse)
async def get_invitation_code(
    code_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    获取指定邀请码信息（仅管理员）
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(InvitationCode).where(InvitationCode.id == code_id))
    code = result.scalar_one_or_none()
    
    if code is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("invitation.not_found", lang)
        )
    
    # 安全访问 revoked_at 字段（兼容旧数据库）
    revoked_at = getattr(code, 'revoked_at', None)
    
    return {
        "id": code.id,
        "code": code.code,
        "created_by": code.created_by,
        "max_uses": code.max_uses,
        "used_count": code.used_count,
        "is_active": code.is_active,
        "is_revoked": code.is_revoked,
        "created_at": code.created_at.isoformat(),
        "revoked_at": revoked_at.isoformat() if revoked_at else None,
        "expires_at": code.expires_at.isoformat() if code.expires_at else None
    }


@router.post("/verify", response_model=InvitationCodeVerifyResponse)
async def verify_invitation_code(
    verify_data: InvitationCodeVerify,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    验证邀请码（公开端点，用于注册时验证）
    
    返回邀请码是否有效及使用情况
    """
    lang = get_language_from_request(request)
    code = verify_data.code.upper().strip()
    
    result = await db.execute(
        select(InvitationCode).where(InvitationCode.code == code)
    )
    invitation_code = result.scalar_one_or_none()
    
    if invitation_code is None:
        return InvitationCodeVerifyResponse(
            valid=False,
            code=code,
            message=i18n.get("invitation.invalid", lang)
        )
    
    # 检查是否已撤回
    if invitation_code.is_revoked or not invitation_code.is_active:
        return InvitationCodeVerifyResponse(
            valid=False,
            code=code,
            message=i18n.get("invitation.revoked", lang)
        )
    
    # 检查是否过期
    if invitation_code.expires_at and invitation_code.expires_at < datetime.now(timezone.utc):
        return InvitationCodeVerifyResponse(
            valid=False,
            code=code,
            message=i18n.get("invitation.expired", lang)
        )
    
    # 检查是否达到最大使用次数
    if invitation_code.used_count >= invitation_code.max_uses:
        return InvitationCodeVerifyResponse(
            valid=False,
            code=code,
            message=i18n.get("invitation.max_uses_reached", lang)
        )
    
    # 邀请码有效
    return InvitationCodeVerifyResponse(
        valid=True,
        code=code,
        message=i18n.get("invitation.valid", lang),
        max_uses=invitation_code.max_uses,
        used_count=invitation_code.used_count,
        expires_at=invitation_code.expires_at.isoformat() if invitation_code.expires_at else None
    )


@router.post("/{code_id}/revoke", response_model=InvitationCodeResponse)
async def revoke_invitation_code(
    code_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    撤回邀请码（仅管理员）
    
    撤回后邀请码将无法使用
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(InvitationCode).where(InvitationCode.id == code_id))
    code = result.scalar_one_or_none()
    
    if code is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("invitation.not_found", lang)
        )
    
    if code.is_revoked:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("invitation.already_revoked", lang)
        )
    
    # 撤回邀请码
    code.is_revoked = True
    code.is_active = False
    # 安全设置 revoked_at 字段（如果字段存在）
    if hasattr(code, 'revoked_at'):
        code.revoked_at = datetime.now(timezone.utc).replace(tzinfo=None)
    await db.commit()
    await db.refresh(code)
    
    # 安全访问 revoked_at 字段（兼容旧数据库）
    revoked_at = getattr(code, 'revoked_at', None)
    
    return {
        "id": code.id,
        "code": code.code,
        "created_by": code.created_by,
        "max_uses": code.max_uses,
        "used_count": code.used_count,
        "is_active": code.is_active,
        "is_revoked": code.is_revoked,
        "created_at": code.created_at.isoformat(),
        "revoked_at": revoked_at.isoformat() if revoked_at else None,
        "expires_at": code.expires_at.isoformat() if code.expires_at else None
    }


@router.get("/{code_id}/usage", response_model=dict)
async def get_invitation_code_usage(
    code_id: int,
    request: Request,
    current_user: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db)
):
    """
    查看邀请码使用情况（仅管理员）
    
    返回使用该邀请码注册的用户列表
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(select(InvitationCode).where(InvitationCode.id == code_id))
    code = result.scalar_one_or_none()
    
    if code is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("invitation.not_found", lang)
        )
    
    # 查询使用该邀请码的用户
    users_result = await db.execute(
        select(User).where(User.invitation_code == code.code)
    )
    users = users_result.scalars().all()
    
    return {
        "code": code.code,
        "max_uses": code.max_uses,
        "used_count": code.used_count,
        "remaining_uses": max(0, code.max_uses - code.used_count),
        "users": [
            {
                "id": u.id,
                "phone": u.phone,
                "username": u.username,
                "nickname": u.nickname,
                "created_at": u.created_at.isoformat()
            }
            for u in users
        ]
    }