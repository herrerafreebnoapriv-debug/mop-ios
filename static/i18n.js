/**
 * 前端 i18n 工具
 * 从后端 API 加载多语言资源
 */

let currentLanguage = 'en_US';
let translations = {};

/**
 * 初始化 i18n
 */
async function initI18n() {
    // 从 localStorage 获取保存的语言
    const savedLang = localStorage.getItem('user_language');
    
    // 从浏览器语言检测
    const browserLang = navigator.language || navigator.userLanguage;
    
    // 确定当前语言（默认繁体中文）
    currentLanguage = savedLang || normalizeLanguage(browserLang) || 'zh_TW';
    
    // 加载翻译资源，确保加载完成
    const loaded = await loadTranslations(currentLanguage);
    
    if (!loaded) {
    }
    
    // 更新页面文本（由调用者负责）
    // updatePageText(); // 移除这里，让调用者控制更新时机
}

/**
 * 规范化语言代码
 */
function normalizeLanguage(lang) {
    if (!lang) return 'en_US';
    
    // 映射表
    const langMap = {
        'en': 'en_US',
        'en-US': 'en_US',
        'en-GB': 'en_US',
        'zh-TW': 'zh_TW',
        'zh-Hant': 'zh_TW',
        'zh-HK': 'zh_TW',
        'zh-MO': 'zh_TW',
        'es': 'es_ES',
        'es-ES': 'es_ES',
        'es-MX': 'es_ES',
        'fr': 'fr_FR',
        'fr-FR': 'fr_FR',
        'fr-CA': 'fr_FR',
        'de': 'de_DE',
        'de-DE': 'de_DE',
        'de-AT': 'de_DE',
        'ja': 'ja_JP',
        'ja-JP': 'ja_JP',
        'ko': 'ko_KR',
        'ko-KR': 'ko_KR',
        'pt-BR': 'pt_BR',
        'pt': 'pt_BR',
        'ru': 'ru_RU',
        'ru-RU': 'ru_RU',
        'ar': 'ar_SA',
        'ar-SA': 'ar_SA',
        'ar-AE': 'ar_SA',
    };
    
    const normalized = lang.replace('_', '-');
    return langMap[normalized] || langMap[normalized.split('-')[0]] || 'zh_TW';
}

/**
 * 加载翻译资源
 */
async function loadTranslations(lang) {
    try {
        const response = await fetch(`/api/v1/i18n/translations?lang=${lang}`);
        if (response.ok) {
            const data = await response.json();
            if (data && typeof data === 'object' && Object.keys(data).length > 0) {
                translations = data;
                return true;
            }
        }
        // 回退到繁体中文（默认语言）
        if (lang !== 'zh_TW') {
            return await loadTranslations('zh_TW');
        }
        // 如果连默认语言都加载失败，使用空对象
        translations = {};
        return false;
    } catch (error) {
        console.error('Failed to load translations:', error);
        // 回退到繁体中文（默认语言）
        if (lang !== 'zh_TW') {
            try {
                return await loadTranslations('zh_TW');
            } catch (fallbackError) {
                console.error('Failed to load fallback translations:', fallbackError);
                translations = {};
                return false;
            }
        }
        translations = {};
        return false;
    }
}

/**
 * 获取翻译文本
 */
function t(key, params = {}) {
    // 如果翻译资源为空，返回键本身（避免显示空字符串）
    if (!translations || Object.keys(translations).length === 0) {
        return key;
    }
    
    const keys = key.split('.');
    let value = translations;
    
    for (const k of keys) {
        if (value && typeof value === 'object' && k in value) {
            value = value[k];
        } else {
            return key; // 返回键本身
        }
    }
    
    if (typeof value !== 'string') {
        return key;
    }
    
    // 替换参数
    return value.replace(/\{(\w+)\}/g, (match, paramKey) => {
        return params[paramKey] !== undefined ? params[paramKey] : match;
    });
}

/**
 * 切换语言
 */
async function switchLanguage(lang) {
    currentLanguage = lang;
    localStorage.setItem('user_language', lang);
    const loaded = await loadTranslations(lang);
    
    if (!loaded) {
    }
    
    // 更新页面文本（由调用者负责）
    // updatePageText(); // 移除这里，让调用者控制更新时机
    
    // 如果已登录，保存到后端
    const token = localStorage.getItem('access_token');
    if (token) {
        try {
            await fetch('/api/v1/i18n/switch', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({ language: lang })
            });
        } catch (error) {
            console.error('Failed to save language preference:', error);
        }
    }
}

/**
 * 更新页面文本（需要在每个页面中实现）
 */
function updatePageText() {
    // 这个方法需要在每个页面中重写
    // 使用 data-i18n 属性自动更新
    document.querySelectorAll('[data-i18n]').forEach(element => {
        const key = element.getAttribute('data-i18n');
        const text = t(key);
        if (text !== key) {
            if (element.tagName === 'INPUT' && element.type !== 'submit' && element.type !== 'button') {
                element.placeholder = text;
            } else {
                element.textContent = text;
            }
        }
    });
    
    // 更新 title
    const titleKey = document.querySelector('meta[name="i18n-title"]');
    if (titleKey) {
        document.title = t(titleKey.content);
    }
}

// 导出到全局
window.i18n = {
    init: initI18n,
    t: t,
    switchLanguage: switchLanguage,
    getCurrentLanguage: () => currentLanguage,
    updatePageText: updatePageText
};
