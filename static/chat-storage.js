/**
 * 消息存储模块（IndexedDB）
 * 负责消息的本地缓存、离线存储和增量同步
 */

(function() {
    'use strict';

    const MessageStorage = {
        DB_NAME: 'MOPChatDB',
        DB_VERSION: 1,
        STORE_MESSAGES: 'messages',
        STORE_CONVERSATIONS: 'conversations',
        STORE_SYNC_STATE: 'syncState',
        db: null,

        /**
         * 初始化数据库
         */
        async init() {
            return new Promise((resolve, reject) => {
                if (this.db) {
                    resolve(this.db);
                    return;
                }

                const request = indexedDB.open(this.DB_NAME, this.DB_VERSION);

                request.onerror = () => {
                    console.error('IndexedDB 打开失败:', request.error);
                    reject(request.error);
                };

                request.onsuccess = () => {
                    this.db = request.result;
                    console.log('✓ IndexedDB 初始化成功');
                    resolve(this.db);
                };

                request.onupgradeneeded = (event) => {
                    const db = event.target.result;

                    // 创建消息存储
                    if (!db.objectStoreNames.contains(this.STORE_MESSAGES)) {
                        const messageStore = db.createObjectStore(this.STORE_MESSAGES, {
                            keyPath: 'id'
                        });
                        messageStore.createIndex('sender_id', 'sender_id', { unique: false });
                        messageStore.createIndex('receiver_id', 'receiver_id', { unique: false });
                        messageStore.createIndex('room_id', 'room_id', { unique: false });
                        messageStore.createIndex('created_at', 'created_at', { unique: false });
                        messageStore.createIndex('chat_key', ['sender_id', 'receiver_id', 'room_id'], { unique: false });
                    }

                    // 创建会话存储
                    if (!db.objectStoreNames.contains(this.STORE_CONVERSATIONS)) {
                        const conversationStore = db.createObjectStore(this.STORE_CONVERSATIONS, {
                            keyPath: 'key'
                        });
                        conversationStore.createIndex('last_message_time', 'last_message_time', { unique: false });
                    }

                    // 创建同步状态存储
                    if (!db.objectStoreNames.contains(this.STORE_SYNC_STATE)) {
                        db.createObjectStore(this.STORE_SYNC_STATE, {
                            keyPath: 'key'
                        });
                    }
                };
            });
        },

        /**
         * 保存消息
         */
        async saveMessage(message) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_MESSAGES], 'readwrite');
                const store = transaction.objectStore(this.STORE_MESSAGES);
                
                // 添加本地存储标记和时间戳
                const messageToSave = {
                    ...message,
                    _local_saved: true,
                    _saved_at: Date.now()
                };
                
                const request = store.put(messageToSave);
                
                request.onsuccess = () => {
                    resolve(messageToSave);
                };
                
                request.onerror = () => {
                    console.error('保存消息失败:', request.error);
                    reject(request.error);
                };
            });
        },

        /**
         * 批量保存消息
         */
        async saveMessages(messages) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_MESSAGES], 'readwrite');
                const store = transaction.objectStore(this.STORE_MESSAGES);
                
                let completed = 0;
                const total = messages.length;
                
                if (total === 0) {
                    resolve([]);
                    return;
                }
                
                messages.forEach((message) => {
                    const messageToSave = {
                        ...message,
                        _local_saved: true,
                        _saved_at: Date.now()
                    };
                    
                    const request = store.put(messageToSave);
                    
                    request.onsuccess = () => {
                        completed++;
                        if (completed === total) {
                            resolve(messages);
                        }
                    };
                    
                    request.onerror = () => {
                        console.error('批量保存消息失败:', request.error);
                        completed++;
                        if (completed === total) {
                            reject(request.error);
                        }
                    };
                });
            });
        },

        /**
         * 获取消息列表
         */
        async getMessages(userId, roomId, limit = 50, beforeId = null) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_MESSAGES], 'readonly');
                const store = transaction.objectStore(this.STORE_MESSAGES);
                
                // 使用 getAll 获取所有消息，然后在内存中过滤
                // 因为复合索引的查询比较复杂，直接遍历更简单
                const request = store.getAll();
                
                request.onsuccess = () => {
                    let messages = request.result || [];
                    
                    // 过滤消息
                    if (roomId) {
                        // 房间消息：room_id 匹配
                        messages = messages.filter(msg => msg.room_id === roomId);
                    } else if (userId) {
                        // 点对点消息：sender_id 或 receiver_id 匹配 userId
                        messages = messages.filter(msg => 
                            (msg.sender_id === userId || msg.receiver_id === userId) && !msg.room_id
                        );
                    } else {
                        reject(new Error('必须指定 userId 或 roomId'));
                        return;
                    }
                    
                    // 如果指定了 beforeId，过滤出该 ID 之前的消息
                    if (beforeId) {
                        messages = messages.filter(msg => msg.id < beforeId);
                    }
                    
                    // 按时间排序（最新的在前）
                    messages.sort((a, b) => {
                        const timeA = new Date(a.created_at).getTime();
                        const timeB = new Date(b.created_at).getTime();
                        return timeB - timeA;
                    });
                    
                    // 限制数量
                    messages = messages.slice(0, limit);
                    
                    resolve(messages);
                };
                
                request.onerror = () => {
                    console.error('获取消息失败:', request.error);
                    reject(request.error);
                };
            });
        },

        /**
         * 获取最后一条消息的时间戳（用于增量同步）
         */
        async getLastMessageTime(userId, roomId) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_MESSAGES], 'readonly');
                const store = transaction.objectStore(this.STORE_MESSAGES);
                const index = store.index('created_at');
                
                // 获取最新的消息
                const request = index.openCursor(null, 'prev');
                let lastTime = null;
                
                request.onsuccess = (event) => {
                    const cursor = event.target.result;
                    if (cursor) {
                        const msg = cursor.value;
                        // 检查是否匹配当前会话
                        if (roomId && msg.room_id === roomId) {
                            lastTime = new Date(msg.created_at).getTime();
                        } else if (userId && (msg.sender_id === userId || msg.receiver_id === userId)) {
                            lastTime = new Date(msg.created_at).getTime();
                        }
                        
                        if (lastTime) {
                            resolve(lastTime);
                        } else {
                            cursor.continue();
                        }
                    } else {
                        resolve(null);
                    }
                };
                
                request.onerror = () => {
                    reject(request.error);
                };
            });
        },

        /**
         * 保存会话列表
         */
        async saveConversations(conversations) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_CONVERSATIONS], 'readwrite');
                const store = transaction.objectStore(this.STORE_CONVERSATIONS);
                
                let completed = 0;
                const total = conversations.length;
                
                if (total === 0) {
                    resolve([]);
                    return;
                }
                
                conversations.forEach((conv) => {
                    const key = conv.room_id ? `room_${conv.room_id}` : `user_${conv.user_id}`;
                    const convToSave = {
                        key,
                        ...conv,
                        _saved_at: Date.now()
                    };
                    
                    const request = store.put(convToSave);
                    
                    request.onsuccess = () => {
                        completed++;
                        if (completed === total) {
                            resolve(conversations);
                        }
                    };
                    
                    request.onerror = () => {
                        console.error('保存会话失败:', request.error);
                        completed++;
                        if (completed === total) {
                            reject(request.error);
                        }
                    };
                });
            });
        },

        /**
         * 获取会话列表
         */
        async getConversations() {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_CONVERSATIONS], 'readonly');
                const store = transaction.objectStore(this.STORE_CONVERSATIONS);
                const index = store.index('last_message_time');
                
                const request = index.getAll();
                
                request.onsuccess = () => {
                    let conversations = request.result || [];
                    
                    // 按最后消息时间排序
                    conversations.sort((a, b) => {
                        const timeA = new Date(a.last_message_time || 0).getTime();
                        const timeB = new Date(b.last_message_time || 0).getTime();
                        return timeB - timeA;
                    });
                    
                    resolve(conversations);
                };
                
                request.onerror = () => {
                    console.error('获取会话列表失败:', request.error);
                    reject(request.error);
                };
            });
        },

        /**
         * 保存同步状态
         */
        async saveSyncState(key, state) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_SYNC_STATE], 'readwrite');
                const store = transaction.objectStore(this.STORE_SYNC_STATE);
                
                const syncState = {
                    key,
                    ...state,
                    _updated_at: Date.now()
                };
                
                const request = store.put(syncState);
                
                request.onsuccess = () => {
                    resolve(syncState);
                };
                
                request.onerror = () => {
                    console.error('保存同步状态失败:', request.error);
                    reject(request.error);
                };
            });
        },

        /**
         * 获取同步状态
         */
        async getSyncState(key) {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([this.STORE_SYNC_STATE], 'readonly');
                const store = transaction.objectStore(this.STORE_SYNC_STATE);
                
                const request = store.get(key);
                
                request.onsuccess = () => {
                    resolve(request.result || null);
                };
                
                request.onerror = () => {
                    reject(request.error);
                };
            });
        },

        /**
         * 清除所有数据
         */
        async clearAll() {
            await this.init();
            
            return new Promise((resolve, reject) => {
                const transaction = this.db.transaction([
                    this.STORE_MESSAGES,
                    this.STORE_CONVERSATIONS,
                    this.STORE_SYNC_STATE
                ], 'readwrite');
                
                let completed = 0;
                const total = 3;
                
                const complete = () => {
                    completed++;
                    if (completed === total) {
                        resolve();
                    }
                };
                
                transaction.objectStore(this.STORE_MESSAGES).clear().onsuccess = complete;
                transaction.objectStore(this.STORE_CONVERSATIONS).clear().onsuccess = complete;
                transaction.objectStore(this.STORE_SYNC_STATE).clear().onsuccess = complete;
                
                transaction.onerror = () => {
                    reject(transaction.error);
                };
            });
        }
    };

    // 导出到全局
    window.MessageStorage = MessageStorage;

})();
