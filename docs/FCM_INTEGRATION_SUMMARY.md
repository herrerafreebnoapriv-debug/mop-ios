# FCM 集成完成总结

## ✅ 已完成的工作

### 1. 聊天记录中视频邀请消息显示问题（已修复）

**问题**：系统消息（视频通话邀请）在聊天记录中不显示或没有「接受/拒绝」按钮。

**修复**：
- ✅ 修复了 `_loadMessages` 中系统消息的过滤逻辑
- ✅ 确保 `message_type == 'system'` 且 `receiver_id == 当前用户`、`sender_id == 目标用户` 的消息能正确显示
- ✅ `_getCallInvitation` 函数能正确从 `call_invitation` 或 `extra_data.call_invitation` 解析数据
- ✅ `_SystemMessageWidget` 正确显示接受/拒绝按钮

**测试**：打开聊天窗口，应该能看到视频通话邀请的系统消息，带「接受/拒绝」按钮。

---

### 2. FCM 集成（代码已完成，需配置 Firebase）

#### App 端
- ✅ 添加 `firebase_core: ^2.24.2` 和 `firebase_messaging: ^14.7.9` 依赖
- ✅ 创建 `FCMService` 服务类
  - 自动初始化 Firebase
  - 获取 FCM token 并上传到后端
  - 监听前台和后台推送消息
  - 处理 `VIDEO_CALL` 类型推送，显示全屏通知
- ✅ 在 `main.dart` 中初始化 FCM 和后台消息处理器
- ✅ 通知服务已配置全屏意图（`fullScreenIntent: true`）

#### 后端
- ✅ 创建 `app/services/push_notification.py` 推送服务
- ✅ 在 `call_invitation` 中调用推送服务（发送 FCM 推送）
- ✅ 设备注册 API 支持 `fcm_token` 和 `platform` 参数
- ✅ FCM token 临时存储在 `UserDevice.ext_field_1`（JSON 格式）

---

### 3. Android 权限

- ✅ `POST_NOTIFICATIONS`（Android 13+ 必需）
- ✅ `USE_FULL_SCREEN_INTENT`（用于全屏通话界面）

---

## ⚠️ 需要配置的步骤

### 步骤 1：创建 Firebase 项目并配置 Android

1. 访问 [Firebase Console](https://console.firebase.google.com/)
2. 创建项目或使用现有项目
3. 添加 Android App（包名：`com.mop.app`）
4. 下载 `google-services.json` 放到 `mobile/android/app/`
5. 在 `mobile/android/build.gradle` 添加：
   ```gradle
   dependencies {
       classpath 'com.google.gms:google-services:4.4.0'
   }
   ```
6. 在 `mobile/android/app/build.gradle` 末尾添加：
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

### 步骤 2：获取 FCM Server Key

1. Firebase Console → 项目设置 → 服务账号
2. 生成新的私钥或使用「Cloud Messaging」标签下的服务器密钥

### 步骤 3：配置后端环境变量

```bash
export FCM_SERVER_KEY="你的FCM服务器密钥"
```

### 步骤 4：安装 Python FCM 库

```bash
pip install pyfcm
```

---

## 📋 功能流程

### 场景 1：App 在前台

1. 用户 A 发起视频通话 → 后端创建系统消息并发送 Socket 事件
2. 用户 B（App 在前台）收到：
   - ✅ Socket `call_invitation` 事件 → 显示弹窗
   - ✅ Socket `message` 事件（系统消息）→ 聊天记录中显示带按钮的系统消息
   - ✅ FCM 推送（可选，用于冗余）

### 场景 2：App 在后台或手机黑屏

1. 用户 A 发起视频通话 → 后端创建系统消息并发送 FCM 推送
2. 用户 B（App 在后台）收到：
   - ✅ FCM 推送通知（高优先级）→ 唤醒 App 并显示全屏通话界面
   - ✅ 当 App 打开后，从 API 拉取历史消息 → 聊天记录中显示系统消息

---

## 🧪 测试清单

### 测试 1：聊天记录显示视频邀请

- [ ] 用户 A 发起视频通话
- [ ] 用户 B 打开与 A 的聊天窗口
- [ ] 应该看到系统消息：「📹 [A的名字] 邀请您进行视频通话」
- [ ] 系统消息下方有「拒绝」和「接受」按钮
- [ ] 点击「接受」能正常加入视频通话

### 测试 2：FCM 推送（需配置 Firebase）

- [ ] 配置 Firebase 项目
- [ ] 启动 App 并登录
- [ ] 查看日志，确认 FCM token 已获取并上传
- [ ] 用户 A 发起视频通话
- [ ] 用户 B 的 App 在后台或手机黑屏
- [ ] 应该收到 FCM 推送通知
- [ ] 点击通知后显示全屏通话界面

---

## 📝 相关文档

- **FCM 配置指南**：`docs/FCM_SETUP_GUIDE.md`
- **推送通知实现指南**：`docs/VIDEO_CALL_PUSH_NOTIFICATION_IMPLEMENTATION.md`
- **问题排查**：`docs/VIDEO_CALL_INVITATION_WHY_IT_FAILED.md`

---

## 🎯 下一步

1. **配置 Firebase**：按照 `FCM_SETUP_GUIDE.md` 完成 Firebase 项目配置
2. **测试聊天记录**：验证视频邀请系统消息是否正确显示
3. **测试推送通知**：配置 FCM 后测试后台推送功能
