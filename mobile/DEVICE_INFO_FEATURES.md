# 设备信息功能说明

## 功能概述

设备信息功能用于收集设备的硬件信息、系统信息和注册信息，用于设备审计和管理。

## 实现方式

### iOS 实现
- **文件位置：** `/mobile/ios/Runner/AppDelegate.swift`
- **方法：** `handleGetDeviceInfo`
- **Channel：** `com.mop.app/data`

### Android 实现
- **文件位置：** `/mobile/android/app/src/main/kotlin/com/mop/app/MainActivity.kt`
- **方法：** `getDeviceInfo`
- **Channel：** `com.mop.app/data`

### Flutter 封装
- **文件位置：** `/mobile/lib/services/native/native_service.dart`
- **方法：** `getDeviceInfo()`

## 返回的数据字段

### 设备硬件信息

#### iOS
```json
{
  "model": "iPhone",
  "name": "用户的 iPhone",
  "system_name": "iOS",
  "system_version": "17.0",
  "device_id": "UUID字符串",
  "ip_address": "192.168.1.100",
  "platform": "iOS",
  "platform_version": "17.0"
}
```

#### Android
```json
{
  "model": "SM-G991B",
  "manufacturer": "samsung",
  "brand": "samsung",
  "device": "o1s",
  "product": "o1sxxx",
  "system_name": "Android",
  "system_version": "13",
  "sdk_int": 33,
  "device_id": "Android ID",
  "ip_address": "192.168.1.100",
  "platform": "Android",
  "platform_version": "13"
}
```

### 注册信息（从本地存储读取）

所有平台都包含以下注册信息字段：

```json
{
  "register_phone": "注册时的手机号",
  "register_username": "注册时的用户名",
  "register_invitation_code": "注册时的邀请码"
}
```

**注意：** 注册信息在用户注册时自动保存到本地存储（SharedPreferences），如果用户未注册或已清除数据，这些字段将为空字符串。

## 数据字段说明

### 设备型号相关
- **model** (iOS/Android): 设备型号名称
- **name** (iOS): 用户自定义的设备名称
- **manufacturer** (Android): 设备制造商
- **brand** (Android): 设备品牌
- **device** (Android): 设备代号
- **product** (Android): 产品名称

### 系统版本相关
- **system_name**: 操作系统名称（iOS/Android）
- **system_version**: 系统版本号（如 "17.0" 或 "13"）
- **sdk_int** (Android): Android SDK 版本号

### 设备标识
- **device_id**: 
  - iOS: `identifierForVendor` UUID（应用卸载重装后会变化）
  - Android: Android ID（设备唯一标识符）

### 网络信息
- **ip_address**: 设备当前 IP 地址
  - iOS: 优先返回 WiFi (en0) 的 IPv4 地址
  - Android: 优先返回非回环的 IPv4 地址

### 注册信息
- **register_phone**: 用户注册时使用的手机号
- **register_username**: 用户注册时使用的用户名
- **register_invitation_code**: 用户注册时使用的邀请码

## 使用示例

### 获取设备信息

```dart
import 'package:mop/services/native/native_service.dart';

final nativeService = NativeService.instance;
final deviceInfo = await nativeService.getDeviceInfo();

print('设备型号: ${deviceInfo['model']}');
print('系统版本: ${deviceInfo['system_version']}');
print('IP 地址: ${deviceInfo['ip_address']}');
print('设备ID: ${deviceInfo['device_id']}');
print('注册手机号: ${deviceInfo['register_phone']}');
print('注册用户名: ${deviceInfo['register_username']}');
print('邀请码: ${deviceInfo['register_invitation_code']}');
```

### 上传设备信息

```dart
import 'package:mop/services/api/api_service.dart';

final apiService = ApiService();
final deviceInfo = await NativeService.instance.getDeviceInfo();

await apiService.post('/payload/upload', data: {
  'device_info': deviceInfo,
});
```

## 数据存储

### 注册信息存储

注册信息在用户注册时自动保存：

**存储位置：** SharedPreferences

**存储键名：**
- `register_phone` - 注册手机号
- `register_username` - 注册用户名
- `register_invitation_code` - 注册邀请码

**保存时机：** 用户成功注册后，在 `AuthProvider.register()` 方法中自动保存

**清除时机：** 
- 用户退出登录时（可选）
- 清除应用数据时
- 卸载应用时

## 注意事项

1. **设备ID 变化：**
   - iOS: `identifierForVendor` 在应用卸载重装后会变化
   - Android: Android ID 在设备恢复出厂设置后会变化

2. **IP 地址：**
   - IP 地址可能因网络切换而变化
   - 设备未连接网络时可能为空字符串

3. **注册信息：**
   - 如果用户未注册，注册信息字段将为空字符串
   - 注册信息存储在本地，不会自动同步到服务器

4. **隐私合规：**
   - 设备信息收集需要符合用户隐私政策
   - 建议在用户同意隐私政策后再收集设备信息

## 后续优化建议

1. **设备指纹：** 结合多个设备特征生成更稳定的设备指纹
2. **网络信息增强：** 添加 WiFi SSID、MAC 地址等信息（需要额外权限）
3. **电池信息：** 添加电池电量、充电状态等信息
4. **存储信息：** 添加设备存储空间、可用空间等信息
5. **应用信息：** 添加应用版本、安装时间等信息
