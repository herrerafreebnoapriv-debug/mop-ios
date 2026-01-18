import 'api_service.dart';

/// 文件 API 服务
class FilesApiService {
  final ApiService _apiService = ApiService();
  
  /// 上传文件
  Future<Map<String, dynamic>?> uploadFile(String filePath, {
    String fieldName = 'file',
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      return await _apiService.uploadFile(
        '/files/upload',
        filePath,
        fieldName: fieldName,
        additionalData: additionalData,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 下载文件
  Future<String?> downloadFile(int fileId, String savePath) async {
    try {
      // TODO: 实现文件下载
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 获取文件信息
  Future<Map<String, dynamic>?> getFileInfo(int fileId) async {
    try {
      return await _apiService.get('/files/$fileId');
    } catch (e) {
      rethrow;
    }
  }
}
