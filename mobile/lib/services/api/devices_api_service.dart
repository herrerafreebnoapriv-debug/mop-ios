import '../../core/config/app_config.dart';
import 'api_service.dart';

/// 设备管理 API 服务
/// 负责设备注册、拉取设备列表等
class DevicesApiService {
  final ApiService _api = ApiService();

  /// 注册当前设备
  /// [payload] 包含 device_fingerprint, device_model, imei 等
  Future<Map<String, dynamic>?> register(Map<String, dynamic> payload) async {
    if (!AppConfig.instance.isConfigured) {
      throw Exception('请先识别凭证');
    }
    return _api.post('/devices/register', data: payload);
  }
  
  /// 注册设备 FCM token（用于推送通知）
  /// [fcmToken] Firebase Cloud Messaging token
  /// [platform] 平台类型：'android' 或 'ios'
  Future<Map<String, dynamic>?> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    if (!AppConfig.instance.isConfigured) {
      throw Exception('请先识别凭证');
    }
    
    // 先注册设备（如果未注册），然后更新 FCM token
    final payload = {
      'fcm_token': fcmToken,
      'platform': platform,
    };
    
    return _api.post('/devices/register', data: payload);
  }
}
