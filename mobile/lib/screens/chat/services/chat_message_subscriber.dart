import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../providers/auth_provider.dart';
import '../../../providers/socket_provider.dart';
import '../../../services/api/chat_api_service.dart';
import '../utils/chat_utils.dart';

/// 聊天消息订阅服务
class ChatMessageSubscriber {
  final ChatApiService _chatApiService = ChatApiService();

  /// 订阅实时消息
  StreamSubscription? subscribeToMessages({
    required BuildContext context,
    required int? userId,
    required int? roomId,
    required bool isRoom,
    required List<Map<String, dynamic>> messages,
    required Function(List<Map<String, dynamic>>) onMessagesUpdate,
    required Function(int) onMessageRead,
  }) {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    
    if (!socketProvider.isConnected) return null;

    // 监听新消息事件
    final subscription = socketProvider.onMessage((message) {
      // 自动识别 base64 数据 URI 为图片消息
      final messageText = message['message']?.toString() ?? '';
      if (message['message_type'] == null || message['message_type'] == 'text') {
        if (messageText.startsWith('data:image/')) {
          message['message_type'] = 'image';
        }
      }
      
      // 检查消息是否属于当前聊天
      final msgSenderId = message['sender_id'] as int? ?? message['from_user_id'] as int?;
      final msgReceiverId = message['receiver_id'] as int?;
      final msgRoomId = message['room_id'] as int?;
      
      final updatedMessages = List<Map<String, dynamic>>.from(messages);
      bool shouldUpdate = false;
      
      if (isRoom) {
        // 房间消息：严格匹配房间ID
        if (msgRoomId == roomId) {
          final messageId = message['id'] as int?;
          if (messageId != null) {
            final exists = updatedMessages.any((msg) => msg['id'] == messageId);
            if (!exists) {
              updatedMessages.add(message);
              updatedMessages.sort((a, b) {
                final timeA = parseChatDateTime(a['created_at']?.toString()) ?? DateTime(1970);
                final timeB = parseChatDateTime(b['created_at']?.toString()) ?? DateTime(1970);
                return timeA.compareTo(timeB);
              });
              shouldUpdate = true;
            }
          }
        }
      } else {
        // 点对点消息
        final currentUserId = currentUser?.id;
        final messageType = message['message_type']?.toString() ?? 'text';
        
        final isSystemMessage = messageType == 'system';
        final isFromTargetToMe = msgSenderId == userId && msgReceiverId == currentUserId;
        final isFromMeToTarget = msgSenderId == currentUserId && msgReceiverId == userId;
        
        if (isSystemMessage && isFromTargetToMe) {
          final messageId = message['id'] as int?;
          if (messageId != null) {
            final exists = updatedMessages.any((msg) => msg['id'] == messageId);
            if (!exists) {
              updatedMessages.add(message);
              updatedMessages.sort((a, b) {
                final timeA = parseChatDateTime(a['created_at']?.toString()) ?? DateTime(1970);
                final timeB = parseChatDateTime(b['created_at']?.toString()) ?? DateTime(1970);
                return timeA.compareTo(timeB);
              });
              shouldUpdate = true;
            }
          }
        } else if (isFromTargetToMe || isFromMeToTarget) {
          final messageId = message['id'] as int?;
          if (messageId != null) {
            final exists = updatedMessages.any((msg) => msg['id'] == messageId);
            if (!exists) {
              updatedMessages.add(message);
              updatedMessages.sort((a, b) {
                final timeA = parseChatDateTime(a['created_at']?.toString()) ?? DateTime(1970);
                final timeB = parseChatDateTime(b['created_at']?.toString()) ?? DateTime(1970);
                return timeA.compareTo(timeB);
              });
              shouldUpdate = true;
              
              // 标记为已读
              if (isFromTargetToMe && message['is_read'] != true) {
                socketProvider.markMessageRead([messageId]);
                _chatApiService.markAsRead([messageId]);
              }
            }
          }
        }
      }
      
      if (shouldUpdate) {
        onMessagesUpdate(updatedMessages);
      }
    });
    
    // 监听消息已读状态更新
    socketProvider.on('message_read', (data) {
      if (data is Map<String, dynamic> && data['message_id'] != null) {
        onMessageRead(data['message_id'] as int);
      }
    });
    
    return subscription;
  }
}
