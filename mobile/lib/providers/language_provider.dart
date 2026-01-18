import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../core/services/storage_service.dart';
import '../core/config/app_config.dart';
import '../services/api/api_service.dart';
import '../locales/app_localizations.dart';

/// 语言状态管理
class LanguageProvider extends ChangeNotifier {
  Locale _currentLocale = const Locale('zh', 'TW');
  bool _isInitialized = false;
  
  Locale get currentLocale => _currentLocale;
  bool get isInitialized => _isInitialized;
  
  LanguageProvider() {
    loadLanguage();
  }
  
  /// 规范化语言代码（与后端 app/core/i18n.py 保持一致）
  static String normalizeLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return 'zh_TW';
    
    // 映射表（与后端 LANGUAGE_MAP 保持一致）
    final langMap = {
      'en': 'en_US',
      'en-US': 'en_US',
      'en-GB': 'en_US',
      // 注意：后端不支持 zh_CN，只支持 zh_TW
      'zh-CN': 'zh_TW',  // 简体中文映射到繁体中文
      'zh': 'zh_TW',     // 默认中文映射到繁体中文
      'zh-TW': 'zh_TW',
      'zh-Hant': 'zh_TW',
      'zh-HK': 'zh_TW',
      'zh-MO': 'zh_TW',
      'es': 'es_ES',
      'es-ES': 'es_ES',
      'es-MX': 'es_ES',
      'es-AR': 'es_ES',
      'fr': 'fr_FR',
      'fr-FR': 'fr_FR',
      'fr-CA': 'fr_FR',
      'de': 'de_DE',
      'de-DE': 'de_DE',
      'de-AT': 'de_DE',
      'de-CH': 'de_DE',
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
      'ar-EG': 'ar_SA',
    };
    
    final normalized = lang.replaceAll('_', '-');
    return langMap[normalized] ?? langMap[normalized.split('-')[0]] ?? 'zh_TW';
  }
  
  /// 从系统语言获取 Locale
  static Locale _getSystemLocale() {
    try {
      final systemLocale = ui.PlatformDispatcher.instance.locale;
      final langCode = normalizeLanguage('${systemLocale.languageCode}-${systemLocale.countryCode}');
      final parts = langCode.split('_');
      if (parts.length == 2) {
        return Locale(parts[0], parts[1]);
      }
    } catch (e) {
      // 忽略错误，使用默认值
    }
    return const Locale('zh', 'TW');
  }
  
  /// 加载语言设置
  Future<void> loadLanguage() async {
    // 先从本地存储读取
    final savedLanguageCode = await StorageService.instance.getLanguage();
    
    if (savedLanguageCode != null && savedLanguageCode.isNotEmpty) {
      // 使用保存的语言
      final parts = savedLanguageCode.split('_');
      if (parts.length == 2) {
        _currentLocale = Locale(parts[0], parts[1]);
        _isInitialized = true;
        notifyListeners();
        return;
      }
    }
    
    // 如果没有保存的语言，使用系统语言（与网页端逻辑一致）
    _currentLocale = _getSystemLocale();
    final systemLangCode = '${_currentLocale.languageCode}_${_currentLocale.countryCode}';
    
    // 保存系统语言到本地存储（与网页端 localStorage 行为一致）
    await StorageService.instance.saveLanguage(systemLangCode);
    
    _isInitialized = true;
    notifyListeners();
  }
  
  /// 切换语言
  Future<void> changeLanguage(Locale locale) async {
    if (_currentLocale != locale) {
      _currentLocale = locale;
      final languageCode = '${locale.languageCode}_${locale.countryCode}';
      
      // 保存到本地存储
      await StorageService.instance.saveLanguage(languageCode);
      
      // 如果已登录，保存到后端（与网页端逻辑一致）
      final token = await StorageService.instance.getToken();
      if (token != null && AppConfig.instance.apiBaseUrl != null) {
        try {
          final apiService = ApiService();
          await apiService.post(
            '/i18n/switch',
            data: {'language': languageCode},
          );
        } catch (e) {
          // 忽略错误，本地已保存
          print('Failed to save language preference to server: $e');
        }
      }
      
      notifyListeners();
    }
  }
  
  /// 支持的语言列表（与网页端保持一致，移除zh_CN，只保留zh_TW）
  static const List<Locale> supportedLocales = [
    Locale('en', 'US'),  // English
    Locale('zh', 'TW'),  // 繁體中文
    Locale('es', 'ES'),  // Español
    Locale('fr', 'FR'),  // Français
    Locale('de', 'DE'),  // Deutsch
    Locale('ja', 'JP'),  // 日本語
    Locale('ko', 'KR'),  // 한국어
    Locale('pt', 'BR'),  // Português (Brasil)
    Locale('ru', 'RU'),  // Русский
    Locale('ar', 'SA'),  // العربية
  ];
  
  /// 获取语言显示名称（使用多语言，禁用硬编码）
  static String getLanguageName(Locale locale, {BuildContext? context}) {
    // 必须提供context才能获取多语言资源
    if (context != null) {
      final l10n = AppLocalizations.of(context);
      if (l10n != null) {
        final code = '${locale.languageCode}_${locale.countryCode}';
        // 根据语言代码从多语言资源文件读取
        switch (code) {
          case 'zh_TW':
            return l10n.t('language.traditional_chinese');
          case 'en_US':
            return l10n.t('language.english');
          case 'es_ES':
            return l10n.t('language.spanish');
          case 'fr_FR':
            return l10n.t('language.french');
          case 'de_DE':
            return l10n.t('language.german');
          case 'ja_JP':
            return l10n.t('language.japanese');
          case 'ko_KR':
            return l10n.t('language.korean');
          case 'pt_BR':
            return l10n.t('language.portuguese');
          case 'ru_RU':
            return l10n.t('language.russian');
          case 'ar_SA':
            return l10n.t('language.arabic');
          default:
            // 如果找不到匹配，尝试使用当前语言环境下的通用语言名称
            // 使用语言代码的首字母大写格式作为最后回退
            final langName = locale.languageCode.isEmpty 
                ? l10n.t('common.unknown') 
                : locale.languageCode[0].toUpperCase() + locale.languageCode.substring(1);
            return langName;
        }
      }
    }
    
    // 如果没有context或l10n，返回语言代码（避免硬编码）
    // 这种情况应该很少发生，因为通常都有context
    final code = '${locale.languageCode}_${locale.countryCode}';
    return code;
  }
}
