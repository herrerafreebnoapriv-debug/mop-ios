import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端点信息
class EndpointInfo {
  final String url;
  final int priority; // 优先级，数字越小优先级越高
  final DateTime? lastChecked;
  final bool isHealthy;
  final int failureCount;
  final Duration? responseTime;
  
  EndpointInfo({
    required this.url,
    this.priority = 0,
    this.lastChecked,
    this.isHealthy = true,
    this.failureCount = 0,
    this.responseTime,
  });
  
  EndpointInfo copyWith({
    String? url,
    int? priority,
    DateTime? lastChecked,
    bool? isHealthy,
    int? failureCount,
    Duration? responseTime,
  }) {
    return EndpointInfo(
      url: url ?? this.url,
      priority: priority ?? this.priority,
      lastChecked: lastChecked ?? this.lastChecked,
      isHealthy: isHealthy ?? this.isHealthy,
      failureCount: failureCount ?? this.failureCount,
      responseTime: responseTime ?? this.responseTime,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'priority': priority,
      'last_checked': lastChecked?.toIso8601String(),
      'is_healthy': isHealthy,
      'failure_count': failureCount,
      'response_time_ms': responseTime?.inMilliseconds,
    };
  }
  
  factory EndpointInfo.fromJson(Map<String, dynamic> json) {
    return EndpointInfo(
      url: json['url'] as String,
      priority: json['priority'] as int? ?? 0,
      lastChecked: json['last_checked'] != null 
          ? DateTime.parse(json['last_checked'] as String)
          : null,
      isHealthy: json['is_healthy'] as bool? ?? true,
      failureCount: json['failure_count'] as int? ?? 0,
      responseTime: json['response_time_ms'] != null
          ? Duration(milliseconds: json['response_time_ms'] as int)
          : null,
    );
  }
}

/// 端点管理器
/// 管理多个 API 端点，支持健康检查、故障转移和自动更新
class EndpointManager {
  static final EndpointManager instance = EndpointManager._internal();
  EndpointManager._internal();
  
  static const String _keyEndpoints = 'api_endpoints';
  static const String _keyCurrentEndpoint = 'current_api_endpoint';
  static const String _keySocketEndpoints = 'socketio_endpoints';
  static const String _keyCurrentSocketEndpoint = 'current_socketio_endpoint';
  
  List<EndpointInfo> _apiEndpoints = [];
  List<EndpointInfo> _socketEndpoints = [];
  EndpointInfo? _currentApiEndpoint;
  EndpointInfo? _currentSocketEndpoint;
  
  Timer? _healthCheckTimer;
  final Dio _healthCheckDio = Dio();
  
  // 健康检查配置
  static const Duration _healthCheckInterval = Duration(minutes: 5);
  static const Duration _healthCheckTimeout = Duration(seconds: 5);
  static const int _maxFailureCount = 3; // 连续失败3次后标记为不健康
  
  // 回调函数
  Function(EndpointInfo)? onEndpointChanged;
  Function(List<EndpointInfo>)? onEndpointsUpdated;
  
  List<EndpointInfo> get apiEndpoints => List.unmodifiable(_apiEndpoints);
  List<EndpointInfo> get socketEndpoints => List.unmodifiable(_socketEndpoints);
  EndpointInfo? get currentApiEndpoint => _currentApiEndpoint;
  EndpointInfo? get currentSocketEndpoint => _currentSocketEndpoint;
  
  /// 初始化端点管理器
  Future<void> init() async {
    await _loadEndpoints();
    await _selectBestEndpoints();
    _startHealthCheck();
  }
  
  /// 从本地存储加载端点列表
  Future<void> _loadEndpoints() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 加载 API 端点（使用 JSON 字符串存储）
    final apiEndpointsJson = prefs.getString(_keyEndpoints);
    if (apiEndpointsJson != null && apiEndpointsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(apiEndpointsJson) as List;
        _apiEndpoints = decoded
            .map((json) => EndpointInfo.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // 如果解析失败，尝试从旧格式加载（单个 URL）
        final oldUrl = prefs.getString(_keyCurrentEndpoint);
        if (oldUrl != null) {
          _apiEndpoints = [EndpointInfo(url: oldUrl)];
        }
      }
    }
    
    // 加载当前 API 端点
    final currentApiUrl = prefs.getString(_keyCurrentEndpoint);
    if (currentApiUrl != null && _apiEndpoints.isEmpty) {
      _apiEndpoints = [EndpointInfo(url: currentApiUrl)];
    }
    if (currentApiUrl != null) {
      _currentApiEndpoint = _apiEndpoints.firstWhere(
        (e) => e.url == currentApiUrl,
        orElse: () => EndpointInfo(url: currentApiUrl),
      );
    }
    
