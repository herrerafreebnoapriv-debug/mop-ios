import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../../services/api/api_service.dart';

/// Jitsi Meet 服务
/// 管理视频通话功能
/// 对齐网页版实现方式，使用后端 /rooms/{room_id}/join API 获取 JWT Token
class JitsiService {
  static final JitsiService instance = JitsiService._internal();
  JitsiService._internal();
  
  final ApiService _apiService = ApiService();
  final JitsiMeet _jitsiMeet = JitsiMeet();
  
  /// 加入房间
  /// 
  /// 对齐网页版实现方式：
  /// 1. 调用后端 /rooms/{room_id}/join API 获取 JWT Token 和服务器地址
  /// 2. 使用返回的 jitsi_token 和 jitsi_server_url 初始化 Jitsi Meet
  /// 
  /// [roomId] 房间ID
  /// [userName] 用户显示名称
  /// [userEmail] 用户邮箱（可选）
  /// [isAudioMuted] 是否静音
  /// [isVideoMuted] 是否关闭视频
  /// [encryptedData] 加密二维码数据（可选，用于扫码加入）
  /// [onConferenceJoined] 已加入会议时回调（用于区分「通话中」与「已结束」）
  /// [onConferenceTerminated] 会议结束时回调
  Future<void> joinRoom({
    required String roomId,
    required String userName,
    String? userEmail,
    bool isAudioMuted = false,
    bool isVideoMuted = false,
    String? encryptedData,
    VoidCallback? onConferenceJoined,
    VoidCallback? onConferenceTerminated,
  }) async {
    try {
      // 第一步：调用后端 API 加入房间（对齐网页版实现）
      // 网页版使用：POST /api/v1/rooms/{room_id}/join
      final joinData = <String, dynamic>{
        'display_name': userName,
      };
      
      // 如果提供了加密二维码数据，添加到请求中
      if (encryptedData != null && encryptedData.isNotEmpty) {
        joinData['encrypted_data'] = encryptedData;
      }
      
      final joinResponse = await _apiService.post(
        '/rooms/$roomId/join',
        data: joinData,
      );
      
      if (joinResponse == null) {
        throw Exception('加入房间失败：服务器未返回数据');
      }
      
      // 解析响应（对齐网页版的 RoomJoinResponse）
      final jitsiToken = joinResponse['jitsi_token'] as String?;
      final jitsiServerUrl = joinResponse['jitsi_server_url'] as String?;
      
      if (jitsiToken == null || jitsiToken.isEmpty) {
        throw Exception('加入房间失败：未获取到 JWT Token');
      }
      
      if (jitsiServerUrl == null || jitsiServerUrl.isEmpty) {
        throw Exception('加入房间失败：未获取到 Jitsi 服务器地址');
      }
      
      debugPrint('✓ 成功获取 JWT Token 和服务器地址');
      debugPrint('  服务器: $jitsiServerUrl');
      
      // 获取系统语言（用于Jitsi界面语言）
      // Jitsi 支持完整的 locale（如 'zh_CN', 'en_US'）或语言代码（如 'zh', 'en'）
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      // 优先使用完整 locale（如 zh_CN），如果没有则使用语言代码（如 zh）
      final jitsiLang = systemLocale.toString().replaceAll('_', '-'); // Jitsi 使用 zh-CN 格式
      
      // 第二步：配置 Jitsi Meet 选项（对齐网页版配置）
      final options = JitsiMeetConferenceOptions(
        room: roomId,
        serverURL: jitsiServerUrl,
        token: jitsiToken,
        
        // 用户信息
        userInfo: JitsiMeetUserInfo(
          displayName: userName,
          email: userEmail,
        ),
        
        // 功能配置：极简通话界面（只保留语音、视频、屏幕共享、挂断）
        featureFlags: {
          'welcomepage.enabled': false,  // 禁用欢迎页面
          'invite.enabled': false,  // 禁用邀请功能
          'calendar.enabled': false,  // 禁用日历集成
          'call-integration.enabled': false,
          'live-streaming.enabled': false,  // 禁用直播流
          'recording.enabled': false,  // 禁用录制服务
          'transcription.enabled': false,  // 禁用转录服务
          'pip.enabled': true,  // 启用画中画
          'screen-sharing.enabled': true,  // 启用屏幕共享
          'chat.enabled': false,  // 禁用聊天（有独立聊天窗口）
          'raise-hand.enabled': false,  // 禁用举手
          'reactions.enabled': false,  // 禁用反应
          'tile-view.enabled': false,  // 禁用宫格视图切换
          'video-share.enabled': false,  // 禁用视频分享
          'toolbox.alwaysVisible': true,  // 工具栏常驻
          'filmstrip.enabled': false,  // 禁用 filmstrip（减少多窗口感）
          'overflow-menu.enabled': false,  // 禁用溢出菜单
          'settings.enabled': false,  // 禁用设置
          'help.enabled': false,  // 禁用帮助
          'security-options.enabled': false,  // 禁用安全选项
          'speaker-stats.enabled': false,  // 禁用发言统计
          'closed-captions.enabled': false,  // 禁用字幕
          'video-quality.enabled': false,  // 禁用视频质量切换
          'participants-pane.enabled': false,  // 禁用参与者面板
        },
        
        // 配置覆盖：精简工具栏按钮
        configOverrides: {
          'startWithAudioMuted': isAudioMuted,
          'startWithVideoMuted': isVideoMuted,
          'disableInviteFunctions': true,  // 禁用邀请功能
          'disableThirdPartyRequests': true,  // 禁用第三方请求
          'enableCalendarIntegration': false,  // 禁用日历集成
          'mobileAppPromo': false,  // 禁用移动应用推广
          'analytics': {},  // 禁用分析
          'defaultLanguage': jitsiLang,  // 设置界面语言为系统语言
          // 精简工具栏：只保留麦克风、摄像头、屏幕共享、挂断
          'toolbarButtons': ['microphone', 'camera', 'desktop', 'hangup'],
          // 禁用预加入页
          'prejoinConfig': {'enabled': false},
          // 禁用更多菜单
          'disableModeratorIndicator': true,
          'disableReactionsModeration': true,
          'hideConferenceSubject': true,
          'hideConferenceTimer': true,
          'hideRecordingLabel': true,
        },
      );
  
      // 第三步：加入会议
      await _jitsiMeet.join(
        options,
        JitsiMeetEventListener(
          conferenceWillJoin: (url) {
            debugPrint('即将加入会议: $url');
          },
          conferenceJoined: (url) {
            debugPrint('✓ 已成功加入会议: $url');
            onConferenceJoined?.call();
          },
          conferenceTerminated: (url, error) {
            debugPrint('会议已结束: $url, error: $error');
            onConferenceTerminated?.call();
          },
        ),
      );
    } catch (e) {
      debugPrint('加入房间失败: $e');
      throw Exception('加入房间失败: $e');
    }
  }
  
