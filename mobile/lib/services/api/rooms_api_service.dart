import 'api_service.dart';

/// 房间 API 服务
class RoomsApiService {
  final ApiService _apiService = ApiService();
  
  /// 获取房间列表
  Future<List<dynamic>> getRooms({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _apiService.get(
        '/rooms',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );
      
      if (response != null && response is Map && response.containsKey('rooms')) {
        return List<dynamic>.from(response['rooms'] as List);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  /// 获取房间信息
  Future<Map<String, dynamic>?> getRoom(String roomId) async {
    try {
      return await _apiService.get('/rooms/$roomId');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 创建房间
  Future<Map<String, dynamic>?> createRoom({
    String? roomId,
    String? roomName,
    int? maxOccupants,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (roomId != null) {
        data['room_id'] = roomId;
      }
      if (roomName != null) {
        data['room_name'] = roomName;
      }
      if (maxOccupants != null) {
        data['max_occupants'] = maxOccupants;
      }
      return await _apiService.post(
        '/rooms/create',
        data: data,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 加入房间
  Future<Map<String, dynamic>?> joinRoom({
    required String roomId,
    String? displayName,
  }) async {
    try {
      return await _apiService.post(
        '/rooms/$roomId/join',
        data: {
          'display_name': displayName,
        },
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 获取房间二维码
  Future<Map<String, dynamic>?> getRoomQRCode(String roomId) async {
    try {
      return await _apiService.get('/qrcode/room/$roomId');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 离开房间
  Future<void> leaveRoom(String roomId) async {
    try {
      await _apiService.post('/rooms/$roomId/leave');
    } catch (e) {
      rethrow;
    }
  }
}
