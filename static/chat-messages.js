/**
 * 聊天消息组件（主入口）
 * 整合消息列表、聊天窗口、消息处理等功能
 */

(function() {
    'use strict';

    // 确保依赖组件已加载
    if (!window.ChatMessagesList) {
        console.error('ChatMessagesList 组件未加载，请检查脚本加载顺序');
    }
    if (!window.ChatMessagesWindow) {
        console.error('ChatMessagesWindow 组件未加载，请检查脚本加载顺序');
    }

    const ChatMessages = {
        currentChat: null,
        chatMessages: [],

        // 消息列表功能（委托给 ChatMessagesList）
        async loadMessages() {
            if (window.ChatMessagesList && window.ChatMessagesList.loadMessages) {
                return window.ChatMessagesList.loadMessages();
            } else {
                console.error('ChatMessagesList.loadMessages 未找到');
            }
        },

        renderMessages() {
            if (window.ChatMessagesList && window.ChatMessagesList.renderMessages) {
                return window.ChatMessagesList.renderMessages();
            } else {
                console.error('ChatMessagesList.renderMessages 未找到');
            }
        },

        searchMessages(keyword) {
            if (window.ChatMessagesList && window.ChatMessagesList.searchMessages) {
                return window.ChatMessagesList.searchMessages(keyword);
            } else {
                console.error('ChatMessagesList.searchMessages 未找到');
            }
        },

        // 聊天窗口功能（委托给 ChatMessagesWindow）
        openChat(id, name, isRoom) {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.openChat) {
                window.ChatMessagesWindow.openChat(id, name, isRoom);
                this.currentChat = window.ChatMessagesWindow.currentChat;
            } else {
                console.error('ChatMessagesWindow.openChat 未找到');
            }
        },

        close() {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.close) {
                window.ChatMessagesWindow.close();
                this.currentChat = null;
            } else {
                console.error('ChatMessagesWindow.close 未找到');
            }
        },

        async loadChatMessages() {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.loadChatMessages) {
                await window.ChatMessagesWindow.loadChatMessages();
                this.chatMessages = window.ChatMessagesWindow.chatMessages || [];
            } else {
                console.error('ChatMessagesWindow.loadChatMessages 未找到');
            }
        },

        renderChatMessages() {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.renderChatMessages) {
                return window.ChatMessagesWindow.renderChatMessages();
            } else {
                console.error('ChatMessagesWindow.renderChatMessages 未找到');
            }
        },

        updateReadStatus(messageId, readAt) {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.updateReadStatus) {
                return window.ChatMessagesWindow.updateReadStatus(messageId, readAt);
            } else {
                console.error('ChatMessagesWindow.updateReadStatus 未找到');
            }
        },

        async send() {
            if (!this.currentChat) {
                alert('请先打开聊天窗口');
                return;
            }
            
            const socket = window.ChatCore.getSocket();
            if (!socket || !socket.connected) {
                alert('Socket.io 未连接，正在尝试重新连接...');
                window.ChatCore.connectSocket();
                return;
            }
            
            const input = document.getElementById('chat-input');
            if (!input) return;
            
            const message = input.value.trim();
            if (!message) return;
            
            input.disabled = true;
            const sendBtn = document.getElementById('chat-send-btn');
            if (sendBtn) sendBtn.disabled = true;
            
            try {
                const data = { message, type: 'text' };
                if (this.currentChat.isRoom) {
                    data.room_id = this.currentChat.id;
                } else {
                    data.target_user_id = this.currentChat.id;
                }
                
                socket.emit('send_message', data);
                socket.once('error', (error) => {
                    console.error('✗ 发送消息错误:', error);
                    alert('发送消息失败: ' + (error.message || '未知错误'));
                });
                
                input.value = '';
                input.style.height = 'auto';
                
                setTimeout(() => this.loadChatMessages(), 500);
            } catch (error) {
                console.error('发送消息失败:', error);
                alert('发送消息失败: ' + (error.message || '未知错误'));
            } finally {
                if (input) {
                    input.disabled = false;
                    input.focus();
                }
                if (sendBtn) sendBtn.disabled = false;
            }
        },

        async markChatMessagesAsRead() {
            if (window.ChatMessagesWindow && window.ChatMessagesWindow.markChatMessagesAsRead) {
                return window.ChatMessagesWindow.markChatMessagesAsRead();
            } else {
                console.error('ChatMessagesWindow.markChatMessagesAsRead 未找到');
            }
        },

        async sendVoiceMessage(audioBlob, durationMs) {
            if (!this.currentChat) return;
            
            if (!window.FileDump) {
                console.error('文件转储组件未加载');
                return;
            }
            
            try {
                const messageData = {};
                if (this.currentChat.isRoom) {
                    messageData.room_id = this.currentChat.id;
                } else {
                    messageData.target_user_id = this.currentChat.id;
                }
                if (durationMs != null && durationMs >= 0) {
                    const durationSec = Math.min(60, Math.max(1, Math.round(durationMs / 1000)));
                    messageData.duration = durationSec;
                }
                messageData.file_name = 'voice.webm';
                
                const socket = window.ChatCore.getSocket();
                if (!socket) throw new Error('Socket.io 未连接');
                
                await window.FileDump.sendFileWithDump(audioBlob, {
                    messageType: 'audio',
                    apiBase: window.ChatCore.getAPIBase(),
                    token: window.ChatCore.getToken(),
                    socketEmit: (event, data) => socket.emit(event, data),
                    messageData: messageData,
                    fileName: 'voice.webm'
                });
                
                setTimeout(() => this.loadChatMessages(), 500);
            } catch (error) {
                console.error('发送语音消息失败:', error);
                alert('发送语音消息失败: ' + (error.message || '未知错误'));
            }
        },

        /**
         * 处理新消息
         */
        async handleNewMessage(data) {
            
            if (!data) return;
            
            const senderId = data.from_user_id || data.sender_id;
            const receiverId = data.receiver_id;
            const roomId = data.room_id;
            
            // 保存新消息到本地缓存
            if (window.MessageStorage && data.id) {
                try {
                    await window.MessageStorage.saveMessage(data);
                } catch (e) {
                    console.warn('保存新消息到缓存失败:', e);
                }
            }
            
            if (data.is_original && data.file_url) {
                this.updateThumbnailMessageWithOriginal(data);
            }
            
            const user = window.ChatCore.getCurrentUser();
            if (!user || !user.id) {
                this.loadMessages();
                return;
            }
            
            this.currentChat = window.ChatCore.getCurrentChat();
            if (this.currentChat) {
                let isCurrentChatMessage = false;
                
                if (this.currentChat.isRoom) {
                    isCurrentChatMessage = roomId === this.currentChat.id;
                } else {
                    const isFromOtherUser = senderId === this.currentChat.id && receiverId === user.id;
                    const isFromMe = senderId === user.id && receiverId === this.currentChat.id;
                    isCurrentChatMessage = (isFromOtherUser || isFromMe) && !roomId;
                }
                
                if (isCurrentChatMessage) {
                    this.loadChatMessages();
                }
            }
            
            this.loadMessages();
        },

        /**
         * 更新缩略图消息
         */
        updateThumbnailMessageWithOriginal(originalMessage) {
            const senderId = originalMessage.from_user_id || originalMessage.sender_id;
            const messageType = originalMessage.type || originalMessage.message_type;
            
            this.chatMessages = window.ChatCore.getChatMessages() || [];
            for (let i = this.chatMessages.length - 1; i >= 0; i--) {
                const msg = this.chatMessages[i];
                const msgSenderId = msg.from_user_id || msg.sender_id;
                const msgType = msg.type || msg.message_type;
                
                if (msgSenderId === senderId && msgType === messageType && msgType === 'image' && !msg.file_url && msg.message && msg.message.startsWith('data:image/')) {
                    msg.file_url = originalMessage.file_url;
                    msg.file_name = originalMessage.file_name || msg.file_name;
                    msg.file_size = originalMessage.file_size || msg.file_size;
                    window.ChatCore.setChatMessages(this.chatMessages);
                    this.renderChatMessages();
                    break;
                }
            }
        }
    };

    // 导出
    window.ChatMessages = ChatMessages;
    window.openChat = (id, name, isRoom) => ChatMessages.openChat(id, name, isRoom);
    window.closeChatWindow = () => ChatMessages.close();
    window.sendChatMessage = () => ChatMessages.send();
    
})();
