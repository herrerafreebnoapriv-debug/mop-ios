/**
 * 图片加载管理器
 * 实现清晰的状态管理，避免"鬼打墙"问题
 * 
 * 状态机：
 * - CACHED: 原图已在本地缓存（Blob URL）
 * - LOADING: 正在从服务器加载原图
 * - THUMBNAIL_ONLY: 只有缩略图，原图未加载
 */

(function() {
    'use strict';

    // 消息状态存储：msgId -> { state, blobUrl, loadingPromise }
    const messageStates = new Map();
    
    // Blob URL 缓存，用于内存管理
    const blobUrlCache = new Map();

    /**
     * 状态枚举
     */
    const ImageState = {
        CACHED: 'cached',           // 原图已缓存
        LOADING: 'loading',         // 正在加载
        THUMBNAIL_ONLY: 'thumbnail_only'  // 只有缩略图
    };

    /**
     * 构建带认证的完整 URL
     */
    function buildAuthenticatedUrl(fileUrl, apiBase, token) {
        if (!fileUrl || !fileUrl.trim()) {
            console.error('❌ buildAuthenticatedUrl: fileUrl 为空');
            return null;
        }
        
        
        let fullUrl = fileUrl;
        
        // 处理不同的 URL 格式
        // 确保 apiBase 是完整的 URL 或正确的相对路径
        let baseUrl = apiBase;
        if (apiBase.startsWith('/')) {
            // 相对路径：使用当前域名
            baseUrl = window.location.origin + apiBase;
        }
        
        if (fileUrl.startsWith('/api/v1/files/photo/')) {
            // 提取 photoId：移除前缀和查询参数
            let photoId = fileUrl.replace('/api/v1/files/photo/', '');
            // 移除查询参数（如果有）
            if (photoId.includes('?')) {
                photoId = photoId.split('?')[0];
            }
            if (photoId.includes('&')) {
                photoId = photoId.split('&')[0];
            }
            // 移除尾部斜杠（如果有）
            photoId = photoId.replace(/\/$/, '');
            
            // 构建完整 URL
            // baseUrl 格式：window.location.origin + apiBase
            if (baseUrl.endsWith('/api/v1')) {
                fullUrl = `${baseUrl}/files/photo/${photoId}`;
            } else if (baseUrl.includes('/api/v1')) {
                // 如果 baseUrl 包含 /api/v1 但不是以它结尾
                fullUrl = `${baseUrl}/files/photo/${photoId}`;
            } else {
                // 如果 baseUrl 格式不对，使用 window.location.origin
                const origin = window.location.origin;
                fullUrl = `${origin}/api/v1/files/photo/${photoId}`;
            }
        } else if (fileUrl.startsWith('/api/v1/files/download')) {
            // 转储文件的下载 URL（已包含查询参数）
            fullUrl = `${baseUrl.replace(/\/api\/v1$/, '')}${fileUrl}`;
        } else if (fileUrl.startsWith('/api/v1/files/')) {
            fullUrl = `${baseUrl.replace(/\/api\/v1$/, '')}${fileUrl}`;
        } else if (fileUrl.startsWith('/api/v1/')) {
            fullUrl = `${baseUrl.replace(/\/api\/v1$/, '')}${fileUrl}`;
        } else if (fileUrl.startsWith('/')) {
            fullUrl = `${baseUrl}${fileUrl}`;
        } else if (!fileUrl.startsWith('http')) {
            fullUrl = `${baseUrl}/files/image/${fileUrl}`;
        } else {
            // 已经是完整 URL
            fullUrl = fileUrl;
        }
        
        // 添加 token 认证
        if (token && !fullUrl.includes('token=')) {
            fullUrl += (fullUrl.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(token);
        }
        
        return fullUrl;
    }

    /**
     * 通过 HTTP 获取原图（不走 Socket）
     */
    async function fetchOriginalImage(fileUrl, apiBase, token) {
        const fullUrl = buildAuthenticatedUrl(fileUrl, apiBase, token);
        if (!fullUrl) {
            throw new Error('无法构建图片 URL');
        }

        try {
            const response = await fetch(fullUrl, {
                method: 'GET',
                headers: {
                    'Authorization': `Bearer ${token}`
                }
            });

            if (!response.ok) {
                const errorText = await response.text().catch(() => '无法读取错误信息');
                console.error('❌ HTTP 错误响应:', {
                    status: response.status,
                    statusText: response.statusText,
                    errorText: errorText,
                    url: fullUrl,
                    headers: Object.fromEntries(response.headers.entries())
                });
                // 提供更详细的错误信息
                let errorMsg = `HTTP ${response.status}`;
                if (response.status === 404) {
                    errorMsg += ': 图片不存在，可能已被删除或路径错误';
                    const photoId = fileUrl.startsWith('/api/v1/files/photo/')
                        ? fileUrl.replace('/api/v1/files/photo/', '').split('?')[0].split('&')[0]
                        : '(非 photo URL)';
                    console.error('❌ 404 错误详情:', {
                        '请求 URL': fullUrl,
                        '原始 fileUrl': fileUrl,
                        'photoId': photoId,
                        'apiBase': apiBase
                    });
                } else if (response.status === 401) {
                    errorMsg += ': 认证失败，请重新登录';
                } else if (response.status === 403) {
                    errorMsg += ': 无权访问此图片';
                } else {
                    errorMsg += `: ${response.statusText}`;
                }
                throw new Error(errorMsg);
            }

            // 获取 Blob，不要转成 Base64
            const blob = await response.blob();
            
            return blob;
        } catch (error) {
            console.error('❌ fetchOriginalImage 异常:', error);
            throw error;
        }
    }

    /**
     * 状态判断：检查消息的图片状态
     */
    function getMessageState(msgId) {
        const state = messageStates.get(msgId);
        if (!state) {
            return ImageState.THUMBNAIL_ONLY;
        }
        return state.state;
    }

    /**
     * 点击缩略图处理器（状态机入口）
     */
    async function handleThumbnailClick(msgId, fileUrl, apiBase, token, onSuccess, onError) {
        // 1. 状态判断 (The Gatekeeper)
        const currentState = getMessageState(msgId);
        
        // 状态 A：原图已在本地缓存
        if (currentState === ImageState.CACHED) {
            const state = messageStates.get(msgId);
            if (onSuccess) onSuccess(state.blobUrl);
            return state.blobUrl;
        }
        
        // 状态 B：正在从服务器转储
        if (currentState === ImageState.LOADING) {
            const state = messageStates.get(msgId);
            // 等待正在进行的加载完成
            try {
                const blobUrl = await state.loadingPromise;
                if (onSuccess) onSuccess(blobUrl);
                return blobUrl;
            } catch (error) {
                console.error('❌ 等待加载失败:', error);
                if (onError) onError(error);
                throw error;
            }
        }
        
        // 状态 C：只有缩略图，启动转储
        
        // 设置加载状态
        const loadingPromise = fetchOriginalImage(fileUrl, apiBase, token)
            .then(blob => {
                // 创建 Blob URL（不要转 Base64）
                const blobUrl = URL.createObjectURL(blob);
                
                // 更新状态为已缓存
                messageStates.set(msgId, {
                    state: ImageState.CACHED,
                    blobUrl: blobUrl,
                    loadingPromise: null
                });
                
                // 记录 Blob URL 用于后续清理
                blobUrlCache.set(msgId, blobUrl);
                
                return blobUrl;
            })
            .catch(error => {
                // 加载失败，重置状态
                messageStates.delete(msgId);
                console.error('❌ 原图转储失败:', error);
                throw error;
            });
        
        // 设置加载中状态
        messageStates.set(msgId, {
            state: ImageState.LOADING,
            blobUrl: null,
            loadingPromise: loadingPromise
        });
        
        try {
            const blobUrl = await loadingPromise;
            if (onSuccess) onSuccess(blobUrl);
            return blobUrl;
        } catch (error) {
            if (onError) onError(error);
            throw error;
        }
    }

    /**
     * 清理消息的 Blob URL（防止内存泄露）
     */
    function revokeMessageBlobUrl(msgId) {
        const blobUrl = blobUrlCache.get(msgId);
        if (blobUrl) {
            URL.revokeObjectURL(blobUrl);
            blobUrlCache.delete(msgId);
        }
        messageStates.delete(msgId);
    }

    /**
     * 批量清理所有 Blob URL（页面卸载时调用）
     */
    function revokeAllBlobUrls() {
        for (const [msgId, blobUrl] of blobUrlCache.entries()) {
            URL.revokeObjectURL(blobUrl);
        }
        blobUrlCache.clear();
        messageStates.clear();
    }

    /**
     * 获取已缓存的原图 URL（如果存在）
     */
    function getCachedOriginalUrl(msgId) {
        const state = messageStates.get(msgId);
        if (state && state.state === ImageState.CACHED) {
            return state.blobUrl;
        }
        return null;
    }

    // 页面卸载时清理所有 Blob URL
    if (typeof window !== 'undefined') {
        window.addEventListener('beforeunload', revokeAllBlobUrls);
    }

    // 导出 API
    window.ImageLoader = {
        handleThumbnailClick: handleThumbnailClick,
        getMessageState: getMessageState,
        getCachedOriginalUrl: getCachedOriginalUrl,
        revokeMessageBlobUrl: revokeMessageBlobUrl,
        revokeAllBlobUrls: revokeAllBlobUrls,
        buildAuthenticatedUrl: buildAuthenticatedUrl,
        ImageState: ImageState
    };

})();
