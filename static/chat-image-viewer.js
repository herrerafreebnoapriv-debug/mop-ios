/**
 * 图片查看器组件
 */

(function() {
    'use strict';

    const ChatImageViewer = {
        /**
         * 显示图片
         */
        show(imageSrc) {
            const modal = document.getElementById('image-viewer-modal');
            const img = document.getElementById('image-viewer-img');
            if (!modal || !img) return;
            
            img.style.display = 'none';
            img.src = '';
            
            const existingLoading = document.getElementById('image-loading');
            if (existingLoading) existingLoading.remove();
            
            const loadingDiv = document.createElement('div');
            loadingDiv.id = 'image-loading';
            loadingDiv.style.cssText = 'position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); color: white; font-size: 16px; z-index: 1001;';
            loadingDiv.textContent = '加载中...';
            const contentDiv = modal.querySelector('.image-viewer-content');
            if (contentDiv) contentDiv.appendChild(loadingDiv);
            
            modal.classList.add('show');
            document.body.style.overflow = 'hidden';
            
            let imageUrl = imageSrc;
            if (!imageSrc.startsWith('blob:') && !imageSrc.startsWith('data:')) {
                if (imageSrc.includes('/api/v1/files/') && !imageSrc.includes('token=')) {
                    const token = window.ChatCore.getToken();
                    if (token) {
                        imageUrl = imageSrc + (imageSrc.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
                    }
                }
            }
            
            const tempImg = new Image();
            tempImg.onload = () => {
                img.src = imageUrl;
                img.style.display = 'block';
                const loading = document.getElementById('image-loading');
                if (loading) loading.remove();
            };
            tempImg.onerror = () => {
                const loading = document.getElementById('image-loading');
                if (loading) {
                    loading.textContent = '图片加载失败';
                    loading.style.color = '#ff4444';
                }
            };
            tempImg.src = imageUrl;
        },

        /**
         * 关闭图片查看器
         */
        close() {
            const modal = document.getElementById('image-viewer-modal');
            if (modal) {
                modal.classList.remove('show');
                document.body.style.overflow = '';
            }
        },

        /**
         * 处理图片点击
         */
        async handleImageClick(msgId, fileUrl) {
            if (!window.ImageLoader) {
                alert('图片加载管理器未初始化');
                return;
            }
            
            const token = window.ChatCore.getToken();
            if (!token) {
                alert('请先登录');
                return;
            }
            
            const loadingToast = document.createElement('div');
            loadingToast.id = 'image-loading-toast';
            loadingToast.style.cssText = 'position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: rgba(0,0,0,0.8); color: white; padding: 15px 25px; border-radius: 8px; z-index: 10000; font-size: 14px;';
            loadingToast.textContent = '正在加载原图...';
            document.body.appendChild(loadingToast);
            
            try {
                const blobUrl = await window.ImageLoader.handleThumbnailClick(
                    msgId,
                    fileUrl,
                    window.ChatCore.getAPIBase(),
                    token,
                    () => {},
                    (error) => {
                        if (loadingToast) loadingToast.remove();
                        alert('加载原图失败: ' + (error.message || '网络错误'));
                    }
                );
                
                if (loadingToast) loadingToast.remove();
                this.show(blobUrl);
            } catch (error) {
                console.error('图片点击处理失败:', error);
                if (loadingToast) loadingToast.remove();
                alert('加载原图失败: ' + (error.message || '网络错误'));
            }
        }
    };

    // 导出
    window.ChatImageViewer = ChatImageViewer;
    window.closeImageViewer = () => ChatImageViewer.close();
    window.showImageViewer = (src) => ChatImageViewer.show(src);
    
})();