  /// 离开房间
  Future<void> leaveRoom() async {
    try {
      _jitsiMeet.hangUp();
    } catch (e) {
      debugPrint('离开房间失败: $e');
    }
  }

  /// 进入画中画（最小化）。通话中按返回键时调用，避免直接关闭房间。
  Future<void> enterPiP() async {
    try {
      await _jitsiMeet.enterPiP();
    } catch (e) {
      debugPrint('进入画中画失败: $e');
    }
  }
  
  /// 开启/关闭音频
  Future<void> toggleAudio() async {
    // Jitsi Meet SDK 会自动处理
    // 如果需要手动控制，可以使用 MethodChannel
  }
  
  /// 开启/关闭视频
  Future<void> toggleVideo() async {
    // Jitsi Meet SDK 会自动处理
    // 如果需要手动控制，可以使用 MethodChannel
  }
  
  /// 开启/关闭屏幕共享
  /// 
  /// 注意：屏幕共享功能由 Jitsi Meet SDK 自动处理
  /// Android 和 iOS 平台都支持屏幕共享
  /// 用户可以通过 Jitsi 界面上的屏幕共享按钮来启动/停止屏幕共享
  Future<void> toggleScreenSharing() async {
    // Jitsi Meet SDK 会自动处理屏幕共享
    // Android: 使用 MediaProjection API（SDK 内部实现）
    // iOS: 使用 ReplayKit（SDK 内部实现）
    // 用户点击 Jitsi 界面上的屏幕共享按钮即可使用
    debugPrint('屏幕共享功能由 Jitsi Meet SDK 自动处理，用户可通过界面按钮操作');
  }
}
