# 原生代码实现总结

## 概述

本文档总结了 iOS 和 Android 原生代码的实现情况，包括权限管理、数据读取、安全检测等功能。

## iOS (Swift) 实现

### 文件位置
- `/mobile/ios/Runner/AppDelegate.swift` - 主应用代理，包含所有原生功能实现
- `/mobile/ios/Runner/Bridging-Header.h` - C 桥接头文件，支持 sysctl 调用

### 实现功能

#### 1. 权限管理 (`com.mop.app/permissions` Channel)

**方法：**
- `checkPermission` - 检查权限状态
  - 参数：`permission` (String) - 权限类型
  - 返回：0-拒绝, 1-已授权, 2-受限
  - 支持的权限：contacts, photos, camera, microphone, location

- `requestPermission` - 申请权限
  - 参数：`permission` (String) - 权限类型
  - 返回：0-拒绝, 1-已授权

**权限类型：**
- `contacts` - 通讯录权限（CNContactStore）
- `photos` - 相册权限（PHPhotoLibrary）
- `camera` - 相机权限（AVCaptureDevice）
- `microphone` - 麦克风权限（AVCaptureDevice）
- `location` - 定位权限（CLLocationManager）

#### 2. 安全检测

**方法：**
- `checkDebugMode` - 检查是否处于调试模式
  - 返回：true/false
  - 实现：使用 `sysctl` 检查进程的 `P_TRACED` 标志

#### 3. 数据读取 (`com.mop.app/data` Channel)

**方法：**
- `getAllContacts` - 获取所有联系人
  - 返回：联系人列表（包含姓名、电话、邮箱）
  - 实现：使用 `CNContactStore.enumerateContacts` 遍历所有联系人

- `getAllPhotos` - 获取所有照片信息
  - 返回：照片信息列表（包含 ID、尺寸、时间戳、文件大小等）
  - 实现：使用 `PHAsset.fetchAssets` 获取所有图片资源

### 注意事项

1. **权限描述**：所有权限使用说明已在 `Info.plist` 中配置
2. **iOS 限制**：
   - iOS 不支持直接读取短信和通话记录
   - iOS 不支持获取应用列表
3. **调试模式检测**：需要桥接头文件支持 `sysctl` 调用

## Android (Kotlin) 实现

### 文件位置
- `/mobile/android/app/src/main/kotlin/com/mop/app/MainActivity.kt` - 主活动，包含所有原生功能实现
- `/mobile/android/app/src/main/kotlin/com/mop/app/SocketForegroundService.kt` - Socket.io 前台服务

### 实现功能

#### 1. 权限管理 (`com.mop.app/permissions` Channel)

**方法：**
- `checkPermission` - 检查权限状态
  - 参数：`permission` (String) - 权限类型
  - 返回：0-拒绝, 1-已授权

- `requestPermission` - 申请权限
  - 参数：`permission` (String) - 权限类型
  - 返回：0-拒绝, 1-已授权

- `openAppSettings` - 打开应用设置页面

**权限类型：**
- `contacts` - 通讯录权限（READ_CONTACTS）
- `sms` - 短信权限（READ_SMS）
- `phone` - 通话记录权限（READ_CALL_LOG）
- `photos` - 相册权限（READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE，根据 Android 版本）
- `camera` - 相机权限（CAMERA）
- `microphone` - 麦克风权限（RECORD_AUDIO）
- `location` - 定位权限（ACCESS_FINE_LOCATION）

#### 2. 安全检测

**方法：**
- `checkDebugMode` - 检查是否处于调试模式
  - 返回：true/false
  - 实现：检查 `ApplicationInfo.FLAG_DEBUGGABLE` 标志

#### 3. 数据读取 (`com.mop.app/data` Channel)

**方法：**
- `getAllContacts` - 获取所有联系人
  - 返回：联系人列表（包含姓名、电话、邮箱）
  - 实现：通过 `ContentResolver` 查询 `ContactsContract`，合并电话和邮箱信息

- `getAllSms` - 获取所有短信
  - 返回：短信列表（包含地址、内容、时间、类型）
  - 实现：通过 `ContentResolver` 查询 `content://sms/`

- `getAllCallLogs` - 获取所有通话记录
  - 返回：通话记录列表（包含号码、时长、时间、类型）
  - 实现：通过 `ContentResolver` 查询 `CallLog.Calls.CONTENT_URI`

- `getAppList` - 获取应用列表
  - 返回：应用列表（包含包名、应用名称、版本号）
  - 实现：通过 `PackageManager.getInstalledPackages` 获取，过滤系统应用

- `getAllPhotos` - 获取所有照片信息
  - 返回：照片信息列表（包含 ID、文件名、大小、时间戳、尺寸、路径）
  - 实现：通过 `ContentResolver` 查询 `MediaStore.Images.Media`

### 注意事项

1. **权限声明**：所有权限已在 `AndroidManifest.xml` 中声明
2. **Android 版本适配**：
   - Android 13+ 使用 `READ_MEDIA_IMAGES` 权限
   - Android 13 以下使用 `READ_EXTERNAL_STORAGE` 权限
3. **前台服务**：`SocketForegroundService` 用于保持 Socket.io 连接活跃

## Flutter 层封装

### NativeService

**文件位置：**
- `/mobile/lib/services/native/native_service.dart`

**功能：**
- 封装所有原生平台调用
- 提供统一的 Dart API
- 处理平台差异（iOS/Android）

**使用示例：**
```dart
// 检查权限
final status = await NativeService.instance.checkPermission('contacts');

// 申请权限
final granted = await NativeService.instance.requestPermission('photos');

// 检查调试模式
final isDebug = await NativeService.instance.checkDebugMode();

// 获取通讯录
final contacts = await NativeService.instance.getAllContacts();

// 获取短信（仅 Android）
final smsList = await NativeService.instance.getAllSms();

// 获取通话记录（仅 Android）
final callLogs = await NativeService.instance.getAllCallLogs();

// 获取应用列表（仅 Android）
final appList = await NativeService.instance.getAppList();

// 获取照片
final photos = await NativeService.instance.getAllPhotos();
```

### 服务类更新

以下服务类已更新为使用 `NativeService`：
- `ContactsDataService` - 通讯录服务
- `SMSService` - 短信服务
- `CallLogService` - 通话记录服务
- `AppListService` - 应用列表服务
- `PhotoService` - 相册服务

## 测试建议

### iOS 测试
1. 测试权限申请流程
2. 测试相册读取功能
3. 测试调试模式检测（在 Release 模式下测试）

### Android 测试
1. 测试所有权限申请
2. 测试短信读取（需要真实设备）
3. 测试通话记录读取（需要真实设备）
4. 测试应用列表获取
5. 测试相册读取
6. 测试前台服务启动和停止

## 后续优化

1. **权限请求结果回调**：Android 的权限请求结果需要通过 `EventChannel` 或回调通知 Flutter
2. **位置权限异步处理**：iOS 位置权限需要实现 `CLLocationManagerDelegate` 来处理异步回调
3. **错误处理增强**：添加更详细的错误信息和错误码
4. **性能优化**：大量数据读取时考虑分页或异步加载

## 编译配置

### iOS
- 确保在 Xcode 项目设置中配置了 Bridging Header
- 路径：`Runner/Bridging-Header.h`

### Android
- 确保 `minSdkVersion` 至少为 21（Android 5.0）
- 确保所有权限已在 `AndroidManifest.xml` 中声明
