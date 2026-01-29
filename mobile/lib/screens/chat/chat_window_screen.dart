import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/socket_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/chat_api_service.dart';
import '../../services/data/message_cache_service.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_status_view.dart';
import 'services/chat_message_service.dart';
import 'services/chat_voice_recorder.dart';
import 'services/chat_message_loader.dart';
import 'services/chat_video_call_service.dart';
import 'services/chat_file_picker_service.dart';
import 'utils/chat_utils.dart';

/// 聊天窗口页面
class ChatWindowScreen extends StatefulWidget {
  final String chatId;
  final String chatName;
  final bool isRoom;
  final int? userId; // 点对点聊天的用户ID
  final int? roomId; // 房间聊天的房间ID

  const ChatWindowScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.isRoom = false,
    this.userId,
    this.roomId,
  });

  @override
  State<ChatWindowScreen> createState() => _ChatWindowScreenState();
}

class _ChatWindowScreenState extends State<ChatWindowScreen> {
  final ChatApiService _chatApiService = ChatApiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 消息管理服务
  final ChatMessageLoader _messageLoader = ChatMessageLoader();
  final ChatMessageService _messageService = ChatMessageService();
  final ChatVoiceRecorder _voiceRecorder = ChatVoiceRecorder();
  final ChatVideoCallService _videoCallService = ChatVideoCallService();
  final ChatFilePickerService _filePickerService = ChatFilePickerService();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _messageReadSubscription;
  StreamSubscription<Map<String, dynamic>>? _callInvitationSentSubscription;
  Timer? _pollingTimer;
  VoidCallback? _socketProviderListener;

