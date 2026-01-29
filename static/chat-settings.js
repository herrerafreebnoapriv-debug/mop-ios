/**
 * 设置组件
 * 负责账户设置、修改密码、退出登录等功能
 */

(function() {
    'use strict';

    const ChatSettings = {
        /**
         * 加载设置
         */
        loadSettings() {
            const user = window.ChatCore.getCurrentUser();
            if (user) {
                const usernameEl = document.getElementById('settings-username');
                const phoneEl = document.getElementById('settings-phone');
                const nicknameEl = document.getElementById('settings-nickname');
                const languageEl = document.getElementById('settings-language');
                
                if (usernameEl) usernameEl.textContent = user.username || '未设置';
                if (phoneEl) phoneEl.textContent = user.phone || '未设置';
                if (nicknameEl) nicknameEl.textContent = user.nickname || '未设置';
                if (languageEl) languageEl.textContent = user.language || 'zh_CN';
            }
        },

        /**
         * 显示修改密码模态框
         */
        showChangePasswordModal() {
            const modal = document.getElementById('change-password-modal');
            if (modal) modal.classList.add('show');
        },

        /**
         * 关闭修改密码模态框
         */
        closeChangePasswordModal() {
            const modal = document.getElementById('change-password-modal');
            const form = document.getElementById('change-password-form');
            if (modal) modal.classList.remove('show');
            if (form) form.reset();
        },

        /**
         * 初始化修改密码表单
         */
        init() {
            const form = document.getElementById('change-password-form');
            if (form) {
                form.addEventListener('submit', async (e) => {
                    e.preventDefault();
                    
                    const oldPassword = document.getElementById('old-password').value;
                    const newPassword = document.getElementById('new-password').value;
                    const confirmPassword = document.getElementById('confirm-password').value;
                    
                    if (newPassword !== confirmPassword) {
                        alert('两次输入的密码不一致');
                        return;
                    }
                    
                    if (newPassword.length < 6) {
                        alert('新密码长度至少6位');
                        return;
                    }
                    
                    try {
                        const token = window.ChatCore.getToken();
                        const response = await fetch(`${window.ChatCore.getAPIBase()}/users/me/change-password`, {
                            method: 'POST',
                            headers: {
                                'Authorization': `Bearer ${token}`,
                                'Content-Type': 'application/json'
                            },
                            body: JSON.stringify({
                                old_password: oldPassword,
                                new_password: newPassword
                            })
                        });
                        
                        if (!response.ok) {
                            const error = await response.json();
                            throw new Error(error.detail || '修改密码失败');
                        }
                        
                        alert('密码修改成功');
                        this.closeChangePasswordModal();
                    } catch (error) {
                        console.error('修改密码失败:', error);
                        alert(error.message || '修改密码失败，请重试');
                    }
                });
            }
        },

        /**
         * 退出登录
         */
        async logout() {
            if (!confirm('确定要退出账户吗？')) {
                return;
            }
            
            try {
                const token = window.ChatCore.getToken();
                await fetch(`${window.ChatCore.getAPIBase()}/auth/logout`, {
                    method: 'POST',
                    headers: { 'Authorization': `Bearer ${token}` }
                });
            } catch (error) {
                console.error('退出失败:', error);
            }
            
            // 清除认证信息
            if (window.AuthManager) {
                window.AuthManager.clearTokens();
            } else {
                localStorage.removeItem('access_token');
                localStorage.removeItem('refresh_token');
            }
            
            // 清除消息缓存（可选，也可以保留）
            // if (window.MessageStorage) {
            //     try {
            //         await window.MessageStorage.clearAll();
            //     } catch (e) {
            //         console.warn('清除缓存失败:', e);
            //     }
            // }
            
            window.location.href = '/login';
        }
    };

    // 导出
    window.ChatSettings = ChatSettings;
    window.showChangePasswordModal = () => ChatSettings.showChangePasswordModal();
    window.closeChangePasswordModal = () => ChatSettings.closeChangePasswordModal();
    window.logout = () => ChatSettings.logout();
    
    // 初始化
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => ChatSettings.init());
    } else {
        ChatSettings.init();
    }
    
})();
