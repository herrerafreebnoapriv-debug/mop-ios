import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/endpoint_manager.dart';

/// 应用配置管理
/// 管理动态获取的 API 地址、Jitsi 服务器地址等配置
/// 支持多端点管理和自动故障转移
class AppConfig {
  static final AppConfig instance = AppConfig._internal();
  
  AppConfig._internal();
  
  static const String _keyApiBaseUrl = 'api_base_url';
  static const String _keyChatUrl = 'chat_url';  // 聊天页面URL（移动端登录前扫码获取）
  static const String _keyJitsiServerUrl = 'jitsi_server_url';
  static const String _keySocketIoUrl = 'socketio_url';
  static const String _keyRoomId = 'current_room_id';
  static const String _keyRsaPublicKey = 'rsa_public_key';
  
  String? _apiBaseUrl;
  String? _chatUrl;  // 聊天页面URL
  String? _jitsiServerUrl;
  String? _socketIoUrl;
  String? _roomId;
  String? _rsaPublicKey;
  
  /// API 基础地址（从 EndpointManager 获取，支持多端点）
  String? get apiBaseUrl {
    // 优先从 EndpointManager 获取
    final endpointUrl = EndpointManager.instance.getCurrentApiUrl();
    if (endpointUrl != null) {
      return endpointUrl;
    }
    // 回退到旧配置
    return _apiBaseUrl;
  }
  
  /// Jitsi 服务器地址
  String? get jitsiServerUrl => _jitsiServerUrl;
  
  /// Socket.io 服务器地址（从 EndpointManager 获取，支持多端点）
  String? get socketIoUrl {
    // 优先从 EndpointManager 获取
    final endpointUrl = EndpointManager.instance.getCurrentSocketUrl();
    if (endpointUrl != null) {
      return endpointUrl;
    }
    // 回退到旧配置
    return _socketIoUrl;
  }
  
  /// 当前房间ID
  String? get roomId => _roomId;
  
  /// RSA 公钥（用于解密二维码）
  String? get rsaPublicKey => _rsaPublicKey;
  
  /// 聊天页面URL（移动端登录前扫码获取的接口）
  String? get chatUrl => _chatUrl;
  
  /// 是否已配置 API 地址
  bool get isConfigured {
    final endpointUrl = EndpointManager.instance.getCurrentApiUrl();
    return (endpointUrl != null && endpointUrl.isNotEmpty) ||
           (_apiBaseUrl != null && _apiBaseUrl!.isNotEmpty);
  }
  
  /// 加载配置（从本地存储）
  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    _apiBaseUrl = prefs.getString(_keyApiBaseUrl);
    _chatUrl = prefs.getString(_keyChatUrl);
    _jitsiServerUrl = prefs.getString(_keyJitsiServerUrl);
    _socketIoUrl = prefs.getString(_keySocketIoUrl);
    _roomId = prefs.getString(_keyRoomId);
    _rsaPublicKey = prefs.getString(_keyRsaPublicKey);
    
    // 如果本地没有 RSA 公钥，尝试从 assets 加载默认公钥
    if (_rsaPublicKey == null || _rsaPublicKey!.isEmpty) {
      await _loadDefaultRsaPublicKey();
    }
    
