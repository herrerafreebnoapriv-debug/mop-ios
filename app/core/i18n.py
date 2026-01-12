"""
国际化（i18n）支持模块
实现多语言资源管理和语言切换功能
"""

from typing import Optional
from fastapi import Request

from app.core.config import settings

# 支持的语言列表（移除简体中文，只保留指定的10种语言）
SUPPORTED_LANGUAGES = {
    "en_US": "English",
    "zh_TW": "繁體中文",
    "es_ES": "Español",
    "fr_FR": "Français",
    "de_DE": "Deutsch",
    "ja_JP": "日本語",
    "ko_KR": "한국어",
    "pt_BR": "Português (Brasil)",
    "ru_RU": "Русский",
    "ar_SA": "العربية",
}

# 默认语言（繁体中文-中国台湾）
DEFAULT_LANGUAGE = "zh_TW"

# 语言映射（简化语言代码到完整语言代码）
LANGUAGE_MAP = {
    # 英语
    "en": "en_US",
    "en-US": "en_US",
    "en-GB": "en_US",
    # 繁体中文
    "zh-TW": "zh_TW",
    "zh-Hant": "zh_TW",
    "zh-HK": "zh_TW",
    "zh-MO": "zh_TW",
    # 西班牙语
    "es": "es_ES",
    "es-ES": "es_ES",
    "es-MX": "es_ES",
    "es-AR": "es_ES",
    # 法语
    "fr": "fr_FR",
    "fr-FR": "fr_FR",
    "fr-CA": "fr_FR",
    # 德语
    "de": "de_DE",
    "de-DE": "de_DE",
    "de-AT": "de_DE",
    "de-CH": "de_DE",
    # 日语
    "ja": "ja_JP",
    "ja-JP": "ja_JP",
    # 韩语
    "ko": "ko_KR",
    "ko-KR": "ko_KR",
    # 葡萄牙语（巴西）
    "pt-BR": "pt_BR",
    "pt": "pt_BR",
    # 俄语
    "ru": "ru_RU",
    "ru-RU": "ru_RU",
    # 阿拉伯语
    "ar": "ar_SA",
    "ar-SA": "ar_SA",
    "ar-AE": "ar_SA",
    "ar-EG": "ar_SA",
}


class I18n:
    """
    国际化管理器
    负责加载和管理多语言资源
    """
    
    def __init__(self):
        self._translations = {}
        self._load_translations()
    
    def _load_translations(self):
        """加载所有语言资源"""
        import json
        import os
        
        locales_dir = os.path.join(os.path.dirname(__file__), "..", "locales")
        
        for lang_code in SUPPORTED_LANGUAGES.keys():
            lang_file = os.path.join(locales_dir, f"{lang_code}.json")
            if os.path.exists(lang_file):
                try:
                    with open(lang_file, "r", encoding="utf-8") as f:
                        self._translations[lang_code] = json.load(f)
                except Exception as e:
                    print(f"Warning: Failed to load {lang_code} translations: {e}")
                    self._translations[lang_code] = {}
            else:
                # 如果文件不存在，使用空字典
                self._translations[lang_code] = {}
    
    def t(self, key: str, lang: str = DEFAULT_LANGUAGE, **kwargs) -> str:
        """别名方法，兼容旧代码"""
        return self.get(key, lang, **kwargs)
    
    def get(self, key: str, lang: str = DEFAULT_LANGUAGE, **kwargs) -> str:
        """
        获取翻译文本
        
        Args:
            key: 翻译键（支持点号分隔的嵌套键，如 "auth.login.success"）
            lang: 语言代码
            **kwargs: 格式化参数
        
        Returns:
            翻译后的文本，如果找不到则返回键本身
        """
        # 规范化语言代码
        lang = self.normalize_language(lang)
        
        # 获取翻译字典
        translations = self._translations.get(lang, {})
        
        # 如果语言不存在，回退到默认语言
        if not translations and lang != DEFAULT_LANGUAGE:
            translations = self._translations.get(DEFAULT_LANGUAGE, {})
        
        # 解析嵌套键
        value = translations
        for part in key.split("."):
            if isinstance(value, dict):
                value = value.get(part)
            else:
                value = None
                break
        
        # 如果找到翻译
        if value and isinstance(value, str):
            # 格式化参数
            if kwargs:
                try:
                    return value.format(**kwargs)
                except (KeyError, ValueError):
                    return value
            return value
        
        # 如果找不到，尝试使用默认语言
        if lang != DEFAULT_LANGUAGE:
            return self.get(key, DEFAULT_LANGUAGE, **kwargs)
        
        # 如果还是找不到，返回键本身
        return key
    
    @staticmethod
    def normalize_language(lang: Optional[str]) -> str:
        """
        规范化语言代码
        
        Args:
            lang: 原始语言代码（可能是 "zh", "zh-TW", "zh_TW" 等）
        
        Returns:
            规范化的语言代码（如 "zh_TW"）
        """
        if not lang:
            return DEFAULT_LANGUAGE
        
        lang = lang.replace("-", "_")
        
        # 检查映射表
        if lang in LANGUAGE_MAP:
            return LANGUAGE_MAP[lang]
        
        # 检查是否直接支持
        if lang in SUPPORTED_LANGUAGES:
            return lang
        
        # 提取基础语言代码（如 "zh_TW" -> "zh"）
        base_lang = lang.split("_")[0]
        if base_lang in LANGUAGE_MAP:
            return LANGUAGE_MAP[base_lang]
        
        # 默认返回繁体中文
        return DEFAULT_LANGUAGE
    
    @staticmethod
    def detect_language(request: Request, user_lang: Optional[str] = None) -> str:
        """
        检测用户语言
        
        优先级：
        1. 用户设置的语言（数据库）
        2. Accept-Language 请求头
        3. 默认语言
        
        Args:
            request: FastAPI 请求对象
            user_lang: 用户设置的语言（从数据库获取）
        
        Returns:
            检测到的语言代码
        """
        # 优先使用用户设置的语言
        if user_lang:
            return I18n.normalize_language(user_lang)
        
        # 从请求头获取
        accept_language = request.headers.get("Accept-Language", "")
        if accept_language:
            # 解析 Accept-Language 头（格式：en-US,en;q=0.9,zh-TW;q=0.8）
            languages = []
            for lang_part in accept_language.split(","):
                lang_part = lang_part.strip()
                if ";" in lang_part:
                    lang_code = lang_part.split(";")[0]
                else:
                    lang_code = lang_part
                languages.append(lang_code)
            
            # 尝试匹配支持的语言
            for lang in languages:
                normalized = I18n.normalize_language(lang)
                if normalized in SUPPORTED_LANGUAGES:
                    return normalized
        
        # 返回默认语言
        return DEFAULT_LANGUAGE


# 全局 i18n 实例
i18n = I18n()


def t(key: str, lang: str = DEFAULT_LANGUAGE, **kwargs) -> str:
    """
    翻译函数（快捷方式）
    
    Args:
        key: 翻译键
        lang: 语言代码
        **kwargs: 格式化参数
    
    Returns:
        翻译后的文本
    """
    return i18n.get(key, lang, **kwargs)


def get_language_from_request(request: Request, user_lang: Optional[str] = None) -> str:
    """
    从请求中获取语言（用于依赖注入）
    
    Args:
        request: FastAPI 请求对象
        user_lang: 用户设置的语言
    
    Returns:
        语言代码
    """
    return I18n.detect_language(request, user_lang)
