import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/socket_provider.dart';
import '../../../services/api/rooms_api_service.dart';
import '../../../services/permission/permission_service.dart';
import '../../../locales/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../room/room_screen.dart';

/// 聊天视频通话服务
class ChatVideoCallService {
  final RoomsApiService _roomsApiService = RoomsApiService();

  /// 开始视频通话
  Future<void> startVideoCall({
    required BuildContext context,
    required int? userId,
    required int? roomId,
    required bool isRoom,
    required String chatName,
    required Function(String) onError,
  }) async {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    
    try {
      // 先请求相机、麦克风权限
      var cam = await PermissionService.instance.checkCameraPermission();
      if (cam != PermissionStatus.granted) {
        cam = await PermissionService.instance.requestCameraPermission();
        if (cam != PermissionStatus.granted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('permission.camera_required') ?? '需要相机权限才能进行视频通话'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: l10n?.t('permission.go_to_settings') ?? '去设置',
                onPressed: () => PermissionService.instance.openAppSettings(),
              ),
            ),
          );
          return;
        }
      }
      
      var mic = await PermissionService.instance.checkMicrophonePermission();
      if (mic != PermissionStatus.granted) {
        mic = await PermissionService.instance.requestMicrophonePermission();
        if (mic != PermissionStatus.granted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('permission.microphone_required') ?? '需要麦克风权限才能进行视频通话'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: l10n?.t('permission.go_to_settings') ?? '去设置',
                onPressed: () => PermissionService.instance.openAppSettings(),
              ),
            ),
          );
          return;
        }
      }

      // 生成房间ID
      String roomIdStr;
      String roomName;
      
      if (isRoom) {
        final roomIdStrRaw = roomId?.toString() ?? '';
        final hash = sha256.convert(utf8.encode('room-$roomIdStrRaw'));
        roomIdStr = 'r-${hash.toString().substring(0, 8)}';
        roomName = '群聊视频通话 - $chatName';
      } else {
        final currentUserId = authProvider.currentUser?.id ?? 0;
        final targetUserId = userId ?? 0;
        final sortedIds = [currentUserId, targetUserId]..sort();
        final hash = sha256.convert(utf8.encode('chat-${sortedIds[0]}-${sortedIds[1]}'));
        roomIdStr = 'r-${hash.toString().substring(0, 8)}';
        roomName = '与 $chatName 的视频通话';
      }
      
      // 显示加载提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.t('chat.joining_video_call') ?? '正在加入视频通话...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      
      // 先尝试创建房间
      try {
        await _roomsApiService.createRoom(
          roomId: roomIdStr,
          roomName: roomName,
          maxOccupants: 10,
        );
      } catch (e) {
        // 如果房间已存在，这是正常的
        debugPrint('创建房间（可能已存在）: $e');
      }
      
      // 如果是点对点聊天，向对方发送通话邀请
      if (!isRoom && userId != null && socketProvider.isConnected) {
        final callerName =
            authProvider.currentUser?.nickname ?? authProvider.currentUser?.username ?? '用户';
        final invitationData = {
          'target_user_id': userId,
          'room_id': roomIdStr,
          'caller_name': callerName,
        };
        debugPrint('📹 发送视频通话邀请: target_user_id=$userId, room_id=$roomIdStr, caller_name=$callerName');
        socketProvider.sendEvent('call_invitation', invitationData);
      }

      // 跳转到房间页面
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RoomScreen(
              roomId: roomIdStr,
              roomName: roomName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('发起视频通话失败: $e');
      onError(e.toString());
    }
  }
}
