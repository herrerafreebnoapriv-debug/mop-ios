import 'api_service.dart';
import '../../models/user_model.dart';

/// 认证 API 服务
class AuthApiService {
  final ApiService _apiService = ApiService();
  
  /// 登录
  /// 注意：后端使用 OAuth2PasswordRequestForm，需要发送 form-data 格式
  Future<TokenResponse?> login(String phoneOrUsername, String password) async {
    try {
      // OAuth2PasswordRequestForm 期望 form-data 格式
      final response = await _apiService.post(
        '/auth/login',
        data: {
          'username': phoneOrUsername,
          'password': password,
        },
        isFormData: true,  // 标记为 form-data
      );
      
      if (response != null && response['access_token'] != null) {
        return TokenResponse.fromJson(response);
      }
      return null;
    } catch (e) {
      // 重新抛出异常，让调用者可以获取详细错误信息
      rethrow;
    }
  }
  
  /// 注册
  Future<TokenResponse?> register({
    required String phone,
    required String username,
    required String password,
    String? nickname,
    required String invitationCode,
    required bool agreedToTerms,
  }) async {
    try {
      final response = await _apiService.post(
        '/auth/register',
        data: {
          'phone': phone,
          'username': username,
          'password': password,
          'nickname': nickname,
          'invitation_code': invitationCode,
          'agreed_to_terms': agreedToTerms,
        },
      );
      
      if (response != null && response['access_token'] != null) {
        return TokenResponse.fromJson(response);
      }
      return null;
    } catch (e) {
      // 重新抛出异常，让调用者可以获取详细错误信息
      rethrow;
    }
  }
  
  /// 获取当前用户信息
  Future<UserModel?> getCurrentUser() async {
    try {
      final response = await _apiService.get('/auth/me');
      if (response != null) {
        return UserModel.fromJson(response);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 同意免责声明
  Future<bool> agreeTerms() async {
    try {
      final response = await _apiService.post(
        '/auth/agree-terms',
        data: {'agreed': true},
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 刷新令牌
  Future<TokenResponse?> refreshToken(String refreshToken) async {
    try {
      final response = await _apiService.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      
      if (response != null && response['access_token'] != null) {
        return TokenResponse.fromJson(response);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
