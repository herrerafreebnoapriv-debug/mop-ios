import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/socket_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/chat_api_service.dart';
import '../../services/api/friends_api_service.dart';
import '../../services/data/message_cache_service.dart';
import 'chat_window_screen.dart';
import 'utils/chat_utils.dart';

/// 取翻译，缺 key 时用 fallback，避免显示 "friends.xxx" 等裸 key
String _t(AppLocalizations? l10n, String key, String fallback) {
  if (l10n == null) return fallback;
  final s = l10n.t(key);
  return (s.isEmpty || s == key) ? fallback : s;
}

/// 消息列表标签页
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final ChatApiService _chatApiService = ChatApiService();
  final FriendsApiService _friendsApiService = FriendsApiService();
  List<dynamic> _conversations = [];
  List<dynamic> _pendingFriendRequests = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchKeyword = '';
  bool _isSearching = false;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _loadConversationsFromCache().then((_) {
      // 无论缓存是否命中，都继续从服务器拉最新数据
      _loadData();
    });
  }

  /// 先从本地缓存加载会话，实现“秒开”
  Future<void> _loadConversationsFromCache() async {
    try {
      final cached =
          await MessageCacheService.instance.getConversations();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _conversations = cached;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('从本地缓存加载会话失败: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 当页面可见时，刷新待处理的好友请求（不重置加载状态）
    _loadPendingFriendRequests();
    // 仅订阅一次：会话列表消费 messageStream，实时更新最后一条/未读
    if (_messageSubscription == null && mounted) {
      _subscribeToRealtimeMessages();
    }
  }

  /// 订阅实时消息流，更新会话列表的最后一条与未读数（排查文档建议的优化）
  void _subscribeToRealtimeMessages() {
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = safeInt(authProvider.currentUser?.id);
    if (currentUserId == null) return;

    _messageSubscription = socketProvider.messageStream.listen((message) {
      if (!mounted) return;
      final senderId = safeInt(message['sender_id']) ?? safeInt(message['from_user_id']);
      final receiverId = safeInt(message['receiver_id']);
      final roomId = safeInt(message['room_id']);
      // 仅处理单聊（无 room_id 或 room_id 为空）
      if (roomId != null && roomId != 0) return;

      final peerUserId = receiverId == currentUserId ? senderId : (senderId == currentUserId ? receiverId : null);
      if (peerUserId == null) return;

      final preview = _previewForMessage(message);
      final createdAt = message['created_at']?.toString() ?? '';

      setState(() {
        final list = List<Map<String, dynamic>>.from(_conversations.map((e) => Map<String, dynamic>.from(e as Map)));
        final idx = list.indexWhere((c) => safeInt(c['user_id']) == peerUserId && c['room_id'] == null);
        if (idx == -1) return;

        final conv = list[idx];
        conv['last_message'] = preview;
        conv['last_message_time'] = createdAt;
        if (receiverId == currentUserId && senderId != currentUserId) {
          conv['unread_count'] = ((conv['unread_count'] as int?) ?? 0) + 1;
        }
        list.removeAt(idx);
        list.insert(0, conv);
        _conversations = list;
      });
    });
  }

  /// 消息预览文案（与聊天页展示一致）
  static String _previewForMessage(Map<String, dynamic> message) {
    final type = message['message_type']?.toString() ?? 'text';
    final content = message['message']?.toString() ?? '';
    if (type == 'image' || content.startsWith('data:image/')) return '[图片]';
    if (type == 'system') return '[系统消息]';
    return content;
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      // 如果已有缓存会话，就不再显示全屏 loading，仅做静默刷新
      _isLoading = _conversations.isEmpty;
      _errorMessage = null;
    });
    await Future.wait([
      _loadConversations(),
      _loadPendingFriendRequests(),
    ]);
  }
  
  Future<void> _refreshData() async {
    await _loadData();
  }

  Future<void> _loadConversations() async {
    try {
      // 获取会话列表
      final response = await _chatApiService.getConversations();
      
      if (mounted) {
        setState(() {
          if (response != null && response['conversations'] != null) {
            _conversations = List<dynamic>.from(response['conversations']);
          } else {
            _conversations = [];
          }
          _isLoading = false;
          _errorMessage = null;
        });

        // 保存到本地缓存，便于下次秒开
        await MessageCacheService.instance.saveConversations(_conversations);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPendingFriendRequests() async {
    try {
      // 获取待处理的好友请求
      // 注意：后端返回的pending好友列表中，只包含对方发送给我的请求（可以接受/拒绝的）
      // 我发送的请求不会出现在这个列表中（后端API逻辑）
      final response = await _friendsApiService.getFriendsList(statusFilter: 'pending');
      
      if (mounted) {
        setState(() {
          if (response != null && response['friends'] != null) {
            final raw = List<dynamic>.from(response['friends'] as Iterable<dynamic>);
            _pendingFriendRequests = raw.whereType<Map>().cast<dynamic>().toList();
          } else {
            _pendingFriendRequests = [];
          }
        });
      }
    } catch (e) {
      debugPrint('加载待处理好友请求失败: $e');
      if (mounted) {
        setState(() {
          _pendingFriendRequests = [];
        });
      }
    }
  }

  Future<void> _acceptFriendRequest(int friendId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final success = await _friendsApiService.acceptFriendRequest(friendId);
      if (success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(l10n, 'friends.request_accepted', '已接受好友请求')),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(l10n, 'errors.accept_failed', '接受失败，请重试')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t(l10n, 'errors.accept_failed', '接受失败')}：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectFriendRequest(int friendId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final success = await _friendsApiService.rejectFriendRequest(friendId);
      if (success && mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(l10n, 'friends.request_rejected', '已拒绝好友请求')),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t(l10n, 'errors.reject_failed', '拒绝失败，请重试')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t(l10n, 'errors.reject_failed', '拒绝失败')}：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchKeyword = '';
      }
    });
  }
  
  /// 公开方法，供外部调用（从 ChatMainScreen 的 AppBar 按钮）
  void toggleSearch() {
    _toggleSearch();
  }

  List<dynamic> get _filteredConversations {
    if (_searchKeyword.isEmpty) {
      return _conversations;
    }
    return _conversations.where((conv) {
      final name = (conv['user_nickname'] ?? conv['room_name'] ?? '').toString().toLowerCase();
      final preview = (conv['last_message'] ?? '').toString().toLowerCase();
      final keyword = _searchKeyword.toLowerCase();
      return name.contains(keyword) || preview.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // 不显示 AppBar，由 ChatMainScreen 统一管理顶部导航栏
      appBar: null,
      body: Column(
        children: [
          // 搜索栏（如果需要显示）
          if (_isSearching)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.white,
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n?.t('chat.search') ?? '搜索...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _toggleSearch,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchKeyword = value;
                  });
                },
              ),
            ),
          // 主内容
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
                          onPressed: _loadData,
                          child: Text(l10n?.t('common.retry') ?? '重试'),
                        ),
                      ],
                    ),
                  )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView(
                    children: [
                    // 待处理的好友请求
                    if (_pendingFriendRequests.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        color: Colors.orange.shade50,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                _t(l10n, 'friends.pending_requests', '待处理的好友请求'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                            ..._pendingFriendRequests.whereType<Map>().where((friend) {
                              final uid = friend['user_id'];
                              return uid != null && (uid is int || int.tryParse(uid.toString()) != null);
                            }).map((friend) {
                              final uid = friend['user_id'];
                              final friendId = uid is int ? uid : int.parse(uid.toString());
                              final raw = friend['nickname']?.toString() ??
                                  friend['username']?.toString() ??
                                  _t(l10n, 'common.unknown', '未知');
                              final name = raw.replaceAll('\n', ' ').trim();
                              final subtitle = _t(l10n, 'friends.wants_to_add_you', '想添加您为好友');
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF667eea),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () => _acceptFriendRequest(friendId),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.green,
                                        ),
                                        child: Text(_t(l10n, 'common.accept', '接受')),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () => _rejectFriendRequest(friendId),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                        child: Text(_t(l10n, 'common.reject', '拒绝')),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    // 会话列表
                    if (_filteredConversations.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
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
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._filteredConversations.map((conv) {
                        final chatId = conv['user_id']?.toString() ?? conv['room_id']?.toString() ?? '';
                        final chatName = conv['user_nickname'] ?? conv['room_name'] ?? l10n?.t('chat.unknown') ?? '未知';
                        final isRoom = conv['room_id'] != null;
                        final lastMessage = conv['last_message'] ?? '';
                        final lastMessageTime = conv['last_message_time'] ?? '';
                        final unreadCount = conv['unread_count'] ?? 0;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF667eea),
                            child: Text(
                              chatName.isNotEmpty ? chatName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(chatName),
                          subtitle: Text(
                            lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (lastMessageTime.isNotEmpty)
                                Text(
                                  lastMessageTime,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            int? userId;
                            int? roomId;
                            if (isRoom) {
                              final rid = conv['room_id'];
                              roomId = rid is int ? rid : (rid != null ? int.tryParse(rid.toString()) : null);
                            } else {
                              final uid = conv['user_id'];
                              userId = uid is int ? uid : (uid != null ? int.tryParse(uid.toString()) : null);
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ChatWindowScreen(
                                  chatId: chatId,
                                  chatName: chatName,
                                  isRoom: isRoom,
                                  userId: userId,
                                  roomId: roomId,
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ],
                  ),
                ),
          ),
        ],
      ),
      // 移除 FloatingActionButton，搜索功能由 AppBar 的按钮触发
    );
  }
}

class _MessageItem extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  const _MessageItem({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
                          final l10n = AppLocalizations.of(context);
                          final name = conversation['user_nickname']?.toString() ?? 
                                         conversation['room_name']?.toString() ?? 
                                         (l10n?.t('common.unknown') ?? '未知');
    final preview = conversation['last_message']?.toString() ?? '';
    final lastMessageTime = conversation['last_message_time']?.toString() ?? '';
    final unreadCount = conversation['unread_count'] as int? ?? 0;
    
    // 格式化时间（正确处理时区）
    String time = '';
    if (lastMessageTime.isNotEmpty) {
      try {
        // 解析时间并转换为本地时区
        DateTime dateTime = DateTime.parse(lastMessageTime);
        if (dateTime.isUtc) {
          dateTime = dateTime.toLocal();
        }
        final now = DateTime.now();
        final difference = now.difference(dateTime);
        
        final l10n = AppLocalizations.of(context);
        if (difference.inDays == 0) {
          time = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } else if (difference.inDays == 1) {
          time = l10n?.t('common.yesterday') ?? '昨天';
        } else if (difference.inDays < 7) {
          time = (l10n?.t('common.days_ago') ?? '{days}天前').replaceAll('{days}', difference.inDays.toString());
        } else {
          time = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
        }
      } catch (e) {
        time = lastMessageTime;
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF667eea),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            time,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
