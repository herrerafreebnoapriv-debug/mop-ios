import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../locales/app_localizations.dart';
import '../../services/api/friends_api_service.dart';
import '../../providers/auth_provider.dart';
import 'chat_window_screen.dart';

/// 联系人列表标签页
class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final FriendsApiService _friendsApiService = FriendsApiService();
  List<dynamic> _friends = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchKeyword = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 参照网页端：使用 status_filter=accepted 获取已接受的好友
      final response = await _friendsApiService.getFriendsList(statusFilter: 'accepted');
      
      if (response != null && response['friends'] != null) {
        setState(() {
          _friends = List<dynamic>.from(response['friends']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _friends = [];
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

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchKeyword = '';
      }
    });
  }

  void _showAddFriendDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddFriendDialog(
        onFriendAdded: () {
          _loadFriends();
        },
      ),
    );
  }
  
  /// 公开方法，供外部调用（从 ChatMainScreen 的 AppBar 按钮）
  void showAddFriendDialog() {
    _showAddFriendDialog();
  }

  List<dynamic> get _filteredFriends {
    if (_searchKeyword.isEmpty) {
      return _friends;
    }
    return _friends.where((friend) {
      final name = friend['nickname']?.toString().toLowerCase() ?? 
                   friend['username']?.toString().toLowerCase() ?? '';
      final keyword = _searchKeyword.toLowerCase();
      return name.contains(keyword);
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
                        onPressed: _loadFriends,
                        child: Text(l10n?.t('common.retry') ?? '重试'),
                      ),
                    ],
                  ),
                )
              : _filteredFriends.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.t('chat.no_friends') ?? '暂无好友',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadFriends,
                      child: ListView.builder(
                        itemCount: _filteredFriends.length,
                        itemBuilder: (context, index) {
                          final friend = _filteredFriends[index];
                          return _FriendItem(
                            friend: friend,
                            onTap: () {
                              // 打开聊天窗口
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ChatWindowScreen(
                                    chatId: friend['user_id']?.toString() ?? '',
                                    chatName: friend['nickname']?.toString() ?? 
                                             friend['username']?.toString() ?? '',
                                    isRoom: false,
                                    userId: friend['user_id'] as int?,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFriendDialog,
        child: const Icon(Icons.person_add),
        backgroundColor: const Color(0xFF667eea),
      ),
    );
  }
}

class _FriendItem extends StatelessWidget {
  final Map<String, dynamic> friend;
  final VoidCallback onTap;

  const _FriendItem({
    required this.friend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = friend['nickname']?.toString() ?? 
                friend['username']?.toString() ?? 
                (l10n?.t('common.unknown') ?? '未知');
    final isOnline = friend['is_online'] == true;
    final status = friend['status']?.toString() ?? '';

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF667eea),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        isOnline 
            ? (l10n?.t('errors.online') ?? '在线')
            : (l10n?.t('errors.offline') ?? '离线'),
        style: TextStyle(
          color: isOnline ? Colors.green : Colors.grey,
          fontSize: 12,
        ),
      ),
      trailing: status == 'pending'
          ? Chip(
              label: Text(l10n?.t('errors.pending') ?? '待接受'),
              backgroundColor: Colors.orange,
            )
          : IconButton(
              icon: const Icon(Icons.chat),
              onPressed: onTap,
            ),
      onTap: status == 'accepted' ? onTap : null,
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  final VoidCallback onFriendAdded;

  const _AddFriendDialog({required this.onFriendAdded});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final FriendsApiService _friendsApiService = FriendsApiService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // 延迟搜索，避免频繁请求
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _friendsApiService.searchUsers(keyword.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('chat.search_failed') ?? '搜索失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addFriend(int friendId) async {
    final l10n = AppLocalizations.of(context);
    try {
      final success = await _friendsApiService.addFriend(friendId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('errors.friend_request_sent') ?? '好友请求已发送'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          widget.onFriendAdded();
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('errors.add_friend_failed') ?? '添加失败，请重试'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // 解析错误信息
        String errorMsg = l10n?.t('errors.add_friend_failed') ?? '添加失败';
        final errorStr = e.toString();
        
        // 尝试从错误信息中提取更友好的提示
        if (errorStr.contains('already_friends') || errorStr.contains('已是好友')) {
          errorMsg = l10n?.t('errors.already_friends') ?? '你们已经是好友了';
        } else if (errorStr.contains('request_already_sent') || errorStr.contains('已发送')) {
          errorMsg = l10n?.t('errors.request_already_sent') ?? '好友请求已发送，等待对方接受';
        } else if (errorStr.contains('cannot_add_self') || errorStr.contains('不能添加自己')) {
          errorMsg = l10n?.t('errors.cannot_add_self') ?? '不能添加自己为好友';
        } else if (errorStr.contains('not_found') || errorStr.contains('未找到')) {
          errorMsg = l10n?.t('errors.user_not_found') ?? '用户不存在';
        } else if (errorStr.isNotEmpty) {
          errorMsg = '${errorMsg}: ${errorStr.length > 50 ? errorStr.substring(0, 50) + "..." : errorStr}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n?.t('chat.add_friend') ?? '添加好友'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n?.t('chat.search_user') ?? '输入手机号或用户名搜索...',
                prefixIcon: const Icon(Icons.search),
                helperText: l10n?.t('chat.search_hint') ?? '提示：请输入完整的手机号或用户名（精确匹配）',
                helperMaxLines: 2,
              ),
              onChanged: _searchUsers,
            ),
            const SizedBox(height: 8),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
              Text(
                l10n?.t('chat.no_users_found') ?? '未找到用户',
                style: const TextStyle(color: Colors.grey),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    final userId = user['user_id'] ?? user['id'];
                    final name = user['nickname']?.toString() ?? 
                                user['username']?.toString() ?? '未知';
                    final status = user['status']?.toString() ?? 'none';
                    final phone = user['phone']?.toString() ?? '';
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF667eea),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(name),
                      subtitle: phone.isNotEmpty ? Text(phone) : null,
                      trailing: status == 'accepted'
                          ? Chip(
                              label: Text(l10n?.t('errors.already_friends') ?? '已是好友'),
                              backgroundColor: Colors.green.withOpacity(0.2),
                            )
                          : status == 'pending'
                              ? Chip(
                                  label: Text(l10n?.t('errors.pending') ?? '待接受'),
                                  backgroundColor: Colors.orange.withOpacity(0.2),
                                )
                              : ElevatedButton(
                                  onPressed: userId != null 
                                      ? () => _addFriend(userId is int ? userId : int.parse(userId.toString()))
                                      : null,
                                  child: Text(l10n?.t('chat.add_friend') ?? '添加'),
                                ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.t('common.cancel') ?? '取消'),
        ),
      ],
    );
  }
}
