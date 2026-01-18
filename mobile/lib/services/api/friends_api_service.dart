import 'api_service.dart';

/// 好友 API 服务
class FriendsApiService {
  final ApiService _apiService = ApiService();
  
  /// 获取好友列表（参照网页端：支持 status_filter 参数）
  Future<Map<String, dynamic>?> getFriendsList({
    String? statusFilter, // pending/accepted/blocked
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (statusFilter != null) {
        queryParams['status_filter'] = statusFilter;
      }
      return await _apiService.get(
        '/friends/list',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 搜索用户
  Future<List<dynamic>> searchUsers(String keyword) async {
    try {
      final response = await _apiService.get(
        '/friends/search',
        queryParameters: {'keyword': keyword},
      );
      
      // 后端 API 直接返回 List[FriendResponse]，不是包含 users 或 results 的对象
      if (response != null) {
        if (response is List) {
          // 直接返回数组
          return List<dynamic>.from(response as List);
        } else if (response is Map) {
          // 兼容处理：如果返回的是对象，尝试提取 users 或 results
          final map = response as Map<String, dynamic>;
          if (map.containsKey('users') && map['users'] is List) {
            return List<dynamic>.from(map['users'] as List);
          } else if (map.containsKey('results') && map['results'] is List) {
            return List<dynamic>.from(map['results'] as List);
          }
        }
      }
      return [];
    } catch (e) {
      // 错误已在上层处理，这里静默返回空列表
      return [];
    }
  }
  
  /// 添加好友
  Future<bool> addFriend(int friendId) async {
    try {
      final response = await _apiService.post(
        '/friends/add',
        data: {'friend_id': friendId},
      );
      // 后端返回成功时会有 message 字段
      if (response != null && response is Map) {
        final map = response as Map<String, dynamic>;
        return map.containsKey('message') || map.containsKey('status');
      }
      return response != null;
    } catch (e) {
      // 重新抛出异常以便上层处理错误信息
      rethrow;
    }
  }
  
  /// 接受好友请求（参照网页端：PUT /friends/update）
  Future<bool> acceptFriendRequest(int friendId) async {
    try {
      final response = await _apiService.put(
        '/friends/update',
        data: {
          'friend_id': friendId,
          'status': 'accepted',
        },
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 拒绝/屏蔽好友请求（参照网页端：PUT /friends/update）
  Future<bool> rejectFriendRequest(int friendId) async {
    try {
      final response = await _apiService.put(
        '/friends/update',
        data: {
          'friend_id': friendId,
          'status': 'blocked',
        },
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 删除好友（参照网页端：DELETE /friends/remove/{friend_id}）
  Future<bool> deleteFriend(int friendId) async {
    try {
      final response = await _apiService.delete('/friends/remove/$friendId');
      return response != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 更新好友备注（参照网页端：PUT /friends/update）
  Future<bool> updateFriendNote(int friendId, String note) async {
    try {
      final response = await _apiService.put(
        '/friends/update',
        data: {
          'friend_id': friendId,
          'note': note,
        },
      );
      return response != null;
    } catch (e) {
      return false;
    }
  }
}
