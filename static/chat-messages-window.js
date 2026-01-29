/**
 * 聊天窗口组件
 * 负责聊天窗口的打开、关闭、消息渲染和发送
 */

(function() {
    'use strict';

    const ChatMessagesWindow = {
        currentChat: null,
        chatMessages: [],
        chatInputKeydownHandler: null,
        chatInputInputHandler: null,

        /**
         * 打开聊天窗口
         */
        openChat(id, name, isRoom) {
            const user = window.ChatCore.getCurrentUser();
            if (!user) {
                alert('用户信息未加载，请稍候再试');
                return;
            }
            
            this.currentChat = { id, name, isRoom: isRoom || false };
            window.ChatCore.setCurrentChat(this.currentChat);
            if (window.ChatMessages) {
                window.ChatMessages.currentChat = this.currentChat;
            }
            
            const chatWindow = document.getElementById('chat-window');
            const chatWindowTitle = document.getElementById('chat-window-title');
            const chatMessagesContainer = document.getElementById('chat-messages-container');
            
            if (!chatWindow || !chatWindowTitle || !chatMessagesContainer) {
                console.error('聊天窗口元素未找到');
                return;
            }
            
            chatWindow.classList.add('active');
            chatWindowTitle.textContent = `💬 ${this.escapeHtml(name)}`;
            
            this.chatMessages = [];
            window.ChatCore.setChatMessages([]);
            chatMessagesContainer.innerHTML = '<div class="empty-state"><div class="empty-icon">💬</div><div>加载消息中...</div></div>';
            
            this.loadChatMessages();
            this.initChatInput();
            this.initChatButtons();
        },

        /**
         * 初始化聊天输入框
         */
        initChatInput() {
            const chatInput = document.getElementById('chat-input');
            if (!chatInput) return;
            
            if (this.chatInputKeydownHandler) {
                chatInput.removeEventListener('keydown', this.chatInputKeydownHandler);
            }
            if (this.chatInputInputHandler) {
                chatInput.removeEventListener('input', this.chatInputInputHandler);
            }
            
            chatInput.value = '';
            chatInput.focus();
            
            this.chatInputKeydownHandler = (e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (window.ChatMessages && window.ChatMessages.send) {
                        window.ChatMessages.send();
                    }
                }
            };
            chatInput.addEventListener('keydown', this.chatInputKeydownHandler);
            
            this.chatInputInputHandler = function() {
                this.style.height = 'auto';
                this.style.height = Math.min(this.scrollHeight, 120) + 'px';
                const sendBtn = document.getElementById('chat-send-btn');
                if (sendBtn) sendBtn.disabled = !this.value.trim();
            };
            chatInput.addEventListener('input', this.chatInputInputHandler);
            
            const sendBtn = document.getElementById('chat-send-btn');
            if (sendBtn) sendBtn.disabled = true;
        },

        /**
         * 初始化聊天按钮
         */
        initChatButtons() {
            const moreBtn = document.getElementById('chat-more-btn');
            const moreMenu = document.getElementById('chat-more-menu');
            
            if (moreBtn && moreMenu) {
                moreBtn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    moreMenu.classList.toggle('show');
                });
                
                document.addEventListener('click', (e) => {
                    if (!moreMenu.contains(e.target) && e.target !== moreBtn) {
                        moreMenu.classList.remove('show');
                    }
                });
            }
            
            this.initVoiceRecording();
        },

        /**
         * 初始化语音录制
         */
        initVoiceRecording() {
            const voiceBtn = document.getElementById('chat-voice-btn');
            const voiceHint = document.getElementById('voice-recording-hint');
            if (!voiceBtn || !voiceHint) return;
            
            let isRecording = false;
            let mediaRecorder = null;
            let audioChunks = [];
            let recordingStartTime = null;
            let lastVoiceDurationMs = 0;
            let recordingTimer = null;
            const MAX_RECORDING_DURATION_MS = 60 * 1000;
            
            const startVoiceRecording = async (e) => {
                e.preventDefault();
                e.stopPropagation();
                if (!this.currentChat || isRecording) return;
                
                try {
                    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
                    mediaRecorder = new MediaRecorder(stream);
                    audioChunks = [];
                    
                    mediaRecorder.ondataavailable = (event) => {
                        if (event.data.size > 0) audioChunks.push(event.data);
                    };
                    
                    mediaRecorder.onstop = async () => {
                        const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
                        if (window.ChatMessages && window.ChatMessages.sendVoiceMessage) {
                            await window.ChatMessages.sendVoiceMessage(audioBlob, lastVoiceDurationMs);
                        }
                        stream.getTracks().forEach(track => track.stop());
                        if (recordingTimer) {
                            clearInterval(recordingTimer);
                            recordingTimer = null;
                        }
                    };
                    
                    mediaRecorder.start();
                    isRecording = true;
                    recordingStartTime = Date.now();
                    lastVoiceDurationMs = 0;
                    voiceBtn.classList.add('recording');
                    voiceHint.classList.add('show', 'recording');
                    voiceHint.textContent = '正在录音... 0秒';
                    
                    recordingTimer = setInterval(() => {
                        if (!isRecording) return;
                        const elapsed = Date.now() - recordingStartTime;
                        const seconds = Math.floor(elapsed / 1000);
                        if (seconds >= 60) {
                            stopVoiceRecording(null);
                            voiceHint.textContent = '录音已达60秒上限';
                            setTimeout(() => {
                                voiceHint.classList.remove('show', 'recording');
                            }, 1000);
                        } else {
                            voiceHint.textContent = `正在录音... ${seconds}秒`;
                        }
                    }, 100);
                } catch (error) {
                    console.error('无法访问麦克风:', error);
                    alert('无法访问麦克风，请检查权限设置');
                }
            };
            
            const stopVoiceRecording = (e) => {
                if (e) {
                    e.preventDefault();
                    e.stopPropagation();
                }
                if (!isRecording || !mediaRecorder) return;
                
                const durationMs = Date.now() - recordingStartTime;
                if (durationMs < 500) {
                    cancelVoiceRecording();
                    return;
                }
                lastVoiceDurationMs = Math.min(durationMs, MAX_RECORDING_DURATION_MS);
                
                mediaRecorder.stop();
                isRecording = false;
                voiceBtn.classList.remove('recording');
                voiceHint.classList.remove('show', 'recording');
                if (recordingTimer) {
                    clearInterval(recordingTimer);
                    recordingTimer = null;
                }
            };
            
            const cancelVoiceRecording = () => {
                if (mediaRecorder) {
                    try { mediaRecorder.stop(); } catch (e) {}
                }
                isRecording = false;
                audioChunks = [];
                voiceBtn.classList.remove('recording');
                voiceHint.classList.remove('show', 'recording');
            };
            
            voiceBtn.addEventListener('touchstart', startVoiceRecording, { passive: false });
            voiceBtn.addEventListener('touchend', stopVoiceRecording, { passive: false });
            voiceBtn.addEventListener('mousedown', startVoiceRecording);
            voiceBtn.addEventListener('mouseup', stopVoiceRecording);
            voiceBtn.addEventListener('mouseleave', cancelVoiceRecording);
        },

        /**
         * 关闭聊天窗口
         */
        close() {
            const chatWindow = document.getElementById('chat-window');
            if (chatWindow) chatWindow.classList.remove('active');
            
            const chatInput = document.getElementById('chat-input');
            if (chatInput) {
                if (this.chatInputKeydownHandler) {
                    chatInput.removeEventListener('keydown', this.chatInputKeydownHandler);
                    this.chatInputKeydownHandler = null;
                }
                if (this.chatInputInputHandler) {
                    chatInput.removeEventListener('input', this.chatInputInputHandler);
                    this.chatInputInputHandler = null;
                }
            }
            
            this.currentChat = null;
            window.ChatCore.setCurrentChat(null);
            if (window.ChatMessages) {
                window.ChatMessages.currentChat = null;
            }
            this.chatMessages = [];
            window.ChatCore.setChatMessages([]);
            
            if (window.ChatMessages && window.ChatMessages.loadMessages) {
                window.ChatMessages.loadMessages();
            } else if (window.ChatMessagesList && window.ChatMessagesList.loadMessages) {
                window.ChatMessagesList.loadMessages();
            }
        },

        /**
         * 加载聊天消息
         */
        async loadChatMessages() {
            if (!this.currentChat) return;
            
            try {
                const state = window.ChatCore.getState();
                const params = new URLSearchParams({ page: '1', limit: '50' });
                if (this.currentChat.isRoom) {
                    params.append('room_id', this.currentChat.id);
                } else {
                    params.append('user_id', this.currentChat.id);
                }
                
                let response;
                if (window.AuthManager) {
                    response = await window.AuthManager.fetchWithAuth(`${state.API_BASE}/chat/messages?${params}`);
                } else {
                    const token = window.ChatCore.getToken();
                    if (!token) throw new Error('未登录');
                    response = await fetch(`${state.API_BASE}/chat/messages?${params}`, {
                        headers: { 'Authorization': `Bearer ${token}` }
                    });
                }
                if (!response.ok) throw new Error('加载消息失败');
                
                const data = await response.json();
                this.chatMessages = (data.messages || []).reverse();
                console.log('[加载消息] 从API获取的消息:', this.chatMessages.length, '条');
                // 详细输出所有包含 voice.webm 的消息
                this.chatMessages.forEach((msg, idx) => {
                    if (msg && (msg.file_name === 'voice.webm' || (msg.file_name && msg.file_name.includes('voice')))) {
                        console.log('[加载消息-语音] 发现语音消息 #' + idx + ':', {
                            id: msg.id,
                            message_type: msg.message_type,
                            type: msg.type,
                            file_name: msg.file_name,
                            file_url: msg.file_url,
                            duration: msg.duration,
                            sender_id: msg.sender_id,
                            receiver_id: msg.receiver_id,
                            full_msg: msg
                        });
                    }
                });
                // 详细输出所有消息，特别是语音消息
                this.chatMessages.forEach((m, i) => {
                    if (m.file_name || m.file_url || m.duration || (m.message_type === 'audio') || (m.type === 'audio')) {
                        console.log(`[消息${i}]`, {
                            id: m.id,
                            message_type: m.message_type,
                            type: m.type,
                            file_name: m.file_name,
                            file_url: m.file_url,
                            duration: m.duration,
                            message: m.message ? (m.message.substring(0, 30) + '...') : ''
                        });
                    }
                });
                window.ChatCore.setChatMessages(this.chatMessages);
                if (window.ChatMessages) {
                    window.ChatMessages.chatMessages = this.chatMessages;
                }
                
                this.renderChatMessages();
                this.markChatMessagesAsRead();
            } catch (error) {
                console.error('加载聊天消息失败:', error);
                const container = document.getElementById('chat-messages-container');
                if (container) {
                    container.innerHTML = '<div class="empty-state"><div>加载消息失败</div></div>';
                }
            }
        },

        /**
         * 渲染聊天消息
         */
        renderChatMessages() {
            const container = document.getElementById('chat-messages-container');
            if (!container) {
                console.error('聊天消息容器元素未找到');
                return;
            }
            
            this.chatMessages = window.ChatCore.getChatMessages() || [];
            
            if (!this.chatMessages || !this.chatMessages.length) {
                container.innerHTML = '<div class="empty-state"><div class="empty-icon">💬</div><div>暂无消息，开始聊天吧</div></div>';
                return;
            }
            
            const user = window.ChatCore.getCurrentUser();
            if (!user || !user.id) {
                console.error('无法渲染消息：currentUser 未初始化或缺少 id');
                container.innerHTML = '<div class="empty-state"><div>用户信息未加载，请刷新页面</div></div>';
                return;
            }
            
            const wasAtBottom = container.scrollHeight - container.scrollTop <= container.clientHeight + 50;
            
            container.innerHTML = this.chatMessages.map((msg, idx) => {
                if (!msg || !msg.sender_id) return '';
                const isSent = msg.sender_id === user.id;
                const time = this.formatTime(msg.created_at);
                
                // 优先使用 message_type，如果没有则使用 type，最后默认为 text
                let messageType = msg.message_type || msg.type || 'text';
                const messageText = msg.message || '';
                const fileName = (msg.file_name || '').trim();
                
                // 如果消息类型是 text 但内容是 base64 图片，自动识别为图片
                if (messageType === 'text' && messageText.startsWith('data:image/')) {
                    messageType = 'image';
                }
                
                // 如果有文件 URL 或文件名，根据文件名重新推断类型（覆盖后端可能错误的类型）
                if (msg.file_url || msg.file_name) {
                    // 语音消息：优先识别
                    if (msg.message_type === 'audio' || msg.type === 'audio' || msg.message_type === 'voice' || msg.type === 'voice' || fileName === 'voice.webm') {
                        messageType = 'audio';
                    } 
                    // 图片：根据扩展名识别（优先于后端类型）
                    else if (fileName.match(/\.(jpg|jpeg|png|gif|webp|bmp)$/i)) {
                        messageType = 'image';
                    } 
                    // 视频：根据扩展名识别
                    else if (fileName.match(/\.(mp4|avi|mov|wmv|flv|mkv|rmvb|3gp)$/i)) {
                        messageType = 'video';
                    } 
                    // 如果后端类型已经是 image/audio/video/file，保持
                    else if (['image', 'audio', 'video', 'file'].includes(messageType)) {
                        // 保持后端类型（即使文件名不匹配扩展名，也信任后端）
                    }
                    // 其他情况（text、document、未知类型等）：统一为 file
                    else {
                        messageType = 'file';
                    }
                }
                
                // 兜底：如果 message_type 是 image 但没有 file_url 和 file_name，且有 message（base64），保持为 image
                if (messageType === 'image' && !msg.file_url && !msg.file_name && messageText.startsWith('data:image/')) {
                    // 保持为 image
                }
                
                let messageContent = '';
                if (messageType === 'image') {
                    const fileUrl = msg.file_url;
                    const fileName = msg.file_name || '图片';
                    const thumbnailSrc = messageText.startsWith('data:image/') ? messageText : '';
                    
                    if (fileUrl && fileUrl.trim()) {
                        if (thumbnailSrc) {
                            const msgId = msg.id;
                            const cachedUrl = window.ImageLoader ? window.ImageLoader.getCachedOriginalUrl(msgId) : null;
                            const displayUrl = cachedUrl || thumbnailSrc;
                            const clickHandler = `ChatImageViewer.handleImageClick(${msgId}, ${JSON.stringify(fileUrl)})`;
                            messageContent = '<div style="position: relative; display: inline-block;">' +
                                '<img src="' + this.escapeHtml(displayUrl) + '" alt="' + this.escapeHtml(fileName) + '" style="max-width: 200px; max-height: 200px; border-radius: 8px; cursor: pointer; border: 2px solid #667eea;" onclick=\'' + clickHandler + '\' title="点击查看原图" />' +
                                '<div style="position: absolute; bottom: 4px; right: 4px; background: rgba(0,0,0,0.6); color: white; padding: 2px 6px; border-radius: 4px; font-size: 10px;">原图</div>' +
                                '</div>';
                        } else {
                            const token = window.ChatCore.getToken();
                            let viewerUrl = fileUrl;
                            if (fileUrl.startsWith('/api/v1/files/photo/')) {
                                const photoId = fileUrl.replace('/api/v1/files/photo/', '');
                                viewerUrl = `${window.ChatCore.getAPIBase()}/files/photo/${photoId}`;
                                if (token) viewerUrl += '?token=' + encodeURIComponent(token);
                            } else if (fileUrl.startsWith('/api/v1/files/download')) {
                                viewerUrl = `${window.location.origin}${fileUrl}`;
                                if (token && !viewerUrl.includes('token=')) {
                                    viewerUrl += (viewerUrl.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                                }
                            }
                            messageContent = `<img src="${this.escapeHtml(viewerUrl)}" alt="${this.escapeHtml(fileName)}" style="max-width: 200px; max-height: 200px; border-radius: 8px; cursor: pointer;" onclick="ChatImageViewer.show('${this.escapeHtml(viewerUrl)}')" />`;
                        }
                    } else if (thumbnailSrc) {
                        messageContent = `<img src="${this.escapeHtml(thumbnailSrc)}" alt="${this.escapeHtml(fileName)}" style="max-width: 200px; max-height: 200px; border-radius: 8px; cursor: pointer;" onclick="ChatImageViewer.show('${this.escapeHtml(thumbnailSrc)}')" />`;
                    } else {
                        messageContent = `<div style="padding: 20px; text-align: center; color: #999;">📷 ${this.escapeHtml(fileName)}</div>`;
                    }
                } else if (messageType === 'audio') {
                    const fileUrl = (msg.file_url || '').trim();
                    const durationSec = Math.max(1, Math.min(60, parseInt(msg.duration, 10) || 1));
                    const durationText = durationSec >= 60
                        ? (Math.floor(durationSec / 60) + "'" + String(durationSec % 60).padStart(2, '0') + '"')
                        : ("0'" + String(durationSec).padStart(2, '0') + '"');
                    const barWidth = Math.min(200, Math.max(80, 80 + (durationSec / 10) * 20));
                    const voiceBarId = 'voice-bar-' + (msg.id != null ? String(msg.id) : 'idx' + idx);
                    const wavesHtml = '<i class="voice-wave"></i><i class="voice-wave"></i><i class="voice-wave"></i><i class="voice-wave"></i><i class="voice-wave"></i>';
                    const sentClass = isSent ? 'sent' : 'received';
                    if (fileUrl) {
                        messageContent = '<div class="voice-msg-bar ' + sentClass + '" id="' + voiceBarId + '" data-msg-id="' + (msg.id != null ? String(msg.id) : '') + '" data-file-url="' + this.escapeHtml(fileUrl) + '" data-duration="' + durationSec + '" style="min-width:' + barWidth + 'px;max-width:' + barWidth + 'px;" onclick="ChatMessagesWindow.playVoiceBar(\'' + voiceBarId + '\')">' +
                            '<span class="voice-duration">' + durationText + '</span>' +
                            '<span class="voice-waves">' + wavesHtml + '</span>' +
                            '<span class="voice-play-btn" aria-label="播放">▶</span>' +
                            '</div>';
                    } else {
                        messageContent = '<div class="voice-msg-bar ' + sentClass + ' voice-loading" style="min-width:80px;max-width:120px;">' +
                            '<span class="voice-duration">' + durationText + '</span>' +
                            '<span class="voice-waves">' + wavesHtml + '</span>' +
                            '<span class="voice-play-btn" aria-label="处理中">⋯</span>' +
                            '</div>';
                    }
                } else if (messageType === 'file' || messageType === 'document' || messageType === 'video') {
                    const fileUrl = msg.file_url;
                    const fileName = msg.file_name || '文件';
                    const fileSize = msg.file_size || 0;
                    const fileSizeText = fileSize < 1024 
                        ? `${fileSize}B` 
                        : fileSize < 1024 * 1024 
                            ? `${(fileSize / 1024).toFixed(2)}KB` 
                            : `${(fileSize / (1024 * 1024)).toFixed(2)}MB`;
                    
                    let fileIcon = '📁';
                    if (messageType === 'video') fileIcon = '🎬';
                    
                    // 即使没有 file_url，也显示文件信息（可能正在上传或转储中）
                    if (fileUrl && fileUrl.trim()) {
                        const token = window.ChatCore.getToken();
                        let downloadUrl = fileUrl;
                        if (fileUrl.startsWith('http')) {
                            if (token && !downloadUrl.includes('token=')) {
                                downloadUrl += (downloadUrl.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                            }
                        } else {
                            const origin = window.location.origin || '';
                            const base = window.ChatCore.getAPIBase() || '/api/v1';
                            downloadUrl = fileUrl.startsWith('/') ? (origin + fileUrl) : (base.replace(/\/+$/, '') + '/' + fileUrl.replace(/^\/+/, ''));
                            if (token && !downloadUrl.includes('token=')) {
                                downloadUrl += (downloadUrl.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                            }
                        }
                        
                        // 使用 JavaScript 下载函数，确保 token 正确传递
                        const downloadHandler = `downloadFile_${msg.id || Date.now()}`;
                        window[downloadHandler] = async function() {
                            try {
                                const token = window.ChatCore.getToken();
                                const apiBase = window.ChatCore.getAPIBase() || '/api/v1';
                                let url = fileUrl;
                                
                                // 构建完整 URL
                                if (url.startsWith('/')) {
                                    url = window.location.origin + url;
                                } else if (!url.startsWith('http')) {
                                    url = window.location.origin + apiBase + (url.startsWith('/') ? url : '/' + url);
                                }
                                
                                // 添加 token 参数
                                if (token && !url.includes('token=')) {
                                    url += (url.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                                }
                                
                                // 使用 fetch 下载文件
                                const response = await fetch(url, {
                                    headers: {
                                        'Authorization': `Bearer ${token}`
                                    }
                                });
                                
                                if (!response.ok) {
                                    throw new Error(`下载失败: ${response.status} ${response.statusText}`);
                                }
                                
                                const blob = await response.blob();
                                const downloadUrl = window.URL.createObjectURL(blob);
                                const a = document.createElement('a');
                                a.href = downloadUrl;
                                a.download = fileName;
                                document.body.appendChild(a);
                                a.click();
                                document.body.removeChild(a);
                                window.URL.revokeObjectURL(downloadUrl);
                            } catch (error) {
                                console.error('文件下载失败:', error);
                                alert('下载失败: ' + (error.message || '未知错误'));
                            }
                        };
                        
                        messageContent = `
                            <div style="display: flex; align-items: center; gap: 12px; padding: 12px; background: rgba(102, 126, 234, 0.1); border-radius: 8px; border: 1px solid rgba(102, 126, 234, 0.3); max-width: 300px;">
                                <div style="font-size: 32px;">${fileIcon}</div>
                                <div style="flex: 1; min-width: 0;">
                                    <div style="font-weight: 500; color: #333; margin-bottom: 4px; word-break: break-all; font-size: 14px;">${this.escapeHtml(fileName)}</div>
                                    <div style="font-size: 12px; color: #666;">${fileSizeText}</div>
                                </div>
                                <button onclick="${downloadHandler}()" style="padding: 6px 12px; background: #667eea; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 12px; white-space: nowrap;">下载</button>
                            </div>
                        `;
                    } else {
                        // 即使没有 file_url，也显示文件信息（可能正在上传或转储中）
                        messageContent = `
                            <div style="display: flex; align-items: center; gap: 12px; padding: 12px; background: rgba(102, 126, 234, 0.1); border-radius: 8px; border: 1px solid rgba(102, 126, 234, 0.3); max-width: 300px;">
                                <div style="font-size: 32px;">${fileIcon}</div>
                                <div style="flex: 1; min-width: 0;">
                                    <div style="font-weight: 500; color: #333; margin-bottom: 4px; word-break: break-all; font-size: 14px;">${this.escapeHtml(fileName)}</div>
                                    <div style="font-size: 12px; color: #666;">${fileSizeText}</div>
                                </div>
                                <div style="padding: 6px 12px; background: #ccc; color: #666; border-radius: 6px; font-size: 12px; white-space: nowrap;">处理中</div>
                            </div>
                        `;
                    }
                } else if (messageText.startsWith('data:image/')) {
                    messageContent = `<img src="${this.escapeHtml(messageText)}" alt="图片" style="max-width: 200px; max-height: 200px; border-radius: 8px; cursor: pointer;" onclick="ChatImageViewer.show('${this.escapeHtml(messageText)}')" />`;
                } else {
                    messageContent = `<div>${this.escapeHtml(messageText)}</div>`;
                }
                
                return `
                    <div class="chat-message ${isSent ? 'sent' : 'received'}" data-message-id="${msg.id}">
                        ${!isSent ? `<div style="font-size: 12px; color: #666; margin-bottom: 4px; padding: 0 5px;">${this.escapeHtml(msg.sender_nickname || `用户${msg.sender_id}`)}</div>` : ''}
                        <div class="chat-message-bubble">
                            ${messageContent}
                        </div>
                        <div class="chat-message-time">${time}</div>
                        ${isSent ? `<div class="chat-message-status ${msg.is_read ? 'read' : 'sent'}">${msg.is_read ? '已读' : '已发送'}</div>` : ''}
                    </div>
                `;
            }).join('');
            
            if (wasAtBottom) {
                container.scrollTop = container.scrollHeight;
            }
        },

        /**
         * 更新消息已读状态
         */
        updateReadStatus(messageId, readAt) {
            this.chatMessages = window.ChatCore.getChatMessages() || [];
            const message = this.chatMessages.find(msg => msg.id === messageId);
            if (message) {
                message.is_read = true;
                message.read_at = readAt;
                window.ChatCore.setChatMessages(this.chatMessages);
                
                const messageElement = document.querySelector(`[data-message-id="${messageId}"]`);
                if (messageElement) {
                    const statusElement = messageElement.querySelector('.chat-message-status');
                    if (statusElement) {
                        statusElement.textContent = '已读';
                        statusElement.className = 'chat-message-status read';
                    }
                }
            }
        },

        /**
         * 标记消息为已读
         */
        async markChatMessagesAsRead() {
            const user = window.ChatCore.getCurrentUser();
            const socket = window.ChatCore.getSocket();
            if (!this.currentChat || !user || !socket) return;
            
            this.chatMessages = window.ChatCore.getChatMessages() || [];
            const unreadMessageIds = this.chatMessages
                .filter(msg => msg.receiver_id === user.id && !msg.is_read)
                .map(msg => msg.id);
            
            if (unreadMessageIds.length === 0) return;
            
            try {
                socket.emit('mark_message_read', { message_ids: unreadMessageIds });
                const base = window.ChatCore.getAPIBase();
                let res;
                if (window.AuthManager) {
                    res = await window.AuthManager.fetchWithAuth(`${base}/chat/messages/mark-read`, {
                        method: 'PUT',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ message_ids: unreadMessageIds })
                    });
                } else {
                    const token = window.ChatCore.getToken();
                    res = await fetch(`${base}/chat/messages/mark-read`, {
                        method: 'PUT',
                        headers: {
                            'Authorization': `Bearer ${token}`,
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({ message_ids: unreadMessageIds })
                    });
                }
                if (!res.ok) console.warn('标记已读 API 失败:', res.status);
            } catch (error) {
                console.error('标记消息已读失败:', error);
            }
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
        },

        escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        },

        _voiceAudio: null,
        _voicePlayingBarId: null,

        async playVoiceBar(voiceBarId) {
            const el = document.getElementById(voiceBarId);
            if (!el || el.classList.contains('voice-loading')) return;
            const fileUrl = el.getAttribute('data-file-url');
            if (!fileUrl || !fileUrl.trim()) return;

            const btn = el.querySelector('.voice-play-btn');
            const isPlaying = el.classList.contains('voice-playing');

            if (isPlaying) {
                if (this._voiceAudio) {
                    this._voiceAudio.pause();
                    this._voiceAudio.currentTime = 0;
                }
                el.classList.remove('voice-playing');
                if (btn) btn.textContent = '▶';
                this._voicePlayingBarId = null;
                return;
            }

            if (this._voicePlayingBarId && this._voicePlayingBarId !== voiceBarId) {
                const prev = document.getElementById(this._voicePlayingBarId);
                if (prev) {
                    prev.classList.remove('voice-playing');
                    const pbtn = prev.querySelector('.voice-play-btn');
                    if (pbtn) pbtn.textContent = '▶';
                }
            }

            try {
                let url = fileUrl;
                if (!url.startsWith('http')) {
                    url = (url.startsWith('/') ? window.location.origin : (window.location.origin + (window.ChatCore.getAPIBase() || '/api/v1'))) + url;
                }
                const token = window.ChatCore.getToken();
                if (token && !url.includes('token=')) {
                    url += (url.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                }
                const headers = {};
                if (token) headers['Authorization'] = 'Bearer ' + token;
                const res = await fetch(url, { headers });
                if (!res.ok) throw new Error(res.statusText);
                const blob = await res.blob();
                const blobUrl = URL.createObjectURL(blob);

                if (!this._voiceAudio) this._voiceAudio = new Audio();
                this._voiceAudio.src = blobUrl;
                this._voiceAudio.onended = () => {
                    URL.revokeObjectURL(blobUrl);
                    el.classList.remove('voice-playing');
                    if (btn) btn.textContent = '▶';
                    this._voicePlayingBarId = null;
                };
                this._voiceAudio.onerror = () => {
                    URL.revokeObjectURL(blobUrl);
                    el.classList.remove('voice-playing');
                    if (btn) btn.textContent = '▶';
                    this._voicePlayingBarId = null;
                };

                await this._voiceAudio.play();
                el.classList.add('voice-playing');
                if (btn) btn.textContent = '❚❚';
                this._voicePlayingBarId = voiceBarId;
            } catch (e) {
                console.error('播放语音失败:', e);
                alert('播放失败: ' + (e.message || '未知错误'));
            }
        }
    };

    window.ChatMessagesWindow = ChatMessagesWindow;
})();
