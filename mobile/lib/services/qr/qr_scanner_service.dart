import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'rsa_decrypt_service.dart';
import 'simple_decrypt_service.dart';
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
      throw Exception('二維碼資料為空');
    }
    
    // 解析二维码数据
    // 优先使用简单解密（新格式），如果失败再尝试 RSA 解密（向后兼容）
    Map<String, dynamic> data;
    final rawValue = barcode.rawValue!;
    
    // 智能判断数据格式：简单加密数据通常是 Base64 URL-safe，长度较短
    // RSA 加密数据通常是标准 Base64，长度较长，且包含 | 分隔符
    final isLikelySimpleEncrypted = rawValue.length < 200 && 
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(rawValue);
    final isLikelyRSAEncrypted = rawValue.length > 200 || rawValue.contains('|');
    
    try {
      if (isLikelySimpleEncrypted || !isLikelyRSAEncrypted) {
        // 先尝试简单解密（新格式，快速且简单）
        data = SimpleDecryptService.parseQRCodeData(rawValue);
      } else {
        // 数据特征像 RSA 加密，直接尝试 RSA 解密
        if (publicKeyPem == null || publicKeyPem.isEmpty) {
          throw Exception('检测到 RSA 加密格式，但未提供 RSA 公钥');
        }
        data = RSADecryptService.parseQRCodeData(
          rawValue,
          publicKeyPem: publicKeyPem,
        );
      }
    } catch (e) {
      // 如果简单解密失败且数据像 RSA 格式，尝试 RSA 解密
      if (isLikelySimpleEncrypted) {
        // 简单加密格式失败，如果提供了 RSA 公钥，尝试 RSA 解密（向后兼容）
        if (publicKeyPem != null && publicKeyPem.isNotEmpty) {
          try {
            data = RSADecryptService.parseQRCodeData(
              rawValue,
              publicKeyPem: publicKeyPem,
            );
          } catch (e2) {
            throw Exception('二维码解析失败\n'
                '简单解密错误: $e\n'
                'RSA 解密错误: $e2\n'
                '数据长度: ${rawValue.length}');
          }
        } else {
          throw Exception('简单解密失败: $e\n'
              '提示：可能需要 RSA 公钥进行解密');
        }
      } else {
        // RSA 解密失败，尝试简单解密（可能误判）
        try {
          data = SimpleDecryptService.parseQRCodeData(rawValue);
        } catch (e2) {
          throw Exception('二维码解析失败\n'
              'RSA 解密错误: $e\n'
              '简单解密错误: $e2\n'
              '数据长度: ${rawValue.length}');
        }
      }
    }
    
    // 驗證必要欄位
    // 客戶端不內置 API，API 唯一獲取方式為掃碼。必須包含 chat_url、api_url、room_id 或 auth_token（授權二維碼）
    final hasAuthToken = data.containsKey('auth_token');
    final hasApiUrl = data.containsKey('api_url');
    final hasChatUrl = data.containsKey('chat_url');
    final hasRoomId = data.containsKey('room_id');
    
    if (!hasAuthToken && !hasApiUrl && !hasChatUrl && !hasRoomId) {
      throw Exception('二維碼資料缺少必要欄位（chat_url、api_url、room_id 或 auth_token）');
    }
    
    // 授權二維碼必須包含 api_url 或 chat_url：API 僅通過掃碼獲取，不使用內置默認 API
    if (hasAuthToken && !hasApiUrl && !hasChatUrl) {
      throw Exception('API 地址僅能通過掃碼獲取，該二維碼未包含 API 地址\n'
          '請掃描包含 API 的授權二維碼或房間二維碼');
    }
    
    // 如果包含聊天页面URL但没有API URL，从聊天页面URL提取API地址（仍屬「從掃碼獲取」）
    if (hasChatUrl && !hasApiUrl) {
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
