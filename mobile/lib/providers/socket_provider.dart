import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../core/config/app_config.dart';
import '../core/services/storage_service.dart';
import '../core/services/network_service.dart';
import '../core/services/endpoint_manager.dart';

/// Socket.io 连接状态管理
/// 支持自动重连和网络状态监听
class SocketProvider extends ChangeNotifier {
  IO.Socket? _socket;
  bool _isConnected = false;
  String? _errorMessage;
  String? _currentToken;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  
  bool get isConnected => _isConnected;
  IO.Socket? get socket => _socket;
  String? get errorMessage => _errorMessage;
  
  SocketProvider() {
    _initNetworkListener();
  }
  
  /// 初始化网络监听
  void _initNetworkListener() {
    NetworkService.instance.onNetworkStatusChanged = (bool isConnected) {
      if (isConnected && _currentToken != null && !_isConnected) {
        // 网络恢复，尝试重连
        _reconnect(_currentToken!);
      } else if (!isConnected) {
        // 网络断开
        _isConnected = false;
        notifyListeners();
      }
    };
  }
  
  /// 连接 Socket.io 服务器（支持多端点故障转移）
  Future<bool> connect(String token) async {
    try {
      _currentToken = token;
      _reconnectAttempts = 0;
      
      // 获取 Socket.io 端点列表
      final endpoints = EndpointManager.instance.socketEndpoints;
      String? socketIoUrl;
      
      if (endpoints.isNotEmpty) {
        // 优先使用健康的端点
        final healthyEndpoints = endpoints.where((e) => e.isHealthy).toList();
        if (healthyEndpoints.isNotEmpty) {
          socketIoUrl = healthyEndpoints.first.url;
        } else {
          // 如果没有健康的端点，使用优先级最高的
          socketIoUrl = endpoints.first.url;
        }
      } else {
        // 回退到旧配置
        socketIoUrl = AppConfig.instance.socketIoUrl;
      }
      
      if (socketIoUrl == null || socketIoUrl.isEmpty) {
        _errorMessage = 'Socket.io 服务器地址未配置';
        notifyListeners();
        return false;
      }
      
      // 如果已有连接，先断开
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
      }
      
      _socket = IO.io(
        socketIoUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .setAuth({'token': token})
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(_maxReconnectAttempts)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .build(),
      );
      
      _setupEventHandlers();
      
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
  
  /// 设置事件处理器
  void _setupEventHandlers() {
    if (_socket == null) return;
    
    _socket!.onConnect((_) {
      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _errorMessage = null;
      _reconnectTimer?.cancel();
      notifyListeners();
    });
    
    _socket!.onDisconnect((_) {
      _isConnected = false;
      notifyListeners();
      
      // 如果还有 token，尝试重连
      if (_currentToken != null && !_isReconnecting) {
        _scheduleReconnect(_currentToken!);
      }
    });
    
    _socket!.onConnectError((error) {
      _errorMessage = error.toString();
      _isConnected = false;
      notifyListeners();
      
      // 如果还有 token，尝试重连
      if (_currentToken != null && !_isReconnecting) {
        _scheduleReconnect(_currentToken!);
      }
    });
    
    _socket!.onError((error) {
      _errorMessage = error.toString();
      notifyListeners();
    });
    
    _socket!.onReconnect((attemptNumber) {
      _reconnectAttempts = attemptNumber;
      _isReconnecting = true;
      notifyListeners();
    });
    
    _socket!.onReconnectAttempt((attemptNumber) {
      _reconnectAttempts = attemptNumber;
      notifyListeners();
    });
    
    _socket!.onReconnectError((error) {
      _errorMessage = '重连失败: $error';
      notifyListeners();
    });
  }
  
  /// 安排重连
  void _scheduleReconnect(String token) {
    if (_isReconnecting) return;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && _currentToken != null) {
        _reconnect(token);
      }
    });
  }
  
  /// 执行重连（支持多端点故障转移）
  Future<void> _reconnect(String token) async {
    if (_isReconnecting || _reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }
    
    // 检查网络状态
    final isNetworkAvailable = await NetworkService.instance.checkConnectivity();
    if (!isNetworkAvailable) {
      // 网络不可用，等待网络恢复
      return;
    }
    
    _isReconnecting = true;
    _reconnectAttempts++;
    
    try {
      // 如果 socket 已存在，先断开
      if (_socket != null) {
        _socket!.disconnect();
        _socket!.dispose();
      }
      
      // 尝试连接所有可用的端点
      final endpoints = EndpointManager.instance.socketEndpoints;
      if (endpoints.isNotEmpty) {
        // 按优先级尝试所有端点
        final sortedEndpoints = List<EndpointInfo>.from(endpoints)
          ..sort((a, b) => a.priority.compareTo(b.priority));
        
        for (final endpoint in sortedEndpoints) {
          try {
            _socket = IO.io(
              endpoint.url,
              IO.OptionBuilder()
                  .setTransports(['websocket'])
                  .setExtraHeaders({'Authorization': 'Bearer $token'})
                  .setAuth({'token': token})
                  .enableAutoConnect()
                  .enableReconnection()
                  .setReconnectionAttempts(_maxReconnectAttempts)
                  .setReconnectionDelay(1000)
                  .setReconnectionDelayMax(5000)
                  .build(),
            );
            
            _setupEventHandlers();
            
            // 等待连接结果
            await Future.delayed(const Duration(seconds: 2));
            if (_isConnected) {
              // 连接成功
              _isReconnecting = false;
              _reconnectAttempts = 0;
              return;
            }
          } catch (e) {
            // 当前端点失败，尝试下一个
            await EndpointManager.instance.markEndpointFailed(endpoint.url);
            continue;
          }
        }
        
        // 所有端点都失败
        _isReconnecting = false;
        _errorMessage = '所有 Socket.io 端点均不可用';
        notifyListeners();
      } else {
        // 使用旧方式连接
        await connect(token);
      }
    } catch (e) {
      _isReconnecting = false;
      _errorMessage = '重连失败: $e';
      notifyListeners();
      
      // 继续尝试重连
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _scheduleReconnect(token);
      }
    }
  }
  
  /// 自动连接（从本地存储读取 token）
  Future<bool> autoConnect() async {
    final token = await StorageService.instance.getToken();
    if (token != null && token.isNotEmpty) {
      return await connect(token);
    }
    return false;
  }
  
  /// 断开连接
  void disconnect() {
    _currentToken = null;
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    _reconnectAttempts = 0;
    
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    notifyListeners();
  }
  
  /// 更新 token（用于 token 刷新后）
  Future<void> updateToken(String newToken) async {
    _currentToken = newToken;
    
    // 如果已连接，需要重新连接以使用新 token
    if (_isConnected || _isReconnecting) {
      disconnect();
      await connect(newToken);
    }
  }
  
  /// 发送事件消息
  void sendEvent(String event, Map<String, dynamic> data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    }
  }
  
  /// 发送聊天消息（参照网页端：socket.emit('send_message', data)）
  /// 网页端格式：{message, type, target_user_id 或 room_id}
  void sendMessage({
    int? receiverId,
    int? roomId,
    required String message,
    String messageType = 'text',
    int? fileId,
  }) {
    if (_socket != null && _isConnected) {
      // 参照网页端格式：使用 target_user_id（点对点）或 room_id（群聊）
      final data = <String, dynamic>{
        'message': message,
        'type': messageType,
      };
      
      if (roomId != null) {
        data['room_id'] = roomId;
      } else if (receiverId != null) {
        data['target_user_id'] = receiverId;
      }
      
      if (fileId != null) {
        data['file_id'] = fileId;
      }
      
      _socket!.emit('send_message', data);
    }
  }
  
  /// 标记消息已读（参照网页端：socket.emit('mark_message_read', data)）
  void markMessageRead(List<int> messageIds) {
    if (_socket != null && _isConnected) {
      _socket!.emit('mark_message_read', {
        'message_ids': messageIds,
      });
    }
  }
  
  /// 监听新消息（参照网页端：socket.on('message', callback)）
  StreamSubscription? onMessage(Function(Map<String, dynamic>) callback) {
    if (_socket != null) {
      _socket!.on('message', (data) {
        if (data is Map<String, dynamic>) {
          callback(data);
        }
      });
    }
    return null; // TODO: 返回实际的StreamSubscription
  }
  
  /// 监听消息发送确认（参照网页端：socket.on('message_sent', callback)）
  void onMessageSent(Function(Map<String, dynamic>) callback) {
    _socket?.on('message_sent', (data) {
      if (data is Map<String, dynamic>) {
        callback(data);
      }
    });
  }
  
  /// 监听错误事件（参照网页端：socket.on('error', callback)）
  void onError(Function(Map<String, dynamic>) callback) {
    _socket?.on('error', (data) {
      if (data is Map<String, dynamic>) {
        callback(data);
      }
    });
  }
  
  /// 监听事件
  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }
  
  /// 取消监听
  void off(String event) {
    _socket?.off(event);
  }
  
  @override
  void dispose() {
    disconnect();
    NetworkService.instance.onNetworkStatusChanged = null;
    super.dispose();
  }
}
