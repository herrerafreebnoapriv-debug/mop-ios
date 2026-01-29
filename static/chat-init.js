/**
 * 聊天页面初始化
 * 域名检查和组件初始化
 */

(function() {
    'use strict';

    // 允许的聊天域名：log / app / api / 主站 / localhost，便于客户端与网页端同源或跨子域访问
    const allowedHosts = [
        'log.chat5202ol.xyz',
        'app.chat5202ol.xyz',
        'api.chat5202ol.xyz',
        'www.chat5202ol.xyz',
        'chat5202ol.xyz',
        'localhost',
        '127.0.0.1'
    ];
    const hostname = window.location.hostname;
    const allowed = allowedHosts.some(h => hostname === h);
    if (!allowed) {
        alert('即时通讯功能仅支持在已配置域名下访问');
        window.location.href = '/login';
        throw new Error('Invalid domain for chat');
    }
    if (hostname === 'www.chat5202ol.xyz' || hostname === 'chat5202ol.xyz') {
        window.location.href = '/dashboard';
        throw new Error('Redirecting to dashboard');
    }
    // log / app / api / localhost / 127.0.0.1 可继续加载聊天页

    // 页面加载时初始化（仅使用组件化方案）
    window.addEventListener('DOMContentLoaded', () => {
        if (!window.ChatCore || !window.ChatCore.init) {
            console.error('ChatCore 组件未加载，请检查脚本加载顺序');
            alert('核心组件加载失败，请刷新页面');
            return;
        }
        
        window.ChatCore.init().catch((error) => {
            console.error('组件化方案初始化失败:', error);
            alert('初始化失败，请刷新页面重试');
        });
    });

})();
