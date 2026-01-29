import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../locales/app_localizations.dart';
import '../../providers/socket_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/jitsi/jitsi_service.dart';
import 'messages_tab.dart';
import 'contacts_tab.dart';
import 'settings_tab.dart';

/// 聊天主界面（与网页端 chat.html 对应）
/// 包含：消息、联系人、账户设置三个标签页
class ChatMainScreen extends StatefulWidget {
  const ChatMainScreen({super.key});

  @override
  State<ChatMainScreen> createState() => _ChatMainScreenState();
}

class _ChatMainScreenState extends State<ChatMainScreen> {
  int _currentIndex = 0;
  
  // 使用 GlobalKey 来访问各个 Tab 的状态（使用类型擦除避免私有类访问问题）
  final GlobalKey _messagesTabKey = GlobalKey();
  final GlobalKey _contactsTabKey = GlobalKey();
  
  List<Widget> get _pages => [
    MessagesTab(key: _messagesTabKey),
    ContactsTab(key: _contactsTabKey),
    const SettingsTab(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 頂部漸變導航欄（參照網頁端 chat.html）
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? '💬 消息'
              : _currentIndex == 1
                  ? '👫 联系人'
                  : '⚙️ 賬戶設置',
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea), // #667eea
                Color(0xFF764ba2), // #764ba2
              ],
            ),
          ),
        ),
        elevation: 0,
        actions: _currentIndex == 0 || _currentIndex == 1
            ? [
                // 消息页和联系人页：同时显示搜索和添加按钮（参照网页版）
                // 搜索按钮（带文字，参照图片样式）
                TextButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('🔍'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    if (_currentIndex == 0) {
                      // 消息页：触发 MessagesTab 的搜索功能
                      final state = _messagesTabKey.currentState;
                      if (state != null && state is State) {
                        (state as dynamic).toggleSearch?.call();
                      }
                    } else if (_currentIndex == 1) {
                      // 联系人页：触发 ContactsTab 的搜索功能
                      final state = _contactsTabKey.currentState;
                      if (state != null && state is State) {
                        (state as dynamic).toggleSearch?.call();
                      }
                    }
                  },
                ),
                const SizedBox(width: 8),
                // 添加按钮（带文字，参照图片样式）
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('+ 添加'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    if (_currentIndex == 0) {
                      // 消息页：添加好友功能（可以跳转到联系人页或显示添加对话框）
                      final state = _contactsTabKey.currentState;
                      if (state != null && state is State) {
                        (state as dynamic).showAddFriendDialog?.call();
                      }
                    } else if (_currentIndex == 1) {
                      // 联系人页：触发 ContactsTab 的添加好友对话框
                      final state = _contactsTabKey.currentState;
                      if (state != null && state is State) {
                        (state as dynamic).showAddFriendDialog?.call();
                      }
                    }
                  },
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          _SystemMessageListener(),
          _CallInvitationListener(),
        ],
      ),
      // 底部导航栏（参照网页端 chat.html）
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF667eea),
          unselectedItemColor: const Color(0xFF999999),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.chat_bubble_outline),
              activeIcon: const Icon(Icons.chat_bubble),
              label: '消息',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_outline),
              activeIcon: const Icon(Icons.people),
              label: '联系人',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: '賬戶設置',
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemMessageListener extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SocketProvider>(
      builder: (context, sp, _) {
        final msg = sp.lastSystemMessage;
        if (msg != null && msg.isNotEmpty) {
          sp.clearLastSystemMessage();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                duration: const Duration(seconds: 4),
              ),
            );
          });
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _CallInvitationListener extends StatefulWidget {
  const _CallInvitationListener();

  @override
  State<_CallInvitationListener> createState() => _CallInvitationListenerState();
}

class _CallInvitationListenerState extends State<_CallInvitationListener> {
  Map<String, dynamic>? _lastProcessedInvitation;
  DateTime? _lastProcessedTime;
  bool _isShowingDialog = false;

  @override
  void initState() {
    super.initState();
    // 监听 SocketProvider 的变化；挂载后立即检查是否已有待处理邀请（避免漏收）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sp = Provider.of<SocketProvider>(context, listen: false);
      sp.addListener(_onSocketProviderChanged);
      _onSocketProviderChanged();
    });
  }

  @override
  void dispose() {
    final sp = Provider.of<SocketProvider>(context, listen: false);
    sp.removeListener(_onSocketProviderChanged);
    super.dispose();
  }

  void _onSocketProviderChanged() {
    if (!mounted || _isShowingDialog) return;
    
    final sp = Provider.of<SocketProvider>(context, listen: false);
    final invitation = sp.lastCallInvitation;
    
    if (invitation == null) return;

    // 避免重复处理同一条邀请
    final invitationTime = sp.lastCallInvitationAt;
    if (_lastProcessedInvitation != null &&
        _lastProcessedTime != null &&
        invitationTime != null &&
        invitation['room_id'] == _lastProcessedInvitation!['room_id'] &&
        invitationTime.difference(_lastProcessedTime!).inSeconds < 2) {
      return;
    }

    // 标记为已处理
    _lastProcessedInvitation = Map<String, dynamic>.from(invitation);
    _lastProcessedTime = invitationTime ?? DateTime.now();
    
    // 清空，避免重复弹出
    sp.clearLastCallInvitation();
    
    // 显示弹窗
    _showInvitationDialog(invitation);
  }

  Future<void> _showInvitationDialog(Map<String, dynamic> invitation) async {
    if (_isShowingDialog || !mounted) return;
    
    _isShowingDialog = true;
    
    final l10n = AppLocalizations.of(context);
    final callerName = (invitation['caller_name']?.toString() ?? (l10n?.t('common.user') ?? '用户'));
    final roomId = invitation['room_id']?.toString();
    
    if (roomId == null || roomId.isEmpty) {
      _isShowingDialog = false;
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final sp = Provider.of<SocketProvider>(context, listen: false);
    final userName = auth.currentUser?.nickname ??
        auth.currentUser?.username ??
        (l10n?.t('common.user') ?? '用户');

    final title = l10n?.t('chat.video_call_invitation_title') ?? '视频通话邀请';
    final contentTemplate = l10n?.t('chat.video_call_invitation_content') ?? '{caller} 邀请您进入视频通话，可共享屏幕';
    final content = contentTemplate.replaceAll('{caller}', callerName);
    final rejectLabel = l10n?.t('common.reject') ?? '拒绝';
    final acceptLabel = l10n?.t('common.accept') ?? '接受';
    final joinFailedPrefix = l10n?.t('chat.join_video_call_failed') ?? '加入视频通话失败';

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              sp.sendEvent('call_invitation_response', {
                'room_id': roomId,
                'accepted': false,
              });
              Navigator.of(ctx).pop('reject');
            },
            child: Text(rejectLabel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop('accept');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(acceptLabel),
          ),
        ],
      ),
    );

    _isShowingDialog = false;

    if (result == 'accept' && mounted) {
      try {
        sp.sendEvent('call_invitation_response', {
          'room_id': roomId,
          'accepted': true,
        });
        await JitsiService.instance.joinRoom(
          roomId: roomId,
          userName: userName,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$joinFailedPrefix: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 这个 Widget 只用于监听，不渲染任何内容
    return const SizedBox.shrink();
  }
}
