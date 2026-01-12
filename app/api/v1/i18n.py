"""
国际化相关 API
包含语言列表、语言切换等功能
"""

from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, Field

from app.core.i18n import i18n, SUPPORTED_LANGUAGES, get_language_from_request
from app.db.session import get_db
from app.api.v1.auth import get_current_user
from app.db.models import User
from typing import Optional

router = APIRouter()


class LanguageInfo(BaseModel):
    """语言信息模型"""
    code: str = Field(..., description="语言代码（如：zh_TW）")
    name: str = Field(..., description="语言名称（本地化）")
    native_name: str = Field(..., description="语言原生名称")


class LanguageSwitchRequest(BaseModel):
    """语言切换请求模型"""
    language: str = Field(..., description="语言代码（如：zh_TW, en_US）")


class LanguageSwitchResponse(BaseModel):
    """语言切换响应模型"""
    message: str = Field(..., description="响应消息")
    language: str = Field(..., description="当前语言代码")


@router.get("/languages", response_model=list[LanguageInfo])
async def get_supported_languages(
    request: Request
):
    """
    获取支持的语言列表
    
    返回所有支持的语言及其本地化名称
    """
    lang = get_language_from_request(request)
    languages = []
    for code, native_name in SUPPORTED_LANGUAGES.items():
        # 获取本地化名称（使用当前语言）
        localized_name = i18n.get(f"languages.{code}", lang)
        if localized_name == f"languages.{code}":  # 如果找不到翻译，使用原生名称
            localized_name = native_name
        languages.append(LanguageInfo(
            code=code,
            name=localized_name,
            native_name=native_name
        ))
    
    return languages


@router.post("/switch", response_model=LanguageSwitchResponse)
async def switch_language(
    request_data: LanguageSwitchRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    切换用户语言偏好
    
    需要登录，语言偏好会保存到数据库
    """
    # 验证语言代码
    normalized_lang = i18n.normalize_language(request_data.language)
    if normalized_lang not in SUPPORTED_LANGUAGES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.get("i18n.invalid_language", current_user.language, language=request_data.language)
        )
    
    # 更新用户语言偏好
    current_user.language = normalized_lang
    await db.commit()
    
    return LanguageSwitchResponse(
        message=i18n.get("i18n.switch_success", normalized_lang),
        language=normalized_lang
    )


@router.get("/current", response_model=LanguageInfo)
async def get_current_language(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    获取当前语言设置
    
    如果已登录，返回用户设置的语言；否则返回检测到的语言
    
    注意：此端点支持可选认证，如果提供了有效的 JWT token，会使用用户的语言偏好
    """
    current_user = None
    
    # 尝试从请求头获取 token（可选）
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        try:
            token = auth_header.split(" ")[1]
            from app.core.security import decode_token
            from sqlalchemy import select
            payload = decode_token(token)
            if payload:
                user_id_str = payload.get("sub")
                if user_id_str:
                    try:
                        user_id = int(user_id_str)
                        result = await db.execute(select(User).where(User.id == user_id))
                        current_user = result.scalar_one_or_none()
                    except:
                        current_user = None
        except:
            pass
    
    lang = current_user.language if current_user else get_language_from_request(request)
    
    localized_name = i18n.get(f"languages.{lang}", lang)
    if localized_name == f"languages.{lang}":
        localized_name = SUPPORTED_LANGUAGES.get(lang, lang)
    
    return LanguageInfo(
        code=lang,
        name=localized_name,
        native_name=SUPPORTED_LANGUAGES.get(lang, lang)
    )


@router.get("/translations")
async def get_translations(
    request: Request,
    lang: Optional[str] = None
):
    """
    获取指定语言的完整翻译资源
    
    用于前端加载多语言资源
    """
    # 如果没有提供语言参数，从请求头检测
    if not lang:
        if request:
            lang = get_language_from_request(request)
        else:
            lang = "zh_TW"  # 默认繁体中文
    
    # 规范化语言代码
    normalized_lang = i18n.normalize_language(lang)
    
    # 如果语言不支持，回退到默认语言（繁体中文）
    if normalized_lang not in SUPPORTED_LANGUAGES:
        normalized_lang = "zh_TW"
    
    # 获取翻译资源
    translations = i18n._translations.get(normalized_lang, {})
    
    # 如果翻译为空，尝试使用默认语言（繁体中文）
    if not translations and normalized_lang != "zh_TW":
        translations = i18n._translations.get("zh_TW", {})
    
    # 确保返回的是字典而不是空值
    if not translations:
        translations = {}
    
    return translations