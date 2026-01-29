"""
认证相关 API
包含登录、注册、刷新令牌等功能
"""

from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, EmailStr, Field

from app.core.config import settings
from app.core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    create_refresh_token,
    decode_token
)
from app.core.i18n import i18n, get_language_from_request
from app.db.session import get_db
from app.db.models import User

router = APIRouter()

# OAuth2 密码流
oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{settings.API_V1_PREFIX}/auth/login")


# ==================== 请求/响应模型 ====================

class UserRegister(BaseModel):
    """用户注册请求模型"""
    phone: str = Field(..., min_length=11, max_length=20, description="手机号")
    username: str = Field(..., min_length=3, max_length=100, description="用户名")
    password: str = Field(..., min_length=6, max_length=12, description="密码（6-12位，支持纯数字和复杂组合）")
    nickname: str = Field(None, max_length=100, description="昵称")
    invitation_code: str = Field(..., min_length=1, max_length=50, description="邀请码（必填）")
    agreed_to_terms: bool = Field(..., description="是否同意用户须知和免责声明")


class AgreementResponse(BaseModel):
    """免责声明响应模型"""
    title: str = Field(..., description="免责声明标题")
    content: str = Field(..., description="免责声明内容")
    checkbox_label: str = Field(..., description="勾选框标签文本")


class AgreeTermsRequest(BaseModel):
    """同意免责声明请求模型"""
    agreed: bool = Field(..., description="是否同意")


class TokenResponse(BaseModel):
    """令牌响应模型"""
    access_token: str = Field(..., description="访问令牌")
    refresh_token: str = Field(..., description="刷新令牌")
    token_type: str = Field(default="bearer", description="令牌类型")


class UserResponse(BaseModel):
    """用户信息响应模型"""
    id: int
    phone: str
    username: str | None
    nickname: str | None
    is_online: bool
    is_admin: bool | None = None
    role: str | None = None
    created_at: str

    class Config:
        from_attributes = True


# ==================== 辅助函数 ====================

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    获取当前登录用户
    用于依赖注入，验证 JWT 令牌并返回用户对象
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    payload = decode_token(token)
    if payload is None:
        raise credentials_exception
    
    user_id_str = payload.get("sub")
    if user_id_str is None:
        raise credentials_exception
    
    # sub是字符串，需要转换为整数
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise credentials_exception
    
    # 从数据库获取用户
    from sqlalchemy import select
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    
    if user is None:
        raise credentials_exception
    
    return user


# ==================== API 路由 ====================

@router.get("/agreement", response_model=AgreementResponse)
async def get_agreement(request: Request):
    """
    获取用户须知和免责声明内容
    
    支持多语言，根据请求头自动检测语言
    """
    lang = get_language_from_request(request)
    
    return {
        "title": i18n.get("auth.agreement.title", lang),
        "content": i18n.get("auth.agreement.content", lang),
        "checkbox_label": i18n.get("auth.agreement.checkbox_label", lang)
    }


@router.post("/agree-terms")
async def agree_terms(
    request_data: AgreeTermsRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    记录用户同意免责声明
    
    需要登录后调用，用于已注册但未同意的用户
    """
    from datetime import datetime, timezone
    
    lang = current_user.language
    
    if not request_data.agreed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("auth.agreement.agree_failed", lang)
        )
    
    # 更新用户同意状态
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    current_user.agreed_at = now_naive
    current_user.updated_at = now_naive
    
    await db.commit()
    await db.refresh(current_user)
    
    return {
        "message": i18n.get("auth.agreement.agree_success", lang),
        "agreed_at": current_user.agreed_at.isoformat() if current_user.agreed_at else None
    }


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(
    user_data: UserRegister,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    用户注册
    
    注意：根据 Spec.txt，首次注册需要同意免责声明
    注册时强制要求邀请码，且仅能创建普通用户角色
    """
    from sqlalchemy import select
    from datetime import datetime, timezone
    
    # 检测语言
    lang = get_language_from_request(request)
    
    # 检查是否同意免责声明
    if not user_data.agreed_to_terms:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("auth.register.agreement_required", lang)
        )
    
    # 检查手机号是否已存在
    result = await db.execute(select(User).where(User.phone == user_data.phone))
    if result.scalar_one_or_none() is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("auth.register.phone_exists", lang)
        )
    
    # 检查用户名是否已存在
    if user_data.username:
        result = await db.execute(select(User).where(User.username == user_data.username))
        if result.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.get("auth.register.username_exists", lang)
            )
    
    # 验证邀请码（必填）
    if not user_data.invitation_code or not user_data.invitation_code.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("auth.register.invitation_code_required", lang) or "邀请码为必填项"
        )
    
    from app.db.models import InvitationCode
    code_result = await db.execute(
        select(InvitationCode).where(InvitationCode.code == user_data.invitation_code.upper().strip())
    )
    invitation_code = code_result.scalar_one_or_none()
    
    if invitation_code is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("invitation.invalid", lang)
        )
    
    # 检查是否已撤回或未激活
    if invitation_code.is_revoked or not invitation_code.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("invitation.revoked", lang)
        )
    
    # 检查是否过期
    if invitation_code.expires_at and invitation_code.expires_at < datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("invitation.expired", lang)
        )
    
    # 检查是否达到最大使用次数
    if invitation_code.used_count >= invitation_code.max_uses:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("invitation.max_uses_reached", lang)
        )
    
    # 增加使用次数
    invitation_code.used_count += 1
    await db.flush()  # 先刷新，但不提交
    
    # 创建新用户（使用检测到的语言作为默认语言）
    # 注册时仅能创建普通用户，角色固定为 "user"，is_admin 固定为 False
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    
    new_user = User(
        phone=user_data.phone,
        username=user_data.username,
        password_hash=get_password_hash(user_data.password),
        nickname=user_data.nickname,
        invitation_code=user_data.invitation_code.upper().strip(),  # 统一转换为大写并去除空格
        language=lang,  # 设置用户语言偏好
        role="user",  # 固定为普通用户角色
        is_admin=False,  # 固定为非管理员
        agreed_at=now_naive if user_data.agreed_to_terms else None  # 设置同意时间
    )
    
    db.add(new_user)
    await db.commit()
    await db.refresh(new_user)
    
    # 注册成功后自动登录：更新用户状态并生成 token
    new_user.last_active_at = now_naive
    new_user.is_online = True
    new_user.updated_at = now_naive
    await db.commit()
    
    # 生成令牌（sub必须是字符串）
    from app.core.security import create_access_token, create_refresh_token
    access_token = create_access_token(data={"sub": str(new_user.id)})
    refresh_token = create_refresh_token(data={"sub": str(new_user.id)})
    
    # 返回 token，实现注册后自动登录
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }


