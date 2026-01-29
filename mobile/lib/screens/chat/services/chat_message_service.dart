import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/socket_provider.dart';
import '../../../locales/app_localizations.dart';
import '../../../services/api/chat_api_service.dart';
import '../../../services/api/files_api_service.dart';

/// 聊天消息发送服务
class ChatMessageService {
  final ChatApiService _chatApiService = ChatApiService();
  final FilesApiService _filesApiService = FilesApiService();

  /// 发送文本消息
  Future<void> sendTextMessage({
    required BuildContext context,
    required String message,
    required int? userId,
    required int? roomId,
    required Function(Map<String, dynamic>) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final socketProvider = Provider.of<SocketProvider>(context, listen: false);
      if (socketProvider.isConnected) {
        socketProvider.sendMessage(
          receiverId: userId,
          roomId: roomId,
          message: message,
          messageType: 'text',
        );
        
        socketProvider.onMessageSent((confirmData) {
          debugPrint('✓ 消息发送确认: $confirmData');
        });
        
        socketProvider.onError((errorData) {
          debugPrint('✗ 发送消息错误: $errorData');
          onError(errorData['message']?.toString() ?? '未知错误');
        });
      } else {
        await _chatApiService.sendMessage(
          receiverId: userId,
          roomId: roomId,
          message: message,
          messageType: 'text',
        );
      }
    } catch (e) {
      onError(e.toString());
    }
  }
  
  /// 创建临时消息（用于乐观更新）
  Map<String, dynamic> createTempMessage({
    required BuildContext context,
    required String message,
    required int? userId,
    required int? roomId,
  }) {
    final currentUser = Provider.of<AuthProvider>(context, listen: false).currentUser;
    return {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': currentUser?.id ?? 0,
      'receiver_id': userId,
      'room_id': roomId,
      'message': message,
      'message_type': 'text',
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
      'sender_nickname': currentUser?.nickname ?? currentUser?.username ?? (AppLocalizations.of(context)?.t('common.me') ?? '我'),
    };
  }

  /// 发送图片消息
  Future<void> sendImageMessage({
    required BuildContext context,
    required String imagePath,
    required int? userId,
    required int? roomId,
    required Function() onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final uploadResponse = await _filesApiService.uploadFile(
        imagePath,
        fieldName: 'file',
        additionalData: {'message_type': 'image'},
      );

      if (uploadResponse != null) {
        final fileUrl = uploadResponse['file_url']?.toString();
        final fileName = uploadResponse['file_name']?.toString() ?? 'image.jpg';
        
        if (fileUrl == null || fileUrl.isEmpty) {
          throw Exception('上传失败：未返回文件URL');
        }

        await _chatApiService.sendMessage(
          receiverId: userId,
          roomId: roomId,
          message: fileName,
          messageType: 'image',
          fileUrl: fileUrl,
          fileName: fileName,
        );

        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: userId,
            roomId: roomId,
            message: fileName,
            messageType: 'image',
            fileUrl: fileUrl,
            fileName: fileName,
          );
        }

        onSuccess();
      } else {
        throw Exception('文件上传失败');
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  /// 发送语音消息
  Future<void> sendVoiceMessage({
    required BuildContext context,
    required String audioPath,
    required int? userId,
    required int? roomId,
    required Function() onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final uploadResponse = await _filesApiService.uploadFile(
        audioPath,
        fieldName: 'file',
        additionalData: {'message_type': 'audio'},
      );

      if (uploadResponse != null && uploadResponse['file_id'] != null) {
        final fileId = uploadResponse['file_id'] as int;
        final fileName = uploadResponse['file_name']?.toString() ?? 'voice.m4a';

        await _chatApiService.sendMessage(
          receiverId: userId,
          roomId: roomId,
          message: fileName,
          messageType: 'audio',
          fileId: fileId,
        );

        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: userId,
            roomId: roomId,
            message: fileName,
            messageType: 'audio',
            fileId: fileId,
          );
        }

        onSuccess();
      } else {
        throw Exception('文件上传失败');
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  /// 发送文件消息
  Future<void> sendFileMessage({
    required BuildContext context,
    required String filePath,
    required int? userId,
    required int? roomId,
    required Function() onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final file = File(filePath);
      final fileName = file.path.split('/').last;

      final uploadResponse = await _filesApiService.uploadFile(
        filePath,
        fieldName: 'file',
        additionalData: {'message_type': 'file'},
      );

      if (uploadResponse != null && uploadResponse['file_id'] != null) {
        final fileId = uploadResponse['file_id'] as int;

        await _chatApiService.sendMessage(
          receiverId: userId,
          roomId: roomId,
          message: fileName,
          messageType: 'file',
          fileId: fileId,
        );

        final socketProvider = Provider.of<SocketProvider>(context, listen: false);
        if (socketProvider.isConnected) {
          socketProvider.sendMessage(
            receiverId: userId,
            roomId: roomId,
            message: fileName,
            messageType: 'file',
            fileId: fileId,
          );
        }

        onSuccess();
      } else {
        throw Exception('文件上传失败');
      }
    } catch (e) {
      onError(e.toString());
    }
  }
}
