import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'rsa_decrypt_service.dart';
import '../../core/config/app_config.dart';

/// 二维码扫描服务
class QRScannerService {
  MobileScannerController? _controller;
  
  /// 创建扫描控制器
  MobileScannerController createController() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    return _controller!;
  }
  
  /// 释放扫描控制器
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
  
  /// 检查相机权限
  Future<bool> checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      return true;
    }
    
    if (status.isDenied) {
      final result = await Permission.camera.request();
      return result.isGranted;
    }
    
    return false;
  }
  
  /// 处理扫描结果
  /// 
  /// [barcode] 扫描到的二维码数据
  /// [publicKeyPem] RSA 公钥（用于解密加密二维码）
  /// 
  /// 返回解析后的配置数据，并自动更新 AppConfig
  Future<Map<String, dynamic>> processScanResult(
    Barcode barcode, {
    String? publicKeyPem,
  }) async {
    if (barcode.rawValue == null || barcode.rawValue!.isEmpty) {
      throw Exception('二维码数据为空');
    }
    
    // 解析二维码数据
    // 注意：MissingPublicKeyException 会直接抛出，不包装
    final data = RSADecryptService.parseQRCodeData(
      barcode.rawValue!,
      publicKeyPem: publicKeyPem,
    );
    
    // 验证必要字段
    // 移动端登录前扫码：必须包含 chat_url 或 api_url（用于获取聊天页面接口）
    // 登录后扫码：可以包含 room_id（用于加入房间）
    if (!data.containsKey('api_url') && 
        !data.containsKey('chat_url') && 
        !data.containsKey('room_id')) {
      throw Exception('二维码数据缺少必要字段（chat_url、api_url 或 room_id）');
    }
    
    // 如果包含聊天页面URL但没有API URL，从聊天页面URL提取API地址
    if (data.containsKey('chat_url') && !data.containsKey('api_url')) {
      final chatUrl = data['chat_url'] as String;
      final uri = Uri.parse(chatUrl);
      if (uri.host.isNotEmpty) {
        final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
        data['api_url'] = '$baseUrl/api/v1';
      } else {
        data['api_url'] = '/api/v1';
      }
    }
    
    // 更新应用配置
    await AppConfig.instance.updateConfig(data);
    
    return data;
  }
  
  /// 从二维码数据中提取 API URL
  /// 
  /// 如果二维码中包含 api_url，直接使用
  /// 如果只包含 room_id，需要从后端获取 API URL
  String? extractApiUrl(Map<String, dynamic> qrData) {
    if (qrData.containsKey('api_url')) {
      return qrData['api_url'] as String;
    }
    
    // 如果二维码是 URL 格式，可以从 URL 中提取
    // 格式：https://domain.com/room/{room_id}
    // 提取为：https://domain.com/api/v1
    return null;
  }
}
