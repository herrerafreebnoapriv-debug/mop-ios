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
  /// 支持 PKCS#8 格式（标准格式）和 PKCS#1 格式（旧格式）
  static RSAPublicKey _parsePublicKeyFromPem(String pemString) {
    // 移除 PEM 格式的头部和尾部
    final publicKeyDER = _removePemHeaders(pemString);
    
    // Base64 解码
    final publicKeyBytes = base64Decode(publicKeyDER);
    
    // 使用 ASN1Parser 解析 DER 格式的公钥
    final asn1Parser = ASN1Parser(publicKeyBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    
    BigInt? modulusInt;
    BigInt? exponentInt;
    
    // PKCS#8 格式 (SubjectPublicKeyInfo):
    // SEQUENCE {
    //   algorithm AlgorithmIdentifier,
    //   subjectPublicKey BIT STRING  -- 包含实际的 RSA 公钥
    // }
    if (topLevelSeq.elements!.length == 2) {
      try {
        // 第二个元素是 BIT STRING，包含 RSA 公钥
        final bitString = topLevelSeq.elements![1] as ASN1BitString;
        final rsaKeyBytes = bitString.stringValues as Uint8List;
        
        // 解析 BIT STRING 内部的 RSA 公钥（PKCS#1 格式）
        final rsaParser = ASN1Parser(rsaKeyBytes);
        final rsaSeq = rsaParser.nextObject() as ASN1Sequence;
        
        // RSA 公钥结构 (PKCS#1):
        // SEQUENCE {
        //   modulus           INTEGER,  -- n
        //   publicExponent    INTEGER   -- e
        // }
        if (rsaSeq.elements!.length >= 2) {
          try {
            final modulusElem = rsaSeq.elements![0];
            final exponentElem = rsaSeq.elements![1];
            
            if (modulusElem is ASN1Integer && exponentElem is ASN1Integer) {
              modulusInt = modulusElem.integer;
              exponentInt = exponentElem.integer;
            } else {
              throw Exception('RSA 公钥结构错误：期望 ASN1Integer，实际 ${modulusElem.runtimeType} 和 ${exponentElem.runtimeType}');
            }
          } catch (e) {
            throw Exception('RSA 公钥解析失败（PKCS#8 BIT STRING 内部）: $e');
          }
        }
      } catch (e) {
        // PKCS#8 解析失败，尝试 PKCS#1 格式
      }
    }
    
    // 如果 PKCS#8 解析失败，尝试 PKCS#1 格式（直接 SEQUENCE { modulus, exponent }）
    if (modulusInt == null || exponentInt == null) {
      try {
        if (topLevelSeq.elements!.length >= 2) {
          final modulusElem = topLevelSeq.elements![0];
          final exponentElem = topLevelSeq.elements![1];
          
          if (modulusElem is ASN1Integer && exponentElem is ASN1Integer) {
            modulusInt = modulusElem.integer;
            exponentInt = exponentElem.integer;
          } else {
            throw Exception('RSA 公钥结构错误（PKCS#1）：期望 ASN1Integer，实际 ${modulusElem.runtimeType} 和 ${exponentElem.runtimeType}');
          }
        }
      } catch (e) {
        final errorMsg = e.toString();
        if (errorMsg.contains('radix') || errorMsg.contains('invalid')) {
          throw Exception('RSA 公钥解析失败：数值解析错误\n'
              '错误: $e\n'
              '提示：可能是 ASN.1 整数解析失败，请检查公钥格式');
        }
        throw Exception('RSA 公钥解析失败：无法识别公钥格式（PKCS#8 或 PKCS#1）。错误: $e');
      }
    }
    
    if (modulusInt == null || exponentInt == null) {
      throw Exception('RSA 公钥解析失败：modulus 或 exponent 为空。可能是不支持的密钥格式');
    }
    
    // 验证解析出的值是否有效
    try {
      // 验证 exponent 是否合理（通常是 65537 或较小的质数）
      if (exponentInt! < BigInt.from(3)) {
        throw Exception('RSA 公钥 exponent 值异常：$exponentInt (应 >= 3)');
      }
      if (exponentInt! > BigInt.from(65537)) {
        throw Exception('RSA 公钥 exponent 值异常：$exponentInt (通常 <= 65537)');
      }
      
      // 验证 modulus 是否合理
      final keySize = modulusInt!.bitLength;
      if (keySize < 1024) {
        throw Exception('RSA 密钥长度过短：${keySize} 位（至少需要 1024 位）');
      }
      
      // 创建公钥对象
      return RSAPublicKey(modulusInt, exponentInt);
    } catch (e) {
      // 如果创建失败，提供详细信息
      final errorMsg = e.toString();
      if (errorMsg.contains('radix') || errorMsg.contains('invalid')) {
        throw Exception('RSA 公钥创建失败：数值解析错误\n'
            '错误: $e\n'
            'modulus 长度: ${modulusInt?.bitLength ?? "null"} 位\n'
            'exponent: ${exponentInt?.toString() ?? "null"}\n'
            '提示：可能是 exponent 或 modulus 的值格式不正确');
      }
      rethrow;
    }
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
      // Base64 解码（每次操作都从原始 Base64 字符串开始，避免数据被修改）
      Uint8List decodedBytes = base64Decode(encryptedData);
      
      // 如果启用解压缩，先解压（使用 gzip）
      if (decompress) {
        try {
          // 尝试解压缩（创建新的 Uint8List，避免修改原数据）
          decodedBytes = Uint8List.fromList(gzip.decode(Uint8List.fromList(decodedBytes)));
        } catch (e) {
          // 解压缩失败，抛出特定错误，不修改原始数据
          throw Exception('GZIP 解压缩失败：数据可能未压缩或已损坏。错误: $e');
        }
      }
      
      // 解码为字符串
      String decoded;
      try {
        decoded = utf8.decode(decodedBytes);
      } catch (e) {
        throw Exception('UTF-8 解码失败：数据可能已损坏。错误: $e');
      }
      
      // 分离 JSON 数据和签名（格式：json_data + "|" + signature）
      final parts = decoded.split('|');
      if (parts.length != 2) {
        throw Exception('无效的加密数据格式：缺少签名部分。数据长度: ${decoded.length}');
      }
      
      final jsonData = parts[0];
      final signatureB64 = parts[1];
      
      // 验证签名 Base64 字符串格式
      if (signatureB64.isEmpty) {
        throw Exception('签名数据为空');
      }
      
      // Base64 解码签名
      Uint8List signature;
      try {
        signature = base64Decode(signatureB64);
        if (signature.isEmpty) {
          throw Exception('签名解码后为空');
        }
      } catch (e) {
        throw Exception('签名 Base64 解码失败: $e');
      }
      
      // 解析公钥（这里可能抛出 ASN.1 错误）
      RSAPublicKey publicKey;
      try {
        publicKey = _parsePublicKeyFromPem(publicKeyPem);
        
        // 验证公钥有效性
        if (publicKey.n == null || publicKey.exponent == null) {
          throw Exception('RSA 公钥无效：modulus 或 exponent 为空');
        }
        
        // 验证密钥大小
        final keySize = publicKey.n!.bitLength;
        if (keySize < 1024) {
          throw Exception('RSA 密钥长度过短：${keySize} 位（至少需要 1024 位）');
        }
        
      } catch (e) {
        final errorMsg = e.toString();
        // 检查是否是 ASN.1 相关错误
        if (errorMsg.contains('ASN1') || 
            errorMsg.contains('ASN.1') || 
            errorMsg.contains('type cast') ||
            errorMsg.contains('ASN1Object') ||
            errorMsg.contains('cast') ||
            errorMsg.contains('Sequence')) {
          throw Exception('RSA 公钥解析失败（ASN.1 错误）: $e\n'
              '提示：\n'
              '1. 可能是公钥格式错误（PKCS#1 vs PKCS#8）\n'
              '2. 可能是公钥内容损坏\n'
              '3. 请检查公钥是否为有效的 PEM 格式');
        }
        throw Exception('RSA 公钥解析失败: $e');
      }
      
      // 使用 RSA 公钥验证签名（PSS padding + SHA256）
      // 这是签名验证过程，不是解密过程
      RSASigner signer;
      try {
        // 验证公钥对象有效性
        if (publicKey.n == null) {
          throw Exception('RSA 公钥无效：modulus (n) 为空');
        }
        if (publicKey.exponent == null) {
          throw Exception('RSA 公钥无效：exponent (e) 为空');
        }
        
        // 创建 PSS 签名器，使用 SHA-256 和 PSS padding
        // PointyCastle 的算法字符串格式：'SHA-256/PSS'
        // 注意：不同版本的 PointyCastle 可能使用不同的格式
        Exception? lastError;
        List<String> triedFormats = [];
        RSASigner? tempSigner;
        
        // 尝试多种算法字符串格式
        final formatsToTry = [
          'SHA-256/PSS',  // 标准格式（带连字符）
          'SHA256/PSS',   // 无连字符
          'SHA-256/PSS-MGF1',  // 完整格式
          'SHA256/PSS-MGF1',
        ];
        
        for (final format in formatsToTry) {
          try {
            tempSigner = RSASigner(SHA256Digest(), format);
            // 如果成功，跳出循环
            break;
          } catch (e) {
            lastError = e is Exception ? e : Exception(e.toString());
            triedFormats.add('"$format" -> $lastError');
            
            // 如果错误不是 radix 或 invalid 相关，可能是其他问题，直接抛出
            final errorMsg = e.toString();
            if (!errorMsg.contains('radix') && 
                !errorMsg.contains('invalid') && 
                !errorMsg.contains('SH') &&
                !errorMsg.contains('format') &&
                !errorMsg.contains('Unsupported')) {
              rethrow;
            }
          }
        }
        
        // 如果所有格式都失败了
        if (tempSigner == null) {
          throw Exception('RSA 签名器创建失败：所有算法字符串格式都失败\n'
              '公钥信息: modulus=${publicKey.n?.bitLength}位, exponent=${publicKey.exponent}\n'
              '尝试的格式:\n${triedFormats.join("\n")}\n'
              '提示：\n'
              '1. 可能是 PointyCastle 版本不支持 PSS padding\n'
              '2. 可能是算法字符串格式不正确\n'
              '3. 请检查 PointyCastle 版本是否 >= 3.0.0\n'
              '4. 当前 PointyCastle 版本: ^3.7.3');
        }
        
        // 赋值给 signer
        signer = tempSigner;
        
        // 初始化签名器用于验证（false 表示验证模式）
        // 需要 PublicKeyParameter 包装公钥
        final publicKeyParam = PublicKeyParameter<RSAPublicKey>(publicKey);
        
        // 初始化签名器
        signer.init(false, publicKeyParam);
        
      } catch (e) {
        final errorMsg = e.toString();
        // 提供更详细的错误信息
        if (errorMsg.contains('null') || errorMsg.contains('Null')) {
          throw Exception('RSA 签名器初始化失败：公钥为空或无效\n'
              '公钥 modulus: ${publicKey.n != null ? "${publicKey.n!.bitLength}位" : "null"}\n'
              '公钥 exponent: ${publicKey.exponent ?? "null"}\n'
              '错误详情: $e');
        } else if (errorMsg.contains('PSS') || errorMsg.contains('padding')) {
          throw Exception('RSA 签名器初始化失败：PSS padding 配置错误\n'
              '错误: $e\n'
              '提示：可能是 PointyCastle 版本不支持 PSS，或需要额外配置\n'
              '请检查 PointyCastle 版本是否 >= 3.0.0');
        } else if (errorMsg.contains('ASN1') || errorMsg.contains('ASN.1')) {
          throw Exception('RSA 签名器初始化失败：公钥 ASN.1 解析错误\n'
              '错误: $e');
        } else if (errorMsg.contains('Unsupported') || errorMsg.contains('不支持')) {
          throw Exception('RSA 签名器初始化失败：不支持的操作\n'
              '错误: $e\n'
              '提示：可能是 PointyCastle 库版本过低或算法不支持');
        } else {
          throw Exception('RSA 签名器初始化失败\n'
              '错误: $e\n'
              '公钥信息: modulus=${publicKey.n?.bitLength ?? "null"}位, '
              'exponent=${publicKey.exponent ?? "null"}\n'
              '请检查公钥格式和 PointyCastle 库版本');
        }
      }
      
      // 验证签名（使用原始 JSON 数据）
      final jsonBytes = utf8.encode(jsonData);
      bool isValid;
      try {
        // 检查签名长度（RSA-2048 应该是 256 字节）
        if (signature.length != 256) {
          throw Exception('签名长度不正确：期望 256 字节（RSA-2048），实际 ${signature.length} 字节');
        }
        
        // 验证签名
        isValid = signer.verifySignature(
          Uint8List.fromList(jsonBytes),
          RSASignature(signature),
        );
      } catch (e) {
        final errorMsg = e.toString();
        // 检查是否是 ASN.1 相关错误
        if (errorMsg.contains('ASN1') || 
            errorMsg.contains('ASN.1') || 
            errorMsg.contains('type cast') ||
            errorMsg.contains('ASN1Object') ||
            errorMsg.contains('cast')) {
          throw Exception('RSA 签名验证过程出错（ASN.1 错误）: $e\n'
              '提示：\n'
              '1. 可能是签名数据格式错误或已损坏\n'
              '2. 可能是公钥格式不匹配（PKCS#1 vs PKCS#8）\n'
              '3. 可能是解压缩失败导致数据损坏\n'
              '签名长度: ${signature.length} 字节\n'
              'JSON 数据: $jsonData');
        }
        throw Exception('RSA 签名验证过程出错: $e');
      }
      
      if (!isValid) {
        throw Exception('RSA 签名验证失败：数据可能被篡改或使用错误的公钥');
      }
      
      // 签名验证成功，返回原始 JSON 数据
      return jsonData;
    } catch (e) {
      // 重新抛出更详细的错误信息
      final errorMsg = e.toString();
      if (errorMsg.contains('ASN1') || errorMsg.contains('ASN.1') || errorMsg.contains('type cast')) {
        throw Exception('RSA 解密失败（ASN.1 解析错误）: $e\n提示：可能是公钥格式错误、签名数据损坏或解压缩失败导致数据损坏');
      }
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
          // 检查错误类型，决定是否尝试不解压缩的方式
          final errorMsg = e.toString().toLowerCase();
          
          // 如果是解压缩相关的错误（GZIP、解压缩），尝试不解压缩的方式（向后兼容）
          // 如果是 ASN.1 错误或其他严重错误，可能表示数据格式问题，但仍可以尝试不解压缩
          // 因为可能是压缩数据损坏导致了解压缩失败，但原始数据可能是正确的
          if (errorMsg.contains('gzip') || 
              errorMsg.contains('解压缩') || 
              errorMsg.contains('asn1') || 
              errorMsg.contains('asn.1') ||
              errorMsg.contains('type cast')) {
            try {
              // 尝试不解压缩的方式（使用原始的 Base64 数据）
              decryptedData = decrypt(qrData, publicKeyPem, decompress: false);
            } catch (e2) {
              // 两次都失败，检查是否是相同的 ASN.1 错误
              final errorMsg2 = e2.toString().toLowerCase();
              if ((errorMsg.contains('asn1') || errorMsg.contains('asn.1') || errorMsg.contains('type cast')) &&
                  (errorMsg2.contains('asn1') || errorMsg2.contains('asn.1') || errorMsg2.contains('type cast'))) {
                // 两次都是 ASN.1 错误，可能是公钥或签名格式问题
                throw Exception('RSA 解密失败（ASN.1 解析错误，解压缩和解压缩都失败）:\n解压缩错误: $e\n不解压缩错误: $e2\n提示：可能是公钥格式错误或二维码数据损坏');
              }
              // 抛出第一个错误（解压缩的错误通常更具体）
              throw Exception('RSA 解密失败（尝试解压缩和不解压缩都失败）:\n解压缩错误: $e\n不解压缩错误: $e2');
            }
          } else {
            // 其他错误，重新抛出
            rethrow;
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
      throw MissingPublicKeyException('无法识别凭证，请确保已正确扫码授权');
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
