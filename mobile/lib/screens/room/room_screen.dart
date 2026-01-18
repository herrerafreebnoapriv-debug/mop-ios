import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../locales/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/jitsi/jitsi_service.dart';
import '../../services/api/api_service.dart';

/// 视频通话房间页面
class RoomScreen extends StatefulWidget {
  final String roomId;
  final String? roomName;
  
  const RoomScreen({
    super.key,
    required this.roomId,
    this.roomName,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  bool _isJoining = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _joinRoom();
  }
  
  Future<void> _joinRoom() async {
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final l10n = AppLocalizations.of(context);
      final userName = authProvider.currentUser?.nickname ?? 
                      authProvider.currentUser?.username ?? 
                      (l10n?.t('common.user') ?? '用户');
      
      await JitsiService.instance.joinRoom(
        roomId: widget.roomId,
        userName: userName,
        isAudioMuted: false,
        isVideoMuted: false,
      );
      
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isJoining = false;
          _errorMessage = e.toString();
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    if (_isJoining) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n?.t('common.loading') ?? '正在加入房间...'),
            ],
          ),
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.roomName ?? (l10n?.t('rooms.room') ?? '房间')),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(l10n?.t('errors.return') ?? '返回'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Jitsi Meet 会全屏显示，这里返回空容器
    // 实际视频通话界面由 Jitsi Meet SDK 控制
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
  
  @override
  void dispose() {
    // 离开房间
    _leaveRoom();
    super.dispose();
  }
  
  Future<void> _leaveRoom() async {
    try {
      // 调用Jitsi SDK离开房间
      JitsiService.instance.leaveRoom();
      
      // 调用后端API更新通话记录
      final apiService = ApiService();
      await apiService.post('/rooms/${widget.roomId}/leave');
    } catch (e) {
      // 静默处理错误，避免影响用户体验
      debugPrint('离开房间API调用失败: $e');
    }
  }
}
