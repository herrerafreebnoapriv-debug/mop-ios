import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../../native/native_service.dart';

/// 应用列表服务
/// 获取设备上安装的应用列表
class AppListService {
  static final AppListService instance = AppListService._internal();
  AppListService._internal();
  
  /// 获取应用列表
  /// 
  /// 返回应用列表，格式：
  /// [
  ///   {
  ///     "package_name": "应用包名",
  ///     "app_name": "应用名称",
  ///     "version": "版本号"
  ///   }
  /// ]
  /// 
  /// 注意：仅 Android 支持，iOS 系统限制无法获取应用列表
  Future<List<Map<String, dynamic>>> getAppList() async {
    try {
      if (!Platform.isAndroid) {
        throw Exception('应用列表功能仅支持 Android 平台');
      }
      
      // 通过原生代码获取应用列表
      final nativeService = NativeService.instance;
      return await nativeService.getAppList();
    } catch (e) {
      throw Exception('获取应用列表失败: $e');
    }
  }
  
  /// 获取设备信息
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'platform': 'Android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'sdk_int': androidInfo.version.sdkInt,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'platform': 'iOS',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'system_version': iosInfo.systemVersion,
          'identifier_for_vendor': iosInfo.identifierForVendor,
        };
      }
      
      return {};
    } catch (e) {
      throw Exception('获取设备信息失败: $e');
    }
  }
}
