import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import '../../services/api/devices_api_service.dart';
import '../notification/notification_service.dart';

/// Firebase Cloud Messaging (FCM) 服务
/// 用于接收后台推送通知（视频通话邀请等）
class FCMService {
  static final FCMService instance = FCMService._internal();
  FCMService._internal();
  
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;
  String? _fcmToken;
  
  /// 初始化 FCM
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    
    try {
      // 确保 Firebase 已初始化（如果未配置会抛出异常，捕获后静默失败）
      try {
        await Firebase.initializeApp();
      } catch (e) {
        debugPrint('⚠️ Firebase 未配置，跳过 FCM 初始化: $e');
        return;  // Firebase 未配置时，静默失败
      }
      
      // 请求通知权限
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✓ FCM 通知权限已授权');
        
        // 获取 FCM token
        _fcmToken = await _fcm.getToken();
        if (_fcmToken != null && _fcmToken!.isNotEmpty) {
          final tokenPreview = _fcmToken!.length > 20 ? _fcmToken!.substring(0, 20) : _fcmToken!;
          debugPrint('✓ 获取到 FCM Token: $tokenPreview...');
          // 上传 token 到后端
          await _uploadFcmToken(_fcmToken!);
        }
        
        // 监听前台推送
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        
        // 监听后台推送（App 从后台打开时）
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageOpened);
        
        // 检查是否有从通知启动的推送
        RemoteMessage? initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          _handleBackgroundMessageOpened(initialMessage);
        }
        
        // 监听 token 刷新
        _fcm.onTokenRefresh.listen((newToken) {
          final tokenPreview = newToken.length > 20 ? newToken.substring(0, 20) : newToken;
          debugPrint('FCM Token 已刷新: $tokenPreview...');
          _fcmToken = newToken;
          _uploadFcmToken(newToken);
        });
        
        _initialized = true;
        debugPrint('✓ FCM 服务初始化成功');
      } else {
        debugPrint('⚠️ FCM 通知权限未授权: ${settings.authorizationStatus}');
      }
    } catch (e) {
      debugPrint('FCM 初始化失败: $e');
      // 如果 Firebase 未配置，静默失败（不影响其他功能）
    }
  }
  
  /// 上传 FCM token 到后端
  Future<void> _uploadFcmToken(String token) async {
    try {
      final devicesApi = DevicesApiService();
      // 使用现有的设备注册 API，传入 fcm_token 和 platform
      // 注意：需要先获取设备指纹等信息，这里简化处理
      final platform = Platform.isAndroid ? 'android' : 'ios';
      await devicesApi.registerDevice(
        fcmToken: token,
        platform: platform,
      );
      debugPrint('✓ FCM Token 已上传到后端');
    } catch (e) {
      debugPrint('上传 FCM Token 失败: $e');
      // 如果设备未注册，这里会失败，但不影响 FCM 功能
    }
  }
  
  /// 处理前台推送消息
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📨 前台收到 FCM 推送: ${message.data}');
    _handlePushMessage(message);
  }
  
  /// 处理后台推送消息（从通知打开）
  void _handleBackgroundMessageOpened(RemoteMessage message) {
    debugPrint('📨 从后台推送打开: ${message.data}');
    _handlePushMessage(message);
  }
  
  /// 处理推送消息
  void _handlePushMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();
    
    if (type == 'VIDEO_CALL') {
      final roomId = data['room_id']?.toString();
      final callerName = data['caller_name']?.toString() ?? '对方';
      
      if (roomId != null && roomId.isNotEmpty) {
        // 显示全屏通话通知
        NotificationService.instance.showIncomingCallNotification(
          callerName: callerName,
          roomId: roomId,
          isVideo: true,
        );
        debugPrint('✓ 已显示视频通话通知: $callerName, roomId: $roomId');
      }
    }
  }
  
  /// 获取当前 FCM token
  String? get token => _fcmToken;
  
  /// 是否已初始化
  bool get isInitialized => _initialized;
}

/// 后台消息处理器（必需，即使 App 被系统杀死也能收到）
/// 注意：必须是顶级函数，不能是类方法
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📨 后台收到 FCM 推送: ${message.data}');
  
  final data = message.data;
  final type = data['type']?.toString();
  
  if (type == 'VIDEO_CALL') {
    final roomId = data['room_id']?.toString();
    final callerName = data['caller_name']?.toString() ?? '对方';
    
    if (roomId != null && roomId.isNotEmpty) {
      // 显示本地通知（全屏意图）
      await NotificationService.instance.showIncomingCallNotification(
        callerName: callerName,
        roomId: roomId,
        isVideo: true,
      );
      debugPrint('✓ 后台已显示视频通话通知: $callerName, roomId: $roomId');
    }
  }
}
