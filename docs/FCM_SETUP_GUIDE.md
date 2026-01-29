# FCM 集成配置指南

## 一、已完成的工作

### ✅ App 端
- 添加 `firebase_core` 和 `firebase_messaging` 依赖
- 创建 `FCMService` 服务（自动初始化、获取 token、监听推送）
- 在 `main.dart` 中初始化 FCM 和后台消息处理器
- 通知服务已配置全屏意图（`fullScreenIntent: true`）

### ✅ 后端
- 创建 `app/services/push_notification.py` 推送服务
- 在 `call_invitation` 中调用推送服务
- 设备注册 API 支持 `fcm_token` 和 `platform` 参数
- FCM token 临时存储在 `UserDevice.ext_field_1`（JSON 格式）

### ✅ 聊天记录修复
- 修复 `_loadMessages` 中系统消息的过滤逻辑
- 确保视频邀请系统消息能正确显示在聊天记录中

---

## 二、需要配置的步骤

### 步骤 1：创建 Firebase 项目

1. 访问 [Firebase Console](https://console.firebase.google.com/)
2. 创建新项目（或使用现有项目）
3. 添加 Android App：
   - 包名：`com.mop.app`
   - 下载 `google-services.json`
   - 放到 `mobile/android/app/` 目录

### 步骤 2：配置 Android 项目

#### 2.1 添加 Google Services 插件

在 `mobile/android/build.gradle`（项目级）的 `dependencies` 中添加：

```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

#### 2.2 应用插件

在 `mobile/android/app/build.gradle` 文件**末尾**添加：

```gradle
apply plugin: 'com.google.gms.google-services'
```

#### 2.3 放置配置文件

确保 `google-services.json` 在 `mobile/android/app/` 目录下。

### 步骤 3：获取 FCM Server Key

1. 在 Firebase Console 中，进入项目设置
2. 选择「服务账号」标签
3. 点击「生成新的私钥」，下载 JSON 文件
4. 或者使用「Cloud Messaging」标签下的「服务器密钥」

### 步骤 4：配置后端环境变量

在服务器上设置环境变量：

```bash
export FCM_SERVER_KEY="你的FCM服务器密钥"
```

或在 `.env` 文件中：

```
FCM_SERVER_KEY=你的FCM服务器密钥
```

### 步骤 5：安装 Python FCM 库

```bash
pip install pyfcm
```

---

## 三、测试流程

### 1. 测试 FCM Token 上传

1. 启动 App 并登录
2. 查看日志，应该看到：
   ```
   ✓ 获取到 FCM Token: ...
   ✓ FCM Token 已上传到后端
   ```

### 2. 测试推送通知

1. 用户 A 发起视频通话给用户 B
2. 如果用户 B 的 App 在后台或手机黑屏：
   - 应该收到 FCM 推送通知
   - 点击通知后应显示全屏通话界面
3. 如果用户 B 的 App 在前台：
   - 应该收到 Socket `call_invitation` 事件
   - 应该显示弹窗和聊天记录中的系统消息

### 3. 检查后端日志

```bash
tail -f /var/log/mop-backend.log | grep -i "fcm\|推送\|push"
```

应该看到：
```
✓ FCM 推送已发送给用户 X，结果: {...}
```

---

## 四、故障排查

### 问题 1：FCM Token 未获取

**可能原因**：
- Firebase 未正确初始化
- `google-services.json` 未放置或格式错误

**解决**：
- 检查 `mobile/android/app/google-services.json` 是否存在
- 检查 `build.gradle` 是否正确配置

### 问题 2：推送通知未收到

**可能原因**：
- FCM Server Key 未配置或错误
- `pyfcm` 未安装
- 设备 FCM token 未上传到后端

**解决**：
- 检查环境变量 `FCM_SERVER_KEY`
- 运行 `pip install pyfcm`
- 检查后端日志，确认 token 是否已存储

### 问题 3：聊天记录中看不到视频邀请

**已修复**：系统消息过滤逻辑已更新，应该能正确显示。

如果仍看不到，检查：
- 后端 `get_messages` API 是否返回 `extra_data`
- 前端 `_getCallInvitation` 是否能正确解析

---

## 五、临时方案（Firebase 未配置时）

如果暂时无法配置 Firebase，系统会：
- **静默失败**：FCM 初始化失败不影响其他功能
- **Socket 推送仍有效**：App 在前台时仍能收到 Socket 事件
- **本地通知**：收到 `call_invitation` 时显示本地通知（全屏意图）

**注意**：此方案无法在 App 被系统杀死后唤醒，必须配置 FCM 才能实现完整的后台唤醒功能。

---

## 六、未来优化

1. **数据库迁移**：添加专门的 `fcm_token` 字段（替代 `ext_field_1`）
2. **iOS 支持**：配置 APNs 和 `GoogleService-Info.plist`
3. **推送统计**：记录推送发送成功/失败率
4. **多设备管理**：支持同一用户多个设备的推送
