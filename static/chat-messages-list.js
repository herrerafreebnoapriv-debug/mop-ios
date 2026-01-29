/**
 * 消息列表组件
 * 负责会话列表的加载、渲染和搜索
 */

(function() {
    'use strict';

    const ChatMessagesList = {
        /**
         * 加载消息列表
         */
        async loadMessages() {
            try {
                const state = window.ChatCore.getState();
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/chat/conversations`);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(`${state.API_BASE}/chat/conversations`, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) throw new Error('加载消息列表失败');
                const data = await response.json();
                window.ChatCore.setConversations(data.conversations || []);
                this.renderMessages();
            } catch (error) {
                console.error('加载消息失败:', error);
                const list = document.getElementById('message-list');
                if (list) list.innerHTML = '<div class="empty-state"><div>加载失败，请重试</div></div>';
            }
        },

        /**
         * 渲染消息列表
         */
        renderMessages() {
            const list = document.getElementById('message-list');
            if (!list) return;
            
            const conversations = window.ChatCore.getConversations();
            if (!conversations.length) {
                list.innerHTML = '<div class="empty-state"><div class="empty-icon">💬</div><div>暂无消息</div></div>';
                return;
            }
            
            list.innerHTML = conversations.map(conv => {
                const name = conv.room_name || conv.user_nickname || `用户${conv.user_id || conv.room_id}`;
                const preview = conv.last_message || '暂无消息';
                const time = this.formatTime(conv.last_message_time);
                const unreadCount = conv.unread_count || 0;
                
                return `
                    <li class="message-item" onclick="ChatMessages.openChat(${conv.room_id || conv.user_id}, '${this.escapeHtml(name)}', ${conv.room_id ? 'true' : 'false'})">
                        <div class="message-info">
                            <div class="message-name">${this.escapeHtml(name)}</div>
                            <div class="message-preview">${this.escapeHtml(preview)}</div>
                        </div>
                        <div class="message-meta">
                            ${unreadCount > 0 ? `<div class="unread-badge">${unreadCount}</div>` : ''}
                            <div class="message-time">${time}</div>
                        </div>
                    </li>
                `;
            }).join('');
        },

        /**
         * 搜索消息
         */
        searchMessages(keyword) {
            if (!keyword) {
                this.renderMessages();
                return;
            }
            
            const conversations = window.ChatCore.getConversations();
            const filtered = conversations.filter(conv => {
                const name = (conv.room_name || conv.user_nickname || '').toLowerCase();
                const preview = (conv.last_message || '').toLowerCase();
                return name.includes(keyword.toLowerCase()) || preview.includes(keyword.toLowerCase());
            });
            
            const list = document.getElementById('message-list');
            if (filtered.length === 0) {
                list.innerHTML = '<div class="empty-state"><div>未找到匹配的消息</div></div>';
                return;
            }
            
            list.innerHTML = filtered.map(conv => {
                const name = conv.room_name || conv.user_nickname || `用户${conv.user_id || conv.room_id}`;
                const preview = conv.last_message || '暂无消息';
                const time = this.formatTime(conv.last_message_time);
                const unreadCount = conv.unread_count || 0;
                
                return `
                    <li class="message-item" onclick="ChatMessages.openChat(${conv.room_id || conv.user_id}, '${this.escapeHtml(name)}', ${conv.room_id ? 'true' : 'false'})">
                        <div class="message-info">
                            <div class="message-name">${this.escapeHtml(name)}</div>
                            <div class="message-preview">${this.escapeHtml(preview)}</div>
                        </div>
                        <div class="message-meta">
                            ${unreadCount > 0 ? `<div class="unread-badge">${unreadCount}</div>` : ''}
                            <div class="message-time">${time}</div>
                        </div>
                    </li>
                `;
            }).join('');
        },

        escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        },

        formatTime(timeStr) {
            if (!timeStr) return '';
            const date = new Date(timeStr);
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            const hours = String(date.getHours()).padStart(2, '0');
            const minutes = String(date.getMinutes()).padStart(2, '0');
            return `${year}/${month}/${day} ${hours}:${minutes}`;
        }
    };

    window.ChatMessagesList = ChatMessagesList;
})();
