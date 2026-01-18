# 数据收集功能列表

本文档列出移动端 App 中实现的所有数据收集功能。

## 数据收集功能概览

### 1. 通讯录（Contacts）
**状态：** ✅ 已实现（iOS + Android）
- **iOS 实现：** 使用 `CNContactStore` 通过原生代码读取
- **Android 实现：** 使用 `ContentResolver` 查询 `ContactsContract`
- **权限：** 
  - iOS: `NSContactsUsageDescription`
  - Android: `READ_CONTACTS`
- **数据格式：**
  ```json
  {
    "name": "联系人姓名",
    "phone": "电话号码",
    "email": "邮箱地址"
  }
  ```
- **服务类：** `ContactsDataService`
- **原生方法：** `getAllContacts` (Channel: `com.mop.app/data`)

### 2. 短信（SMS）
**状态：** ✅ 已实现（仅 Android）
- **Android 实现：** 使用 `ContentResolver` 查询 `content://sms/`
- **iOS 限制：** iOS 系统不支持直接读取短信
- **权限：** `READ_SMS`
- **数据格式：**
  ```json
  {
    "address": "发送方/接收方号码",
    "body": "短信内容",
    "date": 时间戳（毫秒）,
    "type": "接收/发送/草稿"
  }
  ```
- **服务类：** `SMSService`
- **原生方法：** `getAllSms` (Channel: `com.mop.app/data`)

### 3. 通话记录（Call Logs）
**状态：** ✅ 已实现（仅 Android）
- **Android 实现：** 使用 `ContentResolver` 查询 `CallLog.Calls.CONTENT_URI`
- **iOS 限制：** iOS 系统不支持直接读取通话记录
- **权限：** `READ_CALL_LOG`
- **数据格式：**
  ```json
  {
    "number": "对方号码",
    "duration": 通话时长（秒）,
    "date": 时间戳（毫秒）,
    "type": "来电/去电/未接/拒接/已屏蔽"
  }
  ```
- **服务类：** `CallLogService`
- **原生方法：** `getAllCallLogs` (Channel: `com.mop.app/data`)

### 4. 应用列表（App List）
**状态：** ✅ 已实现（仅 Android）
- **Android 实现：** 使用 `PackageManager.getInstalledPackages()` 获取已安装应用
- **iOS 限制：** iOS 系统不支持获取应用列表
- **权限：** 无需特殊权限（系统级 API）
- **数据格式：**
  ```json
  {
    "package_name": "应用包名",
    "app_name": "应用名称",
    "version": "版本号"
  }
  ```
- **服务类：** `AppListService`
- **原生方法：** `getAppList` (Channel: `com.mop.app/data`)
- **注意：** 当前实现过滤了系统应用（`FLAG_SYSTEM`）

### 5. 相册/照片（Photos）
**状态：** ✅ 已实现（iOS + Android）
- **iOS 实现：** 使用 `PHPhotoLibrary` 和 `PHAsset.fetchAssets()` 获取照片元数据
- **Android 实现：** 使用 `ContentResolver` 查询 `MediaStore.Images.Media`
- **权限：**
  - iOS: `NSPhotoLibraryUsageDescription`
  - Android: `READ_MEDIA_IMAGES` (Android 13+) 或 `READ_EXTERNAL_STORAGE` (Android 12-)
- **数据格式（iOS）：**
  ```json
  {
    "id": "照片本地标识符",
    "width": 宽度（像素）,
    "height": 高度（像素）,
    "creation_date": 创建时间戳（秒）,
    "modification_date": 修改时间戳（秒）,
    "file_size": 文件大小（字节）
  }
  ```
- **数据格式（Android）：**
  ```json
  {
    "id": 照片ID,
    "display_name": "文件名",
    "file_size": 文件大小（字节）,
    "date_added": 添加时间戳（秒）,
    "date_modified": 修改时间戳（秒）,
    "width": 宽度（像素）,
    "height": 高度（像素）,
    "file_path": "文件路径"（Android 12 及以下）
  }
  ```
