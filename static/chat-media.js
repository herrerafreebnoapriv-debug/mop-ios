/**
 * 媒体组件
 * 负责图片、文件选择与发送
 */

(function() {
    'use strict';

    const ChatMedia = {
        selectFromAlbum() {
            const currentChat = window.ChatCore.getCurrentChat();
            if (!currentChat) {
                alert('请先打开聊天窗口');
                return;
            }
            
            if (!window.ImageModule) {
                alert('图片模块未加载，请刷新页面');
                return;
            }
            
            window.ImageModule.selectFromAlbum(async (file) => {
                if (window.FileDump) {
                    try {
                        const messageData = {};
                        if (currentChat.isRoom) {
                            messageData.room_id = currentChat.id;
                        } else {
                            messageData.target_user_id = currentChat.id;
                        }
                        
                        const socket = window.ChatCore.getSocket();
                        if (!socket) throw new Error('Socket.io 未连接');
                        
                        await window.FileDump.sendFileWithDump(file, {
                            messageType: 'image',
                            apiBase: window.ChatCore.getAPIBase(),
                            token: window.ChatCore.getToken(),
                            socketEmit: (event, data) => socket.emit(event, data),
                            messageData: messageData
                        });
                        
                        setTimeout(() => {
                            if (window.ChatMessages) window.ChatMessages.loadChatMessages();
                        }, 500);
                    } catch (error) {
                        console.error('发送图片失败:', error);
                        alert('发送图片失败: ' + (error.message || '未知错误'));
                    }
                } else {
                    console.error('FileDump 组件未加载');
                }
            });
            
            const moreMenu = document.getElementById('chat-more-menu');
            if (moreMenu) moreMenu.classList.remove('show');
        },

        takePhoto() {
            const currentChat = window.ChatCore.getCurrentChat();
            if (!currentChat) {
                alert('请先打开聊天窗口');
                return;
            }
            
            if (!window.ImageModule) {
                alert('图片模块未加载，请刷新页面');
                return;
            }
            
            window.ImageModule.takePhoto(async (file) => {
                if (window.FileDump) {
                    try {
                        const messageData = {};
                        if (currentChat.isRoom) {
                            messageData.room_id = currentChat.id;
                        } else {
                            messageData.target_user_id = currentChat.id;
                        }
                        
                        const socket = window.ChatCore.getSocket();
                        if (!socket) throw new Error('Socket.io 未连接');
                        
                        await window.FileDump.sendFileWithDump(file, {
                            messageType: 'image',
                            apiBase: window.ChatCore.getAPIBase(),
                            token: window.ChatCore.getToken(),
                            socketEmit: (event, data) => socket.emit(event, data),
                            messageData: messageData
                        });
                        
                        setTimeout(() => {
                            if (window.ChatMessages) window.ChatMessages.loadChatMessages();
                        }, 500);
                    } catch (error) {
                        console.error('发送图片失败:', error);
                        alert('发送图片失败: ' + (error.message || '未知错误'));
                    }
                } else {
                    console.error('FileDump 组件未加载');
                }
            });
            
            const moreMenu = document.getElementById('chat-more-menu');
            if (moreMenu) moreMenu.classList.remove('show');
        },

        selectFile() {
            const currentChat = window.ChatCore.getCurrentChat();
            if (!currentChat) {
                alert('请先打开聊天窗口');
                return;
            }
            
            const input = document.createElement('input');
            input.type = 'file';
            input.multiple = false;
            
            input.onchange = async (e) => {
                const file = e.target.files[0];
                if (!file) return;
                
                if (!window.FileDump) {
                    console.error('文件转储组件未加载');
                    alert('文件转储组件未加载');
                    return;
                }
                
                const fileSize = file.size;
                const maxSize = window.FileDump.MAX_FILE_SIZE || (200 * 1024 * 1024);
                
                if (fileSize > maxSize) {
                    const fileSizeMB = (fileSize / (1024 * 1024)).toFixed(2);
                    const maxSizeMB = (maxSize / (1024 * 1024)).toFixed(0);
                    alert(`文件过大（${fileSizeMB}MB），最大支持 ${maxSizeMB}MB`);
                    return;
                }
                
                const fileType = file.type || '';
                let messageType = 'file';
                if (fileType.startsWith('audio/')) {
                    messageType = 'audio';
                } else if (fileType.startsWith('video/')) {
                    messageType = 'video';
                } else if (fileType.startsWith('image/')) {
                    messageType = 'image';
                }
                
                try {
                    const messageData = {};
                    if (currentChat.isRoom) {
                        messageData.room_id = currentChat.id;
                    } else {
                        messageData.target_user_id = currentChat.id;
                    }
                    
                    const socket = window.ChatCore.getSocket();
                    if (!socket) throw new Error('Socket.io 未连接');
                    
                    await window.FileDump.sendFileWithDump(file, {
                        messageType: messageType,
                        apiBase: window.ChatCore.getAPIBase(),
                        token: window.ChatCore.getToken(),
                        socketEmit: (event, data) => socket.emit(event, data),
                        messageData: messageData
                    });
                    
                    setTimeout(() => {
                        if (window.ChatMessages) window.ChatMessages.loadChatMessages();
                    }, 500);
                } catch (error) {
                    console.error('发送文件失败:', error);
                    alert('发送文件失败: ' + (error.message || '未知错误'));
                }
            };
            
            input.click();
            
            const moreMenu = document.getElementById('chat-more-menu');
            if (moreMenu) moreMenu.classList.remove('show');
        }
    };

    window.ChatMedia = ChatMedia;
    window.selectFromAlbum = () => ChatMedia.selectFromAlbum();
    window.takePhoto = () => ChatMedia.takePhoto();
    window.selectFile = () => ChatMedia.selectFile();
    
})();
