/**
 * 图片发送模块
 * 实现图片上传、缩略图生成、服务器转储等功能
 * 避免嵌套陷阱，代码结构清晰
 */

// ==================== 配置常量 ====================
const IMAGE_CONFIG = {
    MAX_FILE_SIZE: 200 * 1024 * 1024, // 200MB（与 FileDump 组件保持一致）
    THUMBNAIL_THRESHOLD: 500 * 1024, // 500KB，超过此大小使用缩略图方案
    THUMBNAIL_MAX_WIDTH: 200,
    THUMBNAIL_MAX_HEIGHT: 200,
    THUMBNAIL_QUALITY: 0.7,
    SOCKETIO_LIMIT: 5 * 1024 * 1024 // 5MB，Socket.io 限制
};

// ==================== 工具函数 ====================

/**
 * 生成图片缩略图（客户端生成，不增加服务器负载）
 */
function generateThumbnail(file, maxWidth = IMAGE_CONFIG.THUMBNAIL_MAX_WIDTH, maxHeight = IMAGE_CONFIG.THUMBNAIL_MAX_HEIGHT, quality = IMAGE_CONFIG.THUMBNAIL_QUALITY) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            // 计算缩略图尺寸（保持宽高比）
            let width = img.width;
            let height = img.height;
            
            if (width > maxWidth || height > maxHeight) {
                const ratio = Math.min(maxWidth / width, maxHeight / height);
                width = width * ratio;
                height = height * ratio;
            }
            
            // 创建 Canvas 并绘制缩略图
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, width, height);
            
            // 转换为 base64
            const thumbnailBase64 = canvas.toDataURL('image/jpeg', quality);
            resolve(thumbnailBase64);
        };
        img.onerror = reject;
        img.src = URL.createObjectURL(file);
    });
}

/**
 * 将文件转换为 base64
 */
function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}

/**
 * HTTP 上传图片到服务器
 */
