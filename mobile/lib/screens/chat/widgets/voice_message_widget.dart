import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../locales/app_localizations.dart';
import '../../../core/services/storage_service.dart';
import '../utils/chat_utils.dart';

/// 语音消息组件（参照Telegram/微信的语音条样式）
class VoiceMessageWidget extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String Function(DateTime) formatTime;

  const VoiceMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.formatTime,
  });

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget> with SingleTickerProviderStateMixin {
  bool _isPlaying = false;
  late AnimationController _animationController;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (!_isPlaying) {
            _animationController.stop();
            _animationController.reset();
          } else {
            _animationController.repeat();
          }
        });
      }
    });
    
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _animationController.stop();
          _animationController.reset();
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      final fileUrl = widget.message['file_url']?.toString();
      final messageText = widget.message['message']?.toString();
      
      if (fileUrl != null && fileUrl.isNotEmpty) {
        try {
          // 构建带token的URL
          final authenticatedUrl = await buildAuthenticatedUrl(fileUrl);
          await _audioPlayer.play(UrlSource(authenticatedUrl));
        } catch (e) {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l10n?.t('errors.play_voice_failed') ?? '播放语音失败'}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else if (messageText != null && messageText.isNotEmpty) {
        // 如果 message 包含文件路径（临时）
        try {
          await _audioPlayer.play(DeviceFileSource(messageText));
        } catch (e) {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${l10n?.t('errors.play_voice_failed') ?? '播放语音失败'}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // 尝试通过 file_id 获取文件URL
        final fileId = widget.message['file_id'];
        if (fileId != null) {
          // TODO: 通过 file_id 获取文件信息（包含 URL）
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n?.t('errors.file_url_not_found') ?? '无法获取语音文件地址'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins > 0) {
      return '$mins:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${secs}秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 获取语音时长（秒），如果没有则默认为0
    final duration = widget.message['duration'] as int? ?? 0;
    // 根据时长计算语音条宽度（最小80，最大200，每10秒约增加20）
    final barWidth = (80 + (duration ~/ 10) * 20).clamp(80.0, 200.0).toDouble();
    
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          minWidth: barWidth,
          maxWidth: barWidth,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: widget.isMe
              ? [
                  // 右侧显示时长
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 波形图标（播放时动画）
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(4, (index) {
                          final delay = index * 0.2;
                          final value = _isPlaying
                              ? (0.3 + 0.7 * ((_animationController.value + delay) % 1.0))
                              : 0.3;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 3,
                            height: 20 * value,
                            decoration: BoxDecoration(
                              color: Colors.white70,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // 播放/暂停图标
                  Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 16,
                    color: Colors.white70,
                  ),
                ]
              : [
                  // 左侧播放/暂停图标
                  Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  // 波形图标（播放时动画）
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(4, (index) {
                          final delay = index * 0.2;
                          final value = _isPlaying
                              ? (0.3 + 0.7 * ((_animationController.value + delay) % 1.0))
                              : 0.3;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 3,
                            height: 20 * value,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // 右侧显示时长
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
