/**
 * 通话组件
 * 负责视频通话、通话邀请等功能
 */

(function() {
    'use strict';

    const ChatCalls = {
        currentCallInvitation: null,

        openCallInOverlay(roomPageUrl) {
            const overlay = document.getElementById('call-overlay');
            const iframe = document.getElementById('call-overlay-iframe');
            if (!overlay || !iframe) return;
            const url = roomPageUrl + (roomPageUrl.includes('?') ? '&' : '?') + 'embed=1';
            iframe.src = url;
            overlay.style.display = 'block';
        },

        closeCallOverlay() {
            const overlay = document.getElementById('call-overlay');
            const iframe = document.getElementById('call-overlay-iframe');
            if (overlay) overlay.style.display = 'none';
            if (iframe) iframe.src = 'about:blank';
        },

        async sha256Hash(str) {
            const encoder = new TextEncoder();
            const data = encoder.encode(str);
            const hashBuffer = await crypto.subtle.digest('SHA-256', data);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        },

        async startVideoCall() {
            const currentChat = window.ChatCore.getCurrentChat();
            if (!currentChat) {
                alert('请先打开聊天窗口');
                return;
            }
            
            const moreMenu = document.getElementById('chat-more-menu');
            if (moreMenu) moreMenu.classList.remove('show');
            
            try {
                const token = window.ChatCore.getToken();
                if (!token) {
                    alert('请先登录');
                    window.location.href = '/login';
                    return;
                }
                
                const user = window.ChatCore.getCurrentUser();
                if (!user) throw new Error('用户信息未加载');
                
                let roomId;
                if (currentChat.isRoom) {
                    // 群聊房间：使用固定ID（群聊通常需要长期存在）
                    const hash = await this.sha256Hash(`room-${currentChat.id}`);
                    roomId = `r-${hash.substring(0, 8)}`;
                } else {
                    // 1对1通话：每次通话都是新房间（添加秒级时间戳）
                    const userId1 = user.id;
                    const userId2 = currentChat.id;
                    const sortedIds = [userId1, userId2].sort((a, b) => a - b);
                    // 添加秒级时间戳，确保每次通话都是新房间
                    const timestamp = Math.floor(Date.now() / 1000);
                    const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${timestamp}`);
                    roomId = `r-${hash.substring(0, 8)}`;
                }
                
                const roomName = currentChat.isRoom 
                    ? `群聊视频通话 - ${currentChat.name}`
                    : `与 ${currentChat.name} 的视频通话`;
                
                try {
                    const createResponse = await fetch(`${window.ChatCore.getAPIBase()}/rooms/create`, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${token}`
                        },
                        body: JSON.stringify({
                            room_id: roomId,
                            room_name: roomName,
                            max_occupants: 10
                        })
                    });
                    
                    if (!createResponse.ok) {
                        const errorData = await createResponse.json().catch(() => ({ detail: '' }));
                        if (!errorData.detail || !errorData.detail.includes('已存在')) {
                        }
                    }
                } catch (e) {
                }
                
                const joinResponse = await fetch(`${window.ChatCore.getAPIBase()}/rooms/${roomId}/join`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify({
                        display_name: user.nickname || user.username || '用户'
                    })
                });
                
                if (!joinResponse.ok) {
                    const errorData = await joinResponse.json().catch(() => ({ detail: '加入房间失败' }));
                    throw new Error(errorData.detail || '加入房间失败');
                }
                
                const joinData = await joinResponse.json();
                let roomPageUrl = joinData.room_url || 
                    `/room/${joinData.room_id}?jwt=${encodeURIComponent(joinData.jitsi_token)}&server=${encodeURIComponent(joinData.jitsi_server_url)}`;
                const displayName = user.nickname || user.username || '用户';
                roomPageUrl += (roomPageUrl.includes('?') ? '&' : '?') + 'display_name=' + encodeURIComponent(displayName);

                if (!currentChat.isRoom) {
                    try {
                        if (window.ChatCore.tryEnsureSocketConnected) {
                            await window.ChatCore.tryEnsureSocketConnected(5000);
                        }
                    } catch (e) {
                    }
                    const socket = window.ChatCore.getSocket();
                    if (socket && socket.connected) {
                        const invitationData = {
                            target_user_id: currentChat.id,
                            room_id: roomId,
                            room_url: roomPageUrl,
                            jitsi_token: joinData.jitsi_token,
                            jitsi_server_url: joinData.jitsi_server_url,
                            caller_name: user.nickname || user.username || '用户'
                        };
                        socket.emit('call_invitation', invitationData);
                        socket.once('error', (err) => {
                            console.error('✗ 发送通话邀请错误:', err);
                            alert('发送通话邀请失败: ' + (err?.message || '未知错误'));
                        });
                    } else {
                    }
                }
                ChatCalls.openCallInOverlay(roomPageUrl);
            } catch (error) {
                console.error('启动视频通话失败:', error);
                alert('启动视频通话失败: ' + (error.message || '网络错误'));
            }
        },

        showInvitation(data) {
            if (!data) return;
            
            this.currentCallInvitation = data;
            
            const modal = document.getElementById('call-invitation-modal');
            const title = document.getElementById('call-invitation-title');
            const message = document.getElementById('call-invitation-message');
            
            if (!modal || !title) return;
            
            const callerName = data.caller_name || '对方';
            title.textContent = `${callerName}邀请您进入通话`;
            if (message) message.textContent = '对方邀请您进入通话会议，可共享屏幕';
            
            modal.classList.add('show');
        },

        async acceptInvitation() {
            if (!this.currentCallInvitation) return;
            
            const invitation = this.currentCallInvitation;
            this.currentCallInvitation = null;
            
            const modal = document.getElementById('call-invitation-modal');
            if (modal) modal.classList.remove('show');
            
            try {
                const token = window.ChatCore.getToken();
                if (!token) {
                    alert('请先登录');
                    window.location.href = '/login';
                    return;
                }
                
                if (invitation.room_url) {
                    const user = window.ChatCore.getCurrentUser();
                    const displayName = user ? (user.nickname || user.username || '用户') : '用户';
                    const url = invitation.room_url + (invitation.room_url.includes('?') ? '&' : '?') + 'display_name=' + encodeURIComponent(displayName);
                    ChatCalls.openCallInOverlay(url);
                    return;
                }

                const user = window.ChatCore.getCurrentUser();
                if (!user) throw new Error('用户信息未加载');
                
                const joinResponse = await fetch(`${window.ChatCore.getAPIBase()}/rooms/${invitation.room_id}/join`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify({
                        display_name: user.nickname || user.username || '用户'
                    })
                });
                
                if (!joinResponse.ok) {
                    const errorData = await joinResponse.json().catch(() => ({ detail: '加入房间失败' }));
                    throw new Error(errorData.detail || '加入房间失败');
                }
                
                const joinData = await joinResponse.json();
                let roomPageUrl = joinData.room_url || 
                    `/room/${joinData.room_id}?jwt=${encodeURIComponent(joinData.jitsi_token)}&server=${encodeURIComponent(joinData.jitsi_server_url)}`;
                const displayName = user.nickname || user.username || '用户';
                roomPageUrl += (roomPageUrl.includes('?') ? '&' : '?') + 'display_name=' + encodeURIComponent(displayName);
                ChatCalls.openCallInOverlay(roomPageUrl);
            } catch (error) {
                console.error('接受通话邀请失败:', error);
                alert('接受通话邀请失败: ' + (error.message || '网络错误'));
            }
        },

        rejectInvitation() {
            const invitation = this.currentCallInvitation;
            this.currentCallInvitation = null;
            
            const modal = document.getElementById('call-invitation-modal');
            if (modal) modal.classList.remove('show');
            
            const socket = window.ChatCore.getSocket();
            if (socket && invitation) {
                socket.emit('call_invitation_response', {
                    room_id: invitation.room_id,
                    accepted: false
                });
            }
        }
    };

    window.ChatCalls = ChatCalls;
    window.startVideoCall = () => ChatCalls.startVideoCall();
    window.acceptCallInvitation = () => ChatCalls.acceptInvitation();
    window.rejectCallInvitation = () => ChatCalls.rejectInvitation();

    window.addEventListener('message', function onCallOverlayMessage(e) {
        if (e.data && e.data.type === 'jitsi-ready-to-close') {
            if (e.origin !== location.origin) return;
            ChatCalls.closeCallOverlay();
        }
    });
})();
