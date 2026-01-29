import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 通知服务
/// 管理本地通知功能
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  
  /// 初始化通知服务
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    
    try {
      // Android 初始化设置
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS 初始化设置
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      // 初始化设置
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // 初始化
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      // 请求权限
      if (!kIsWeb) {
        await _requestPermissions();
      }
      
      _initialized = true;
      debugPrint('✓ 通知服务初始化成功');
    } catch (e) {
      debugPrint('通知服务初始化失败: $e');
    }
  }
  
  /// 请求通知权限
  Future<void> _requestPermissions() async {
    try {
      // Android 13+ 需要请求通知权限
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _notifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('请求通知权限失败: $e');
    }
  }
  
  /// 显示通话通知
  /// 
  /// [title] 通知标题
  /// [body] 通知内容
  /// [roomId] 房间ID（可选，用于点击跳转）
  Future<void> showCallNotification({
    required String title,
    required String body,
    String? roomId,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    
    try {
      // Android 通知详情（支持全屏意图，用于视频通话来电）
      const androidDetails = AndroidNotificationDetails(
        'call_channel',
        '通话通知',
        channelDescription: '视频通话和语音通话通知',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        fullScreenIntent: true,  // 启用全屏意图（来电时全屏显示，即使手机锁屏）
        category: AndroidNotificationCategory.call,  // 设置为通话类别
      );
      
      // iOS 通知详情
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      // 通知详情
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // 显示通知
      await _notifications.show(
        roomId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
        title,
        body,
        details,
        payload: roomId,  // 传递房间ID作为payload
      );
      
      debugPrint('✓ 显示通话通知: $title - $body');
    } catch (e) {
      debugPrint('显示通话通知失败: $e');
    }
  }
  
  /// 显示来电通知
  Future<void> showIncomingCallNotification({
    required String callerName,
    required String roomId,
    bool isVideo = true,
  }) async {
    await showCallNotification(
      title: isVideo ? '视频通话' : '语音通话',
      body: '$callerName 正在呼叫您',
      roomId: roomId,
    );
  }
  
  /// 显示通话结束通知
  Future<void> showCallEndedNotification({
    required String roomName,
    int? duration,
  }) async {
    final durationText = duration != null 
        ? '通话时长: ${_formatDuration(duration)}'
        : '通话已结束';
    
    await showCallNotification(
      title: '通话结束',
      body: '$roomName - $durationText',
    );
  }
  
  /// 取消通知
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _notifications.cancel(notificationId);
    } catch (e) {
      debugPrint('取消通知失败: $e');
    }
  }
  
  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
    } catch (e) {
      debugPrint('取消所有通知失败: $e');
    }
  }
  
  /// 格式化通话时长
  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }
  
  /// 通知点击回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('通知被点击: ${response.payload}');
    // 这里可以处理通知点击事件，例如跳转到房间页面
    // 可以通过 EventBus 或者 callback 传递给上层
  }
}
