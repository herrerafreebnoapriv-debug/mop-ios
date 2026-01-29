import 'package:flutter/material.dart';
import '../../../locales/app_localizations.dart';

/// 聊天输入栏：文本框、语音、附件、发送
class ChatInputBar extends StatelessWidget {
  final TextEditingController messageController;
  final bool isSending;
  final bool isRecording;
  final VoidCallback onSendMessage;
  final VoidCallback onStartVoiceRecording;
  final VoidCallback onStopVoiceRecording;
  final VoidCallback onCancelVoiceRecording;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onStartVideoCall;
  final VoidCallback onPickFile;

  const ChatInputBar({
    super.key,
    required this.messageController,
    required this.isSending,
    required this.isRecording,
    required this.onSendMessage,
    required this.onStartVoiceRecording,
    required this.onStopVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onPickImage,
    required this.onTakePhoto,
    required this.onStartVideoCall,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inputHint = l10n?.t('chat.input_hint') ?? '输入消息...';
    final sendImageLabel = l10n?.t('chat.send_image') ?? '相册';
    final takePhotoLabel = l10n?.t('chat.take_photo') ?? '拍照';
    final videoCallLabel = l10n?.t('chat.video_call') ?? '视频通话';
    final sendFileLabel = l10n?.t('chat.send_file') ?? '文件';
    final moreLabel = l10n?.t('chat.more') ?? '更多';
    final voiceHint = l10n?.t('chat.voice_long_press_hint') ?? '长按左侧麦克风按钮发送语音消息';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onLongPress: onStartVoiceRecording,
              onLongPressUp: onStopVoiceRecording,
              onLongPressCancel: onCancelVoiceRecording,
              child: Tooltip(
                message: voiceHint,
                child: IconButton(
                  icon: Icon(
                    isRecording ? Icons.stop_circle : Icons.mic,
                    color: isRecording ? Colors.red : null,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(voiceHint), duration: const Duration(seconds: 2)),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: messageController,
                decoration: InputDecoration(
                  hintText: inputHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSendMessage(),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: moreLabel,
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (value) {
                switch (value) {
                  case 'image':
                    onPickImage();
                    break;
                  case 'photo':
                    onTakePhoto();
                    break;
                  case 'video':
                    onStartVideoCall();
                    break;
                  case 'file':
                    onPickFile();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'image', child: Text(sendImageLabel)),
                PopupMenuItem(value: 'photo', child: Text(takePhotoLabel)),
                PopupMenuItem(value: 'video', child: Text(videoCallLabel)),
                PopupMenuItem(value: 'file', child: Text(sendFileLabel)),
              ],
            ),
            IconButton(
              icon: isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: isSending ? null : onSendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
