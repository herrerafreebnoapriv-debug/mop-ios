# 聊天图片功能 - 完成进度

**完成时间**: 2026-01-24

## 一、已完成功能

### 1. 图片发送与展示
- 缩略图 + 原图：支持 data URL 缩略图 + `file_url` 原图，点击查看原图
- HTTP 上传：`/api/v1/files/upload`、`/api/v1/files/upload-photo`，存储至 `uploads/photos/{user_id}/{photo_id}.{ext}`
- 转储组件：`chat-file-dump.js` 通用文件转储（图片/语音/文件），≤200MB，HTTP 优先、超限 base64 走 Socket

### 2. 原图加载与查看
- **ImageLoader**（`chat-image-loader.js`）：状态机（THUMBNAIL_ONLY → LOADING → CACHED），Blob URL 缓存，防重复请求
- **ImageViewer**（`chat-image-viewer.js`）：弹窗查看原图，`handleImageClick(msgId, fileUrl)` 委托 ImageLoader
- **buildAuthenticatedUrl**：统一构建带 token 的图片 URL（`/api/v1/files/photo/{id}`、`/api/v1/files/download` 等）

### 3. 后端图片接口
- **get_photo**（`GET /api/v1/files/photo/{photo_id}`）：JWT（Header 或 query `token`）校验，**全用户目录**搜索 `uploads/photos/*/{photo_id}.{ext}`，接收方可查看发送方上传的图片
- **UPLOAD_PHOTOS_DIR**：使用**绝对路径** `Path(__file__).resolve().../uploads/photos`，避免工作目录导致的 404
- 启动时校验：`main.py` lifespan 打印 `UPLOAD_PHOTOS_DIR` 及存在性

### 4. 其他
- Socket.io 本地化：`/static/socket.io.min.js`（4.5.4），告别 CDN 超时
- 聊天页防缓存：`/chat` 的 `FileResponse` 加 `Cache-Control`，`chat.html` 内 no-cache meta
- 好友请求通知：`friend_request` 弹窗、待处理列表、接受/拒绝

## 二、涉及文件（简要）

| 类型 | 文件 |
|------|------|
| 前端 | `chat-image.js`、`chat-image-loader.js`、`chat-image-viewer.js`、`chat-file-dump.js`、`chat-messages-window.js` |
| 后端 | `app/api/v1/files.py`（get_photo、upload、UPLOAD_PHOTOS_DIR） |
| 静态 | `chat.html`、`chat-styles.css`、`socket.io.min.js` |

## 三、验证要点

- 己方发图 → 缩略图展示 → 点击查看原图 ✅
- 对方收图 → 缩略图展示 → 点击查看原图（同 `get_photo`）✅
- 重启后端后，`UPLOAD_PHOTOS_DIR` 正确、get_photo 返回 200 ✅

---

*下一步：视频通话（见 `PROGRESS_VIDEO_CALL_NEXT.md`）*
