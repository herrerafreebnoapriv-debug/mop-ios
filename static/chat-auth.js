/**
 * 认证和 Token 管理模块
 * 负责 token 的存储、刷新和验证
 */

(function() {
    'use strict';

    const AuthManager = {
        API_BASE: '/api/v1',
        TOKEN_REFRESH_INTERVAL: 5 * 60 * 1000, // 5分钟检查一次
        TOKEN_EXPIRY_BUFFER: 2 * 60 * 1000, // 提前2分钟刷新
        refreshTimer: null,
        isRefreshing: false,

        /**
         * 获取 access token
         */
        getAccessToken() {
            return localStorage.getItem('access_token');
        },

        /**
         * 获取 refresh token
         */
        getRefreshToken() {
            return localStorage.getItem('refresh_token');
        },

        /**
         * 保存 tokens
         */
        saveTokens(accessToken, refreshToken) {
            if (accessToken) {
                localStorage.setItem('access_token', accessToken);
            }
            if (refreshToken) {
                localStorage.setItem('refresh_token', refreshToken);
            }
        },

        /**
         * 清除 tokens
         */
        clearTokens() {
            localStorage.removeItem('access_token');
            localStorage.removeItem('refresh_token');
            localStorage.removeItem('user_info');
            this.stopAutoRefresh();
        },

        /**
         * 保存用户信息
         */
        saveUserInfo(userInfo) {
            if (userInfo) {
                localStorage.setItem('user_info', JSON.stringify(userInfo));
            }
        },

        /**
         * 获取用户信息
         */
        getUserInfo() {
            const userInfoStr = localStorage.getItem('user_info');
            if (userInfoStr) {
                try {
                    return JSON.parse(userInfoStr);
                } catch (e) {
                    console.error('解析用户信息失败:', e);
                    return null;
                }
            }
            return null;
        },

        /**
         * 检查 token 是否即将过期
         */
        isTokenExpiringSoon(token) {
            if (!token) return true;
            
            try {
                // 解析 JWT token（不验证签名，只获取过期时间）
                const payload = JSON.parse(atob(token.split('.')[1]));
                const exp = payload.exp * 1000; // 转换为毫秒
                const now = Date.now();
                const timeUntilExpiry = exp - now;
                
                // 如果剩余时间少于缓冲时间，需要刷新
                return timeUntilExpiry < this.TOKEN_EXPIRY_BUFFER;
            } catch (e) {
                console.error('解析 token 失败:', e);
                return true; // 解析失败，认为需要刷新
            }
        },

        /**
         * 刷新 token
         */
        async refreshToken() {
            if (this.isRefreshing) {
                console.log('Token 正在刷新中，跳过重复请求');
                return false;
            }

            const refreshToken = this.getRefreshToken();
            if (!refreshToken) {
                console.warn('没有 refresh token，无法刷新');
                return false;
            }

            this.isRefreshing = true;

            try {
                const response = await fetch(`${this.API_BASE}/auth/refresh`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        refresh_token: refreshToken
                    })
                });

                if (!response.ok) {
                    const error = await response.json().catch(() => ({ detail: '刷新 token 失败' }));
                    throw new Error(error.detail || '刷新 token 失败');
                }

                const data = await response.json();
                
                if (data.access_token) {
                    this.saveTokens(data.access_token, data.refresh_token);
                    console.log('✓ Token 刷新成功');
                    
                    // 触发 token 更新事件
                    window.dispatchEvent(new CustomEvent('tokenRefreshed', {
                        detail: { accessToken: data.access_token }
                    }));
                    
                    return true;
                } else {
                    throw new Error('刷新 token 响应中缺少 access_token');
                }
            } catch (error) {
                console.error('刷新 token 失败:', error);
                
                // 刷新失败，清除 tokens 并触发登出事件
                this.clearTokens();
                window.dispatchEvent(new CustomEvent('tokenRefreshFailed'));
                
                return false;
            } finally {
                this.isRefreshing = false;
            }
        },

        /**
         * 验证 token 有效性
         */
        async validateToken() {
            const token = this.getAccessToken();
            if (!token) {
                return false;
            }

            try {
                const response = await fetch(`${this.API_BASE}/auth/me`, {
                    headers: {
                        'Authorization': `Bearer ${token}`
                    }
                });

                if (response.ok) {
                    const userInfo = await response.json();
                    this.saveUserInfo(userInfo);
                    return true;
                } else {
                    // Token 无效，尝试刷新
                    if (response.status === 401) {
                        return await this.refreshToken();
                    }
                    return false;
                }
            } catch (error) {
                console.error('验证 token 失败:', error);
                return false;
            }
        },

        /**
         * 启动自动刷新
         */
        startAutoRefresh() {
            this.stopAutoRefresh(); // 先清除旧的定时器

            // 立即检查一次
            this.checkAndRefreshToken();

            // 设置定期检查
            this.refreshTimer = setInterval(() => {
                this.checkAndRefreshToken();
            }, this.TOKEN_REFRESH_INTERVAL);

            console.log('✓ Token 自动刷新已启动');
        },

        /**
         * 停止自动刷新
         */
        stopAutoRefresh() {
            if (this.refreshTimer) {
                clearInterval(this.refreshTimer);
                this.refreshTimer = null;
            }
        },

        /**
         * 检查并刷新 token
         */
        async checkAndRefreshToken() {
            const token = this.getAccessToken();
            if (!token) {
                return;
            }

            if (this.isTokenExpiringSoon(token)) {
                console.log('Token 即将过期，开始刷新...');
                await this.refreshToken();
            }
        },

        /**
         * 确保 token 有效（如果无效则刷新）
         */
        async ensureValidToken() {
            const token = this.getAccessToken();
            if (!token) {
                return null;
            }

            // 如果 token 即将过期，先刷新
            if (this.isTokenExpiringSoon(token)) {
                const refreshed = await this.refreshToken();
                if (!refreshed) {
                    return null;
                }
            }

            return this.getAccessToken();
        },

        /**
         * 带自动刷新的 fetch 封装
         */
        async fetchWithAuth(url, options = {}) {
            // 确保 token 有效
            const token = await this.ensureValidToken();
            if (!token) {
                throw new Error('未登录或 token 无效');
            }

            // 设置 Authorization header
            const headers = {
                ...options.headers,
                'Authorization': `Bearer ${token}`
            };

            let response = await fetch(url, {
                ...options,
                headers
            });

            // 如果返回 401，尝试刷新 token 后重试一次
            if (response.status === 401) {
                const refreshed = await this.refreshToken();
                if (refreshed) {
                    // 使用新 token 重试
                    headers['Authorization'] = `Bearer ${this.getAccessToken()}`;
                    response = await fetch(url, {
                        ...options,
                        headers
                    });
                }
            }

            return response;
        }
    };

    // 监听页面可见性变化，恢复时检查 token
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden) {
            // 页面变为可见时，检查 token
            AuthManager.checkAndRefreshToken();
        }
    });

    // 监听网络恢复事件
    window.addEventListener('online', () => {
        AuthManager.checkAndRefreshToken();
    });

    // 导出到全局
    window.AuthManager = AuthManager;

})();
