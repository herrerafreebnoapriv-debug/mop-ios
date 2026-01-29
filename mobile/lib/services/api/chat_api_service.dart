import 'api_service.dart';

/// 聊天 API 服务
class ChatApiService {
  final ApiService _apiService = ApiService();
  
  /// 获取消息列表
  Future<Map<String, dynamic>?> getMessages({
    int page = 1,
    int limit = 50,
    int? userId,
    int? roomId,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      if (userId != null) {
        queryParams['user_id'] = userId;
      }
      if (roomId != null) {
        queryParams['room_id'] = roomId;
      }
      
      print('[ChatApiService] 请求消息 - queryParams: $queryParams');
      final result = await _apiService.get(
        '/chat/messages',
        queryParameters: queryParams,
      );
      print('[ChatApiService] 响应结果 - messages数量: ${result?['messages']?.length ?? 0}');
      return result;
    } catch (e) {
      print('[ChatApiService] 获取消息失败: $e');
      rethrow;
    }
  }

  /// 增量获取消息列表（按最后消息ID之后）
  Future<Map<String, dynamic>?> getMessagesSince({
    required int lastMessageId,
    int? userId,
    int? roomId,
    int limit = 200,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'last_message_id': lastMessageId,
        'limit': limit,
      };
      if (userId != null) {
        queryParams['user_id'] = userId;
      }
      if (roomId != null) {
        queryParams['room_id'] = roomId;
      }

      final result = await _apiService.get(
        '/chat/messages/since',
        queryParameters: queryParams,
      );
      return result;
    } catch (e) {
      print('[ChatApiService] 增量获取消息失败: $e');
      rethrow;
    }
  }
  
  /// 获取会话列表
  Future<Map<String, dynamic>?> getConversations() async {
    try {
      return await _apiService.get('/chat/conversations');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 发送消息（参照网页端：POST /chat/messages）
  /// 图片：传 file_url + file_name，不传 file_id。语音/文件：传 file_id（int）。
  Future<Map<String, dynamic>?> sendMessage({
    int? receiverId,
    int? roomId,
    required String message,
    String messageType = 'text',
    int? fileId,
    String? fileUrl,
    String? fileName,
  }) async {
    try {
      final data = <String, dynamic>{
        'receiver_id': receiverId,
        'room_id': roomId,
        'message': message,
        'message_type': messageType,
      };
      if (fileId != null) data['file_id'] = fileId;
      if (fileUrl != null && fileUrl.isNotEmpty) data['file_url'] = fileUrl;
      if (fileName != null && fileName.isNotEmpty) data['file_name'] = fileName;
      return await _apiService.post('/chat/messages', data: data);
    } catch (e) {
      rethrow;
    }
  }
  
  /// 标记消息已读（参照网页端：PUT /chat/messages/mark-read）
  Future<bool> markAsRead(List<int> messageIds) async {
    try {
      final response = await _apiService.put(
        '/chat/messages/mark-read',
        data: {'message_ids': messageIds},
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
}
