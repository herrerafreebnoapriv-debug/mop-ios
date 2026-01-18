import 'api_service.dart';

/// 通话记录 API 服务
class CallsApiService {
  final ApiService _apiService = ApiService();
  
  /// 获取通话记录列表
  Future<List<dynamic>> getCalls({
    int skip = 0,
    int limit = 100,
    String? callType,
    String? callStatus,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'skip': skip,
        'limit': limit,
      };
      
      if (callType != null) {
        queryParams['call_type'] = callType;
      }
      if (callStatus != null) {
        queryParams['call_status'] = callStatus;
      }
      
      final response = await _apiService.get(
        '/calls',
        queryParameters: queryParams,
      );
      
      if (response != null && response is List) {
        return List<dynamic>.from(response);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  /// 获取通话记录详情
  Future<Map<String, dynamic>?> getCall(int callId) async {
    try {
      return await _apiService.get('/calls/$callId');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 获取通话统计信息
  Future<Map<String, dynamic>?> getCallStats() async {
    try {
      return await _apiService.get('/calls/stats/summary');
    } catch (e) {
      rethrow;
    }
  }
  
  /// 创建通话记录
  Future<Map<String, dynamic>?> createCall({
    required String callType,
    required String jitsiRoomId,
    String callStatus = 'initiated',
    int? calleeId,
    int? roomId,
  }) async {
    try {
      return await _apiService.post(
        '/calls',
        data: {
          'call_type': callType,
          'call_status': callStatus,
          'callee_id': calleeId,
          'room_id': roomId,
          'jitsi_room_id': jitsiRoomId,
        },
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// 更新通话记录
  Future<Map<String, dynamic>?> updateCall({
    required int callId,
    String? callStatus,
    DateTime? startTime,
    DateTime? endTime,
    int? duration,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (callStatus != null) {
        data['call_status'] = callStatus;
      }
      if (startTime != null) {
        data['start_time'] = startTime.toIso8601String();
      }
      if (endTime != null) {
        data['end_time'] = endTime.toIso8601String();
      }
      if (duration != null) {
        data['duration'] = duration;
      }
      
      return await _apiService.put(
        '/calls/$callId',
        data: data,
      );
    } catch (e) {
      rethrow;
    }
  }
}
