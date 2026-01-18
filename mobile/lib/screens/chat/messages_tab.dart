import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/chat_api_service.dart';
import 'chat_window_screen.dart';

/// 消息列表标签页
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final ChatApiService _chatApiService = ChatApiService();
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchKeyword = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 获取会话列表
      final response = await _chatApiService.getConversations();
      
      if (response != null && response['conversations'] != null) {
        setState(() {
          _conversations = List<dynamic>.from(response['conversations']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _conversations = [];
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
                          onPressed: _loadConversations,
                          child: Text(l10n?.t('common.retry') ?? '重试'),
                        ),
                      ],
                    ),
                  )
              : _filteredConversations.isEmpty
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
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredConversations.length,
                      itemBuilder: (context, index) {
                        final conv = _filteredConversations[index];
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
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ChatWindowScreen(
                                  chatId: chatId,
                                  chatName: chatName,
                                  isRoom: isRoom,
                                  userId: isRoom ? null : conv['user_id'] as int?,
                                  roomId: isRoom ? conv['room_id'] as int? : null,
                                ),
                              ),
                            );
                          },
                        );
                      },
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
    
    // 格式化时间
    String time = '';
    if (lastMessageTime.isNotEmpty) {
      try {
        final dateTime = DateTime.parse(lastMessageTime);
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
