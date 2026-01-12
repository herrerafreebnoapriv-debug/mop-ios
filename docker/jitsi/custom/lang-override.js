// 语言文件覆盖 - 替换 "Jitsi Meet" 为 "Messenger of Peace"
// 此文件会在容器启动时注入到页面中

(function() {
    'use strict';
    
    // 等待页面加载
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', replaceJitsiText);
    } else {
        replaceJitsiText();
    }
    
    function replaceJitsiText() {
        // 替换标题
        if (document.title) {
            document.title = document.title.replace(/Jitsi Meet/gi, 'Messenger of Peace');
        }
        
        // 替换 meta 标签
        const metaTags = document.querySelectorAll('meta[property="og:title"], meta[itemprop="name"]');
        metaTags.forEach(tag => {
            if (tag.content) {
                tag.content = tag.content.replace(/Jitsi Meet/gi, 'Messenger of Peace');
            }
        });
        
        // 使用 MutationObserver 监听动态内容变化
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                mutation.addedNodes.forEach(function(node) {
                    if (node.nodeType === 1) { // Element node
                        replaceTextInNode(node);
                    }
                });
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        
        // 初始替换
        replaceTextInNode(document.body);
    }
    
    function replaceTextInNode(node) {
        if (node.nodeType === 3) { // Text node
            node.textContent = node.textContent.replace(/Jitsi Meet/gi, 'Messenger of Peace');
        } else if (node.nodeType === 1) { // Element node
            // 跳过 script 和 style 标签
            if (node.tagName === 'SCRIPT' || node.tagName === 'STYLE') {
                return;
            }
            
            // 替换文本内容
            if (node.childNodes) {
                node.childNodes.forEach(replaceTextInNode);
            }
            
            // 替换属性值
            ['title', 'aria-label', 'alt'].forEach(attr => {
                if (node.hasAttribute(attr)) {
                    const value = node.getAttribute(attr);
                    if (value) {
                        node.setAttribute(attr, value.replace(/Jitsi Meet/gi, 'Messenger of Peace'));
                    }
                }
            });
        }
    }
})();
