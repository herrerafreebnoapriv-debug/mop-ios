import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../../core/config/app_config.dart';
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
  Future<void> joinRoom({
    required String roomId,
    required String userName,
    String? userEmail,
    bool isAudioMuted = false,
    bool isVideoMuted = false,
    String? encryptedData,
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
        
        // 功能配置（对齐网页版 room.html）
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
        },
        
        // 配置覆盖（对齐网页版 configOverwrite）
        configOverrides: {
          'startWithAudioMuted': isAudioMuted,
          'startWithVideoMuted': isVideoMuted,
          'disableInviteFunctions': true,  // 禁用邀请功能
          'disableThirdPartyRequests': true,  // 禁用第三方请求
          'enableCalendarIntegration': false,  // 禁用日历集成
          'mobileAppPromo': false,  // 禁用移动应用推广
          'desktopSharing.enabled': true,  // 启用屏幕共享
          'analytics': {},  // 禁用分析
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
          },
          conferenceTerminated: (url, error) {
            debugPrint('会议已结束: $url, error: $error');
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
