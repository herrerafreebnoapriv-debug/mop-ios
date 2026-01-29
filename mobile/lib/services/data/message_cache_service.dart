import 'dart:convert';

import '../../core/services/storage_service.dart';

/// 简单的消息/会话本地缓存服务
/// 使用 SharedPreferences 保存最近若干条消息和会话列表，支持：
/// - 会话列表秒开
/// - 聊天窗口使用本地消息秒开
/// - 配合后端 /chat/messages/since 做增量补齐
class MessageCacheService {
  MessageCacheService._internal();

  static final MessageCacheService instance = MessageCacheService._internal();

  static const String _conversationsKey = 'chat_conversations_cache';

  String _messagesKey({
    required bool isRoom,
    required int? userId,
    required int? roomId,
  }) {
    if (isRoom) {
      return 'chat_messages_room_${roomId ?? 0}';
    } else {
      return 'chat_messages_user_${userId ?? 0}';
    }
  }

  String _lastIdKey({
    required bool isRoom,
    required int? userId,
    required int? roomId,
  }) {
    if (isRoom) {
      return 'chat_last_id_room_${roomId ?? 0}';
    } else {
      return 'chat_last_id_user_${userId ?? 0}';
    }
  }

  /// 保存会话列表
  Future<void> saveConversations(List<dynamic> conversations) async {
    try {
      final jsonStr = jsonEncode(conversations);
      await StorageService.instance.setString(_conversationsKey, jsonStr);
    } catch (_) {
      // 忽略缓存失败
    }
  }

  /// 读取会话列表缓存
  Future<List<dynamic>> getConversations() async {
    try {
      final jsonStr = StorageService.instance.getString(_conversationsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final data = jsonDecode(jsonStr);
      if (data is List) {
        return List<dynamic>.from(data);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 保存某个会话的消息（只保留最近 maxCount 条）
  Future<void> saveMessagesForChat({
    required bool isRoom,
    required int? userId,
    required int? roomId,
    required List<Map<String, dynamic>> messages,
    int maxCount = 100,
  }) async {
    try {
      if (messages.isEmpty) return;
      // 只保留最近 maxCount 条（假设传入已按时间升序排列）
      final trimmed = messages.length > maxCount
          ? messages.sublist(messages.length - maxCount)
          : messages;

      final key = _messagesKey(isRoom: isRoom, userId: userId, roomId: roomId);
      final jsonStr = jsonEncode(trimmed);
      await StorageService.instance.setString(key, jsonStr);

      // 记录该会话的最大 message_id，供 /messages/since 使用
      int lastId = 0;
      for (final m in trimmed) {
        final id = m['id'];
        if (id is int && id > lastId) {
          lastId = id;
        } else if (id != null) {
          final parsed = int.tryParse(id.toString());
          if (parsed != null && parsed > lastId) {
            lastId = parsed;
          }
        }
      }
      final lastKey =
          _lastIdKey(isRoom: isRoom, userId: userId, roomId: roomId);
      await StorageService.instance
          .setString(lastKey, lastId > 0 ? lastId.toString() : '0');
    } catch (_) {
      // 忽略缓存失败
    }
  }

  /// 读取某个会话的本地消息（按时间升序）
  Future<List<Map<String, dynamic>>> getMessagesForChat({
    required bool isRoom,
    required int? userId,
    required int? roomId,
  }) async {
    try {
      final key = _messagesKey(isRoom: isRoom, userId: userId, roomId: roomId);
      final jsonStr = StorageService.instance.getString(key);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final data = jsonDecode(jsonStr);
      if (data is List) {
        final list = data
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: true);
        // 再按 created_at 排序兜底
        list.sort((a, b) {
          final ta = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return ta.compareTo(tb);
        });
        return list;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 获取某个会话已缓存的最大 message_id（默认 0）
  Future<int> getLastMessageIdForChat({
    required bool isRoom,
    required int? userId,
    required int? roomId,
  }) async {
    try {
      final key =
          _lastIdKey(isRoom: isRoom, userId: userId, roomId: roomId);
      final v = StorageService.instance.getString(key);
      if (v == null || v.isEmpty) return 0;
      return int.tryParse(v) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

