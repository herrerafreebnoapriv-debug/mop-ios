import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../core/services/storage_service.dart';

/// 图片查看器页面（全屏显示）
class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String? imageBase64; // base64 数据 URI

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.imageBase64,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: _buildImage(),
        ),
      ),
    );
  }

  Future<String> _buildAuthenticatedUrl(String url) async {
    if (url.isEmpty) return '';
    // 已经是完整 http/https
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final uri = Uri.parse(url);
      final token = await StorageService.instance.getToken();
      if (token != null && token.isNotEmpty) {
        return uri.replace(queryParameters: {
          ...uri.queryParameters,
          'token': token,
        }).toString();
      }
      return url;
    }

    // 相对路径，拼接 API Base
    final apiBase = AppConfig.instance.apiBaseUrl;
    if (apiBase == null || apiBase.isEmpty) return url;

    String baseUrl = apiBase;
    if (baseUrl.endsWith('/api/v1')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 7);
    }
    baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');

    final path = url.startsWith('/') ? url : '/$url';
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

  Widget _buildImage() {
    // 优先使用 base64 数据 URI
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        // 处理 data:image/png;base64,xxxxx 格式
        final commaIndex = imageBase64!.indexOf(',');
        if (commaIndex != -1 && commaIndex < imageBase64!.length - 1) {
          final base64String = imageBase64!.substring(commaIndex + 1);
          final cleanBase64 = base64String.replaceAll(RegExp(r'\s'), '');
          final imageBytes = base64.decode(cleanBase64);
          return Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildErrorWidget(),
          );
        }
      } catch (e) {
        debugPrint('Base64 解析失败: $e');
      }
    }
    
    // 使用网络图片 URL（带 token）
    if (imageUrl.isNotEmpty) {
      return FutureBuilder<String>(
        future: _buildAuthenticatedUrl(imageUrl),
        builder: (context, snapshot) {
          final url = snapshot.data ?? imageUrl;
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, _) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (context, _, __) => _buildErrorWidget(),
          );
        },
      );
    }
    
    return _buildErrorWidget();
  }

  Widget _buildErrorWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, color: Colors.white70, size: 64),
          SizedBox(height: 16),
          Text(
            '无法加载图片',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
