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
      
      return await _apiService.get(
        '/chat/messages',
        queryParameters: queryParams,
      );
    } catch (e) {
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
  Future<Map<String, dynamic>?> sendMessage({
    int? receiverId,
    int? roomId,
    required String message,
    String messageType = 'text',
    int? fileId,
  }) async {
    try {
      return await _apiService.post(
        '/chat/messages',
        data: {
          'receiver_id': receiverId,
          'room_id': roomId,
          'message': message,
          'message_type': messageType,
          'file_id': fileId,
        },
      );
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