  @override
  void initState() {
    super.initState();
    _loadMessagesFromCache();
    _loadMessages();
    _subscribeToMessages();
    _startDisconnectPollingFallback();
    // 延迟刷新一次，兜底未及时收到的消息（如视频邀请系统消息）
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _loadMessages();
    });
  }

  @override
  void dispose() {
    _stopDisconnectPollingFallback();
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _messageReadSubscription?.cancel();
    _callInvitationSentSubscription?.cancel();
    _voiceRecorder.dispose();
    super.dispose();
  }

  /// Socket 断开时启动轮询兜底，连接恢复时停止
  void _startDisconnectPollingFallback() {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    void onSocketProviderChanged() {
      if (!mounted) return;
      if (socketProvider.isConnected) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
      } else {
        if (_pollingTimer?.isActive ?? false) return;
        _pollingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
          if (mounted && !socketProvider.isConnected) _loadMessages();
        });
      }
    }
    _socketProviderListener = onSocketProviderChanged;
    socketProvider.addListener(_socketProviderListener!);
    onSocketProviderChanged();
  }

  void _stopDisconnectPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    if (_socketProviderListener != null) {
      socketProvider.removeListener(_socketProviderListener!);
      _socketProviderListener = null;
    }
  }

  /// 从本地缓存加载消息，实现聊天窗口“秒开”
  Future<void> _loadMessagesFromCache() async {
    try {
      final cached = await MessageCacheService.instance.getMessagesForChat(
        isRoom: widget.isRoom,
        userId: widget.userId,
        roomId: widget.roomId,
      );
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _messages = cached;
          _isLoading = false;
          _errorMessage = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('从本地缓存加载聊天消息失败: $e');
    }
  }

  /// 加载消息历史
  Future<void> _loadMessages() async {
    setState(() {
      if (_messages.isEmpty) _isLoading = true;
      _errorMessage = null;
    });

    final filteredMessages = await _messageLoader.loadMessages(
      context: context,
      userId: widget.userId,
      roomId: widget.roomId,
      isRoom: widget.isRoom,
      onError: (error) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      },
    );

    if (mounted) {
      setState(() {
        _messages = filteredMessages;
        _isLoading = false;
      });

      // 写入缓存，供秒开使用
      if (filteredMessages.isNotEmpty) {
        MessageCacheService.instance.saveMessagesForChat(
          isRoom: widget.isRoom,
          userId: widget.userId,
          roomId: widget.roomId,
          messages: filteredMessages,
        );
      }
      
      // 标记消息为已读
      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
      final curId = safeInt(currentUser?.id);
      final unreadMessageIds = _messages
          .where((msg) =>
              safeInt(msg['receiver_id']) == curId &&
              msg['is_read'] != true)
          .map((msg) => safeInt(msg['id']))
          .whereType<int>()
          .toList();
      
      if (unreadMessageIds.isNotEmpty) {
        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.markMessageRead(unreadMessageIds);
        }
        await _chatApiService.markAsRead(unreadMessageIds);
      }
      
      // 滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// 订阅实时消息：监听 Provider 全局 message / message_read 流，重连后不丢失
  void _subscribeToMessages() {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final currentUserId = currentUser?.id;

    _messageSubscription = socketProvider.messageStream.listen((message) {
      if (!mounted) return;
      // 自动识别 base64 数据 URI 为图片消息
      final messageText = message['message']?.toString() ?? '';
      if (message['message_type'] == null || message['message_type'] == 'text') {
        if (messageText.startsWith('data:image/')) {
          message['message_type'] = 'image';
        }
      }

      final msgSenderId = safeInt(message['sender_id']) ?? safeInt(message['from_user_id']);
      final msgReceiverId = safeInt(message['receiver_id']);
      final msgRoomId = safeInt(message['room_id']);

      if (widget.isRoom) {
        if (msgRoomId != widget.roomId) return;
        final messageId = safeInt(message['id']);
        if (messageId == null) return;
        if (_messages.any((msg) => msg['id'] == messageId)) return;
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) {
            final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
            final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
            return timeA.compareTo(timeB);
          });
        });
        _scrollToBottom();
        return;
      }

      final messageType = message['message_type']?.toString() ?? 'text';
      final isSystemMessage = messageType == 'system';
      final isFromTargetToMe = msgSenderId == widget.userId && msgReceiverId == currentUserId;
      final isFromMeToTarget = msgSenderId == currentUserId && msgReceiverId == widget.userId;

      // 系统消息（视频邀请等）：对方发给我，必须显示「接受/拒绝」；用 safeInt 避免 JSON number 被丢弃
      if (isSystemMessage && isFromTargetToMe) {
        final messageId = safeInt(message['id']);
        if (messageId == null) return;
        if (_messages.any((msg) => safeInt(msg['id']) == messageId)) return;
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) {
            final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
            final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
            return timeA.compareTo(timeB);
          });
        });
        _scrollToBottom();
        return;
      }

      if (!isFromTargetToMe && !isFromMeToTarget) return;
      final messageId = safeInt(message['id']);
      if (messageId == null) return;
      if (_messages.any((msg) => msg['id'] == messageId)) return;
      setState(() {
        _messages.add(message);
        _messages.sort((a, b) {
          final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
          final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
          return timeA.compareTo(timeB);
        });
      });
      _scrollToBottom();
      if (isFromTargetToMe && message['is_read'] != true) {
        socketProvider.markMessageRead([messageId]);
        _chatApiService.markAsRead([messageId]);
      }
    });

    _messageReadSubscription = socketProvider.messageReadStream.listen((data) {
      if (!mounted) return;
      final messageId = safeInt(data['message_id']);
      if (messageId == null) return;
      setState(() {
        final index = _messages.indexWhere((msg) => safeInt(msg['id']) == messageId);
        if (index != -1) {
          _messages[index]['is_read'] = true;
          if (data['read_at'] != null) {
            _messages[index]['read_at'] = data['read_at'];
          }
        }
      });
    });

    // 主叫收到「邀请已发送」确认时，将系统消息写入当前聊天（推送层备用路径）
    _callInvitationSentSubscription = socketProvider.callInvitationSentStream.listen((data) {
      if (!mounted || widget.isRoom) return;
      final sysMsg = data['system_message'];
      if (sysMsg is! Map) return;
      final targetId = safeInt(data['target_user_id']);
      if (targetId != widget.userId) return;
      final msg = Map<String, dynamic>.from(sysMsg as Map);
      final msgId = safeInt(msg['id']);
      if (msgId == null) return;
      if (_messages.any((m) => safeInt(m['id']) == msgId)) return;
      setState(() {
        _messages.add(msg);
        _messages.sort((a, b) {
          final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
          final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
          return timeA.compareTo(timeB);
        });
      });
      _scrollToBottom();
    });
  }

  /// 发送消息
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    Map<String, dynamic>? tempMessage;
    try {
      // 先显示本地消息（乐观更新）
      tempMessage = _messageService.createTempMessage(
        context: context,
        message: message,
        userId: widget.userId,
        roomId: widget.roomId,
      );
      
      setState(() {
        _messages.add(tempMessage!);
        _messageController.clear();
      });
      _scrollToBottom();

      // 发送消息
      await _messageService.sendTextMessage(
        context: context,
        message: message,
        userId: widget.userId,
        roomId: widget.roomId,
        onSuccess: (confirmData) {
          debugPrint('✓ 消息发送确认: $confirmData');
        },
        onError: (error) {
          debugPrint('✗ 发送消息错误: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('发送失败: $error'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      );

      // 重新加载消息以获取服务器返回的真实消息ID
      await _loadMessages();
    } catch (e) {
      // 发送失败，移除临时消息
      if (tempMessage != null) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == tempMessage!['id']);
          final l10n = AppLocalizations.of(context);
          _errorMessage = '${l10n?.t('errors.send_failed') ?? '发送失败'}: $e';
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('errors.send_failed') ?? '发送失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// 滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 选择图片
  Future<void> _pickImage() async {
    final imagePath = await _filePickerService.pickImage(
      context: context,
      onError: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.t('errors.pick_image_failed') ?? '选择图片失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
    
    if (imagePath != null && mounted) {
      await _sendImageFile(imagePath);
    }
  }

  /// 选择文件
  Future<void> _pickFile() async {
    final filePath = await _filePickerService.pickFile(
      context: context,
      onError: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.t('errors.pick_file_failed') ?? '选择文件失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
    
    if (filePath != null && mounted) {
      await _sendFile(filePath);
    }
  }

  /// 发送图片文件
  Future<void> _sendImageFile(String imagePath) async {
    setState(() {
      _isSending = true;
    });

    await _messageService.sendImageMessage(
      context: context,
      imagePath: imagePath,
      userId: widget.userId,
      roomId: widget.roomId,
      onSuccess: () async {
        await _loadMessages();
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)?.t('errors.send_image_failed') ?? '发送图片失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  /// 开始语音录制（长按触发）
  Future<void> _startVoiceRecording() async {
    final success = await _voiceRecorder.startRecording(
      onDurationUpdate: (duration) {
        if (mounted) {
          setState(() {});
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
    
    if (success && mounted) {
      setState(() {});
    }
  }

  /// 停止语音录制并发送（长按结束触发）
  Future<void> _stopVoiceRecording() async {
    if (!_voiceRecorder.isRecording) return;
    
    final path = await _voiceRecorder.stopRecording();
    
    if (mounted) {
      setState(() {});
    }
    
    if (path == null) {
      // 录音时间太短或失败
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.t('chat.voice_too_short') ?? '录音时间太短，请重新录制'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    
    // 发送语音文件
    await _sendVoiceFile(path);
  }

  /// 取消语音录制（长按取消触发）
  Future<void> _cancelVoiceRecording() async {
    await _voiceRecorder.cancelRecording();
    if (mounted) {
      setState(() {});
    }
  }

  /// 拍照
  Future<void> _takePhoto() async {
    final photoPath = await _filePickerService.takePhoto(
      context: context,
      onError: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.t('errors.take_photo_failed') ?? '拍照失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
    
    if (photoPath != null && mounted) {
      await _sendImageFile(photoPath);
    }
  }


  /// 开始视频通话
  Future<void> _startVideoCall() async {
    await _videoCallService.startVideoCall(
      context: context,
      userId: widget.userId,
      roomId: widget.roomId,
      isRoom: widget.isRoom,
      chatName: widget.chatName,
      onError: (error) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.t('chat.video_call_failed') ?? '视频通话失败'}: $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }

  /// 发送语音文件
  Future<void> _sendVoiceFile(String audioPath) async {
    setState(() {
      _isSending = true;
    });

    await _messageService.sendVoiceMessage(
      context: context,
      audioPath: audioPath,
      userId: widget.userId,
      roomId: widget.roomId,
      onSuccess: () async {
        await _loadMessages();
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)?.t('errors.send_voice_failed') ?? '发送语音失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  /// 发送文件
  Future<void> _sendFile(String filePath) async {
    setState(() {
      _isSending = true;
    });

    await _messageService.sendFileMessage(
      context: context,
      filePath: filePath,
      userId: widget.userId,
      roomId: widget.roomId,
      onSuccess: () async {
        await _loadMessages();
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)?.t('errors.send_file_failed') ?? '发送文件失败'}: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatName),
        actions: [
          if (widget.isRoom)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                // TODO: 显示房间信息
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _isLoading || _errorMessage != null || _messages.isEmpty
                ? ChatStatusView(
                    isLoading: _isLoading,
                    errorMessage: _errorMessage,
                    isEmpty: _messages.isEmpty,
                    onRetry: _loadMessages,
                  )
                : ChatMessageList(
                    messages: _messages,
                    scrollController: _scrollController,
                    onRefresh: _loadMessages,
                    userId: widget.userId,
                  ),
          ),
          
          // 输入框
          ChatInputBar(
            messageController: _messageController,
            isSending: _isSending,
            isRecording: _voiceRecorder.isRecording,
            onSendMessage: _sendMessage,
            onStartVoiceRecording: _startVoiceRecording,
            onStopVoiceRecording: _stopVoiceRecording,
            onCancelVoiceRecording: _cancelVoiceRecording,
            onPickImage: _pickImage,
            onTakePhoto: _takePhoto,
            onStartVideoCall: _startVideoCall,
            onPickFile: _pickFile,
          ),
        ],
      ),
    );
  }
}
