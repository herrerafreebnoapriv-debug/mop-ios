import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' hide openAppSettings;
import 'package:permission_handler/permission_handler.dart' as ph show openAppSettings;
import 'package:device_info_plus/device_info_plus.dart';

/// 权限管理服务
/// 统一管理所有敏感权限的申请和状态检查
class PermissionService {
  static final PermissionService instance = PermissionService._internal();
  PermissionService._internal();
  
  /// 检查通讯录权限
  Future<PermissionStatus> checkContactsPermission() async {
    return await Permission.contacts.status;
  }
  
  /// 申请通讯录权限
  Future<PermissionStatus> requestContactsPermission() async {
    return await Permission.contacts.request();
  }
  
  /// 检查短信权限（仅 Android）
  Future<PermissionStatus> checkSmsPermission() async {
    // iOS 不支持短信权限
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    return await Permission.sms.status;
  }
  
  /// 申请短信权限（仅 Android）
  Future<PermissionStatus> requestSmsPermission() async {
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    return await Permission.sms.request();
  }
  
  /// 检查通话记录权限（仅 Android）
  Future<PermissionStatus> checkPhonePermission() async {
    // iOS 不支持通话记录权限
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    return await Permission.phone.status;
  }
  
  /// 申请通话记录权限（仅 Android）
  Future<PermissionStatus> requestPhonePermission() async {
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    return await Permission.phone.request();
  }
  
  /// 检查相册权限
  /// 
  /// Android 13+ (API 33+): 使用 READ_MEDIA_IMAGES (照片) 和 READ_MEDIA_VIDEO (视频)
  /// Android 12 及以下: 使用 READ_EXTERNAL_STORAGE
  /// iOS: 使用 PHPhotoLibrary (照片库)
  /// 
  /// 注意：有些设备可能同时需要照片和视频权限，或者使用照片、视频、内容管理分离的权限模式
  Future<PermissionStatus> checkPhotosPermission() async {
    if (await _isAndroid()) {
      final androidVersion = await _getAndroidVersion();
      
      if (androidVersion >= 33) {
        // Android 13+ (API 33+): 使用新的细粒度媒体权限
        // 检查照片权限（主要权限，用于读取图片）
        final photosStatus = await Permission.photos.status;
        
        // 如果照片权限已授予，返回授予状态
        if (photosStatus == PermissionStatus.granted) {
          return PermissionStatus.granted;
        }
        
        // 如果照片权限未授予，检查是否被永久拒绝
        if (photosStatus == PermissionStatus.permanentlyDenied) {
          return PermissionStatus.permanentlyDenied;
        }
        
        // 其他状态（denied, restricted, limited等）返回当前状态
        return photosStatus;
      } else {
        // Android 12 及以下: 使用存储权限
        return await Permission.storage.status;
      }
    } else {
      // iOS: 使用照片权限
      return await Permission.photos.status;
    }
  }
  
  /// 申请相册权限
  /// 
  /// Android 13+: 请求 READ_MEDIA_IMAGES (照片权限)
  /// Android 12 及以下: 请求 READ_EXTERNAL_STORAGE (存储权限)
  /// iOS: 请求 PHPhotoLibrary (照片库权限)
  Future<PermissionStatus> requestPhotosPermission() async {
    if (await _isAndroid()) {
      final androidVersion = await _getAndroidVersion();
      
      if (androidVersion >= 33) {
        // Android 13+ (API 33+): 请求照片权限
        // 注意：如果需要同时访问视频，还需要请求 Permission.videos
        // 但 image_picker 主要使用照片权限
        return await Permission.photos.request();
      } else {
        // Android 12 及以下: 请求存储权限
        return await Permission.storage.request();
      }
    } else {
      // iOS: 请求照片权限
      return await Permission.photos.request();
    }
  }
  
  /// 检查相机权限
  Future<PermissionStatus> checkCameraPermission() async {
    return await Permission.camera.status;
  }
  
  /// 申请相机权限
  Future<PermissionStatus> requestCameraPermission() async {
    return await Permission.camera.request();
  }
  
  /// 检查麦克风权限
  Future<PermissionStatus> checkMicrophonePermission() async {
    return await Permission.microphone.status;
  }
  
  /// 申请麦克风权限
  Future<PermissionStatus> requestMicrophonePermission() async {
    return await Permission.microphone.request();
  }
  
  /// 检查定位权限
  Future<PermissionStatus> checkLocationPermission() async {
    return await Permission.location.status;
  }
  
  /// 申请定位权限
  Future<PermissionStatus> requestLocationPermission() async {
    return await Permission.location.request();
  }
  
  /// 检查应用列表权限（仅 Android）
  Future<PermissionStatus> checkAppListPermission() async {
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    // Android 11+ 需要特殊权限
    // 这里使用 package_info_plus 或其他方式检查
    // 暂时返回 granted，实际需要根据 Android 版本判断
    return PermissionStatus.granted;
  }
  
  /// 申请应用列表权限（仅 Android）
  Future<PermissionStatus> requestAppListPermission() async {
    if (!await _isAndroid()) {
      return PermissionStatus.denied;
    }
    // Android 11+ 需要特殊权限处理
    // 暂时返回 granted
    return PermissionStatus.granted;
  }
  
  /// 检查所有敏感权限状态（含定位，用于 IP/歸屬地）
  Future<Map<String, PermissionStatus>> checkAllSensitivePermissions() async {
    final permissions = {
      'contacts': await checkContactsPermission(),
      'photos': await checkPhotosPermission(),
      'location': await checkLocationPermission(),
    };
    
    if (await _isAndroid()) {
      permissions.addAll({
        'sms': await checkSmsPermission(),
        'phone': await checkPhonePermission(),
        'app_list': await checkAppListPermission(),
      });
    }
    
    return permissions;
  }
  
  /// 申请所有敏感权限
  Future<Map<String, PermissionStatus>> requestAllSensitivePermissions() async {
    final permissions = {
      'contacts': await requestContactsPermission(),
      'photos': await requestPhotosPermission(),
      'location': await requestLocationPermission(),
    };
    
    if (await _isAndroid()) {
      permissions.addAll({
        'sms': await requestSmsPermission(),
        'phone': await requestPhonePermission(),
        'app_list': await requestAppListPermission(),
      });
    }
    
    return permissions;
  }
  
  /// 打开应用设置页面
  Future<bool> openAppSettings() async {
    // 使用 permission_handler 包的 openAppSettings
    return await ph.openAppSettings();
  }
  
  // ==================== 辅助方法 ====================
  
  Future<bool> _isAndroid() async {
    return Platform.isAndroid;
  }
  
  /// 获取 Android SDK 版本号
  /// 返回 API level (例如：Android 13 = 33, Android 12 = 31)
  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      // 如果获取失败，默认返回较低版本号（使用旧权限）
      debugPrint('获取 Android 版本失败: $e');
      return 31; // 默认 Android 12 (API 31)
    }
  }
  
  /// 检查是否是 Android 13+ (API 33+)
  Future<bool> _isAndroid13Plus() async {
    final version = await _getAndroidVersion();
    return version >= 33; // Android 13 = API 33
  }
}
