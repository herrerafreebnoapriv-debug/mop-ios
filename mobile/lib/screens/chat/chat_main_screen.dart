import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../locales/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      // 顶部渐变导航栏（参照网页端 chat.html）
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? (l10n?.t('chat.messages') ?? '消息')
              : _currentIndex == 1
                  ? (l10n?.t('chat.contacts') ?? '联系人')
                  : (l10n?.t('chat.settings') ?? '账户设置'),
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
                  label: Text(l10n?.t('chat.search') ?? '搜索'),
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
                  label: Text(l10n?.t('chat.add_friend') ?? '添加'),
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
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
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
              label: l10n?.t('chat.messages') ?? '消息',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_outline),
              activeIcon: const Icon(Icons.people),
              label: l10n?.t('chat.contacts') ?? '联系人',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: l10n?.t('chat.settings') ?? '账户设置',
            ),
          ],
        ),
      ),
    );
  }
}
