# 视频通话推送通知实现指南

## 问题根源

**核心病因**：当 App 在后台或手机黑屏时，WebSocket/Socket.io 连接会被系统立即杀掉，导致无法通过 Socket 收到视频通话邀请。

**解决方案**：必须引入 **FCM (Firebase Cloud Messaging)** 或 **苹果 APNs**，在发起通话时发送高优先级推送通知来唤醒 App。

---

## 一、当前状态

### ✅ 已实现
- Socket.io 实时推送（仅限 App 前台时有效）
- 本地通知服务（`NotificationService`，但无法在后台唤醒 App）
- Android 权限已添加：`POST_NOTIFICATIONS`、`USE_FULL_SCREEN_INTENT`

### ❌ 缺失
- **FCM/APNs 集成**（必需，用于后台唤醒）
- 后端推送通知 API（在 `call_invitation` 时发送 FCM/APNs）
- App 端推送监听（收到推送后显示全屏通话界面）

---

## 二、完整实现方案

### 步骤 1：集成 Firebase Cloud Messaging (FCM)

#### 1.1 添加依赖

在 `mobile/pubspec.yaml` 中添加：

```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.9
```

#### 1.2 配置 Firebase

1. 在 [Firebase Console](https://console.firebase.google.com/) 创建项目
2. 添加 Android App（包名：`com.mop.app`）
3. 下载 `google-services.json` 放到 `mobile/android/app/`
4. 在 `mobile/android/build.gradle` 添加：
   ```gradle
   dependencies {
       classpath 'com.google.gms:google-services:4.4.0'
   }
   ```
5. 在 `mobile/android/app/build.gradle` 末尾添加：
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

#### 1.3 iOS 配置（如需要）

1. 在 Firebase Console 添加 iOS App（Bundle ID）
2. 下载 `GoogleService-Info.plist` 放到 `mobile/ios/Runner/`
3. 在 `mobile/ios/Runner/Info.plist` 添加推送权限说明

---

### 步骤 2：后端 - 在 `call_invitation` 时发送推送

#### 2.1 安装 Python FCM 库

```bash
pip install pyfcm
# 或
pip install firebase-admin
```

#### 2.2 修改 `app/core/socketio.py`

在 `call_invitation` 函数中，发送 Socket 事件后，**同时发送 FCM 推送**：

```python
@sio.event
async def call_invitation(sid, data):
    # ... 现有逻辑（创建系统消息、发送 Socket 事件）...
    
    # 新增：发送 FCM 推送通知（即使对方不在线也能收到）
    try:
        from app.services.push_notification import send_video_call_push
        
        await send_video_call_push(
            target_user_id=target_user_id,
            caller_name=caller_name,
            room_id=room_id,
            invitation_data=invitation_data,
        )
        logger.info(f"✓ 已发送 FCM 推送通知给用户 {target_user_id}")
    except Exception as push_error:
        logger.warning(f"发送 FCM 推送失败: {push_error}")  # 不影响 Socket 流程
```

#### 2.3 创建推送服务

创建 `app/services/push_notification.py`：

```python
from pyfcm import FCMNotification
import os
from app.db.models import Device  # 假设有设备表存储 FCM token

push_service = FCMNotification(api_key=os.getenv("FCM_SERVER_KEY"))

async def send_video_call_push(
    target_user_id: int,
    caller_name: str,
    room_id: str,
    invitation_data: dict,
):
    """发送视频通话推送通知"""
    # 1. 从数据库获取目标用户的所有设备 FCM token
    from app.db.session import get_db
    async for session in get_db():
        devices = await session.execute(
            select(Device).where(Device.user_id == target_user_id)
        )
        fcm_tokens = [d.fcm_token for d in devices.scalars() if d.fcm_token]
        break
    
    if not fcm_tokens:
        logger.warning(f"用户 {target_user_id} 没有注册 FCM token")
        return
    
    # 2. 构建推送数据
    message_title = "视频通话邀请"
    message_body = f"{caller_name} 邀请您进行视频通话"
    
    data_message = {
        "type": "VIDEO_CALL",
        "room_id": room_id,
        "caller_name": caller_name,
        "caller_id": str(invitation_data.get("caller_id")),
        "invitation_data": json.dumps(invitation_data),
    }
    
    # 3. 发送高优先级推送（唤醒 App）
    result = push_service.notify_multiple_devices(
        registration_ids=fcm_tokens,
        message_title=message_title,
        message_body=message_body,
        data_message=data_message,
        sound="default",
        priority="high",  # 高优先级，即使省电模式也能收到
        content_available=True,  # iOS 后台唤醒
    )
    
    logger.info(f"FCM 推送结果: {result}")
```

---

### 步骤 3：App 端 - 监听推送并显示全屏界面

#### 3.1 初始化 FCM

在 `mobile/lib/main.dart` 或应用启动时：

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 后台消息处理器（必需，即使 App 被系统杀死也能收到）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('后台收到推送: ${message.data}');
  
  if (message.data['type'] == 'VIDEO_CALL') {
    // 显示本地通知（全屏意图）
    await NotificationService.instance.showIncomingCallNotification(
      callerName: message.data['caller_name'] ?? '对方',
      roomId: message.data['room_id'] ?? '',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // 注册后台消息处理器
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  runApp(MyApp());
}
```

#### 3.2 在 App 中监听推送

在 `mobile/lib/providers/socket_provider.dart` 或主界面初始化时：

```dart
import 'package:firebase_messaging/firebase_messaging.dart';

class SocketProvider extends ChangeNotifier {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  
  Future<void> _initPushNotifications() async {
    // 请求权限
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 获取 FCM token 并上传到后端
      String? token = await _fcm.getToken();
      if (token != null) {
        await _uploadFcmToken(token);
      }
      
      // 监听前台推送
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('前台收到推送: ${message.data}');
        _handlePushMessage(message);
      });
      
      // 监听后台推送（App 打开时）
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('从后台推送打开: ${message.data}');
        _handlePushMessage(message);
      });
    }
  }
  
  void _handlePushMessage(RemoteMessage message) {
    if (message.data['type'] == 'VIDEO_CALL') {
      final roomId = message.data['room_id'];
      final callerName = message.data['caller_name'] ?? '对方';
      
      // 显示全屏通话界面
      _showVideoCallDialog(callerName, roomId);
    }
  }
  
  Future<void> _uploadFcmToken(String token) async {
    // 调用后端 API 上传 token
    // POST /api/v1/devices/register
    // { "fcm_token": token, "platform": "android" }
  }
}
```

#### 3.3 显示全屏通话界面

在收到推送时，使用 `NotificationService` 显示全屏通知：

```dart
Future<void> _showVideoCallDialog(String callerName, String roomId) async {
  // 使用全屏意图显示通知（即使锁屏也能显示）
  await NotificationService.instance.showIncomingCallNotification(
    callerName: callerName,
    roomId: roomId,
    isVideo: true,
  );
  
  // 同时显示应用内弹窗（如果 App 在前台）
  // 这里可以复用现有的 _CallInvitationListener 逻辑
}
```

---

## 三、检查清单

### A. 权限问题
- ✅ Android 13+：`POST_NOTIFICATIONS` 权限已添加
- ✅ 全屏意图：`USE_FULL_SCREEN_INTENT` 权限已添加
- ⚠️ **需要**：在 App 启动时请求通知权限（`NotificationService` 已有）

### B. 全屏意图配置
- ✅ `AndroidNotificationDetails` 已设置 `fullScreenIntent: true`
- ✅ `category: AndroidNotificationCategory.call` 已设置
- ⚠️ **需要**：确保通知渠道重要性为 `Importance.high`

### C. FCM 集成（待实现）
- ❌ Firebase 项目未创建
- ❌ `google-services.json` 未配置
- ❌ 后端 FCM Server Key 未配置
- ❌ 设备 FCM token 未上传到后端
- ❌ 推送监听逻辑未实现

---

## 四、快速测试方案（临时）

在 FCM 集成完成前，可以先用**本地通知 + 前台服务保活**来测试：

1. **前台服务保活**：已有 `SocketForegroundService`，确保 Socket 连接不断
2. **本地通知**：当收到 `call_invitation` Socket 事件时，立即显示本地通知（全屏意图）
3. **测试场景**：App 在前台或后台（但未杀死进程）时，应该能收到通知

**注意**：此方案无法在 App 被系统杀死后唤醒，必须集成 FCM/APNs。

---

## 五、总结

| 环节 | 状态 | 优先级 |
|------|------|--------|
| Android 权限 | ✅ 已添加 | - |
| 本地通知（全屏意图） | ✅ 已配置 | - |
| FCM 集成 | ❌ 待实现 | **P0** |
| 后端推送 API | ❌ 待实现 | **P0** |
| App 推送监听 | ❌ 待实现 | **P0** |

**下一步**：按照本指南的步骤 1-3 依次实现 FCM 集成、后端推送、App 监听，即可解决「发送视频通话仍然没有任何提示」的问题。
