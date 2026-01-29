import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 简单的解密服务
/// 支持两种格式（与后端 simple_encrypt / simple_decrypt 匹配）：
/// - 无盐（legacy）：Base64(XOR(json, fix_key))
/// - 带盐（v1）：Base64(0x01 || salt_8 || XOR(json, derived_key))，derived_key = SHA256(master_key||salt)
class SimpleDecryptService {
  static const String _defaultKey = "MOP_QR_KEY_2026";

  static Uint8List _xorBytes(List<int> data, List<int> key) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ key[i % key.length];
    }
    return out;
  }

  static List<int> _derivedKey(String masterKey, List<int> salt) {
    final h = sha256.convert([...utf8.encode(masterKey), ...salt]);
    return h.bytes;
  }

  /// 解密数据（Base64 + XOR）。自动识别无盐（legacy）与带盐（v1）格式。
  /// 
  /// [encryptedData] Base64 URL-safe 编码的加密数据
  /// [key] 主密钥（默认 MOP_QR_KEY_2026，与后端匹配）
  /// 
  /// 返回解密后的 JSON 字符串
  static String decrypt(
    String encryptedData, {
    String? key,
  }) {
    try {
      final decryptKey = key ?? _defaultKey;
      String padded = encryptedData;
      final missing = padded.length % 4;
      if (missing != 0) {
        padded += List.filled(4 - missing, '=').join();
      }
      final raw = base64Url.decode(padded);

      List<int> jsonBytes;
      if (raw.length >= 9 && raw[0] == 0x01) {
        final salt = raw.sublist(1, 9);
        final cipher = raw.sublist(9);
        final dk = _derivedKey(decryptKey, salt);
        jsonBytes = _xorBytes(cipher, dk);
      } else {
        final keyBytes = utf8.encode(decryptKey);
        jsonBytes = _xorBytes(raw, keyBytes);
      }
      return utf8.decode(jsonBytes);
    } catch (e) {
      throw Exception('简单解密失败: $e');
    }
  }
  
  /// 解析二维码数据
  /// 
  /// 支持两种格式：
  /// 1. 简单加密二维码：Base64 + XOR 混淆
  /// 2. 未加密二维码：JSON 字符串或 URL
  /// 
  /// 返回解析后的数据字典
  static Map<String, dynamic> parseQRCodeData(String qrData) {
    // 尝试作为 URL 解析
    if (qrData.startsWith('http://') || qrData.startsWith('https://')) {
      return _parseUrlFormat(qrData);
    }
    
      // 尝试作为 JSON 解析（未加密）
    try {
      final jsonData = jsonDecode(qrData) as Map<String, dynamic>;
      // 支持授权二维码（type: "auth_qr" 或 auth_token）、房间二维码（room_id）、聊天页面（chat_url）、API地址（api_url）
      if (jsonData.containsKey('room_id') || 
          jsonData.containsKey('api_url') || 
          jsonData.containsKey('chat_url') ||
          jsonData.containsKey('auth_token') ||
          (jsonData.containsKey('type') && jsonData['type'] == 'auth_qr')) {
        // 如果包含聊天页面URL但没有API URL，从聊天页面URL提取API地址
        if (jsonData.containsKey('chat_url') && !jsonData.containsKey('api_url')) {
          final chatUrl = jsonData['chat_url'] as String;
          final parsed = _parseUrlFormat(chatUrl);
          jsonData['api_url'] = parsed['api_url'];
        }
        // 如果是授权二维码（type: "auth_qr"），将 token 映射为 auth_token（统一字段名）
        if (jsonData.containsKey('type') && jsonData['type'] == 'auth_qr' && jsonData.containsKey('token')) {
          jsonData['auth_token'] = jsonData['token'];
        }
        return jsonData;
      }
    } catch (e) {
      // 不是 JSON 格式，继续尝试解密
    }
    
    // 尝试简单解密
    try {
      // 首先检查数据长度和格式
      // 简单加密的数据通常是 Base64 URL-safe 编码，长度通常在 20-200 字符之间
      // 且只包含字母、数字、- 和 _ 字符（Base64 URL-safe 字符集）
      if (qrData.length < 15) {
        throw Exception('数据长度异常（${qrData.length}字符），可能是二维码扫描不完整或被截断\n'
            '请确保二维码清晰完整，重新扫描');
      }
      
      if (qrData.length > 500) {
        throw Exception('数据长度异常（${qrData.length}字符），可能不是简单加密格式');
      }
      
      final base64UrlPattern = RegExp(r'^[A-Za-z0-9_-]+$');
      final isValidBase64Url = base64UrlPattern.hasMatch(qrData);
      
      if (!isValidBase64Url) {
        // 数据格式不对，可能包含特殊字符，不是简单加密格式
        throw Exception('数据格式不符合简单加密特征\n'
            '简单加密数据应只包含字母、数字、- 和 _ 字符\n'
            '数据长度: ${qrData.length}');
      }
      
      final decryptedData = decrypt(qrData);
      final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;
      
      // 扩展短键名为完整键名
      final expandedData = <String, dynamic>{};
      final keyMapping = {
        'u': 'api_url',
        'r': 'room_id',
        't': 'timestamp',
        'e': 'expires_at',
      };
      
      jsonData.forEach((key, value) {
        final expandedKey = keyMapping[key] ?? key;
        expandedData[expandedKey] = value;
      });
      
      return expandedData;
    } catch (e) {
      // 提供更详细的错误信息，帮助调试
      final errorMsg = e.toString();
      if (errorMsg.contains('Invalid character') || errorMsg.contains('FormatException')) {
        throw Exception('简单解密失败：Base64 解码错误\n'
            '数据格式可能不正确或数据已损坏\n'
            '错误: $e');
      } else if (errorMsg.contains('JsonException') || errorMsg.contains('SyntaxError')) {
        throw Exception('简单解密失败：JSON 解析错误\n'
            '解密后的数据不是有效的 JSON 格式\n'
            '错误: $e');
      } else {
        throw Exception('简单解密失败: $e\n'
            '提示：可能不是有效的简单加密二维码数据');
      }
    }
  }
  
  /// 解析 URL 格式的二维码数据
  static Map<String, dynamic> _parseUrlFormat(String url) {
    final uri = Uri.parse(url);
    final pathParts = uri.path.split('/').where((p) => p.isNotEmpty).toList();
    
    final data = <String, dynamic>{};
    
    // 检查是否是聊天页面URL
    if (pathParts.isNotEmpty && pathParts[0] == 'chat') {
      data['chat_url'] = url;
      if (uri.host.isNotEmpty) {
        final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
        data['api_url'] = '$baseUrl/api/v1';
      } else {
        data['api_url'] = '/api/v1';
      }
      return data;
    }
    
    // 提取房间ID（房间URL格式：/room/{room_id}）
    if (pathParts.length >= 2 && pathParts[pathParts.length - 2] == 'room') {
      data['room_id'] = pathParts[pathParts.length - 1];
    }
    
    // 提取查询参数（如 jwt, server 等）
    uri.queryParameters.forEach((key, value) {
      data[key] = value;
    });
    
    // 必须从 URL 中提取 API URL（明文二维码必须包含）
    if (uri.host.isNotEmpty) {
      final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
      data['api_url'] = '$baseUrl/api/v1';
      // 同时保存聊天页面URL（如果有房间ID）
      if (data.containsKey('room_id')) {
        data['chat_url'] = '$baseUrl/room/${data['room_id']}';
      }
    } else {
      // 相对路径，使用默认路径
      data['api_url'] = '/api/v1';
    }
    
    return data;
  }
}
