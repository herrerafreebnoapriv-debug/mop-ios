import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../locales/app_localizations.dart';
import '../../../core/services/storage_service.dart';
import '../utils/chat_utils.dart';
import '../../image/image_viewer_screen.dart';

/// 图片消息组件
class ImageMessageWidget extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;

  const ImageMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final messageText = message['message']?.toString() ?? '';
    final fileUrl = message['file_url']?.toString();
    final fileName = message['file_name']?.toString() ?? messageText;
    
    // 检查是否是 base64 数据 URI
    final bool isBase64DataUri = messageText.startsWith('data:image/');
    
    // 确定图片源
    Widget? imageWidget;
    if (fileUrl != null && fileUrl.isNotEmpty) {
      // 使用 file_url 显示网络图片（需要添加token）
      imageWidget = FutureBuilder<String>(
        future: buildAuthenticatedUrl(fileUrl),
        builder: (context, snapshot) {
          final authenticatedUrl = snapshot.data ?? fileUrl;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: authenticatedUrl,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              httpHeaders: {
                'Authorization': 'Bearer ${StorageService.instance.getToken()}',
              },
              placeholder: (context, url) => Container(
                width: 200,
                height: 200,
                color: Colors.grey[300],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 200,
                color: Colors.grey[300],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.t('errors.load_image_failed') ?? '加载失败',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else if (isBase64DataUri) {
      // 解析 base64 数据 URI
      try {
        // 处理 data:image/png;base64,xxxxx 格式
        final commaIndex = messageText.indexOf(',');
        if (commaIndex == -1 || commaIndex >= messageText.length - 1) {
          throw Exception('Invalid base64 data URI format: no comma found');
        }
        final base64String = messageText.substring(commaIndex + 1);
        // 移除可能的空白字符
        final cleanBase64 = base64String.replaceAll(RegExp(r'\s'), '');
        final imageBytes = base64.decode(cleanBase64);
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 200,
              height: 200,
              color: Colors.grey[300],
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.grey, size: 40),
                  SizedBox(height: 8),
                  Text(
                    '图片格式错误',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        // base64 解析失败，显示错误
        imageWidget = Container(
          width: 200,
          height: 200,
          color: Colors.grey[300],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: Colors.grey, size: 40),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)?.t('errors.load_image_failed') ?? '加载失败',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        );
      }
    } else {
      // 没有图片源，显示占位符
      imageWidget = Container(
        width: 200,
        height: 200,
        color: Colors.grey[300],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image, color: Colors.grey, size: 40),
            const SizedBox(height: 8),
            Text(
              fileName.isNotEmpty ? fileName : (AppLocalizations.of(context)?.t('chat.send_image') ?? '图片'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    
    return GestureDetector(
      onTap: () {
        // 点击图片时全屏显示
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              imageUrl: fileUrl ?? '',
              imageBase64: isBase64DataUri ? messageText : null,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          imageWidget,
          if (fileName.isNotEmpty && !isBase64DataUri)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                fileName,
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white70 : Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
