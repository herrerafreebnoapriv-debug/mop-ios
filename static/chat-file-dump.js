/**
 * 通用文件转储组件
 * 用于处理所有超出 Socket.io 大小限制的文件（图片、语音、文件等）
 * 支持二进制数据（Blob/File）和 base64 数据 URI
 */

(function() {
    'use strict';

    // Socket.io 消息大小阈值（超过此值将触发文件转储）
    const MESSAGE_SIZE_THRESHOLD = 4 * 1024 * 1024; // 4MB
    
    // 文件大小上限（200MB）
    const MAX_FILE_SIZE = 200 * 1024 * 1024; // 200MB

    /**
     * 将文件转换为 base64 数据 URI
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
     * 尝试通过 HTTP 上传文件到服务器
     * @param {File|Blob} file - 要上传的文件
     * @param {string} apiBase - API 基础路径
     * @param {string} token - 认证 token
     * @param {string} preferredFileName - 首选文件名（如果 file 是 Blob 且没有 name）
     * @returns {Promise<string|null>} 返回 file_url 或 null
     */
    async function uploadFileViaHTTP(file, apiBase, token, preferredFileName) {
        try {
            const formData = new FormData();
            // 如果 file 是 Blob 且没有 name，使用 preferredFileName 或创建一个 File 对象
            let fileToUpload = file;
            if (file instanceof Blob && !file.name && preferredFileName) {
                fileToUpload = new File([file], preferredFileName, { type: file.type || 'audio/webm' });
            }
            formData.append('file', fileToUpload);

            // 使用通用上传端点
            const response = await fetch(`${apiBase}/files/upload`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`
                },
                body: formData
            });

            if (!response.ok) {
                const errorText = await response.text().catch(() => '');
                return null;
            }

            const result = await response.json();
            const fileUrl = result.file_url || null;
            // 注意：不直接使用 result.file_name，因为可能不准确（如 "blob"）
            // 文件名应该由调用方通过 messageData.file_name 提供
            
            return fileUrl;
        } catch (error) {
            return null;
        }
    }

    /**
     * 发送文件消息（自动选择最佳传输方式）
     * @param {File|Blob} file - 要发送的文件
     * @param {Object} options - 选项
     * @param {string} options.messageType - 消息类型 (image/audio/file)
     * @param {string} options.apiBase - API 基础路径
     * @param {string} options.token - 认证 token
     * @param {Function} options.socketEmit - Socket.io emit 函数
     * @param {Object} options.messageData - 额外的消息数据（target_user_id, room_id 等）
     * @returns {Promise<Object>} 返回发送结果
     */
    async function sendFileWithDump(file, options) {
        const {
            messageType = 'file',
            apiBase,
            token,
            socketEmit,
            messageData = {},
            fileName: fileNameOverride,
            duration
        } = options;

        const fileName = fileNameOverride || file.name || `文件.${file.type ? file.type.split('/')[1] : 'bin'}`;
        const fileSize = file.size;
        
        // 检查文件大小限制（200MB）
        if (fileSize > MAX_FILE_SIZE) {
            const fileSizeMB = (fileSize / (1024 * 1024)).toFixed(2);
            const maxSizeMB = (MAX_FILE_SIZE / (1024 * 1024)).toFixed(0);
            const errorMsg = `文件过大（${fileSizeMB}MB），最大支持 ${maxSizeMB}MB`;
            console.error('❌', errorMsg);
            throw new Error(errorMsg);
        }

        // 1. 尝试 HTTP 上传（适用于所有文件类型）
        let fileUrl = null;
        if (apiBase && token) {
            // 传递首选文件名（用于 Blob 对象）
            const preferredFileName = messageData.file_name || fileNameOverride || file.name;
            fileUrl = await uploadFileViaHTTP(file, apiBase, token, preferredFileName);
            if (fileUrl) {
            }
        }

        // 2. 检查文件大小，决定是否需要转储
        const needsDump = fileSize > MESSAGE_SIZE_THRESHOLD;
        // 语音和文件类型总是需要转储（不直接发送二进制）
        const shouldDump = needsDump || (messageType === 'voice' || messageType === 'audio' || messageType === 'file');

        // 3. 构建消息数据（duration 由 messageData 提供，如语音消息）
        // 确保 type 字段不会被 messageData 中的其他字段覆盖
        const data = {
            ...messageData,
            type: messageType,
            file_name: messageData.file_name || fileName,
            file_size: fileSize
        };
        // 语音消息：添加冗余字段 message_type，避免 type 被中间层丢弃
        if (messageType === 'audio' || messageType === 'voice') {
            data.message_type = 'audio';
        }

        if (fileUrl) {
            // HTTP 上传成功：直接使用 file_url
            data.file_url = fileUrl;
            // 对于图片，生成缩略图；对于其他类型，不发送 base64
            if (messageType === 'image') {
                // 图片：生成缩略图作为 message 内容
                const thumbnail = await generateThumbnail(file);
                data.message = thumbnail;
            } else if (messageType === 'voice' || messageType === 'audio' || messageType === 'file') {
                // 语音/文件：不发送 base64，只发送 file_url
                data.message = '';
            } else {
                // 其他类型：发送原始 base64
                const base64DataUri = await fileToBase64(file);
                data.message = base64DataUri;
            }
        } else if (shouldDump) {
            // HTTP 上传失败，但需要转储：转换为 base64 让服务器转储
            const base64DataUri = await fileToBase64(file);
            data.message = base64DataUri;
            data.is_original = true; // 标记为需要转储
        } else {
            // 小文件且 HTTP 上传失败：直接发送 base64
            const base64DataUri = await fileToBase64(file);
            data.message = base64DataUri;
        }

        // 4. 通过 Socket.io 发送消息
        socketEmit('send_message', data);

        return {
            success: true,
            fileUrl: fileUrl,
            messageType: messageType
        };
    }

    /**
     * 生成图片缩略图（用于图片消息）
     */
    function generateThumbnail(file) {
        return new Promise((resolve, reject) => {
            if (!file.type.startsWith('image/')) {
                reject(new Error('不是图片文件'));
                return;
            }

            const reader = new FileReader();
            reader.onloadend = () => {
                const img = new Image();
                img.onload = () => {
                    const canvas = document.createElement('canvas');
                    const maxSize = 200;
                    let width = img.width;
                    let height = img.height;

                    if (width > height) {
                        if (width > maxSize) {
                            height = (height * maxSize) / width;
                            width = maxSize;
                        }
                    } else {
                        if (height > maxSize) {
                            width = (width * maxSize) / height;
                            height = maxSize;
                        }
                    }

                    canvas.width = width;
                    canvas.height = height;
                    const ctx = canvas.getContext('2d');
                    ctx.drawImage(img, 0, 0, width, height);

                    const thumbnail = canvas.toDataURL('image/jpeg', 0.8);
                    resolve(thumbnail);
                };
                img.onerror = reject;
                img.src = reader.result;
            };
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    // 导出 API
    window.FileDump = {
        sendFileWithDump: sendFileWithDump,
        MESSAGE_SIZE_THRESHOLD: MESSAGE_SIZE_THRESHOLD,
        MAX_FILE_SIZE: MAX_FILE_SIZE,
        fileToBase64: fileToBase64,
        uploadFileViaHTTP: uploadFileViaHTTP
    };

})();
