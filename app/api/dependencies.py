"""
API 依赖注入函数
包含语言检测等通用依赖
注意：get_current_user 已移至 app.api.v1.auth 以避免循环导入
"""

from typing import Optional
from fastapi import Request

from app.core.i18n import get_language_from_request
from app.db.models import User


def get_language(
    request: Request,
    current_user: Optional[User] = None
) -> str:
    """
    获取当前请求的语言
    
    优先级：
    1. 用户设置的语言（如果已登录）
    2. Accept-Language 请求头
    3. 默认语言（zh_TW）
    
    Args:
        request: FastAPI 请求对象
        current_user: 当前登录用户（可选）
    
    Returns:
        语言代码（如：zh_TW, en_US）
    """
    user_lang = current_user.language if current_user else None
    return get_language_from_request(request, user_lang)
