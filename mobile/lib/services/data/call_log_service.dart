import 'dart:io';
import '../../services/native/native_service.dart';

/// 通话记录服务（仅 Android）
/// 读取设备通话记录并转换为上传格式
class CallLogService {
  static final CallLogService instance = CallLogService._internal();
  CallLogService._internal();
  
  final NativeService _nativeService = NativeService.instance;
  
  /// 获取所有通话记录
  /// 
  /// 返回通话记录列表，格式：
  /// [
  ///   {
  ///     "number": "对方号码",
  ///     "duration": "通话时长（秒）",
  ///     "date": "时间戳",
  ///     "type": "来电/去电/未接"
  ///   }
  /// ]
  Future<List<Map<String, dynamic>>> getAllCallLogs() async {
    try {
      // 仅 Android 支持
      if (!Platform.isAndroid) {
        throw Exception('通话记录功能仅支持 Android 平台');
      }
      
      // 检查权限
      var permissionStatus = await _nativeService.checkPermission('phone');
      if (permissionStatus != 1) {
        // 尝试申请权限
        permissionStatus = await _nativeService.requestPermission('phone');
        if (permissionStatus != 1) {
          throw Exception('没有通话记录权限');
        }
      }
      
      // 通过原生代码获取通话记录
      return await _nativeService.getAllCallLogs();
    } catch (e) {
      throw Exception('读取通话记录失败: $e');
    }
  }
  
  /// 获取通话记录数量
  Future<int> getCallLogCount() async {
    final callLogs = await getAllCallLogs();
    return callLogs.length;
  }
}
