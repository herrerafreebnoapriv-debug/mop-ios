/**
 * 聊天核心模块
 * 负责 Socket.io 连接、消息加载、用户信息等核心功能
 */

(function() {
    'use strict';

    // 全局状态（通过 window 暴露给其他模块）
    const state = {
        socket: null,
        currentUser: null,
        currentPage: 'messages',
        conversations: [],
        friends: [],
        currentChat: null, // {id: number, name: string, isRoom: boolean}
        chatMessages: [],
        API_BASE: '/api/v1',
        reconnectAttempts: 0,
        MAX_RECONNECT_ATTEMPTS: 5,
        reconnectTimeout: null
    };

    /**
     * 获取 Token（使用 AuthManager）
     */
    function getToken() {
        if (window.AuthManager) {
            return window.AuthManager.getAccessToken();
        }
        return localStorage.getItem('access_token');
    }

    /**
     * 加载用户信息（优先从缓存读取，然后从服务器更新）
     */
    async function loadUserInfo() {
        try {
            // 先尝试从缓存读取
            if (window.AuthManager) {
                const cachedUser = window.AuthManager.getUserInfo();
                if (cachedUser) {
                    state.currentUser = cachedUser;
                    updateUserInfoUI(cachedUser);
                }
            }
            
            // 使用 AuthManager 的 fetchWithAuth 确保 token 有效
            let response;
            if (window.AuthManager) {
                response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/auth/me`);
            } else {
                const token = getToken();
                response = await fetch(`${state.API_BASE}/auth/me`, {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });
            }
            
            if (!response.ok) {
                if (response.status === 401) {
                    // Token 无效，跳转到登录页
                    if (window.AuthManager) {
                        window.AuthManager.clearTokens();
                    }
                    window.location.href = '/login';
                    return;
                }
                throw new Error('获取用户信息失败');
            }
            
            state.currentUser = await response.json();
            
            // 保存用户信息到缓存
            if (window.AuthManager) {
                window.AuthManager.saveUserInfo(state.currentUser);
            }
            
            // 更新 UI
            updateUserInfoUI(state.currentUser);
            
            return state.currentUser;
        } catch (error) {
            console.error('加载用户信息失败:', error);
            alert('加载用户信息失败，请重新登录');
            window.location.href = '/login';
            throw error;
        }
    }
    
    /**
     * 更新用户信息 UI
     */
    function updateUserInfoUI(user) {
        const usernameEl = document.getElementById('settings-username');
        const phoneEl = document.getElementById('settings-phone');
        const nicknameEl = document.getElementById('settings-nickname');
        const languageEl = document.getElementById('settings-language');
        
        if (usernameEl) usernameEl.textContent = user.username || '未设置';
        if (phoneEl) phoneEl.textContent = user.phone || '未设置';
        if (nicknameEl) nicknameEl.textContent = user.nickname || '未设置';
        if (languageEl) languageEl.textContent = user.language || 'zh_CN';
    }

    /**
     * 连接 Socket.io
     */
    function connectSocket() {
        if (typeof io !== 'function') {
            console.error('Socket.io 未加载（io is not defined），请检查网络或 CDN');
            console.error('请确保 Socket.io 脚本在 chat-core.js 之前加载');
            return;
        }
        
        const token = getToken();
        if (!token) {
            console.error('无法连接 Socket.io：缺少 token');
            return;
        }
        
        
        // 如果已有连接，先断开
        if (state.socket) {
            state.socket.disconnect();
            state.socket = null;
        }
        
        // 确保使用最新的 token
        const currentToken = getToken();
        if (!currentToken) {
            console.error('无法连接 Socket.io：缺少 token');
            if (window.AuthManager) {
                window.AuthManager.clearTokens();
            }
            window.location.href = '/login';
            return;
        }
        
        state.socket = io('/', {
            auth: { token: currentToken },
            transports: ['websocket', 'polling'],
            reconnection: true,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 10000, // 增加最大重连延迟
            reconnectionAttempts: Infinity, // 无限重连（由前端逻辑控制）
            timeout: 30000, // 增加连接超时时间
            forceNew: false, // 复用连接
            upgrade: true, // 允许升级到 WebSocket
            rememberUpgrade: true // 记住升级选择
        });
        
        state.socket.on('connect', () => {
            state.reconnectAttempts = 0;
            state.connectionStatus = 'connected';
            updateConnectionStatusUI('connected');
            
            if (state.reconnectTimeout) {
                clearTimeout(state.reconnectTimeout);
                state.reconnectTimeout = null;
            }
            
            // 启动客户端心跳
            startClientHeartbeat();
            
            // 连接成功后立即发送一次心跳
            if (state.socket && state.socket.connected) {
                state.socket.emit('ping', { timestamp: new Date().toISOString() });
                state.lastHeartbeatTime = Date.now();
            }
        });
        
        state.socket.on('connected', (data) => {
            state.connectionStatus = 'connected';
            updateConnectionStatusUI('connected');
        });
        
        // 监听 pong 响应
        state.socket.on('pong', (data) => {
            state.lastHeartbeatTime = Date.now();
        });
        
        state.socket.on('disconnect', (reason) => {
            state.connectionStatus = 'disconnected';
            updateConnectionStatusUI('disconnected', reason);
            stopClientHeartbeat();
            
            if (reason === 'io server disconnect') {
                // 服务器主动断开，可能是认证失败或服务器重启
                // 等待一段时间后重连
                state.reconnectTimeout = setTimeout(() => {
                    connectSocket();
                }, 3000);
            } else if (reason === 'io client disconnect') {
                // 客户端主动断开，不自动重连
            } else {
                // 网络错误或其他原因，使用指数退避重连
                if (state.reconnectAttempts < state.MAX_RECONNECT_ATTEMPTS) {
                    state.reconnectAttempts++;
                    // 指数退避：1s, 2s, 4s, 8s, 最大10s
                    const delay = Math.min(1000 * Math.pow(2, state.reconnectAttempts - 1), 10000);
                    state.connectionStatus = 'connecting';
                    updateConnectionStatusUI('connecting', `正在重连 (${state.reconnectAttempts}/${state.MAX_RECONNECT_ATTEMPTS})...`);
                    state.reconnectTimeout = setTimeout(() => {
                        connectSocket();
                    }, delay);
                } else {
                    console.error('达到最大重连次数，停止重连');
                    updateConnectionStatusUI('disconnected', '连接失败，请刷新页面');
                }
            }
        });
        
        state.socket.on('connect_error', (error) => {
            console.error('✗ Socket.io 连接错误:', error);
            state.connectionStatus = 'disconnected';
            updateConnectionStatusUI('disconnected', '连接失败: ' + (error.message || '未知错误'));
        });
        
        state.socket.on('reconnect', (attemptNumber) => {
            state.reconnectAttempts = 0;
        });
        
        state.socket.on('reconnect_attempt', (attemptNumber) => {
            state.connectionStatus = 'connecting';
            updateConnectionStatusUI('connecting', `重连中 (${attemptNumber})...`);
        });
        
        state.socket.on('reconnect_error', (error) => {
            console.error('✗ Socket.io 重连错误:', error);
            state.connectionStatus = 'connecting';
            updateConnectionStatusUI('connecting', '重连失败，继续尝试...');
        });
        
        state.socket.on('reconnect_failed', () => {
            console.error('✗ Socket.io 重连失败，已达到最大尝试次数');
            state.connectionStatus = 'disconnected';
            updateConnectionStatusUI('disconnected', '重连失败，请刷新页面');
            // 即使 Socket.io 内置重连失败，我们也继续尝试
            if (state.reconnectAttempts < state.MAX_RECONNECT_ATTEMPTS) {
                const delay = 10000; // 10秒后再次尝试
                state.reconnectTimeout = setTimeout(() => {
                    connectSocket();
                }, delay);
            }
        });
        
        // 消息事件（由 chat-messages.js 处理）
        state.socket.on('message', (data) => {
            if (window.ChatMessages && window.ChatMessages.handleNewMessage) {
                window.ChatMessages.handleNewMessage(data);
            } else {
                console.error('ChatMessages.handleNewMessage 未找到，消息无法处理');
            }
        });
        
        state.socket.on('notification', (data) => {
            if (data.type === 'friend_request') {
                // 显示好友请求通知
                if (window.ChatFriends && window.ChatFriends.showFriendRequestNotification) {
                    window.ChatFriends.showFriendRequestNotification(data);
                }
                // 刷新好友列表（包括待处理请求）
                if (window.ChatFriends && window.ChatFriends.loadFriends) {
                    window.ChatFriends.loadFriends();
                } else {
                    console.error('ChatFriends.loadFriends 未找到');
                }
            }
        });
        
        state.socket.on('call_invitation', (data) => {
            if (window.ChatCalls && window.ChatCalls.showInvitation) {
                window.ChatCalls.showInvitation(data);
            } else {
                console.error('ChatCalls.showInvitation 未找到');
            }
        });
        
        state.socket.on('message_read', (data) => {
            if (window.ChatMessages && window.ChatMessages.updateReadStatus) {
                window.ChatMessages.updateReadStatus(data.message_id, data.read_at);
            }
        });
        
        state.socket.on('message_read_confirmed', (data) => {
            if (window.ChatMessages && window.ChatMessages.updateReadStatus) {
                data.message_ids?.forEach(msgId => {
                    window.ChatMessages.updateReadStatus(msgId, data.timestamp);
                });
            }
        });
    }

    /**
     * 确保 Socket 已连接；若未连接则尝试重连并等待（供发起通话等场景使用）
     * @param {number} timeoutMs 等待连接的最长时间（毫秒）
     * @returns {Promise<void>} 连接成功 resolve；超时或无法连接 reject
     */
    function tryEnsureSocketConnected(timeoutMs) {
        timeoutMs = timeoutMs || 5000;
        if (state.socket && state.socket.connected) {
            return Promise.resolve();
        }
        return new Promise((resolve, reject) => {
            let listener = null;
            const done = (ok) => {
                clearTimeout(tid);
                if (listener && state.socket) {
                    try { state.socket.off('connect', listener); } catch (e) {}
                }
                if (ok) resolve(); else reject(new Error('Socket 连接超时'));
            };
            const tid = setTimeout(() => done(false), timeoutMs);
            connectSocket();
            if (!state.socket) {
                done(false);
                return;
            }
            listener = () => done(true);
            state.socket.once('connect', listener);
        });
    }

    /**
     * 加载消息列表（会话列表）- 支持本地缓存
     */
    async function loadMessages() {
        try {
            // 先尝试从本地缓存加载
            if (window.MessageStorage) {
                try {
                    const cachedConversations = await window.MessageStorage.getConversations();
                    if (cachedConversations && cachedConversations.length > 0) {
                        state.conversations = cachedConversations;
                        // 先显示缓存的数据
                        if (window.ChatMessages && window.ChatMessages.renderMessages) {
                            window.ChatMessages.renderMessages();
                        }
                    }
                } catch (e) {
                    console.warn('从缓存加载会话列表失败:', e);
                }
            }
            
            // 从服务器获取最新数据
            let response;
            if (window.AuthManager) {
                response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/chat/conversations`);
            } else {
                const token = getToken();
                response = await fetch(`${state.API_BASE}/chat/conversations`, {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });
            }
            
            if (!response.ok) {
                throw new Error('加载消息列表失败');
            }
            
            const data = await response.json();
            state.conversations = data.conversations || [];
            
            // 保存到本地缓存
            if (window.MessageStorage && state.conversations.length > 0) {
                try {
                    await window.MessageStorage.saveConversations(state.conversations);
                } catch (e) {
                    console.warn('保存会话列表到缓存失败:', e);
                }
            }
            
            // 确保消息列表组件已加载
            if (window.ChatMessages && window.ChatMessages.renderMessages) {
                window.ChatMessages.renderMessages();
            } else {
                console.error('ChatMessages.renderMessages 未找到，请检查脚本加载顺序');
            }
        } catch (error) {
            console.error('加载消息失败:', error);
            const list = document.getElementById('message-list');
            if (list) list.innerHTML = '<div class="empty-state"><div>加载失败</div></div>';
        }
    }

    /**
     * 加载聊天消息 - 支持本地缓存和增量同步
     */
    async function loadChatMessages() {
        if (!state.currentChat) return;
        
        try {
            // 先尝试从本地缓存加载
            if (window.MessageStorage) {
                try {
                    const cachedMessages = await window.MessageStorage.getMessages(
                        state.currentChat.isRoom ? null : state.currentChat.id,
                        state.currentChat.isRoom ? state.currentChat.id : null,
                        50
                    );
                    if (cachedMessages && cachedMessages.length > 0) {
                        state.chatMessages = cachedMessages;
                        // 先显示缓存的消息
                        if (window.ChatMessages && window.ChatMessages.renderChatMessages) {
                            window.ChatMessages.renderChatMessages();
                        }
                    }
                } catch (e) {
                    console.warn('从缓存加载消息失败:', e);
                }
            }
            
            // 从服务器获取最新数据
            const params = new URLSearchParams({
                page: '1',
                limit: '50'
            });
            
            if (state.currentChat.isRoom) {
                params.append('room_id', state.currentChat.id);
            } else {
                params.append('user_id', state.currentChat.id);
            }
            
            let response;
            if (window.AuthManager) {
                response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/chat/messages?${params}`);
            } else {
                const token = getToken();
                response = await fetch(`${state.API_BASE}/chat/messages?${params}`, {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });
            }
            
            if (!response.ok) {
                throw new Error('加载消息失败');
            }
            
            const data = await response.json();
            state.chatMessages = (data.messages || []).reverse();
            
            // 保存到本地缓存
            if (window.MessageStorage && state.chatMessages.length > 0) {
                try {
                    await window.MessageStorage.saveMessages(state.chatMessages);
                } catch (e) {
                    console.warn('保存消息到缓存失败:', e);
                }
            }
            
            if (window.ChatMessages && window.ChatMessages.renderChatMessages) {
                window.ChatMessages.renderChatMessages();
            } else {
                console.error('ChatMessages.renderChatMessages 未找到');
            }
            
            // 标记消息为已读
            if (window.ChatMessages && window.ChatMessages.markChatMessagesAsRead) {
                window.ChatMessages.markChatMessagesAsRead();
            } else {
                console.error('ChatMessages.markChatMessagesAsRead 未找到');
            }
        } catch (error) {
            console.error('加载聊天消息失败:', error);
            const container = document.getElementById('chat-messages-container');
            if (container) {
                container.innerHTML = '<div class="empty-state"><div>加载消息失败</div></div>';
            }
        }
    }

    /**
     * 初始化
     */
    async function init() {
        // 初始化存储模块
        if (window.MessageStorage) {
            try {
                await window.MessageStorage.init();
            } catch (e) {
                console.warn('IndexedDB 初始化失败，将使用在线模式:', e);
            }
        }
        
        // 验证并刷新 token
        if (window.AuthManager) {
            const isValid = await window.AuthManager.validateToken();
            if (!isValid) {
                window.location.href = '/login';
                return;
            }
            // 启动自动刷新
            window.AuthManager.startAutoRefresh();
        } else {
            const token = getToken();
            if (!token) {
                window.location.href = '/login';
                return;
            }
        }
        
        // 初始化 UI（必须先初始化，设置页面状态）
        if (window.ChatUI) {
            if (window.ChatUI.init) {
                window.ChatUI.init();
            }
            if (window.ChatUI.switchPage) {
                window.ChatUI.switchPage('messages');
            } else {
                console.error('ChatUI.switchPage 未找到，请检查脚本加载顺序');
                return;
            }
        } else {
            console.error('ChatUI 未找到，请检查脚本加载顺序');
            return;
        }
        
        // 加载用户信息（必须先加载，其他功能依赖用户信息）
        await loadUserInfo();
        
        // 连接 Socket.io
        state.connectionStatus = 'connecting';
        updateConnectionStatusUI('connecting', '正在连接...');
        connectSocket();
        
        // 监听 token 刷新事件，更新 Socket.io 连接
        if (window.AuthManager) {
            window.addEventListener('tokenRefreshed', (event) => {
                // Token 刷新后，重新连接 Socket.io（使用新 token）
                if (state.socket && state.socket.connected) {
                    // 断开旧连接
                    state.socket.disconnect();
                }
                // 重新连接
                connectSocket();
            });
            
            window.addEventListener('tokenRefreshFailed', () => {
                // Token 刷新失败，跳转到登录页
                window.location.href = '/login';
            });
        }
        
        // 监听页面可见性变化，保持连接
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) {
                // 页面变为可见时，检查连接状态和 token
                if (window.AuthManager) {
                    window.AuthManager.checkAndRefreshToken();
                }
                
                if (!state.socket || !state.socket.connected) {
                    state.connectionStatus = 'connecting';
                    updateConnectionStatusUI('connecting', '页面恢复，重新连接...');
                    connectSocket();
                } else {
                    // 连接正常，发送一次心跳确认
                    if (state.socket && state.socket.connected) {
                        state.socket.emit('ping', { timestamp: new Date().toISOString() });
                    }
                }
            }
        });
        
        // 监听网络状态变化
        window.addEventListener('online', () => {
            // 网络恢复时，检查 token
            if (window.AuthManager) {
                window.AuthManager.checkAndRefreshToken();
            }
            
            if (!state.socket || !state.socket.connected) {
                state.connectionStatus = 'connecting';
                updateConnectionStatusUI('connecting', '网络恢复，重新连接...');
                connectSocket();
            }
        });
        
        window.addEventListener('offline', () => {
            state.connectionStatus = 'disconnected';
            updateConnectionStatusUI('disconnected', '网络已断开');
            stopClientHeartbeat();
        });
        
        // 加载初始数据（消息列表）
        await loadMessages();
        
        // 加载好友列表
        if (window.ChatFriends && window.ChatFriends.loadFriends) {
            await window.ChatFriends.loadFriends();
        } else {
            console.error('ChatFriends.loadFriends 未找到，请检查脚本加载顺序');
        }
    }

    /**
     * 启动客户端心跳（每25秒发送一次）
     */
    function startClientHeartbeat() {
        stopClientHeartbeat(); // 先清除旧的定时器
        
        if (!state.socket || !state.socket.connected) {
            return;
        }
        
        state.heartbeatInterval = setInterval(() => {
            if (state.socket && state.socket.connected) {
                state.socket.emit('ping', {
                    timestamp: new Date().toISOString()
                });
                state.lastHeartbeatTime = Date.now();
            } else {
                stopClientHeartbeat();
            }
        }, 25000); // 25秒发送一次心跳（小于服务器30秒间隔）
    }
    
    /**
     * 停止客户端心跳
     */
    function stopClientHeartbeat() {
        if (state.heartbeatInterval) {
            clearInterval(state.heartbeatInterval);
            state.heartbeatInterval = null;
        }
    }
    
    /**
     * 更新连接状态UI
     */
    function updateConnectionStatusUI(status, message) {
        // 查找或创建连接状态指示器
        let statusIndicator = document.getElementById('socket-connection-status');
        if (!statusIndicator) {
            statusIndicator = document.createElement('div');
            statusIndicator.id = 'socket-connection-status';
            statusIndicator.style.cssText = 'position: fixed; top: 10px; right: 10px; padding: 8px 16px; border-radius: 20px; font-size: 12px; z-index: 10000; transition: all 0.3s; cursor: pointer;';
            statusIndicator.onclick = () => {
                if (status === 'disconnected' || status === 'connecting') {
                    connectSocket();
                }
            };
            document.body.appendChild(statusIndicator);
        }
        
        const statusText = message || '';
        switch (status) {
            case 'connected':
                statusIndicator.style.background = '#4caf50';
                statusIndicator.style.color = 'white';
                statusIndicator.textContent = '🟢 已连接' + (statusText ? ` - ${statusText}` : '');
                statusIndicator.style.display = 'none'; // 连接正常时隐藏
                break;
            case 'connecting':
                statusIndicator.style.background = '#ff9800';
                statusIndicator.style.color = 'white';
                statusIndicator.textContent = '🟡 ' + (statusText || '连接中...');
                statusIndicator.style.display = 'block';
                break;
            case 'disconnected':
                statusIndicator.style.background = '#f44336';
                statusIndicator.style.color = 'white';
                statusIndicator.textContent = '🔴 未连接' + (statusText ? ` - ${statusText}` : '');
                statusIndicator.style.display = 'block';
                break;
        }
    }

    // 导出 API
    window.ChatCore = {
        // 状态访问
        getState: () => state,
        getSocket: () => state.socket,
        getCurrentUser: () => state.currentUser,
        getCurrentChat: () => state.currentChat,
        setCurrentChat: (chat) => { state.currentChat = chat; },
        getChatMessages: () => state.chatMessages,
        setChatMessages: (messages) => { state.chatMessages = messages; },
        getConversations: () => state.conversations,
        setConversations: (conversations) => { state.conversations = conversations; },
        getFriends: () => state.friends,
        setFriends: (friends) => { state.friends = friends; },
        getAPIBase: () => state.API_BASE,
        getConnectionStatus: () => state.connectionStatus,
        
        // 功能函数
        getToken: getToken,
        loadUserInfo: loadUserInfo,
        connectSocket: connectSocket,
        tryEnsureSocketConnected: tryEnsureSocketConnected,
        loadMessages: loadMessages,
        loadChatMessages: loadChatMessages,
        updateConnectionStatusUI: updateConnectionStatusUI,
        init: init
    };

})();
