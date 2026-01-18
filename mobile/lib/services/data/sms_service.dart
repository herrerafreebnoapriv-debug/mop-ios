import 'dart:io';
import '../../services/native/native_service.dart';

/// 短信服务（仅 Android）
/// 读取设备短信并转换为上传格式
class SMSService {
  static final SMSService instance = SMSService._internal();
  SMSService._internal();
  
  final NativeService _nativeService = NativeService.instance;
  
  /// 获取所有短信
  /// 
  /// 返回短信列表，格式：
  /// [
  ///   {
  ///     "address": "发送方/接收方号码",
  ///     "body": "短信内容",
  ///     "date": "时间戳",
  ///     "type": "发送/接收"
  ///   }
  /// ]
  Future<List<Map<String, dynamic>>> getAllSms() async {
    try {
      // 仅 Android 支持
      if (!Platform.isAndroid) {
        throw Exception('短信功能仅支持 Android 平台');
      }
      
      // 检查权限
      var permissionStatus = await _nativeService.checkPermission('sms');
      if (permissionStatus != 1) {
        // 尝试申请权限
        permissionStatus = await _nativeService.requestPermission('sms');
        if (permissionStatus != 1) {
          throw Exception('没有短信权限');
        }
      }
      
      // 通过原生代码获取短信
      return await _nativeService.getAllSms();
    } catch (e) {
      throw Exception('读取短信失败: $e');
    }
  }
  
  /// 获取短信数量
  Future<int> getSmsCount() async {
    final smsList = await getAllSms();
    return smsList.length;
  }
}
