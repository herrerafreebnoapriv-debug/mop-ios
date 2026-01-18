import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import '../../providers/auth_provider.dart';
import '../../providers/socket_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/chat_api_service.dart';
import '../../services/api/files_api_service.dart';
import '../../services/permission/permission_service.dart';

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
  final FilesApiService _filesApiService = FilesApiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false; // 语音录制状态
  String? _errorMessage;
  StreamSubscription? _messageSubscription;
  
  // 音频录制和播放
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentRecordingPath;
  String? _currentlyPlayingMessageId; // 当前正在播放的语音消息ID
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 加载消息历史
  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _chatApiService.getMessages(
        userId: widget.userId,
        roomId: widget.roomId,
        limit: 50,
      );

      if (response != null && response['messages'] != null) {
        // 参照网页端：后端返回的是降序（最新的在前），需要反转成升序（最旧的在顶部，最新的在底部）
        final messagesList = List<Map<String, dynamic>>.from(
          response['messages'].map((msg) => msg as Map<String, dynamic>),
        );
        
        // 过滤并排序消息：只保留属于当前会话的消息，并按时间升序排列
        final filteredMessages = messagesList.where((msg) {
          if (widget.isRoom) {
            // 房间消息：只保留当前房间的消息
            return msg['room_id'] == widget.roomId;
          } else {
            // 点对点消息：只保留与当前用户相关的消息
            final msgSenderId = msg['sender_id'] as int? ?? msg['from_user_id'] as int?;
            final msgReceiverId = msg['receiver_id'] as int?;
            final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
            final isFromTargetToMe = msgSenderId == widget.userId && msgReceiverId == currentUser?.id;
            final isFromMeToTarget = msgSenderId == currentUser?.id && msgReceiverId == widget.userId;
            return isFromTargetToMe || isFromMeToTarget;
          }
        }).toList();
        
        // 按时间升序排序（最旧的在前面，最新的在后面）
        filteredMessages.sort((a, b) {
          final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
          final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
          return timeA.compareTo(timeB);
        });
        
        setState(() {
          _messages = filteredMessages;
          _isLoading = false;
        });
        
        // 标记消息为已读（参照网页端）
        final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
        final unreadMessageIds = _messages
            .where((msg) => 
                msg['receiver_id'] == currentUser?.id && 
                msg['is_read'] != true)
            .map((msg) => msg['id'] as int)
            .toList();
        
        if (unreadMessageIds.isNotEmpty) {
          // 通过 Socket.io 标记已读
          final socketProvider = Provider.of<SocketProvider>(context, listen: false);
          if (socketProvider.isConnected) {
            socketProvider.markMessageRead(unreadMessageIds);
          }
          
          // 同时通过 API 更新（确保数据库同步，参照网页端）
          await _chatApiService.markAsRead(unreadMessageIds);
        }
        
        // 滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      } else {
        setState(() {
          _messages = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 订阅实时消息（参照网页端：socket.on('message', callback)）
  void _subscribeToMessages() {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    
    if (socketProvider.isConnected) {
      // 监听新消息事件（参照网页端：事件名称为 'message'）
      _messageSubscription = socketProvider.onMessage((message) {
        // 检查消息是否属于当前聊天
        final msgSenderId = message['sender_id'] as int? ?? message['from_user_id'] as int?;
        final msgReceiverId = message['receiver_id'] as int?;
        final msgRoomId = message['room_id'] as int?;
        
        if (widget.isRoom) {
          // 房间消息：严格匹配房间ID
          if (msgRoomId == widget.roomId) {
            // 检查消息是否已存在（避免重复添加）
            final messageId = message['id'] as int?;
            if (messageId != null) {
              final exists = _messages.any((msg) => msg['id'] == messageId);
              if (!exists) {
                setState(() {
                  _messages.add(message);
                  // 按时间排序（确保消息顺序正确）
                  _messages.sort((a, b) {
                    final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
                    final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
                    return timeA.compareTo(timeB);
                  });
                });
                _scrollToBottom();
              }
            }
          }
        } else {
          // 点对点消息（参照网页端逻辑）
          // 严格匹配：只显示发送给当前用户或从当前用户发送给目标用户的消息
          final isFromTargetToMe = msgSenderId == widget.userId && msgReceiverId == currentUser?.id;
          final isFromMeToTarget = msgSenderId == currentUser?.id && msgReceiverId == widget.userId;
          
          if (isFromTargetToMe || isFromMeToTarget) {
            // 检查消息是否已存在（避免重复添加）
            final messageId = message['id'] as int?;
            if (messageId != null) {
              final exists = _messages.any((msg) => msg['id'] == messageId);
              if (!exists) {
                setState(() {
                  _messages.add(message);
                  // 按时间排序（确保消息顺序正确）
                  _messages.sort((a, b) {
                    final timeA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
                    final timeB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
                    return timeA.compareTo(timeB);
                  });
                });
                _scrollToBottom();
                
                // 标记为已读（参照网页端）
                if (isFromTargetToMe && message['is_read'] != true) {
                  socketProvider.markMessageRead([messageId]);
                  _chatApiService.markAsRead([messageId]);
                }
              }
            }
          }
        }
      });
      
      // 监听消息已读状态更新（参照网页端：socket.on('message_read', callback)）
      socketProvider.on('message_read', (data) {
        if (data is Map<String, dynamic> && data['message_id'] != null) {
          final messageId = data['message_id'] as int;
          setState(() {
            final index = _messages.indexWhere((msg) => msg['id'] == messageId);
            if (index != -1) {
              _messages[index]['is_read'] = true;
              if (data['read_at'] != null) {
                _messages[index]['read_at'] = data['read_at'];
              }
            }
          });
        }
      });
    }
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
      final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
      tempMessage = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'sender_id': currentUser?.id ?? 0,
        'receiver_id': widget.userId,
        'room_id': widget.roomId,
        'message': message,
        'message_type': 'text',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
        'sender_nickname': currentUser?.nickname ?? currentUser?.username ?? (AppLocalizations.of(context)?.t('common.me') ?? '我'),
      };
      
      setState(() {
        _messages.add(tempMessage!);
        _messageController.clear();
      });
      _scrollToBottom();

      // 通过Socket发送（参照网页端：优先使用 Socket.io）
      final socketProvider = Provider.of<SocketProvider>(context, listen: false);
      if (socketProvider.isConnected) {
        // 优先使用 Socket.io 发送（实时性更好）
        socketProvider.sendMessage(
          receiverId: widget.userId,
          roomId: widget.roomId,
          message: message,
          messageType: 'text',
        );
        
        // 监听发送确认
        socketProvider.onMessageSent((confirmData) {
          debugPrint('✓ 消息发送确认: $confirmData');
        });
        
        // 监听错误
        socketProvider.onError((errorData) {
          debugPrint('✗ 发送消息错误: $errorData');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('发送失败: ${errorData['message'] ?? '未知错误'}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      } else {
        // Socket 未连接，使用 API 发送
        await _chatApiService.sendMessage(
          receiverId: widget.userId,
          roomId: widget.roomId,
          message: message,
          messageType: 'text',
        );
      }

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
    try {
      // 重新检查相册权限（确保获取最新状态）
      var permissionStatus = await PermissionService.instance.checkPhotosPermission();
      
      // 如果权限未授予，尝试申请
      if (permissionStatus != PermissionStatus.granted) {
        permissionStatus = await PermissionService.instance.requestPhotosPermission();
        
        // 申请后再次检查（某些系统需要重新检查）
        if (permissionStatus == PermissionStatus.granted) {
          // 等待一小段时间让系统更新权限状态
          await Future.delayed(const Duration(milliseconds: 100));
          permissionStatus = await PermissionService.instance.checkPhotosPermission();
        }
        
        if (permissionStatus != PermissionStatus.granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)?.t('permission.photos_required') ?? '需要相册权限才能发送图片'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: AppLocalizations.of(context)?.t('permission.go_to_settings') ?? '前往设置',
                  onPressed: () {
                    PermissionService.instance.openAppSettings();
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85, // 压缩质量
      );

      if (image != null && mounted) {
        await _sendImageFile(image.path);
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.pick_image_failed') ?? '选择图片失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 选择文件
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        await _sendFile(result.files.single.path!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('errors.pick_file_failed') ?? '选择文件失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 发送图片文件
  Future<void> _sendImageFile(String imagePath) async {
    setState(() {
      _isSending = true;
    });

    try {
      // 上传文件
      final uploadResponse = await _filesApiService.uploadFile(
        imagePath,
        fieldName: 'file',
        additionalData: {
          'message_type': 'image',
        },
      );

      if (uploadResponse != null && uploadResponse['file_id'] != null) {
        final fileId = uploadResponse['file_id'] as int;
        final fileName = uploadResponse['file_name']?.toString() ?? 'image.jpg';

        // 发送消息
        await _chatApiService.sendMessage(
          receiverId: widget.userId,
          roomId: widget.roomId,
          message: fileName,
          messageType: 'image',
          fileId: fileId,
        );

        // 通过Socket发送
        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: widget.userId,
            roomId: widget.roomId,
            message: fileName,
            messageType: 'image',
            fileId: fileId,
          );
        }

        // 重新加载消息
        await _loadMessages();
      } else {
        final l10n = AppLocalizations.of(context);
        throw Exception(l10n?.t('errors.upload_failed') ?? '文件上传失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('errors.send_image_failed') ?? '发送图片失败'}: $e'),
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

  /// 开始语音录制（长按触发）
  Future<void> _startVoiceRecording() async {
    try {
      // 检查麦克风权限
      final permissionStatus = await PermissionService.instance.checkMicrophonePermission();
      if (permissionStatus != PermissionStatus.granted) {
        final requestStatus = await PermissionService.instance.requestMicrophonePermission();
        if (requestStatus != PermissionStatus.granted) {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n?.t('permission.microphone_required') ?? '需要麦克风权限才能录制语音'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      
      // 获取临时目录
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/voice_$timestamp.m4a';
      
      // 开始录制
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );
      
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      
      // 启动计时器
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration = Duration(seconds: timer.tick);
          });
        }
      });
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.start_recording_failed') ?? '开始录音失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 停止语音录制并发送（长按结束触发）
  Future<void> _stopVoiceRecording() async {
    if (!_isRecording || _currentRecordingPath == null) return;
    
    try {
      // 停止录制
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      
      if (path != null && path.isNotEmpty) {
        setState(() {
          _isRecording = false;
          _recordingDuration = Duration.zero;
        });
        
        // 如果录制时长太短（小于0.5秒），不发送
        final recordingFile = File(path);
        if (await recordingFile.exists() && _recordingDuration.inMilliseconds < 500) {
          await recordingFile.delete();
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
        
        // 清理临时文件
        _currentRecordingPath = null;
      } else {
        setState(() {
          _isRecording = false;
          _recordingDuration = Duration.zero;
        });
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer?.cancel();
      
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.stop_recording_failed') ?? '停止录音失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 取消语音录制（长按取消触发）
  Future<void> _cancelVoiceRecording() async {
    if (!_isRecording) return;
    
    try {
      await _audioRecorder.stop();
      _recordingTimer?.cancel();
      
      // 删除临时文件
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentRecordingPath = null;
      }
      
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer?.cancel();
    }
  }

  /// 拍照
  Future<void> _takePhoto() async {
    try {
      // 检查相机权限
      final permissionStatus = await PermissionService.instance.checkCameraPermission();
      if (permissionStatus != PermissionStatus.granted) {
        final requestStatus = await PermissionService.instance.requestCameraPermission();
        if (requestStatus != PermissionStatus.granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)?.t('permission.camera_required') ?? '需要相机权限才能拍照'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo != null && mounted) {
        await _sendImageFile(photo.path);
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.take_photo_failed') ?? '拍照失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 开始视频通话
  void _startVideoCall() {
    // TODO: 实现视频通话功能（使用 Jitsi Meet）
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n?.t('chat.video_call_coming_soon') ?? '视频通话功能开发中...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 发送语音文件
  Future<void> _sendVoiceFile(String audioPath) async {
    setState(() {
      _isSending = true;
    });

    try {
      // 上传文件
      final uploadResponse = await _filesApiService.uploadFile(
        audioPath,
        fieldName: 'file',
        additionalData: {
          'message_type': 'audio',
        },
      );

      if (uploadResponse != null && uploadResponse['file_id'] != null) {
        final fileId = uploadResponse['file_id'] as int;
        final fileName = uploadResponse['file_name']?.toString() ?? 'voice.m4a';

        // 发送消息（使用 audio 类型）
        await _chatApiService.sendMessage(
          receiverId: widget.userId,
          roomId: widget.roomId,
          message: fileName,
          messageType: 'audio',
          fileId: fileId,
        );

        // 通过Socket发送
        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: widget.userId,
            roomId: widget.roomId,
            message: fileName,
            messageType: 'audio',
            fileId: fileId,
          );
        }

        // 重新加载消息
        await _loadMessages();
      } else {
        final l10n = AppLocalizations.of(context);
        throw Exception(l10n?.t('errors.upload_failed') ?? '文件上传失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('errors.send_voice_failed') ?? '发送语音失败'}: $e'),
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

  /// 发送文件
  Future<void> _sendFile(String filePath) async {
    setState(() {
      _isSending = true;
    });

    try {
      final file = File(filePath);
      final fileName = file.path.split('/').last;

      // 上传文件
      final uploadResponse = await _filesApiService.uploadFile(
        filePath,
        fieldName: 'file',
        additionalData: {
          'message_type': 'file',
        },
      );

      if (uploadResponse != null && uploadResponse['file_id'] != null) {
        final fileId = uploadResponse['file_id'] as int;

        // 发送消息
        await _chatApiService.sendMessage(
          receiverId: widget.userId,
          roomId: widget.roomId,
          message: fileName,
          messageType: 'file',
          fileId: fileId,
        );

        // 通过Socket发送
        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: widget.userId,
            roomId: widget.roomId,
            message: fileName,
            messageType: 'file',
            fileId: fileId,
          );
        }

        // 重新加载消息
        await _loadMessages();
      } else {
        final l10n = AppLocalizations.of(context);
        throw Exception(l10n?.t('errors.upload_failed') ?? '文件上传失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('errors.send_file_failed') ?? '发送文件失败'}: $e'),
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

  /// 格式化时间（格式：YYYY/MM/DD HH:mm，例如：2026/01/16 22:58）
  String _formatTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.id ?? 0;

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
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadMessages,
                              child: Text(l10n?.t('common.retry') ?? '重试'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n?.t('chat.no_messages') ?? '暂无消息',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadMessages,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                // 处理 sender_id 可能为 int 或 null 的情况
                                final senderId = message['sender_id'] ?? message['from_user_id'];
                                final isMe = (senderId is int ? senderId : int.tryParse(senderId.toString()) ?? 0) == currentUserId;
                                
                                return _MessageBubble(
                                  message: message,
                                  isMe: isMe,
                                  formatTime: _formatTime,
                                );
                              },
                            ),
                          ),
          ),
          
          // 输入框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // 语音按钮（左侧，参照网页端）
                  GestureDetector(
                    onLongPressStart: (_) => _startVoiceRecording(),
                    onLongPressEnd: (_) => _stopVoiceRecording(),
                    onLongPressCancel: () => _cancelVoiceRecording(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: _isRecording ? Colors.white : Colors.grey[600],
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: l10n?.t('chat.input_hint') ?? '输入消息...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  // 发送按钮
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                  // 功能菜单按钮（+按钮）
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add),
                    onSelected: (value) {
                      if (value == 'album') {
                        _pickImage(); // 相册
                      } else if (value == 'camera') {
                        _takePhoto(); // 拍照
                      } else if (value == 'video') {
                        _startVideoCall(); // 视频通话
                      } else if (value == 'file') {
                        _pickFile(); // 文件
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'album',
                        child: Row(
                          children: [
                            const Icon(Icons.photo_library, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(l10n?.t('chat.send_image') ?? '相册'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'camera',
                        child: Row(
                          children: [
                            const Icon(Icons.camera_alt, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(l10n?.t('chat.take_photo') ?? '拍照'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'video',
                        child: Row(
                          children: [
                            const Icon(Icons.videocam, color: Colors.purple),
                            const SizedBox(width: 8),
                            Text(l10n?.t('chat.video_call') ?? '视频通话'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'file',
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(l10n?.t('chat.send_file') ?? '文件'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String Function(DateTime) formatTime;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final messageText = message['message']?.toString() ?? '';
    final messageType = message['message_type']?.toString() ?? 'text';
    final createdAt = message['created_at']?.toString() ?? '';
    final l10n = AppLocalizations.of(context);
    final senderName = message['sender_nickname']?.toString() ?? 
                      message['sender_username']?.toString() ?? 
                      (l10n?.t('common.unknown') ?? '未知');

    DateTime? dateTime;
    try {
      dateTime = DateTime.parse(createdAt);
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
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.image, color: Colors.blue, size: 20),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    messageText.isNotEmpty ? messageText : (l10n?.t('chat.send_image') ?? '图片'),
                                    style: TextStyle(
                                      color: isMe ? Colors.white70 : Colors.blue,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : messageType == 'file'
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file,
                                      color: isMe ? Colors.white70 : Colors.green,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        messageText.isNotEmpty ? messageText : (l10n?.t('chat.send_file') ?? '文件'),
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.green,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              : messageType == 'audio'
                                  ? _VoiceMessageWidget(
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

/// 语音消息组件（参照Telegram/微信的语音条样式）
class _VoiceMessageWidget extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final String Function(DateTime) formatTime;

  const _VoiceMessageWidget({
    required this.message,
    required this.isMe,
    required this.formatTime,
  });

  @override
  State<_VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<_VoiceMessageWidget> with SingleTickerProviderStateMixin {
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
          await _audioPlayer.play(UrlSource(fileUrl));
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
