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
  bool _inCall = false;
  /// 是否因「按返回进画中画」而关闭页面（此时不应挂断，避免窗口消失）
  bool _minimizedToPiP = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _joinRoom();
  }

  Future<void> _joinRoom() async {
    if (!mounted) return;
    setState(() {
      _isJoining = true;
      _errorMessage = null;
      _inCall = false;
    });

    AuthProvider? authProvider;
    String userName = '用户';
    try {
      authProvider = Provider.of<AuthProvider>(context, listen: false);
      final l10n = AppLocalizations.of(context);
      userName = authProvider.currentUser?.nickname ??
          authProvider.currentUser?.username ??
          (l10n?.t('common.user') ?? '用户');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isJoining = false;
          _errorMessage = '无法获取用户信息: $e';
        });
      }
      return;
    }

    try {
      await JitsiService.instance.joinRoom(
        roomId: widget.roomId,
        userName: userName,
        isAudioMuted: false,
        isVideoMuted: false,
        onConferenceJoined: () {
          if (mounted) {
            setState(() {
              _isJoining = false;
              _inCall = true;
            });
          }
        },
        onConferenceTerminated: () {
          // 会议结束（挂断/被踢/断线）：仅当未最小化到 PiP 时才 pop（避免重复 pop）
          if (mounted && !_minimizedToPiP) {
            Navigator.of(context).pop();
          }
        },
      );
      // join 返回表示会议已结束；若此时仍在页面，pop 掉
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isJoining = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

    // 通话中：Jitsi 全屏。按返回进入画中画并 pop 掉 RoomScreen，只保留 PiP 窗口。
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_inCall) {
          // 标记为「最小化到 PiP」，dispose 时不再调用 leaveRoom()，避免挂断导致窗口消失
          _minimizedToPiP = true;
          try {
            await JitsiService.instance.enterPiP();
            // 留足时间让系统完成 PiP 切换再 pop，避免窗口被销毁
            await Future.delayed(const Duration(milliseconds: 600));
          } catch (e) {
            debugPrint('进入画中画失败: $e，继续关闭窗口');
          }
          if (mounted) Navigator.of(context).pop();
        } else {
          Navigator.of(context).pop();
        }
      },
      // 通话全屏时，此 Scaffold 被 Jitsi 覆盖；此处仅作占位
      child: const Scaffold(
        body: SizedBox.shrink(),
      ),
    );
  }

  @override
  void dispose() {
    // 最小化到 PiP 时不要挂断、不要调离开接口，否则通话窗口会消失
    if (!_minimizedToPiP) {
      _leaveRoom();
    }
    super.dispose();
  }

  Future<void> _leaveRoom() async {
    try {
      if (_inCall) JitsiService.instance.leaveRoom();
      final apiService = ApiService();
      await apiService.post('/rooms/${widget.roomId}/leave');
    } catch (e) {
      debugPrint('离开房间API调用失败: $e');
    }
  }
}
