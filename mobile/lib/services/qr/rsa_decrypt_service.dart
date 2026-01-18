import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show gzip;
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';

/// RSA 公钥缺失异常
/// 当检测到加密二维码但缺少 RSA 公钥时抛出
class MissingPublicKeyException implements Exception {
  final String message;
  MissingPublicKeyException(this.message);
  
  @override
  String toString() => message;
}

/// RSA 解密服务
/// 用于解密从二维码扫描获取的加密数据
class RSADecryptService {
  /// 从 PEM 格式的公钥字符串加载公钥
  static RSAPublicKey _parsePublicKeyFromPem(String pemString) {
    // 移除 PEM 格式的头部和尾部
    final publicKeyDER = _removePemHeaders(pemString);
    
    // Base64 解码
    final publicKeyBytes = base64Decode(publicKeyDER);
    
    // 使用 ASN1Parser 解析 DER 格式的公钥
    final asn1Parser = ASN1Parser(publicKeyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    
    // RSA 公钥的 ASN1 结构：
    // RSAPublicKey ::= SEQUENCE {
    //   modulus           INTEGER,  -- n
    //   publicExponent    INTEGER   -- e
    // }
    final modulusInt = (topLevelSeq.elements![0] as ASN1Integer).integer;
    final exponentInt = (topLevelSeq.elements![1] as ASN1Integer).integer;
    
    if (modulusInt == null || exponentInt == null) {
      throw Exception('RSA 公钥解析失败：modulus 或 exponent 为空');
    }
    
    return RSAPublicKey(modulusInt, exponentInt);
  }
  
  /// 移除 PEM 格式的头部和尾部
  static String _removePemHeaders(String pemString) {
    return pemString
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('-----BEGIN RSA PUBLIC KEY-----', '')
        .replaceAll('-----END RSA PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll(' ', '');
  }
  
  /// 使用 RSA 公钥验证签名并解密数据
  /// 
  /// 注意：后端使用的是 RSA 签名方式（PSS padding + SHA256），不是加密
  /// 流程：私钥签名 -> 公钥验证签名 -> 提取原始数据
  /// 
  /// [encryptedData] Base64 编码的加密数据（格式：base64(json_data + "|" + signature)）
  /// [publicKeyPem] PEM 格式的 RSA 公钥
  /// [decompress] 是否解压缩（如果加密时使用了压缩）
  /// 
  /// 返回解密后的 JSON 字符串
  static String decrypt(
    String encryptedData,
    String publicKeyPem, {
    bool decompress = false,
  }) {
    try {
      // Base64 解码
      Uint8List decodedBytes = base64Decode(encryptedData);
      
      // 如果启用解压缩，先解压（使用 gzip）
      if (decompress) {
        decodedBytes = Uint8List.fromList(gzip.decode(decodedBytes));
      }
      
      // 解码为字符串
      final decoded = utf8.decode(decodedBytes);
      
      // 分离 JSON 数据和签名（格式：json_data + "|" + signature）
      final parts = decoded.split('|');
      if (parts.length != 2) {
        throw Exception('无效的加密数据格式：缺少签名部分');
      }
      
      final jsonData = parts[0];
      final signatureB64 = parts[1];
      
      // Base64 解码签名
      final signature = base64Decode(signatureB64);
      
      // 解析公钥
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);
      
      // 使用 RSA 公钥验证签名（PSS padding + SHA256）
      // 这是签名验证过程，不是解密过程
      final signer = RSASigner(SHA256Digest(), 'SHA-256/PSS');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      
      // 验证签名（使用原始 JSON 数据）
      final jsonBytes = utf8.encode(jsonData);
      final isValid = signer.verifySignature(
        Uint8List.fromList(jsonBytes),
        RSASignature(signature),
      );
      
      if (!isValid) {
        throw Exception('RSA 签名验证失败：数据可能被篡改或使用错误的公钥');
      }
      
      // 签名验证成功，返回原始 JSON 数据
      return jsonData;
    } catch (e) {
      throw Exception('RSA 解密失败: $e');
    }
  }
  
  /// 验证并解析二维码数据
  /// 
  /// 支持两种格式：
  /// 1. 加密二维码：RSA 加密的 Base64 数据
  /// 2. 未加密二维码：JSON 字符串或 URL
  /// 
  /// 返回解析后的数据字典
  /// 
  /// 抛出 [MissingPublicKeyException] 如果检测到加密二维码但缺少公钥
  static Map<String, dynamic> parseQRCodeData(
    String qrData, {
    String? publicKeyPem,
  }) {
    // 尝试作为 URL 解析
    if (qrData.startsWith('http://') || qrData.startsWith('https://')) {
      return _parseUrlFormat(qrData);
    }
    
      // 尝试作为 JSON 解析（未加密）
      try {
        final jsonData = jsonDecode(qrData) as Map<String, dynamic>;
        // 支持聊天页面URL或API URL或房间ID
        if (jsonData.containsKey('room_id') || 
            jsonData.containsKey('api_url') || 
            jsonData.containsKey('chat_url')) {
          // 如果包含聊天页面URL但没有API URL，从聊天页面URL提取API地址
          if (jsonData.containsKey('chat_url') && !jsonData.containsKey('api_url')) {
            final chatUrl = jsonData['chat_url'] as String;
            final parsed = _parseUrlFormat(chatUrl);
            jsonData['api_url'] = parsed['api_url'];
          }
          return jsonData;
        }
      } catch (e) {
        // 不是 JSON 格式，继续尝试解密
      }
    
    // 如果既不是 URL 也不是 JSON，可能是加密的二维码
    // 尝试 RSA 解密（加密二维码，实际是签名验证）
    if (publicKeyPem != null && publicKeyPem.isNotEmpty) {
      try {
        // 先尝试解压缩的方式（因为后端默认使用压缩）
        String decryptedData;
        try {
          decryptedData = decrypt(qrData, publicKeyPem, decompress: true);
        } catch (e) {
          // 如果解压缩失败，尝试不解压缩的方式（向后兼容）
          try {
            decryptedData = decrypt(qrData, publicKeyPem, decompress: false);
          } catch (e2) {
            // 两次都失败，抛出第一个错误（解压缩的错误通常更具体）
            throw Exception('RSA 解密失败（尝试解压缩和解压缩都失败）: $e');
          }
        }
        
        // 解析 JSON 数据
        final jsonData = jsonDecode(decryptedData) as Map<String, dynamic>;
        
        // 扩展短键名为完整键名（如果需要）
        // 后端使用短键名：u -> api_url, r -> room_id, t -> timestamp, e -> expires_at
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
        throw Exception('RSA 解密失败: $e');
      }
    } else {
      // 检测到可能是加密二维码，但缺少公钥
      // 抛出特定异常，让调用者可以区分这种情况
      throw MissingPublicKeyException('未提供 RSA 公钥，无法解密加密二维码。请先设定 API 地址或确保应用已加载内置公钥');
    }
  }
  
  /// 解析 URL 格式的二维码数据
  /// 支持格式：
  /// 1. 聊天页面URL：https://domain.com/chat 或 /chat
  /// 2. 房间URL：https://domain.com/room/{room_id}?token=xxx
  static Map<String, dynamic> _parseUrlFormat(String url) {
    final uri = Uri.parse(url);
    final pathParts = uri.path.split('/').where((p) => p.isNotEmpty).toList();
    
    final data = <String, dynamic>{};
    
    // 检查是否是聊天页面URL（移动端登录前扫码获取的接口）
    if (pathParts.isNotEmpty && pathParts[0] == 'chat') {
      // 这是聊天页面URL，保存聊天页面URL，并提取API地址
      data['chat_url'] = url;
      // 从聊天页面URL提取API地址
      if (uri.host.isNotEmpty) {
        final baseUrl = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
        data['api_url'] = '$baseUrl/api/v1';
      } else {
        // 相对路径，使用当前域名
        data['api_url'] = '/api/v1';
      }
      return data;
    }
    
    // 提取房间ID（房间URL格式）
    if (pathParts.length >= 2 && pathParts[pathParts.length - 2] == 'room') {
      data['room_id'] = pathParts[pathParts.length - 1];
    }
    
    // 提取查询参数
    uri.queryParameters.forEach((key, value) {
      data[key] = value;
    });
    
    // 如果 URL 包含域名，可以提取 API URL
    if (uri.host.isNotEmpty) {
      data['api_url'] = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}/api/v1';
    }
    
    return data;
  }
}
