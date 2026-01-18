import 'dart:io';
import 'package:permission_handler/permission_handler.dart' hide openAppSettings;
import 'package:permission_handler/permission_handler.dart' as ph show openAppSettings;

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
  Future<PermissionStatus> checkPhotosPermission() async {
    if (await _isAndroid()) {
      // Android 13+ 使用新的权限
      if (await _isAndroid13Plus()) {
        return await Permission.photos.status;
      } else {
        return await Permission.storage.status;
      }
    } else {
      // iOS
      return await Permission.photos.status;
    }
  }
  
  /// 申请相册权限
  Future<PermissionStatus> requestPhotosPermission() async {
    if (await _isAndroid()) {
      if (await _isAndroid13Plus()) {
        return await Permission.photos.request();
      } else {
        return await Permission.storage.request();
      }
    } else {
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
  
  /// 检查所有敏感权限状态
  Future<Map<String, PermissionStatus>> checkAllSensitivePermissions() async {
    final permissions = {
      'contacts': await checkContactsPermission(),
      'photos': await checkPhotosPermission(),
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
  
  Future<bool> _isAndroid13Plus() async {
    // 需要 device_info_plus 插件来检查 Android 版本
    // 这里简化处理，假设 Android 13+ 使用新权限
    // 实际使用时需要检查 Android 版本
    return false; // 默认返回 false，实际需要根据设备信息判断
  }
}
