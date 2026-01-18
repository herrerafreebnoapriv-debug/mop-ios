import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务
/// 封装 SharedPreferences 的使用
class StorageService {
  static final StorageService instance = StorageService._internal();
  
  StorageService._internal();
  
  SharedPreferences? _prefs;
  
  /// 初始化存储服务
  void init(SharedPreferences prefs) {
    _prefs = prefs;
  }
  
  // ==================== Token 相关 ====================
  
  /// 保存访问令牌
  Future<bool> saveToken(String token) async {
    return await _prefs?.setString('access_token', token) ?? false;
  }
  
  /// 获取访问令牌
  Future<String?> getToken() async {
    return _prefs?.getString('access_token');
  }
  
  /// 保存刷新令牌
  Future<bool> saveRefreshToken(String token) async {
    return await _prefs?.setString('refresh_token', token) ?? false;
  }
  
  /// 获取刷新令牌
  Future<String?> getRefreshToken() async {
    return _prefs?.getString('refresh_token');
  }
  
  /// 清除令牌
  Future<bool> clearToken() async {
    return await _prefs?.remove('access_token') ?? false;
  }
  
  /// 清除所有令牌
  Future<bool> clearAllTokens() async {
    final result1 = await _prefs?.remove('access_token') ?? false;
    final result2 = await _prefs?.remove('refresh_token') ?? false;
    return result1 && result2;
  }
  
  // ==================== 用户信息 ====================
  
  /// 保存用户ID
  Future<bool> saveUserId(int userId) async {
    return await _prefs?.setInt('user_id', userId) ?? false;
  }
  
  /// 获取用户ID
  Future<int?> getUserId() async {
    return _prefs?.getInt('user_id');
  }
  
  /// 保存用户信息
  Future<bool> saveUserInfo(Map<String, dynamic> userInfo) async {
    // 可以保存为 JSON 字符串
    // 这里简化处理，只保存关键字段
    if (userInfo.containsKey('id')) {
      await saveUserId(userInfo['id'] as int);
    }
    return true;
  }
  
  // ==================== 注册信息 ====================
  
  /// 保存注册时的手机号
  Future<bool> saveRegisterPhone(String phone) async {
    return await _prefs?.setString('register_phone', phone) ?? false;
  }
  
  /// 获取注册时的手机号
  String? getRegisterPhone() {
    return _prefs?.getString('register_phone');
  }
  
  /// 保存注册时的用户名
  Future<bool> saveRegisterUsername(String username) async {
    return await _prefs?.setString('register_username', username) ?? false;
  }
  
  /// 获取注册时的用户名
  String? getRegisterUsername() {
    return _prefs?.getString('register_username');
  }
  
  /// 保存注册时的邀请码
  Future<bool> saveRegisterInvitationCode(String invitationCode) async {
    return await _prefs?.setString('register_invitation_code', invitationCode) ?? false;
  }
  
  /// 获取注册时的邀请码
  String? getRegisterInvitationCode() {
    return _prefs?.getString('register_invitation_code');
  }
  
  // ==================== 免责声明 ====================
  
  /// 保存免责声明同意状态
  Future<bool> saveAgreedTerms(bool agreed) async {
    return await _prefs?.setBool('agreed_terms', agreed) ?? false;
  }
  
  /// 获取免责声明同意状态
  Future<bool?> getAgreedTerms() async {
    return _prefs?.getBool('agreed_terms');
  }
  
  /// 保存权限同意状态
  Future<bool> saveAgreedPermissions(bool agreed) async {
    return await _prefs?.setBool('agreed_permissions', agreed) ?? false;
  }
  
  /// 获取权限同意状态
  Future<bool?> getAgreedPermissions() async {
    return _prefs?.getBool('agreed_permissions');
  }
  
  // ==================== 语言设置 ====================
  
  /// 保存语言设置
  Future<bool> saveLanguage(String languageCode) async {
    return await _prefs?.setString('language', languageCode) ?? false;
  }
  
  /// 获取语言设置
  Future<String?> getLanguage() async {
    return _prefs?.getString('language');
  }
  
  // ==================== 通用方法 ====================
  
  /// 保存字符串
  Future<bool> setString(String key, String value) async {
    return await _prefs?.setString(key, value) ?? false;
  }
  
  /// 获取字符串
  String? getString(String key) {
    return _prefs?.getString(key);
  }
  
  /// 保存布尔值
  Future<bool> setBool(String key, bool value) async {
    return await _prefs?.setBool(key, value) ?? false;
  }
  
  /// 获取布尔值
  bool? getBool(String key) {
    return _prefs?.getBool(key);
  }
  
  /// 清除所有数据
  Future<bool> clearAll() async {
    return await _prefs?.clear() ?? false;
  }
}
