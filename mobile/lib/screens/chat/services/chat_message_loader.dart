import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/socket_provider.dart';
import '../../../services/api/chat_api_service.dart';
import '../../../services/data/message_cache_service.dart';
import '../utils/chat_utils.dart';

/// 聊天消息加载服务
class ChatMessageLoader {
  final ChatApiService _chatApiService = ChatApiService();

  /// 加载消息历史
  Future<List<Map<String, dynamic>>> loadMessages({
    required BuildContext context,
    required int? userId,
    required int? roomId,
    required bool isRoom,
    required Function(String) onError,
  }) async {
    try {
      final response = await _chatApiService.getMessages(
        userId: userId,
        roomId: roomId,
        limit: 50,
      );

      if (response != null && response['messages'] != null) {
        // 处理消息列表
        final messagesList = List<Map<String, dynamic>>.from(
          response['messages'].map((msg) {
            final messageMap = Map<String, dynamic>.from(msg as Map<String, dynamic>);
            // 确保 extra_data 被保留
            if (msg is Map && (msg as Map).containsKey('extra_data')) {
              messageMap['extra_data'] = (msg as Map)['extra_data'];
            }
            // 自动识别 base64 数据 URI 为图片消息
            final messageText = messageMap['message']?.toString() ?? '';
            if (messageMap['message_type'] == null || messageMap['message_type'] == 'text') {
              if (messageText.startsWith('data:image/')) {
                messageMap['message_type'] = 'image';
              }
            }
            return messageMap;
          }),
        );
        
        // 过滤消息
        final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
        final currentUserId = currentUser?.id;
        
        final filteredMessages = messagesList.where((msg) {
          if (isRoom) {
            final msgRoomId = msg['room_id'];
            final roomIdInt = safeInt(msgRoomId);
            return roomIdInt == roomId;
          } else {
            final msgSenderId = safeInt(msg['sender_id'] ?? msg['from_user_id']);
            final msgReceiverId = safeInt(msg['receiver_id']);
            final messageType = msg['message_type']?.toString() ?? 'text';
            
            final isSystemMessage = messageType == 'system';
            if (isSystemMessage) {
              final isFromTargetToMe = msgSenderId == userId && msgReceiverId == currentUserId;
              final isFromMeToTarget = msgSenderId == currentUserId && msgReceiverId == userId;
              return isFromTargetToMe || isFromMeToTarget;
            }
            
            final isFromTargetToMe = msgSenderId != null && msgReceiverId != null &&
                msgSenderId == userId && msgReceiverId == currentUserId;
            final isFromMeToTarget = msgSenderId != null && msgReceiverId != null &&
                msgSenderId == currentUserId && msgReceiverId == userId;
            return isFromTargetToMe || isFromMeToTarget;
          }
        }).toList();
        
        // 按时间升序排序
        filteredMessages.sort((a, b) {
          final timeA = parseChatDateTime(a['created_at']?.toString()) ?? DateTime(1970);
          final timeB = parseChatDateTime(b['created_at']?.toString()) ?? DateTime(1970);
          return timeA.compareTo(timeB);
        });
        
        return filteredMessages;
      }
      
      return [];
    } catch (e) {
      onError(e.toString());
      return [];
    }
  }

  /// 从本地缓存加载消息
  Future<List<Map<String, dynamic>>> loadMessagesFromCache({
    required bool isRoom,
    required int? userId,
    required int? roomId,
  }) async {
    try {
      return await MessageCacheService.instance.getMessagesForChat(
        isRoom: isRoom,
        userId: userId,
        roomId: roomId,
      );
    } catch (e) {
      debugPrint('从本地缓存加载聊天消息失败: $e');
      return [];
    }
  }
}