    // 如果 API 地址已配置，确保 EndpointManager 也有这个地址
    if (_apiBaseUrl != null && _apiBaseUrl!.isNotEmpty) {
      await EndpointManager.instance.addApiEndpoint(_apiBaseUrl!, priority: 0);
    }
  }
  
  /// 从 assets 加载默认 RSA 公钥（内置公钥）
  Future<void> _loadDefaultRsaPublicKey() async {
    try {
      // 从 assets 加载内置的 RSA 公钥文件
      // 这是应用的默认公钥，用于首次扫码时解密二维码
      // RSA 公钥是公开的，可以安全地内置到客户端
      final publicKeyString = await rootBundle.loadString('assets/config/rsa_public_key.pem');
      if (publicKeyString.isNotEmpty) {
        _rsaPublicKey = publicKeyString.trim();
        // 保存到本地存储，避免每次都从 assets 读取
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyRsaPublicKey, _rsaPublicKey!);
        debugPrint('✓ 已加载内置 RSA 公钥');
      }
    } catch (e) {
      // 如果加载失败（例如文件不存在），保持为 null
      // 后续可以从 API 获取
      debugPrint('从 assets 加载 RSA 公钥失败: $e（如果尚未构建，这是正常的）');
      _rsaPublicKey = null;
    }
  }
  
  /// 从 API 获取 RSA 公钥
  /// 
  /// [customApiUrl] 自定义 API 地址（可选，如果不提供则使用当前配置的地址）
  Future<bool> fetchRsaPublicKeyFromApi({String? customApiUrl}) async {
    try {
      // 确定要使用的 API 地址
      String? targetUrl = customApiUrl ?? apiBaseUrl;
      
      // 如果还没有配置 API 地址，无法获取公钥
      if (targetUrl == null || targetUrl.isEmpty) {
        return false;
      }
      
      // 确保 URL 格式正确（移除末尾的 /api/v1，因为路径中已经包含了）
      String baseUrl = targetUrl;
      if (baseUrl.endsWith('/api/v1')) {
        baseUrl = baseUrl.replaceAll('/api/v1', '');
      }
      baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''); // 移除末尾斜杠
      
      // 使用 Dio 直接请求，因为此时可能还没有配置完整的 API 服务
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      
      final response = await dio.get(
        '$baseUrl/api/v1/qrcode/public-key',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final publicKey = response.data['public_key'] as String?;
        if (publicKey != null && publicKey.isNotEmpty) {
          await setRsaPublicKey(publicKey);
          // 如果使用了自定义地址，也更新 API 地址配置
          if (customApiUrl != null && customApiUrl.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyApiBaseUrl, customApiUrl);
            _apiBaseUrl = customApiUrl;
            await EndpointManager.instance.addApiEndpoint(customApiUrl, priority: 0);
          }
          return true;
        }
      }
      return false;
    } catch (e) {
      // 获取失败，返回 false
      debugPrint('获取 RSA 公钥失败: $e');
      return false;
    }
  }
  
  /// 设置 RSA 公钥
  Future<void> setRsaPublicKey(String publicKey) async {
    final prefs = await SharedPreferences.getInstance();
    _rsaPublicKey = publicKey;
    await prefs.setString(_keyRsaPublicKey, publicKey);
  }
  
  /// 更新配置（扫码后调用）
  /// [data] 是从二维码解析出来的配置数据
  Future<void> updateConfig(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 更新端点管理器
    await EndpointManager.instance.updateEndpointsFromQRCode(data);
    
    // 移动端登录前扫码：优先处理聊天页面URL（chat_url）
    if (data.containsKey('chat_url')) {
      _chatUrl = data['chat_url'] as String;
      await prefs.setString(_keyChatUrl, _chatUrl!);
      
      // 从聊天页面URL提取API地址
      if (!data.containsKey('api_url')) {
        final uri = Uri.parse(_chatUrl!);
        if (uri.host.isNotEmpty) {
          final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
          _apiBaseUrl = '$baseUrl/api/v1';
        } else {
          _apiBaseUrl = '/api/v1';
        }
        await prefs.setString(_keyApiBaseUrl, _apiBaseUrl!);
        await EndpointManager.instance.addApiEndpoint(_apiBaseUrl!, priority: 0);
      }
    }
    
    // 兼容旧格式：直接提供 API URL
    if (data.containsKey('api_url')) {
      _apiBaseUrl = data['api_url'] as String;
      await prefs.setString(_keyApiBaseUrl, _apiBaseUrl!);
      // 同时添加到端点管理器
      await EndpointManager.instance.addApiEndpoint(_apiBaseUrl!, priority: 0);
    }
    
    if (data.containsKey('jitsi_server_url')) {
      _jitsiServerUrl = data['jitsi_server_url'] as String;
      await prefs.setString(_keyJitsiServerUrl, _jitsiServerUrl!);
    }
    
    if (data.containsKey('socketio_url')) {
      _socketIoUrl = data['socketio_url'] as String;
      await prefs.setString(_keySocketIoUrl, _socketIoUrl!);
      // 同时添加到端点管理器
      await EndpointManager.instance.addSocketEndpoint(_socketIoUrl!, priority: 0);
    }
    
    if (data.containsKey('room_id')) {
      _roomId = data['room_id'] as String;
      await prefs.setString(_keyRoomId, _roomId!);
    }
    
    // 如果只有 room_id 而没有 api_url，尝试保留已有的 API 配置
    // 这样可以避免扫码后清空已有的 API 地址配置
    if (!data.containsKey('api_url') && !data.containsKey('chat_url')) {
      // 如果之前有配置过 API 地址，保留使用
      if (_apiBaseUrl == null || _apiBaseUrl!.isEmpty) {
        // 尝试从 SharedPreferences 重新加载
        final savedApiUrl = prefs.getString(_keyApiBaseUrl);
        if (savedApiUrl != null && savedApiUrl.isNotEmpty) {
          _apiBaseUrl = savedApiUrl;
          // 确保端点管理器也有这个地址
          await EndpointManager.instance.addApiEndpoint(_apiBaseUrl!, priority: 0);
        }
      }
    }
  }
  
  /// 清除配置
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.remove(_keyApiBaseUrl);
    await prefs.remove(_keyChatUrl);
    await prefs.remove(_keyJitsiServerUrl);
    await prefs.remove(_keySocketIoUrl);
    await prefs.remove(_keyRoomId);
    // 不清除 RSA 公钥，因为它是应用级别的配置
    
    _apiBaseUrl = null;
    _chatUrl = null;
    _jitsiServerUrl = null;
    _socketIoUrl = null;
    _roomId = null;
  }
}