@router.post("/login", response_model=TokenResponse)
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    request: Request = None,
    db: AsyncSession = Depends(get_db)
):
    """
    用户登录
    
    支持使用手机号或用户名登录
    """
    from sqlalchemy import select
    from datetime import datetime
    
    # 检测语言
    lang = get_language_from_request(request) if request else "zh_TW"
    
    # 尝试通过手机号或用户名查找用户
    # OAuth2PasswordRequestForm 的 username 字段可以用于手机号或用户名
    result = await db.execute(
        select(User).where(
            (User.phone == form_data.username) | (User.username == form_data.username)
        )
    )
    user = result.scalar_one_or_none()
    
    # 如果找到用户，使用用户的语言偏好
    if user:
        lang = user.language
    
    if user is None or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=i18n.get("auth.login.failed", lang),
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # 检查用户是否可以登录后端（仅超级管理员和普通管理员可以登录后端）
    from app.core.permissions import can_access_backend
    if not can_access_backend(user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("auth.login.backend_access_denied", lang) or "普通用户不能登录后端管理系统"
        )
    
    # 检查是否已同意免责声明
    if user.agreed_at is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("auth.login.agreement_required", lang)
        )
    
    # 更新最后活跃时间
    # 确保使用 naive datetime，避免时区问题
    from datetime import timezone
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    
    user.last_active_at = now_naive
    user.is_online = True
    # 确保 updated_at 是 naive datetime（事件监听器也会处理，但这里显式设置更安全）
    user.updated_at = now_naive
    
    await db.commit()
    await db.refresh(user)
    
    # 生成令牌（sub必须是字符串）
    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})
    
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }


class RefreshTokenRequest(BaseModel):
    """刷新令牌请求模型"""
    refresh_token: str = Field(..., description="刷新令牌")


class ConfirmScanRequest(BaseModel):
    """扫码授权确认请求模型"""
    token: str = Field(..., description="授权二维码中的 JWT")


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    request_data: RefreshTokenRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db)
):
    """
    刷新访问令牌
    
    使用刷新令牌获取新的访问令牌
    """
    # 检测语言
    lang = get_language_from_request(request) if request else "zh_TW"
    
    payload = decode_token(request_data.refresh_token)
    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=i18n.get("auth.token.refresh_failed", lang)
        )
    
    user_id_str = payload.get("sub")
    if user_id_str is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=i18n.get("auth.token.invalid", lang)
        )
    
    # sub是字符串，需要转换为整数
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=i18n.get("auth.token.invalid", lang)
        )
    
    # 验证用户是否存在
    from sqlalchemy import select
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=i18n.get("auth.user.not_found", lang)
        )
    
    # 使用用户的语言偏好
    lang = user.language
    
    # 生成新的访问令牌（sub必须是字符串）
    new_access_token = create_access_token(data={"sub": str(user.id)})
    new_refresh_token = create_refresh_token(data={"sub": str(user.id)})
    
    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer"
    }


@router.get("/me", response_model=UserResponse)
async def get_current_user_info(
    current_user: User = Depends(get_current_user)
):
    """
    获取当前登录用户信息
    """
    return UserResponse(
        id=current_user.id,
        phone=current_user.phone,
        username=current_user.username,
        nickname=current_user.nickname,
        is_online=current_user.is_online or False,
        is_admin=current_user.is_admin or False,
        role=current_user.role or "user",
        created_at=current_user.created_at.isoformat() if current_user.created_at else ""
    )


@router.post("/confirm-scan")
async def confirm_scan(
    request_data: ConfirmScanRequest,
    request: Request = None,
):
    """
    客户端扫码授权确认
    
    客户端扫描后台生成的授权二维码后，将二维码中的 token 提交至此接口完成授权。
    """
    lang = get_language_from_request(request) if request else "zh_CN"
    payload = decode_token(request_data.token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="二维码已过期或无效，请重新生成"
        )
    if payload.get("type") != "auth_qr":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="无效的授权二维码"
        )
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="无效的授权二维码")
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="无效的授权二维码")
    return {"user_id": user_id, "message": "授权成功"}


@router.post("/logout")
async def logout(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    用户登出
    
    更新用户在线状态
    """
    from datetime import datetime, timezone
    current_user.is_online = False
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    current_user.last_active_at = now_naive
    # 强制设置 updated_at 为 naive datetime
    current_user.updated_at = now_naive
    await db.commit()
    
    return {"message": i18n.get("auth.logout.success", current_user.language)}
