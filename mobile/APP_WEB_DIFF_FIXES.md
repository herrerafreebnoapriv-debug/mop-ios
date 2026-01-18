# App与网页端差异修复计划

## 发现的问题

### 1. ✅ 多国语言支持不完整
- **状态**: 仅实现了 `zh_CN.json` 和 `en_US.json`
- **缺失**: `zh_TW.json`, `ja_JP.json`, `ko_KR.json` 等
- **影响**: 用户无法切换到日文、韩文、繁体中文等语言

### 2. ✅ 登录页面语言按钮被覆盖
- **位置**: `lib/screens/auth/login_screen.dart` 第89-147行
- **问题**: 语言选择器使用 `Positioned` 但可能被登录表单覆盖
- **解决方案**: 调整 z-index 或使用 `SafeArea` + `Stack` 优化布局

### 3. ✅ 消息页面右上角搜索和添加按钮未实现
- **位置**: 
  - `lib/screens/chat/chat_main_screen.dart` 第56-78行（AppBar actions）
  - `lib/screens/chat/messages_tab.dart` 第226-232行（FloatingActionButton）
- **问题**: 按钮存在但功能未连接，需要实现搜索和添加好友功能

### 4. ✅ 聊天窗口左侧语音按钮缺失
- **位置**: `lib/screens/chat/chat_window_screen.dart`
- **问题**: 输入框左侧缺少语音录制按钮（网页端有 🎤 按钮）
- **参考**: 网页端 `chat.html` 第987行和1649-1799行的语音录制逻辑

### 5. ✅ 消息输入框右侧+按钮功能不完整
- **位置**: `lib/screens/chat/chat_window_screen.dart` 第608-639行
- **当前功能**: 仅支持图片和文件
- **缺失功能**: 拍照、视频通话（网页端有这些选项）
- **参考**: 网页端 `chat.html` 第993-1010行的功能菜单

## 修复优先级

1. **高优先级**: 
   - 登录页面语言按钮覆盖问题（影响用户体验）
   - 消息页面搜索和添加功能（核心功能）

2. **中优先级**:
   - 语音按钮和功能菜单完善（增强功能）

3. **低优先级**:
   - 多语言文件补充（可逐步完善）

## 参考网页端实现

### 语音录制功能
- 位置: `static/chat.html` 第1669-1799行
- 功能: 按住录音，松开发送，使用 MediaRecorder API

### 功能菜单
- 位置: `static/chat.html` 第993-1010行
- 选项: 相册、拍照、视频通话、文件

### 搜索和添加
- 搜索: `chat.html` 第1019行，点击搜索按钮切换搜索输入框
- 添加: `chat.html` 第1020行，打开添加好友对话框
