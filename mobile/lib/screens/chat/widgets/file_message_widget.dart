import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../locales/app_localizations.dart';
import '../../../core/services/storage_service.dart';
import '../utils/chat_utils.dart';

/// 文件消息组件（支持下载）
class FileMessageWidget extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;

  const FileMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
  });

  static final Map<int, String> _downloadedFilePaths = {};

  Future<void> _downloadFile(BuildContext context) async {
    final fileUrl = message['file_url']?.toString();
    final fileName = message['file_name']?.toString() ?? 'file';
    
    if (fileUrl == null || fileUrl.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.t('errors.file_url_not_found') ?? '无法获取文件地址'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // 构建带token的URL
      final authenticatedUrl = await buildAuthenticatedUrl(fileUrl);
      
      // 获取token用于请求头
      final token = await StorageService.instance.getToken();
      
      // 使用Dio下载文件
      final dio = Dio();
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }
      
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      
      // 显示下载进度
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.t('chat.downloading') ?? '正在下载...'),
          duration: const Duration(seconds: 2),
        ),
      );
      
      // 下载文件
      await dio.download(authenticatedUrl, filePath);

      // 记录本地路径，便于下次直接打开
      final msgId = message['id'];
      if (msgId is int) {
        _downloadedFilePaths[msgId] = filePath;
      }
      
      // 下载成功提示
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('chat.download_success') ?? '下载成功'}: $fileName'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: l10n?.t('chat.open') ?? '打开',
              onPressed: () {
                // TODO: 打开文件（需要根据文件类型使用不同的应用）
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.download_failed') ?? '下载失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes == 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    final i = (bytes / k).floor();
    if (i == 0) return '$bytes ${sizes[0]}';
    return '${(bytes / k).toStringAsFixed(1)} ${sizes[i.clamp(0, sizes.length - 1)]}';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = message['file_name']?.toString() ?? 'file';
    final fileSize = message['file_size'] as int?;
    final messageId = message['id'] is int ? message['id'] as int? : null;
    
    return GestureDetector(
      onTap: () async {
        // 如果已下载过，直接打开
        if (messageId != null && _downloadedFilePaths.containsKey(messageId)) {
          final path = _downloadedFilePaths[messageId]!;
          final result = await OpenFilex.open(path);
          if (result.type != ResultType.done) {
            // 打开失败则尝试重新下载
            await _downloadFile(context);
          }
        } else {
          await _downloadFile(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[400] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file,
              color: isMe ? Colors.white : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (fileSize != null && fileSize > 0)
                    Text(
                      _formatFileSize(fileSize),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.download,
              color: isMe ? Colors.white : Colors.blue,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
