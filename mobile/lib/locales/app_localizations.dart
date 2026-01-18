import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

/// 应用国际化
class AppLocalizations {
  final Locale locale;
  
  AppLocalizations(this.locale);
  
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }
  
  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  
  Map<String, String>? _localizedStrings;
  
  Future<bool> load() async {
    try {
      // 尝试加载语言文件
      final jsonString = await rootBundle.loadString('assets/locales/${locale.languageCode}_${locale.countryCode}.json');
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      
      // 扁平化嵌套的 JSON 结构
      _localizedStrings = _flattenMap(jsonMap);
      return true;
    } catch (e) {
      // 如果加载失败，尝试加载默认语言（繁体中文，与后端保持一致）
      if (locale.toString() != 'zh_TW') {
        try {
          final jsonString = await rootBundle.loadString('assets/locales/zh_TW.json');
          final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
          _localizedStrings = _flattenMap(jsonMap);
          return true;
        } catch (e2) {
          // 如果默认语言也加载失败，使用空映射
          _localizedStrings = {};
          return false;
        }
      } else {
        _localizedStrings = {};
        return false;
      }
    }
  }
  
  /// 扁平化嵌套的 JSON 映射
  /// 例如：{"app": {"name": "和平信使"}} -> {"app.name": "和平信使"}
  Map<String, String> _flattenMap(Map<String, dynamic> map, {String prefix = ''}) {
    final result = <String, String>{};
    
    map.forEach((key, value) {
      final newKey = prefix.isEmpty ? key : '$prefix.$key';
      
      if (value is Map<String, dynamic>) {
        // 递归处理嵌套的 Map
        result.addAll(_flattenMap(value, prefix: newKey));
      } else {
        // 直接添加字符串值
        result[newKey] = value.toString();
      }
    });
    
    return result;
  }
  
  String translate(String key) {
    return _localizedStrings?[key] ?? key;
  }
  
  String t(String key) => translate(key);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  
  @override
  bool isSupported(Locale locale) {
    // 支持所有后端定义的语言（与网页端保持一致）
    final supportedCodes = [
      'en', 'zh', 'es', 'fr', 'de', 'ja', 'ko', 'pt', 'ru', 'ar'
    ];
    return supportedCodes.contains(locale.languageCode);
  }
  
  @override
  Future<AppLocalizations> load(Locale locale) async {
    final localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }
  
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
