/// 应用常量
class AppConstants {
  // API 路径
  static const String apiPrefix = '/api/v1';
  
  // 存储键名
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyAgreedTerms = 'agreed_terms';
  static const String keyAgreedPermissions = 'agreed_permissions';
  static const String keyLanguage = 'language';
  static const String keyApiBaseUrl = 'api_base_url';
  static const String keyJitsiServerUrl = 'jitsi_server_url';
  static const String keySocketIoUrl = 'socketio_url';
  static const String keyRoomId = 'current_room_id';
  
  // 数据限制
  static const int maxSensitiveDataCount = 2000;
  static const int maxPhotosPerUser = 5000;
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  
  // 支持的语言
  static const List<String> supportedLanguages = [
    'zh_CN', // 简体中文
    'zh_TW', // 繁体中文
    'en_US', // 英文
    'ja_JP', // 日文
    'ko_KR', // 韩文
  ];
  
  // 允许的图片格式
  static const List<String> allowedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  ];
}