    // 加载 Socket.io 端点
    final socketEndpointsJson = prefs.getString(_keySocketEndpoints);
    if (socketEndpointsJson != null && socketEndpointsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(socketEndpointsJson) as List;
        _socketEndpoints = decoded
            .map((json) => EndpointInfo.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        final oldUrl = prefs.getString(_keyCurrentSocketEndpoint);
        if (oldUrl != null) {
          _socketEndpoints = [EndpointInfo(url: oldUrl)];
        }
      }
    }
    
    // 加载当前 Socket.io 端点
    final currentSocketUrl = prefs.getString(_keyCurrentSocketEndpoint);
    if (currentSocketUrl != null && _socketEndpoints.isEmpty) {
      _socketEndpoints = [EndpointInfo(url: currentSocketUrl)];
    }
    if (currentSocketUrl != null) {
      _currentSocketEndpoint = _socketEndpoints.firstWhere(
        (e) => e.url == currentSocketUrl,
        orElse: () => EndpointInfo(url: currentSocketUrl),
      );
    }
  }
  
  /// 保存端点列表到本地存储
  Future<void> _saveEndpoints() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存 API 端点（使用 JSON 字符串）
    if (_apiEndpoints.isNotEmpty) {
      final endpointsJson = jsonEncode(
        _apiEndpoints.map((e) => e.toJson()).toList()
      );
      await prefs.setString(_keyEndpoints, endpointsJson);
    }
    
    // 保存当前 API 端点
    if (_currentApiEndpoint != null) {
      await prefs.setString(_keyCurrentEndpoint, _currentApiEndpoint!.url);
    }
    
    // 保存 Socket.io 端点
    if (_socketEndpoints.isNotEmpty) {
      final endpointsJson = jsonEncode(
        _socketEndpoints.map((e) => e.toJson()).toList()
      );
      await prefs.setString(_keySocketEndpoints, endpointsJson);
    }
    
    // 保存当前 Socket.io 端点
    if (_currentSocketEndpoint != null) {
      await prefs.setString(_keyCurrentSocketEndpoint, _currentSocketEndpoint!.url);
    }
  }
  
  /// 添加 API 端点
  Future<void> addApiEndpoint(String url, {int priority = 0}) async {
    // 检查是否已存在
    final existingIndex = _apiEndpoints.indexWhere((e) => e.url == url);
    if (existingIndex >= 0) {
      // 更新优先级
      _apiEndpoints[existingIndex] = _apiEndpoints[existingIndex].copyWith(
        priority: priority,
      );
    } else {
      // 添加新端点
      _apiEndpoints.add(EndpointInfo(url: url, priority: priority));
    }
    
    // 按优先级排序
    _apiEndpoints.sort((a, b) => a.priority.compareTo(b.priority));
    
    await _saveEndpoints();
    await _selectBestEndpoints();
    onEndpointsUpdated?.call(_apiEndpoints);
  }
  
  /// 添加 Socket.io 端点
  Future<void> addSocketEndpoint(String url, {int priority = 0}) async {
    // 检查是否已存在
    final existingIndex = _socketEndpoints.indexWhere((e) => e.url == url);
    if (existingIndex >= 0) {
      // 更新优先级
      _socketEndpoints[existingIndex] = _socketEndpoints[existingIndex].copyWith(
        priority: priority,
      );
    } else {
      // 添加新端点
      _socketEndpoints.add(EndpointInfo(url: url, priority: priority));
    }
    
    // 按优先级排序
    _socketEndpoints.sort((a, b) => a.priority.compareTo(b.priority));
    
    await _saveEndpoints();
    await _selectBestEndpoints();
    onEndpointsUpdated?.call(_socketEndpoints);
  }
  
  /// 批量更新端点（从远程服务器获取）
  Future<void> updateEndpointsFromRemote({
    String? fallbackUrl,
    String? token,
  }) async {
    // 如果有备用 URL，尝试从备用 URL 获取端点列表
    if (fallbackUrl != null) {
      try {
        final dio = Dio();
        dio.options.connectTimeout = _healthCheckTimeout;
        dio.options.receiveTimeout = _healthCheckTimeout;
        
        if (token != null) {
          dio.options.headers['Authorization'] = 'Bearer $token';
        }
        
        // 尝试从备用端点获取配置
        final response = await dio.get('$fallbackUrl/api/v1/config/endpoints');
        
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          
          // 更新 API 端点
          if (data.containsKey('api_endpoints')) {
            final apiEndpoints = data['api_endpoints'] as List;
            _apiEndpoints.clear();
            for (var endpoint in apiEndpoints) {
              if (endpoint is Map) {
                _apiEndpoints.add(EndpointInfo(
                  url: endpoint['url'] as String,
                  priority: endpoint['priority'] as int? ?? 0,
                ));
              } else if (endpoint is String) {
                _apiEndpoints.add(EndpointInfo(url: endpoint));
              }
            }
            _apiEndpoints.sort((a, b) => a.priority.compareTo(b.priority));
          }
          
          // 更新 Socket.io 端点
          if (data.containsKey('socketio_endpoints')) {
            final socketEndpoints = data['socketio_endpoints'] as List;
            _socketEndpoints.clear();
            for (var endpoint in socketEndpoints) {
              if (endpoint is Map) {
                _socketEndpoints.add(EndpointInfo(
                  url: endpoint['url'] as String,
                  priority: endpoint['priority'] as int? ?? 0,
                ));
              } else if (endpoint is String) {
                _socketEndpoints.add(EndpointInfo(url: endpoint));
              }
            }
            _socketEndpoints.sort((a, b) => a.priority.compareTo(b.priority));
          }
          
          await _saveEndpoints();
          await _selectBestEndpoints();
          onEndpointsUpdated?.call(_apiEndpoints);
        }
      } catch (e) {
        // 远程更新失败，使用现有端点
        print('从远程更新端点失败: $e');
      }
    }
  }
  
  /// 从二维码数据更新端点
  Future<void> updateEndpointsFromQRCode(Map<String, dynamic> qrData) async {
    // 更新 API 端点
    if (qrData.containsKey('api_url')) {
      final apiUrl = qrData['api_url'] as String;
      await addApiEndpoint(apiUrl, priority: 0);
    }
    
    // 如果二维码包含多个端点
    if (qrData.containsKey('api_endpoints')) {
      final endpoints = qrData['api_endpoints'] as List;
      for (var i = 0; i < endpoints.length; i++) {
        final endpoint = endpoints[i] as String;
        await addApiEndpoint(endpoint, priority: i);
      }
    }
    
    // 更新 Socket.io 端点
    if (qrData.containsKey('socketio_url')) {
      final socketUrl = qrData['socketio_url'] as String;
      await addSocketEndpoint(socketUrl, priority: 0);
    }
    
    // 如果二维码包含多个 Socket.io 端点
    if (qrData.containsKey('socketio_endpoints')) {
      final endpoints = qrData['socketio_endpoints'] as List;
      for (var i = 0; i < endpoints.length; i++) {
        final endpoint = endpoints[i] as String;
        await addSocketEndpoint(endpoint, priority: i);
      }
    }
  }
  
  /// 选择最佳端点
  Future<void> _selectBestEndpoints() async {
    // 选择最佳 API 端点
    final healthyApiEndpoints = _apiEndpoints.where((e) => e.isHealthy).toList();
    if (healthyApiEndpoints.isNotEmpty) {
      // 优先选择健康且优先级高的端点
      healthyApiEndpoints.sort((a, b) {
        if (a.priority != b.priority) {
          return a.priority.compareTo(b.priority);
        }
        // 如果优先级相同，选择响应时间短的
        if (a.responseTime != null && b.responseTime != null) {
          return a.responseTime!.compareTo(b.responseTime!);
        }
        return 0;
      });
      
      final newEndpoint = healthyApiEndpoints.first;
      if (_currentApiEndpoint?.url != newEndpoint.url) {
        _currentApiEndpoint = newEndpoint;
        await _saveEndpoints();
        onEndpointChanged?.call(newEndpoint);
      }
    } else if (_apiEndpoints.isNotEmpty) {
      // 如果没有健康的端点，选择优先级最高的
      _currentApiEndpoint = _apiEndpoints.first;
      await _saveEndpoints();
    }
    
    // 选择最佳 Socket.io 端点
    final healthySocketEndpoints = _socketEndpoints.where((e) => e.isHealthy).toList();
    if (healthySocketEndpoints.isNotEmpty) {
      healthySocketEndpoints.sort((a, b) {
        if (a.priority != b.priority) {
          return a.priority.compareTo(b.priority);
        }
        return 0;
      });
      
      final newEndpoint = healthySocketEndpoints.first;
      if (_currentSocketEndpoint?.url != newEndpoint.url) {
        _currentSocketEndpoint = newEndpoint;
        await _saveEndpoints();
        onEndpointChanged?.call(newEndpoint);
      }
    } else if (_socketEndpoints.isNotEmpty) {
      _currentSocketEndpoint = _socketEndpoints.first;
      await _saveEndpoints();
    }
  }
  
  /// 检查端点健康状态
  Future<bool> checkEndpointHealth(EndpointInfo endpoint) async {
    try {
      final stopwatch = Stopwatch()..start();
      
      _healthCheckDio.options.connectTimeout = _healthCheckTimeout;
      _healthCheckDio.options.receiveTimeout = _healthCheckTimeout;
      
      // 尝试访问健康检查端点
      final response = await _healthCheckDio.get(
        '${endpoint.url}/health',
        options: Options(
          validateStatus: (status) => status! < 500, // 接受 2xx, 3xx, 4xx
        ),
      );
      
      stopwatch.stop();
      final responseTime = stopwatch.elapsed;
      
      final isHealthy = response.statusCode != null && 
                       response.statusCode! >= 200 && 
                       response.statusCode! < 500;
      
      // 更新端点状态
      final index = _apiEndpoints.indexWhere((e) => e.url == endpoint.url);
      if (index >= 0) {
        _apiEndpoints[index] = _apiEndpoints[index].copyWith(
          isHealthy: isHealthy,
          lastChecked: DateTime.now(),
          responseTime: responseTime,
          failureCount: isHealthy ? 0 : _apiEndpoints[index].failureCount + 1,
        );
      }
      
      // 检查 Socket.io 端点
      final socketIndex = _socketEndpoints.indexWhere((e) => e.url == endpoint.url);
      if (socketIndex >= 0) {
        _socketEndpoints[socketIndex] = _socketEndpoints[socketIndex].copyWith(
          isHealthy: isHealthy,
          lastChecked: DateTime.now(),
          responseTime: responseTime,
          failureCount: isHealthy ? 0 : _socketEndpoints[socketIndex].failureCount + 1,
        );
      }
      
      // 如果失败次数超过阈值，标记为不健康
      if (!isHealthy && (index >= 0 ? _apiEndpoints[index] : _socketEndpoints[socketIndex]).failureCount >= _maxFailureCount) {
        if (index >= 0) {
          _apiEndpoints[index] = _apiEndpoints[index].copyWith(isHealthy: false);
        }
        if (socketIndex >= 0) {
          _socketEndpoints[socketIndex] = _socketEndpoints[socketIndex].copyWith(isHealthy: false);
        }
        await _selectBestEndpoints();
      }
      
      return isHealthy;
    } catch (e) {
      // 检查失败
      final index = _apiEndpoints.indexWhere((e) => e.url == endpoint.url);
      if (index >= 0) {
        _apiEndpoints[index] = _apiEndpoints[index].copyWith(
          isHealthy: false,
          lastChecked: DateTime.now(),
          failureCount: _apiEndpoints[index].failureCount + 1,
        );
        
        if (_apiEndpoints[index].failureCount >= _maxFailureCount) {
          await _selectBestEndpoints();
        }
      }
      
      final socketIndex = _socketEndpoints.indexWhere((e) => e.url == endpoint.url);
      if (socketIndex >= 0) {
        _socketEndpoints[socketIndex] = _socketEndpoints[socketIndex].copyWith(
          isHealthy: false,
          lastChecked: DateTime.now(),
          failureCount: _socketEndpoints[socketIndex].failureCount + 1,
        );
        
        if (_socketEndpoints[socketIndex].failureCount >= _maxFailureCount) {
          await _selectBestEndpoints();
        }
      }
      
      return false;
    }
  }
  
  /// 开始健康检查
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) async {
      // 检查所有端点
      for (final endpoint in _apiEndpoints) {
        await checkEndpointHealth(endpoint);
      }
      for (final endpoint in _socketEndpoints) {
        await checkEndpointHealth(endpoint);
      }
      
      // 重新选择最佳端点
      await _selectBestEndpoints();
    });
  }
  
  /// 获取当前 API 端点 URL
  String? getCurrentApiUrl() {
    return _currentApiEndpoint?.url;
  }
  
  /// 获取当前 Socket.io 端点 URL
  String? getCurrentSocketUrl() {
    return _currentSocketEndpoint?.url;
  }
  
  /// 标记端点失败（用于 API 请求失败时）
  Future<void> markEndpointFailed(String url) async {
    final index = _apiEndpoints.indexWhere((e) => e.url == url);
    if (index >= 0) {
      _apiEndpoints[index] = _apiEndpoints[index].copyWith(
        failureCount: _apiEndpoints[index].failureCount + 1,
      );
      
      if (_apiEndpoints[index].failureCount >= _maxFailureCount) {
        _apiEndpoints[index] = _apiEndpoints[index].copyWith(isHealthy: false);
        await _selectBestEndpoints();
      }
    }
  }
  
  /// 清除所有端点
  Future<void> clearAll() async {
    _apiEndpoints.clear();
    _socketEndpoints.clear();
    _currentApiEndpoint = null;
    _currentSocketEndpoint = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEndpoints);
    await prefs.remove(_keyCurrentEndpoint);
    await prefs.remove(_keySocketEndpoints);
    await prefs.remove(_keyCurrentSocketEndpoint);
  }
  
  /// 释放资源
  void dispose() {
    _healthCheckTimer?.cancel();
    _healthCheckDio.close();
  }
}
