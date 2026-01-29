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

  String? _lastSystemMessage;
  DateTime? _lastSystemMessageAt;
  String? get lastSystemMessage => _lastSystemMessage;
  DateTime? get lastSystemMessageAt => _lastSystemMessageAt;

  Map<String, dynamic>? _lastCallInvitation;
  DateTime? _lastCallInvitationAt;
  Map<String, dynamic>? get lastCallInvitation => _lastCallInvitation;
  DateTime? get lastCallInvitationAt => _lastCallInvitationAt;

  /// 全局 message 流（重连后仍会推送，供聊天页/列表消费）
  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageStreamController.stream;

  /// 全局 message_read 流（已读回执）
  final StreamController<Map<String, dynamic>> _messageReadStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageReadStream => _messageReadStreamController.stream;

  /// 主叫收到「邀请已发送」确认时推送（含 system_message 时主叫可写入聊天列表）
  final StreamController<Map<String, dynamic>> _callInvitationSentStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callInvitationSentStream =>
      _callInvitationSentStreamController.stream;

  void clearLastSystemMessage() {
    _lastSystemMessage = null;
    _lastSystemMessageAt = null;
    notifyListeners();
  }

  void clearLastCallInvitation() {
    _lastCallInvitation = null;
    _lastCallInvitationAt = null;
    notifyListeners();
  }
  
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
    if (_socket == null) {
      debugPrint('⚠️ _setupEventHandlers: socket 为 null');
      return;
    }
    debugPrint('🔧 设置 Socket 事件监听器...');
    
    _socket!.onConnect((_) {
      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _errorMessage = null;
      _reconnectTimer?.cancel();
      debugPrint('✅ Socket 已连接，事件监听器已设置');
      notifyListeners();
    });
    
    // 监听连接成功确认
    _socket!.on('connected', (data) {
      debugPrint('✅ 收到服务器连接确认: $data');
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

    _socket!.on('system_message', (data) {
      if (data is Map && data['message'] != null) {
        _lastSystemMessage = data['message'].toString();
        _lastSystemMessageAt = DateTime.now();
        notifyListeners();
      }
    });

    _socket!.on('call_invitation', (data) {
      debugPrint('📞 [Socket] 收到 call_invitation 事件: data=$data, type=${data.runtimeType}');
      if (data != null && data is Map) {
        final payload = Map<String, dynamic>.from(data as Map);
        _lastCallInvitation = payload;
        _lastCallInvitationAt = DateTime.now();
        debugPrint('📞 [Socket] 已设置 lastCallInvitation: room_id=${_lastCallInvitation?['room_id']}, caller_name=${_lastCallInvitation?['caller_name']}');
        notifyListeners();
        Future.microtask(() => notifyListeners());
        // 被叫：同一条「带接受/拒绝」的系统消息推入 messageStream，聊天页可写入
        final sysMsg = payload['system_message'];
        if (sysMsg != null && sysMsg is Map && !_messageStreamController.isClosed) {
          _messageStreamController.add(Map<String, dynamic>.from(sysMsg as Map));
          debugPrint('📞 [Socket] 已把 call_invitation 内 system_message 推入 messageStream');
        }
      } else {
        debugPrint('⚠️ [Socket] call_invitation 数据格式错误: ${data.runtimeType}');
      }
    });

    // 统一监听 message，推入流；重连后新 socket 会再次注册，不丢失
    // 兼容 Map 任意泛型（Socket 可能返回 Map<dynamic, dynamic> 等）
    _socket!.on('message', (data) {
      if (data != null && data is Map) {
        final payload = Map<String, dynamic>.from(data as Map);
        debugPrint('📨 [Socket] 收到 message: type=${payload['message_type']}, id=${payload['id']}');
        if (!_messageStreamController.isClosed) {
          _messageStreamController.add(payload);
        }
      } else {
        debugPrint('⚠️ [Socket] message 数据格式错误: ${data.runtimeType}');
      }
    });

    // 统一监听 message_read，推入流
    _socket!.on('message_read', (data) {
      if (data != null && data is Map) {
        final payload = Map<String, dynamic>.from(data as Map);
        if (!_messageReadStreamController.isClosed) {
          _messageReadStreamController.add(payload);
        }
      }
    });

    // 主叫收到邀请已发送确认（可携带 system_message 供主叫写入聊天）
    _socket!.on('call_invitation_sent', (data) {
      if (data != null && data is Map) {
        final payload = Map<String, dynamic>.from(data as Map);
        if (!_callInvitationSentStreamController.isClosed) {
          _callInvitationSentStreamController.add(payload);
        }
      }
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
      debugPrint('📤 发送 Socket 事件: $event, data: $data');
      _socket!.emit(event, data);
    } else {
      debugPrint('⚠️ 无法发送事件 $event: socket=${_socket != null}, connected=$_isConnected');
    }
  }
  
  /// 发送聊天消息（参照网页端：socket.emit('send_message', data)）
  /// 网页端格式：{message, type, target_user_id 或 room_id, file_id 或 file_url}
  void sendMessage({
    int? receiverId,
    int? roomId,
    required String message,
    String messageType = 'text',
    int? fileId,
    String? fileUrl,
    String? fileName,
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
      
      // 文件消息：优先使用 file_id（语音/文件），否则使用 file_url（图片）
      if (fileId != null) {
        data['file_id'] = fileId;
      } else if (fileUrl != null && fileUrl.isNotEmpty) {
        data['file_url'] = fileUrl;
        if (fileName != null && fileName.isNotEmpty) {
          data['file_name'] = fileName;
        }
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
        debugPrint('📨 收到 message 事件: type=${data is Map ? data['message_type'] : 'unknown'}, id=${data is Map ? data['id'] : 'unknown'}');
        if (data is Map<String, dynamic>) {
          callback(data);
        } else {
          debugPrint('⚠️ message 数据格式错误: ${data.runtimeType}');
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
    if (!_messageStreamController.isClosed) _messageStreamController.close();
    if (!_messageReadStreamController.isClosed) _messageReadStreamController.close();
    if (!_callInvitationSentStreamController.isClosed) _callInvitationSentStreamController.close();
    NetworkService.instance.onNetworkStatusChanged = null;
    super.dispose();
  }
}
