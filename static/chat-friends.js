/**
 * 好友组件
 * 负责好友列表、搜索、添加好友等功能
 */

(function() {
    'use strict';

    const ChatFriends = {
        friends: [],
        pendingRequests: [],

        /**
         * 显示好友请求通知
         */
        showFriendRequestNotification(notificationData) {
            const title = notificationData.title || '好友请求';
            const content = notificationData.content || '有人想添加您为好友';
            const relatedUserId = notificationData.related_user_id;
            
            // 创建通知弹窗
            const notification = document.createElement('div');
            notification.className = 'friend-request-notification';
            notification.style.cssText = `
                position: fixed;
                top: 80px;
                right: 20px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 15px 20px;
                border-radius: 12px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.15);
                z-index: 10000;
                max-width: 300px;
                animation: slideInRight 0.3s ease-out;
            `;
            
            notification.innerHTML = `
                <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 10px;">
                    <div style="font-size: 24px;">👫</div>
                    <div style="flex: 1;">
                        <div style="font-weight: 600; font-size: 16px; margin-bottom: 4px;">${this.escapeHtml(title)}</div>
                        <div style="font-size: 14px; opacity: 0.9;">${this.escapeHtml(content)}</div>
                    </div>
                    <button onclick="this.parentElement.parentElement.remove()" style="background: none; border: none; color: white; font-size: 20px; cursor: pointer; padding: 0; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center;">×</button>
                </div>
                <div style="display: flex; gap: 8px; margin-top: 10px;">
                    <button onclick="ChatFriends.viewPendingRequests(); this.closest('.friend-request-notification').remove();" 
                            style="flex: 1; padding: 8px; background: rgba(255,255,255,0.2); border: 1px solid rgba(255,255,255,0.3); border-radius: 6px; color: white; cursor: pointer; font-size: 14px;">
                        查看请求
                    </button>
                    <button onclick="this.closest('.friend-request-notification').remove();" 
                            style="flex: 1; padding: 8px; background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.2); border-radius: 6px; color: white; cursor: pointer; font-size: 14px;">
                        稍后
                    </button>
                </div>
            `;
            
            document.body.appendChild(notification);
            
            // 5秒后自动消失
            setTimeout(() => {
                if (notification.parentElement) {
                    notification.style.animation = 'slideOutRight 0.3s ease-out';
                    setTimeout(() => notification.remove(), 300);
                }
            }, 5000);
        },

        /**
         * 查看待处理的好友请求
         */
        async viewPendingRequests() {
            // 切换到联系人页面
            if (window.ChatUI && window.ChatUI.switchPage) {
                window.ChatUI.switchPage('contacts');
            }
            
            // 加载待处理请求
            await this.loadPendingRequests();
        },

        /**
         * 加载待处理的好友请求
         */
        async loadPendingRequests() {
            try {
                const state = window.ChatCore.getState();
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/friends/list?status_filter=pending`);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) return;
                    response = await fetch(`${state.API_BASE}/friends/list?status_filter=pending`, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) throw new Error('加载待处理请求失败');
                const data = await response.json();
                this.pendingRequests = data.friends || [];
                this.renderPendingRequests();
            } catch (error) {
                console.error('加载待处理请求失败:', error);
            }
        },

        /**
         * 渲染待处理的好友请求
         */
        renderPendingRequests() {
            const list = document.getElementById('friend-list');
            if (!list) return;
            
            if (!this.pendingRequests.length) {
                // 如果没有待处理请求，显示已接受的好友列表
                this.loadFriends();
                return;
            }
            
            list.innerHTML = `
                <div style="padding: 10px; background: #fff3cd; border-radius: 8px; margin-bottom: 15px; color: #856404;">
                    <strong>待处理的好友请求 (${this.pendingRequests.length})</strong>
                </div>
                ${this.pendingRequests.map(request => {
                    const name = request.nickname || request.username || `用户${request.user_id}`;
                    const firstChar = name.charAt(0).toUpperCase();
                    
                    return `
                        <li class="friend-item" style="background: #fff3cd; border-left: 4px solid #ffc107;">
                            <div class="friend-info">
                                <div class="friend-avatar">${this.escapeHtml(firstChar)}</div>
                                <div class="friend-details">
                                    <div class="friend-name">${this.escapeHtml(name)}</div>
                                    <div class="friend-status" style="color: #856404;">待您确认</div>
                                </div>
                            </div>
                            <div class="friend-actions" style="display: flex; gap: 5px;">
                                <button class="btn-small btn-primary" onclick="ChatFriends.acceptFriendRequest(${request.user_id})" style="background: #28a745; color: white; border: none;">接受</button>
                                <button class="btn-small" onclick="ChatFriends.rejectFriendRequest(${request.user_id})" style="background: #dc3545; color: white; border: none;">拒绝</button>
                            </div>
                        </li>
                    `;
                }).join('')}
                <div style="padding: 10px; text-align: center;">
                    <button onclick="ChatFriends.loadFriends()" style="padding: 8px 16px; background: #667eea; color: white; border: none; border-radius: 6px; cursor: pointer;">
                        查看已添加的好友
                    </button>
                </div>
            `;
        },

        /**
         * 接受好友请求
         */
        async acceptFriendRequest(friendId) {
            const base = window.ChatCore.getAPIBase();
            const opts = {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ friend_id: friendId, status: 'accepted' })
            };
            try {
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${base}/friends/update`, opts);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(`${base}/friends/update`, {
                        ...opts,
                        headers: { ...opts.headers, 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) {
                    const err = await response.json().catch(() => ({}));
                    throw new Error(err.detail || '接受请求失败');
                }
                const result = await response.json();
                alert(result.message || '已接受好友请求');
                await this.loadFriends();
            } catch (error) {
                console.error('接受好友请求失败:', error);
                alert(error.message || '接受请求失败，请重试');
            }
        },

        /**
         * 拒绝好友请求
         */
        async rejectFriendRequest(friendId) {
            if (!confirm('确定要拒绝此好友请求吗？')) return;
            const base = window.ChatCore.getAPIBase();
            const opts = {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ friend_id: friendId, status: 'blocked' })
            };
            try {
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${base}/friends/update`, opts);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(`${base}/friends/update`, {
                        ...opts,
                        headers: { ...opts.headers, 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) {
                    const err = await response.json().catch(() => ({}));
                    throw new Error(err.detail || '拒绝请求失败');
                }
                await this.loadPendingRequests();
            } catch (error) {
                console.error('拒绝好友请求失败:', error);
                alert(error.message || '拒绝请求失败，请重试');
            }
        },

        async loadFriends() {
            try {
                const state = window.ChatCore.getState();
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/friends/list?status_filter=accepted`);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) return;
                    response = await fetch(`${state.API_BASE}/friends/list?status_filter=accepted`, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) throw new Error('加载好友列表失败');
                const data = await response.json();
                this.friends = data.friends || [];
                window.ChatCore.setFriends(this.friends);
                this.renderFriends();
            } catch (error) {
                console.error('加载好友列表失败:', error);
                const list = document.getElementById('friend-list');
                if (list) list.innerHTML = '<div class="empty-state"><div>加载失败，请重试</div></div>';
            }
        },

        renderFriends() {
            const list = document.getElementById('friend-list');
            if (!list) return;
            
            if (!this.friends.length) {
                list.innerHTML = '<div class="empty-state"><div class="empty-icon">👫</div><div>暂无好友</div></div>';
                return;
            }
            
            list.innerHTML = this.friends.map(friend => {
                const name = friend.note || friend.nickname || friend.username || `用户${friend.user_id}`;
                const firstChar = name.charAt(0).toUpperCase();
                const isOnline = friend.is_online || false;
                
                return `
                    <li class="friend-item">
                        <div class="friend-info">
                            <div class="friend-avatar">${this.escapeHtml(firstChar)}</div>
                            <div class="friend-details">
                                <div class="friend-name">${this.escapeHtml(name)}</div>
                                <div class="friend-status">
                                    <span class="status-dot ${isOnline ? 'online' : 'offline'}"></span>
                                    ${isOnline ? '在线' : '离线'}
                                </div>
                            </div>
                        </div>
                        <div class="friend-actions">
                            <button class="btn-small btn-chat" onclick="ChatMessages.openChat(${friend.user_id}, '${this.escapeHtml(name)}', false)">聊天</button>
                        </div>
                    </li>
                `;
            }).join('');
        },

        searchFriends(keyword) {
            if (!keyword) {
                this.renderFriends();
                return;
            }
            
            const filtered = this.friends.filter(friend => {
                const name = (friend.note || friend.nickname || friend.username || '').toLowerCase();
                return name.includes(keyword.toLowerCase());
            });
            
            const list = document.getElementById('friend-list');
            if (filtered.length === 0) {
                list.innerHTML = '<div class="empty-state"><div>未找到匹配的好友</div></div>';
                return;
            }
            
            list.innerHTML = filtered.map(friend => {
                const name = friend.note || friend.nickname || friend.username || `用户${friend.user_id}`;
                const firstChar = name.charAt(0).toUpperCase();
                const isOnline = friend.is_online || false;
                
                return `
                    <li class="friend-item">
                        <div class="friend-info">
                            <div class="friend-avatar">${this.escapeHtml(firstChar)}</div>
                            <div class="friend-details">
                                <div class="friend-name">${this.escapeHtml(name)}</div>
                                <div class="friend-status">
                                    <span class="status-dot ${isOnline ? 'online' : 'offline'}"></span>
                                    ${isOnline ? '在线' : '离线'}
                                </div>
                            </div>
                        </div>
                        <div class="friend-actions">
                            <button class="btn-small btn-chat" onclick="ChatMessages.openChat(${friend.user_id}, '${this.escapeHtml(name)}', false)">聊天</button>
                        </div>
                    </li>
                `;
            }).join('');
        },

        showAddModal() {
            const modal = document.getElementById('add-friend-modal');
            const input = document.getElementById('friend-search-input');
            if (modal) modal.classList.add('show');
            if (input) {
                input.focus();
                this.initFriendSearch();
            }
        },

        closeAddModal() {
            const modal = document.getElementById('add-friend-modal');
            const input = document.getElementById('friend-search-input');
            const results = document.getElementById('search-results');
            if (modal) modal.classList.remove('show');
            if (input) input.value = '';
            if (results) results.innerHTML = '<div class="empty-search">输入手机号或用户名搜索</div>';
        },

        _friendSearchInit: false,
        initFriendSearch() {
            const input = document.getElementById('friend-search-input');
            if (!input) return;
            if (this._friendSearchInit) return;
            this._friendSearchInit = true;
            
            let searchTimeout = null;
            input.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') this.closeAddModal();
            });
            input.addEventListener('input', (e) => {
                const keyword = e.target.value.trim();
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => {
                    const results = document.getElementById('search-results');
                    if (keyword.length < 1) {
                        if (results) results.innerHTML = '<div class="empty-search">输入手机号或用户名搜索</div>';
                        return;
                    }
                    this.searchUsers(keyword);
                }, 500);
            });
        },

        async searchUsers(keyword) {
            const resultsContainer = document.getElementById('search-results');
            if (!resultsContainer) return;
            const base = window.ChatCore.getAPIBase();
            const url = `${base}/friends/search?keyword=${encodeURIComponent(keyword)}`;
            try {
                resultsContainer.innerHTML = '<div class="empty-search">搜索中...</div>';
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(url);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(url, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) throw new Error('搜索用户失败');
                const users = await response.json();
                this.renderSearchResults(Array.isArray(users) ? users : []);
            } catch (error) {
                console.error('搜索用户失败:', error);
                resultsContainer.innerHTML = `<div class="empty-search" style="color: #e74c3c;">搜索失败：${this.escapeHtml(error.message || '请重试')}</div>`;
            }
        },

        renderSearchResults(users) {
            const container = document.getElementById('search-results');
            if (!container) return;
            
            if (users.length === 0) {
                container.innerHTML = '<div class="empty-search">未找到匹配的用户</div>';
                return;
            }
            
            container.innerHTML = users.map(user => {
                let actionBtn = '';
                if (user.status === 'none') {
                    actionBtn = `<button class="btn-small btn-add" onclick="ChatFriends.addFriend(${user.user_id})">添加</button>`;
                } else if (user.status === 'pending') {
                    actionBtn = `<button class="btn-small btn-pending" disabled>待确认</button>`;
                } else if (user.status === 'accepted') {
                    actionBtn = `<button class="btn-small btn-accepted" disabled>已是好友</button>`;
                } else if (user.status === 'blocked') {
                    actionBtn = `<button class="btn-small" disabled>已屏蔽</button>`;
                }
                
                return `
                    <div class="user-item">
                        <div class="user-info">
                            <div class="user-name">
                                <span class="user-status ${user.is_online ? 'online' : 'offline'}"></span>
                                ${this.escapeHtml(user.nickname || user.username || `用户${user.user_id}`)}
                            </div>
                            <div class="user-meta">
                                ${user.username ? `@${this.escapeHtml(user.username)}` : ''}
                                ${user.is_online ? '<span style="color: #28a745;">在线</span>' : '<span style="color: #999;">离线</span>'}
                            </div>
                        </div>
                        <div class="user-actions">
                            ${actionBtn}
                        </div>
                    </div>
                `;
            }).join('');
        },

        async addFriend(friendId) {
            const base = window.ChatCore.getAPIBase();
            const opts = {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ friend_id: friendId })
            };
            try {
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${base}/friends/add`, opts);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(`${base}/friends/add`, {
                        ...opts,
                        headers: { ...opts.headers, 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) {
                    const err = await response.json().catch(() => ({}));
                    throw new Error(err.detail || '添加好友失败');
                }
                const result = await response.json();
                alert(result.message || '好友请求已发送');
                const keyword = document.getElementById('friend-search-input')?.value.trim();
                if (keyword) await this.searchUsers(keyword);
                await this.loadFriends();
            } catch (error) {
                console.error('添加好友失败:', error);
                alert(error.message || '添加好友失败，请重试');
            }
        },

        escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
    };

    window.ChatFriends = ChatFriends;
    window.showAddFriendModal = () => ChatFriends.showAddModal();
    window.closeAddFriendModal = () => ChatFriends.closeAddModal();
    window.addFriend = (id) => ChatFriends.addFriend(id);
    
})();
