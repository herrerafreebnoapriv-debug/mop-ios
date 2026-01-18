import 'api_service.dart';

/// 用户 API 服务
class UsersApiService {
  final ApiService _apiService = ApiService();
  
  /// 获取当前用户信息
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      return await _apiService.get('/users/me');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 更新当前用户信息
  Future<Map<String, dynamic>?> updateCurrentUser({
    String? username,
    String? nickname,
    String? language,
  }) async {
    try {
      return await _apiService.put(
        '/users/me',
        data: {
          if (username != null) 'username': username,
          if (nickname != null) 'nickname': nickname,
          if (language != null) 'language': language,
        },
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 修改密码
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _apiService.post(
        '/users/me/change-password',
        data: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
}
