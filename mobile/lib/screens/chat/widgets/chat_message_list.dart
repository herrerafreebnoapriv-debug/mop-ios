import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/socket_provider.dart';
import '../../../locales/app_localizations.dart';
import '../../../services/jitsi/jitsi_service.dart';
import 'message_bubble.dart';
import 'system_message_widget.dart';
import '../utils/chat_utils.dart';

/// 聊天消息列表组件
class ChatMessageList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final int? userId;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.onRefresh,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.id ?? 0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          final messageType = message['message_type']?.toString() ?? 'text';
          
          // 系统消息（折中方案）：双方均显示「进入房间」+ 被叫多一个「拒绝」
          if (messageType == 'system') {
            final inv = getCallInvitation(message);
            final msgSenderId = safeInt(message['sender_id']) ?? safeInt(message['from_user_id']);
            final isFromOther = msgSenderId != null && msgSenderId != currentUserId;
            final isCaller = inv != null && !isFromOther;
            final isCallee = inv != null && isFromOther;
            final joinRoom = () async {
              if (inv == null) return;
              final roomId = inv['room_id']?.toString();
              if (roomId == null || roomId.isEmpty) return;
              final socketProvider = Provider.of<SocketProvider>(context, listen: false);
              final userName = authProvider.currentUser?.nickname ??
                  authProvider.currentUser?.username ??
                  (l10n?.t('common.user') ?? '用户');
              try {
                if (isCallee) {
                  socketProvider.sendEvent('call_invitation_response', {
                    'room_id': roomId,
                    'accepted': true,
                  });
                }
                await JitsiService.instance.joinRoom(
                  roomId: roomId,
                  userName: userName,
                );
              } catch (e) {
                if (context.mounted) {
                  final joinFailed = AppLocalizations.of(context)?.t('chat.join_video_call_failed') ?? '加入视频通话失败';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$joinFailed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SystemMessageWidget(
                message: message,
                onAccept: (isCaller || isCallee) ? joinRoom : null,
                onReject: isCallee
                    ? () {
                        final roomId = inv!['room_id']?.toString();
                        if (roomId == null || roomId.isEmpty) return;
                        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
                        socketProvider.sendEvent('call_invitation_response', {
                          'room_id': roomId,
                          'accepted': false,
                        });
                      }
                    : null,
                acceptButtonLabel: (isCaller || isCallee) ? (l10n?.t('chat.enter_room') ?? '进入房间') : null,
              ),
            );
          }
          
          // 普通消息
          final senderId = message['sender_id'] ?? message['from_user_id'];
          final isMe = (senderId is int ? senderId : int.tryParse(senderId.toString()) ?? 0) == currentUserId;
          
          return MessageBubble(
            message: message,
            isMe: isMe,
            formatTime: formatChatTime,
          );
        },
      ),
    );
  }
}
