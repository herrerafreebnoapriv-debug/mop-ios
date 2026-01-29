import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/storage_service.dart';

/// 聊天工具函数

/// 格式化时间（格式：YYYY/MM/DD HH:mm，正确处理时区）
String formatChatTime(DateTime dateTime) {
  // 确保使用本地时区
  final localTime = dateTime.toLocal();
  return '${localTime.year}/${localTime.month.toString().padLeft(2, '0')}/${localTime.day.toString().padLeft(2, '0')} ${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
}

/// 解析时间字符串（正确处理时区）
DateTime? parseChatDateTime(String? timeStr) {
  if (timeStr == null || timeStr.isEmpty) return null;
  try {
    // 如果字符串包含时区信息，parse 会自动处理
    // 如果没有时区信息，假设是 UTC，然后转换为本地时间
    final dt = DateTime.parse(timeStr);
    // 如果解析的时间没有时区信息，假设是 UTC
    if (dt.isUtc) {
      return dt.toLocal();
    }
    return dt;
  } catch (e) {
    debugPrint('⚠️ 时间解析失败: $timeStr, error: $e');
    return null;
  }
}

/// 构建带认证token的文件URL
Future<String> buildAuthenticatedUrl(String? fileUrl) async {
  if (fileUrl == null || fileUrl.isEmpty) return '';
  
  // 如果已经是完整URL（包含http/https），直接使用
  if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
    final uri = Uri.parse(fileUrl);
    final token = await StorageService.instance.getToken();
    if (token != null && token.isNotEmpty) {
      return uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': token,
      }).toString();
    }
    return fileUrl;
  }
  
  // 如果是相对路径，需要拼接API base URL
  final apiBase = AppConfig.instance.apiBaseUrl;
  if (apiBase == null || apiBase.isEmpty) return fileUrl;
  
  // 移除 /api/v1 后缀（如果存在），因为文件路径可能已经包含
  String baseUrl = apiBase;
  if (baseUrl.endsWith('/api/v1')) {
    baseUrl = baseUrl.substring(0, baseUrl.length - 7);
  }
  baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
  
  // 确保 fileUrl 以 / 开头
  String path = fileUrl.startsWith('/') ? fileUrl : '/$fileUrl';
  
  final fullUrl = '$baseUrl$path';
  final uri = Uri.parse(fullUrl);
  final token = await StorageService.instance.getToken();
  if (token != null && token.isNotEmpty) {
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'token': token,
    }).toString();
  }
  return fullUrl;
}

/// 从消息中解析 call_invitation（Socket 顶层 或 API extra_data）
Map<String, dynamic>? getCallInvitation(Map<String, dynamic> msg) {
  // 先检查顶层 call_invitation（Socket 实时推送）
  var v = msg['call_invitation'];
  if (v is Map) {
    debugPrint('✓ 从顶层 call_invitation 解析到邀请数据: room_id=${v['room_id']}');
    return Map<String, dynamic>.from(v);
  }
  
  // 再检查 extra_data.call_invitation（API 历史消息）
  final ed = msg['extra_data'];
  if (ed is Map) {
    v = (ed as Map)['call_invitation'];
    if (v is Map) {
      debugPrint('✓ 从 extra_data.call_invitation 解析到邀请数据: room_id=${v['room_id']}');
      return Map<String, dynamic>.from(v);
    }
  }
  
  debugPrint('⚠️ 未找到 call_invitation 数据: msg keys=${msg.keys.toList()}, extra_data present=${ed != null}');
  return null;
}

/// 统一把 ID 转为 int 再比较，避免 API 返回 number/string 导致过滤掉系统消息
int? safeInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}
