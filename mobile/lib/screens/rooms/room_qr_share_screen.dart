import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:convert';

import '../../locales/app_localizations.dart';
import '../../services/api/rooms_api_service.dart';

/// 房间二维码分享页面
class RoomQRShareScreen extends StatefulWidget {
  final String roomId;
  final String? roomName;

  const RoomQRShareScreen({
    super.key,
    required this.roomId,
    this.roomName,
  });

  @override
  State<RoomQRShareScreen> createState() => _RoomQRShareScreenState();
}

class _RoomQRShareScreenState extends State<RoomQRShareScreen> {
  final RoomsApiService _roomsApiService = RoomsApiService();
  Uint8List? _qrCodeImage;
  String? _encryptedData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadQRCode();
  }

  Future<void> _loadQRCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _roomsApiService.getRoomQRCode(widget.roomId);

      if (response != null) {
        // 获取二维码图片（Base64编码）
        final qrCodeBase64 = response['qr_code_image'] as String?;
        final encryptedData = response['encrypted_data'] as String?;

        if (qrCodeBase64 != null) {
          // 解码Base64图片
          final imageBytes = base64Decode(qrCodeBase64);
          setState(() {
            _qrCodeImage = imageBytes;
            _encryptedData = encryptedData;
            _isLoading = false;
          });
        } else {
          final l10n = AppLocalizations.of(context);
          throw Exception(l10n?.t('errors.no_qr_image') ?? '未获取到二维码图片');
        }
      } else {
        final l10n = AppLocalizations.of(context);
        throw Exception(l10n?.t('errors.get_qr_failed') ?? '获取二维码失败');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _shareQRCode() async {
    if (_qrCodeImage == null) return;

    final l10n = AppLocalizations.of(context);
    try {
      // 保存图片到临时目录
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/room_qr_${widget.roomId}.png');
      await file.writeAsBytes(_qrCodeImage!);

      // 分享图片
      await Share.shareXFiles(
        [XFile(file.path)],
        text: (l10n?.t('rooms.share_text') ?? '房间二维码：{room_name}\n扫描二维码加入房间')
            .replaceAll('{room_name}', widget.roomName ?? widget.roomId),
        subject: l10n?.t('rooms.share_subject') ?? '房间邀请',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.share_failed') ?? '分享失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyEncryptedData() async {
    if (_encryptedData == null) return;

    try {
      // 使用 Clipboard 复制
      await Clipboard.setData(ClipboardData(text: _encryptedData!));
      
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.t('rooms.qr_data_copied') ?? '二维码数据已复制到剪贴板'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.t('errors.copy_failed') ?? '复制失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.t('rooms.share_qr') ?? '分享房间二维码'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadQRCode,
                        child: Text(l10n?.t('common.retry') ?? '重试'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 房间信息
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n?.t('rooms.room_info') ?? '房间信息',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${l10n?.t('rooms.room_name') ?? '房间名称'}: ${widget.roomName ?? widget.roomId}',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${l10n?.t('rooms.room_id') ?? '房间ID'}: ${widget.roomId}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 二维码图片
                      if (_qrCodeImage != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Text(
                                  l10n?.t('rooms.scan_to_join') ?? '扫描二维码加入房间',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Image.memory(
                                    _qrCodeImage!,
                                    width: 250,
                                    height: 250,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // 分享按钮
                      ElevatedButton.icon(
                        onPressed: _shareQRCode,
                        icon: const Icon(Icons.share),
                        label: Text(l10n?.t('rooms.share_qr') ?? '分享二维码'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFF667eea),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 复制二维码数据按钮（可选）
                      OutlinedButton.icon(
                        onPressed: _copyEncryptedData,
                        icon: const Icon(Icons.copy),
                        label: Text(l10n?.t('rooms.copy_qr_data') ?? '复制二维码数据'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