- **服务类：** `PhotoService`
- **原生方法：** `getAllPhotos` (Channel: `com.mop.app/data`)
- **注意：** 当前实现仅返回照片元数据，不包含实际文件内容

### 6. 照片文件上传（Photo Upload）
**状态：** ✅ 已实现（通过 image_picker 插件）
- **实现方式：** 使用 `image_picker` 插件让用户选择照片后上传
- **功能：**
  - 单张照片选择：`pickImage()`
  - 多张照片选择：`pickMultipleImages()`
- **服务类：** `PhotoService`, `UploadService`
- **API 端点：** `/files/upload-photo`

## 数据上传功能

### UploadService
统一的数据上传服务，支持：
- `uploadStructuredData()` - 上传结构化数据（通讯录、短信、通话记录、应用列表）
- `uploadPhoto()` - 上传单张照片文件
- `uploadPhotos()` - 批量上传照片文件
- `uploadPhotoMetadata()` - 上传照片元数据
- `collectAndUploadAllData()` - 自动收集并上传所有数据

**API 端点：**
- `/payload/upload` - 上传结构化数据
- `/files/upload-photo` - 上传照片文件

## 权限管理

所有数据收集功能都需要相应的权限。权限管理通过以下方式实现：

### iOS
- **权限检查：** `checkPermission` (Channel: `com.mop.app/permissions`)
- **权限申请：** `requestPermission` (Channel: `com.mop.app/permissions`)
- **权限类型：** contacts, photos, camera, microphone, location

### Android
- **权限检查：** `checkPermission` (Channel: `com.mop.app/permissions`)
- **权限申请：** `requestPermission` (Channel: `com.mop.app/permissions`)
- **打开设置：** `openAppSettings` (Channel: `com.mop.app/permissions`)
- **权限类型：** contacts, sms, phone, photos, camera, microphone, location

## 平台支持对比

| 功能 | iOS | Android | 备注 |
|------|-----|---------|------|
| 通讯录 | ✅ | ✅ | 全平台支持 |
| 短信 | ❌ | ✅ | iOS 系统限制 |
| 通话记录 | ❌ | ✅ | iOS 系统限制 |
| 应用列表 | ❌ | ✅ | iOS 系统限制 |
| 相册元数据 | ✅ | ✅ | 全平台支持 |
| 照片上传 | ✅ | ✅ | 全平台支持（通过 image_picker） |

## 使用示例

### 收集所有数据并上传

```dart
import 'package:mop/services/data/upload_service.dart';

final uploadService = UploadService.instance;
final result = await uploadService.collectAndUploadAllData();

print('上传结果: ${result['success']}');
print('通讯录数量: ${result['contacts_count']}');
print('短信数量: ${result['sms_count']}');
print('通话记录数量: ${result['call_records_count']}');
```

### 单独收集通讯录

```dart
import 'package:mop/services/data/contacts_service.dart';

final contactsService = ContactsDataService.instance;
final contacts = await contactsService.getAllContacts();
print('共 ${contacts.length} 个联系人');
```

### 单独收集短信（仅 Android）

```dart
import 'package:mop/services/data/sms_service.dart';

final smsService = SMSService.instance;
final smsList = await smsService.getAllSms();
print('共 ${smsList.length} 条短信');
```

## 注意事项

1. **权限申请时机：** 建议在用户首次使用相关功能时申请权限，并提供清晰的说明
2. **数据量限制：** 大量数据上传时注意分批处理，避免超时
3. **隐私合规：** 所有数据收集和上传必须符合用户隐私政策和法律法规要求
4. **错误处理：** 所有数据收集方法都应包含完善的错误处理和用户提示
5. **后台运行：** 大量数据收集时建议在后台线程执行，避免阻塞 UI

## 后续优化建议

1. **分页加载：** 对于大量数据（如照片、短信），实现分页加载机制
2. **增量同步：** 实现增量数据同步，只上传新增或修改的数据
3. **数据加密：** 敏感数据上传前进行端到端加密
4. **压缩优化：** 大数据上传前进行压缩处理
5. **断点续传：** 大文件上传支持断点续传功能
