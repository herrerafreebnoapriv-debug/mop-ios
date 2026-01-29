import 'package:flutter/material.dart';
import '../../../locales/app_localizations.dart';
import '../utils/chat_utils.dart';
import 'image_message_widget.dart';
import 'file_message_widget.dart';
import 'voice_message_widget.dart';

/// 消息气泡组件
class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String Function(DateTime) formatTime;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final messageText = message['message']?.toString() ?? '';
    var messageType = message['message_type']?.toString() ?? 'text';
    final createdAt = message['created_at']?.toString() ?? '';
    final l10n = AppLocalizations.of(context);
    final senderName = message['sender_nickname']?.toString() ?? 
                      message['sender_username']?.toString() ?? 
                      (l10n?.t('common.unknown') ?? '未知');
    
    // 自动识别 base64 数据 URI 为图片消息（双重检查，确保识别）
    if (messageText.isNotEmpty && messageText.startsWith('data:image/')) {
      messageType = 'image';
      // 同时更新 message 对象，确保后续使用正确
      message['message_type'] = 'image';
    }

    DateTime? dateTime;
    try {
      dateTime = parseChatDateTime(createdAt) ?? DateTime.now();
    } catch (e) {
      dateTime = DateTime.now();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF667eea),
              child: Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF667eea)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: messageType == 'text'
                          ? Text(
                              messageText.isNotEmpty ? messageText : (l10n?.t('common.unknown') ?? '未知内容'),
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                            )
                          : messageType == 'image'
                              ? ImageMessageWidget(
                                  message: message,
                                  isMe: isMe,
                                )
                              : messageType == 'file'
                                  ? FileMessageWidget(
                                      message: message,
                                      isMe: isMe,
                                    )
                                  : messageType == 'audio'
                                      ? VoiceMessageWidget(
                                          message: message,
                                          isMe: isMe,
                                          formatTime: formatTime,
                                        )
                                      : Text(
                                          messageText.isNotEmpty ? messageText : (l10n?.t('common.unknown') ?? '未知内容'),
                                          style: TextStyle(
                                            color: isMe ? Colors.white : Colors.black87,
                                            fontSize: 16,
                                          ),
                                        ),
                ),
              ],
            ),
          ),
          // 时间和状态显示在气泡外部（参照网页端）
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatTime(dateTime),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (message['is_read'] == true)
                    Text(
                      l10n?.t('chat.read') ?? '已读',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    )
                  else
                    Text(
                      l10n?.t('chat.sent') ?? '已发送',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                formatTime(dateTime),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
