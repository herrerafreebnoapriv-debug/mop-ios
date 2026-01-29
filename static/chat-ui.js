/**
 * 聊天 UI 组件
 * 负责页面切换、搜索、模态框等 UI 交互
 */

(function() {
    'use strict';

    const ChatUI = {
        currentPage: 'messages',

        /**
         * 切换页面
         */
        switchPage(page) {
            this.currentPage = page;
            
            // 隐藏所有页面
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            
            // 显示目标页面
            const targetPage = document.getElementById(`${page}-page`);
            if (targetPage) {
                targetPage.classList.add('active');
            }
            
            // 更新底部导航栏状态
            document.querySelectorAll('.nav-item').forEach(item => {
                item.classList.remove('active');
            });
            const activeNav = document.querySelector(`[onclick="ChatUI.switchPage('${page}')"]`);
            if (activeNav) {
                activeNav.classList.add('active');
            }
            
            // 更新标题
            const titles = {
                'messages': '💬 消息',
                'contacts': '👫 联系人',
                'settings': '⚙️ 账户设置'
            };
            const pageTitle = document.getElementById('page-title');
            if (pageTitle) {
                pageTitle.textContent = titles[page] || 'MOP';
            }
            
            // 显示/隐藏搜索和添加按钮
            const searchBtn = document.getElementById('search-btn');
            const addFriendBtn = document.getElementById('add-friend-btn');
            if (searchBtn && addFriendBtn) {
                if (page === 'messages' || page === 'contacts') {
                    searchBtn.style.display = 'block';
                    addFriendBtn.style.display = 'block';
                } else {
                    searchBtn.style.display = 'none';
                    addFriendBtn.style.display = 'none';
                }
            }
            
            // 页面特定逻辑
            if (page === 'messages') {
                if (window.ChatMessages && window.ChatMessages.loadMessages) {
                    window.ChatMessages.loadMessages();
                } else if (window.ChatMessagesList && window.ChatMessagesList.loadMessages) {
                    window.ChatMessagesList.loadMessages();
                } else {
                }
            } else if (page === 'contacts') {
                // 切换到联系人页面时，先检查是否有待处理的好友请求
                if (window.ChatFriends) {
                    if (window.ChatFriends.loadPendingRequests) {
                        window.ChatFriends.loadPendingRequests().then(() => {
                            // 如果没有待处理请求，加载已接受的好友列表
                            if (!window.ChatFriends.pendingRequests || window.ChatFriends.pendingRequests.length === 0) {
                                if (window.ChatFriends.loadFriends) {
                                    window.ChatFriends.loadFriends();
                                }
                            }
                        });
                    } else if (window.ChatFriends.loadFriends) {
                        window.ChatFriends.loadFriends();
                    }
                } else {
                }
            } else if (page === 'settings') {
                if (window.ChatSettings && window.ChatSettings.loadSettings) {
                    window.ChatSettings.loadSettings();
                } else {
                }
            }
        },

        /**
         * 切换搜索
         */
        toggleSearch() {
            const searchInput = document.getElementById('search-input');
            const searchBtn = document.getElementById('search-btn');
            
            if (searchInput && searchBtn) {
                if (searchInput.style.display === 'none' || !searchInput.classList.contains('active')) {
                    searchInput.style.display = 'block';
                    searchInput.classList.add('active');
                    searchInput.focus();
                    searchBtn.textContent = '✕';
                } else {
                    searchInput.style.display = 'none';
                    searchInput.classList.remove('active');
                    searchInput.value = '';
                    searchBtn.textContent = '🔍';
                    if (this.currentPage === 'messages') {
                        if (window.ChatMessages && window.ChatMessages.renderMessages) {
                            window.ChatMessages.renderMessages();
                        } else if (window.ChatMessagesList && window.ChatMessagesList.renderMessages) {
                            window.ChatMessagesList.renderMessages();
                        }
                    } else if (this.currentPage === 'contacts' && window.ChatFriends) {
                        window.ChatFriends.renderFriends();
                    }
                }
            }
        },

        _searchInit: false,
        /**
         * 初始化搜索（仅绑定一次，避免重复监听）
         */
        initSearch() {
            const searchInput = document.getElementById('search-input');
            if (!searchInput || this._searchInit) return;
            this._searchInit = true;
            
            let searchTimeout = null;
            searchInput.addEventListener('input', (e) => {
                clearTimeout(searchTimeout);
                const keyword = e.target.value.trim();
                searchTimeout = setTimeout(() => {
                    if (this.currentPage === 'messages') {
                        if (window.ChatMessages && window.ChatMessages.searchMessages) {
                            window.ChatMessages.searchMessages(keyword);
                        } else if (window.ChatMessagesList && window.ChatMessagesList.searchMessages) {
                            window.ChatMessagesList.searchMessages(keyword);
                        }
                    } else if (this.currentPage === 'contacts' && window.ChatFriends) {
                        window.ChatFriends.searchFriends(keyword);
                    }
                }, 300);
            });
        },

        /**
         * 初始化模态框
         */
        initModals() {
            // ESC 键关闭模态框（通过 .show class 判断是否打开）
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    const addFriend = document.getElementById('add-friend-modal');
                    const changePwd = document.getElementById('change-password-modal');
                    const callInv = document.getElementById('call-invitation-modal');
                    if (addFriend && addFriend.classList.contains('show') && window.ChatFriends) {
                        window.ChatFriends.closeAddModal();
                    } else if (changePwd && changePwd.classList.contains('show') && window.ChatSettings) {
                        window.ChatSettings.closeChangePasswordModal();
                    } else if (callInv && callInv.classList.contains('show') && window.ChatCalls) {
                        window.ChatCalls.rejectInvitation();
                    }
                }
            });
        },

        /**
         * 初始化
         */
        init() {
            this.initSearch();
            this.initModals();
            this.switchPage('messages');
            
            // 更新标题和按钮显示
            const pageTitle = document.getElementById('page-title');
            if (pageTitle) pageTitle.textContent = '💬 消息';
            
            const searchBtn = document.getElementById('search-btn');
            const addFriendBtn = document.getElementById('add-friend-btn');
            if (searchBtn && addFriendBtn) {
                searchBtn.style.display = 'block';
                addFriendBtn.style.display = 'block';
            }
        }
    };

    // 导出
    window.ChatUI = ChatUI;
    window.switchPage = (page) => ChatUI.switchPage(page);
    window.toggleSearch = () => ChatUI.toggleSearch();
    
    // 不在这里自动初始化，由 ChatCore.init() 调用
})();
