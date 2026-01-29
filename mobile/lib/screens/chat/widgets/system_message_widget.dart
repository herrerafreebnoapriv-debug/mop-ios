import 'package:flutter/material.dart';
import '../../../locales/app_localizations.dart';
import '../utils/chat_utils.dart';

/// 系统消息组件（用于显示通话邀请等，折中方案）
/// 主叫与被叫均显示「进入房间」按钮；被叫另显示「拒绝」
class SystemMessageWidget extends StatelessWidget {
  final Map<String, dynamic> message;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  /// 主叫/被叫统一为「进入房间」
  final String? acceptButtonLabel;

  const SystemMessageWidget({
    super.key,
    required this.message,
    this.onAccept,
    this.onReject,
    this.acceptButtonLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messageText = message['message']?.toString() ?? '';
    final callInvitation = getCallInvitation(message);
    final hasCallInvitation = callInvitation != null;
    final rejectLabel = l10n?.t('common.reject') ?? '拒绝';
    final acceptLabel = acceptButtonLabel ?? (l10n?.t('common.accept') ?? '接受');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.video_call, size: 20, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  messageText,
                  style: TextStyle(
                    color: Colors.blue[900],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          // 只要有 call_invitation 数据就显示按钮
          if (hasCallInvitation) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null)
                  TextButton(
                    onPressed: onReject,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(rejectLabel),
                  )
                else
                  const SizedBox.shrink(),
                if (onAccept != null)
                  ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(acceptLabel),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