async function uploadImageFile(file, apiBase, token) {
    const formData = new FormData();
    formData.append('file', file);
    
    try {
        const response = await fetch(`${apiBase}/files/upload-photo`, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`
            },
            body: formData
        });
        
        if (!response.ok) {
            if (response.status === 413) {
                throw new Error(`文件大小超过服务器限制（最大约 1MB）。请使用较小的图片或压缩后再上传。`);
            }
            
            let errorMessage = '上传失败';
            try {
                const errorData = await response.json();
                errorMessage = errorData.detail || errorData.message || '上传失败';
            } catch (jsonError) {
                const text = await response.text();
                if (text.includes('413') || text.includes('Request Entity Too Large')) {
                    errorMessage = '文件大小超过服务器限制（最大约 1MB）。请使用较小的图片或压缩后再上传。';
                } else if (text.includes('<html>')) {
                    errorMessage = `服务器返回错误 (${response.status}): 请检查文件大小和格式`;
                } else {
                    errorMessage = text.substring(0, 200) || `上传失败 (${response.status})`;
                }
            }
            throw new Error(errorMessage);
        }
        
        const result = await response.json();
        return Array.isArray(result) ? result[0] : result;
    } catch (error) {
        console.error('上传图片失败:', error);
        if (error.message.includes('Unexpected token') || error.message.includes('is not valid JSON')) {
            throw new Error('服务器返回了非 JSON 响应，可能是文件过大或服务器配置问题。请尝试使用较小的图片。');
        }
        throw error;
    }
}

// ==================== 主要功能函数 ====================

/**
 * 发送图片（带缩略图和服务器转储）
 * 
 * @param {File} file - 图片文件
 * @param {Object} options - 配置选项
 * @param {string} options.apiBase - API 基础路径
 * @param {string} options.token - 认证 token
 * @param {Object} options.socket - Socket.io 实例
 * @param {Object} options.currentChat - 当前聊天对象 {id, isRoom}
 * @param {Function} options.onSuccess - 成功回调
 * @param {Function} options.onError - 错误回调
 */
async function sendImageWithThumbnail(file, options) {
    const { apiBase, token, socket, currentChat, onSuccess, onError } = options;
    
    // 检查文件大小
    if (file.size > IMAGE_CONFIG.MAX_FILE_SIZE) {
        const error = `文件大小超过限制（最大 ${IMAGE_CONFIG.MAX_FILE_SIZE / 1024 / 1024}MB）`;
        if (onError) onError(error);
        return;
    }
    
    try {
        let thumbnailBase64 = null;
        let fileUrl = null;
        const fileName = file.name;
        
        // 如果文件较大，生成缩略图
        if (file.size > IMAGE_CONFIG.THUMBNAIL_THRESHOLD) {
            thumbnailBase64 = await generateThumbnail(file);
            
            // 优先尝试 HTTP 上传原图（更高效）
            try {
                const uploadResult = await uploadImageFile(file, apiBase, token);
                fileUrl = `/api/v1/files/photo/${uploadResult.photo_id}`;
            } catch (uploadError) {
                
                // HTTP 上传失败，准备通过 Socket.io 转储技术上传原图
                try {
                    const originalBase64 = await fileToBase64(file);
                    const originalBase64Size = originalBase64.length;
                    
                    // 如果 base64 大小在 Socket.io 限制内（< 5MB），可以通过转储技术处理
                    if (originalBase64Size < IMAGE_CONFIG.SOCKETIO_LIMIT) {
                        // 将原图 base64 保存，稍后通过 Socket.io 发送（会触发转储）
                        window._pendingOriginalImage = {
                            base64: originalBase64,
                            fileName: fileName,
                            fileSize: file.size
                        };
                    } else {
                    }
                } catch (base64Error) {
                    console.error('转换原图为 base64 失败:', base64Error);
                }
            }
        } else {
            // 小文件直接转换为 base64
            thumbnailBase64 = await fileToBase64(file);
        }
        
        // 构建消息数据
        const data = {
            message: thumbnailBase64, // 缩略图或小图片的 base64
            type: 'image'
        };
        
        // 如果有原图 URL，添加到消息中
        if (fileUrl) {
            data.file_url = fileUrl;
            data.file_name = fileName;
            data.file_size = file.size;
        }
        
        if (currentChat.isRoom) {
            data.room_id = currentChat.id;
        } else {
            data.target_user_id = currentChat.id;
        }
        
        if (socket && socket.connected) {
            // 先发送缩略图消息
            socket.emit('send_message', data);
            
            // 如果有待上传的原图（HTTP 上传失败，需要通过 Socket.io 转储），发送原图
            if (window._pendingOriginalImage) {
                const pendingOriginal = window._pendingOriginalImage;
                delete window._pendingOriginalImage; // 清除待上传标记
                
                // 发送原图，触发转储技术（标记为 is_original，即使小于4MB也会转储）
                const originalData = {
                    message: pendingOriginal.base64,
                    type: 'image',
                    file_name: pendingOriginal.fileName,
                    file_size: pendingOriginal.fileSize,
                    is_original: true // 标记这是原图，触发转储以节省网络开销
                };
                
                if (currentChat.isRoom) {
                    originalData.room_id = currentChat.id;
                } else {
                    originalData.target_user_id = currentChat.id;
                }
                
                socket.emit('send_message', originalData);
            }
            
            if (onSuccess) onSuccess();
        } else {
            throw new Error('Socket.io 未连接');
        }
    } catch (error) {
        console.error('发送图片失败:', error);
        if (onError) onError(error.message || '发送图片失败');
    }
}

/**
 * 从相册选择图片
 */
function selectFromAlbum(onImageSelected) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.onchange = (e) => {
        const file = e.target.files[0];
        if (file) {
            onImageSelected(file);
        }
    };
    input.click();
}

/**
 * 拍照（移动端）
 */
function takePhoto(onImageSelected) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.capture = 'environment'; // 使用后置摄像头
    input.onchange = (e) => {
        const file = e.target.files[0];
        if (file) {
            onImageSelected(file);
        }
    };
    input.click();
}

// ==================== 导出函数 ====================
// 将函数暴露到全局作用域，供 chat.html 调用
if (typeof window !== 'undefined') {
    window.ImageModule = {
        sendImageWithThumbnail,
        selectFromAlbum,
        takePhoto,
        generateThumbnail,
        uploadImageFile,
        fileToBase64
    };
}
