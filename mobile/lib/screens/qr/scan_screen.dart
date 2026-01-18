import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan_snap/scan_snap.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/services/endpoint_manager.dart';
import '../../locales/app_localizations.dart';
import '../../services/qr/qr_scanner_service.dart';
import '../../services/qr/rsa_decrypt_service.dart';
import '../../services/permission/permission_service.dart';

/// 二维码扫描页面
class ScanScreen extends StatefulWidget {
  final String? publicKeyPem; // RSA 公钥（用于解密）
  final bool isForLogin; // 是否用于登录（扫码授权）
  
  const ScanScreen({
    super.key,
    this.publicKeyPem,
    this.isForLogin = false,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final QRScannerService _qrService = QRScannerService();
  MobileScannerController? _controller;
  bool _hasPermission = false;
  bool _isProcessing = false;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _initScanner();
  }
  
  Future<void> _initScanner() async {
    // 检查相机权限
    final hasPermission = await _qrService.checkCameraPermission();
    setState(() {
      _hasPermission = hasPermission;
      _errorMessage = null; // 清除之前的错误提示
    });
    
    // 尝试从 API 获取 RSA 公钥（静默获取，不显示错误）
    // 如果获取失败也没关系，因为未加密的二维码不需要公钥
    // 如果已配置 API 地址，尝试获取公钥；如果没有配置，尝试使用默认地址获取公钥
    String? publicKeyPem = widget.publicKeyPem;
    if (publicKeyPem == null || publicKeyPem.isEmpty) {
      if (AppConfig.instance.isConfigured) {
        await AppConfig.instance.fetchRsaPublicKeyFromApi();
      } else {
        // 如果没有配置，尝试使用默认地址获取公钥（使用聊天接口域名）
        await AppConfig.instance.fetchRsaPublicKeyFromApi(
          customApiUrl: 'https://log.chat5202ol.xyz/api/v1',
        );
      }
    }
    
    if (hasPermission) {
      _controller = _qrService.createController();
      
      // 监听扫描结果
      _controller?.barcodes.listen((barcodeCapture) {
        if (barcodeCapture.barcodes.isNotEmpty && !_isProcessing) {
          _handleScanResult(barcodeCapture.barcodes.first);
        }
      });
    }
  }
  
  /// 从相册选择图片并识别二维码
  /// 显示 API 地址配置对话框
  Future<void> _showApiConfigDialog() async {
    final apiUrlController = TextEditingController(
      text: AppConfig.instance.apiBaseUrl ?? 'https://log.chat5202ol.xyz',
    );
    final l10n = AppLocalizations.of(context);
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.t('qr.manual_config') ?? '手动配置 API 地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n?.t('qr.api_url_hint') ?? 
              '请输入 API 服务器地址（例如：https://log.chat5202ol.xyz）',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: apiUrlController,
              decoration: InputDecoration(
                labelText: l10n?.t('qr.api_url') ?? 'API 地址',
                hintText: 'https://log.chat5202ol.xyz',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.t('common.cancel') ?? '取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiUrl = apiUrlController.text.trim();
              if (apiUrl.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n?.t('qr.api_url_required') ?? '请输入 API 地址'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              
              // 确保 URL 格式正确
              String finalUrl = apiUrl;
              if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
                finalUrl = 'https://$finalUrl';
              }
              
              // 移除末尾的斜杠
              finalUrl = finalUrl.replaceAll(RegExp(r'/$'), '');
              
              // 如果不是完整路径，添加 /api/v1
              if (!finalUrl.contains('/api/v1')) {
                finalUrl = '$finalUrl/api/v1';
              }
              
              // 更新配置
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('api_base_url', finalUrl);
              await EndpointManager.instance.addApiEndpoint(finalUrl, priority: 0);
              
              // 加载配置
              await AppConfig.instance.loadConfig();
              
              // 尝试获取 RSA 公钥
              final fetched = await AppConfig.instance.fetchRsaPublicKeyFromApi(
                customApiUrl: finalUrl,
              );
              
              if (mounted) {
                Navigator.of(context).pop();
                
                if (fetched) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n?.t('qr.config_success') ?? 
                        '配置成功！已获取 RSA 公钥，现在可以扫描二维码了',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {
                    _errorMessage = null;
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n?.t('qr.config_partial') ?? 
                        'API 地址已配置，但获取 RSA 公钥失败。请检查 API 地址是否正确',
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
            child: Text(l10n?.t('common.confirm') ?? '确认'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _pickImageFromGallery() async {
    try {
      // 直接尝试选择图片，image_picker 会自动处理权限
      // 如果权限未授予，系统会自动弹出权限请求对话框
      final ImagePicker picker = ImagePicker();
      
      // 先尝试选择图片（image_picker 会处理权限）
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100, // 保持原始质量，确保二维码清晰
      );
      
      if (image == null) {
        // 用户取消了选择，或者权限被拒绝
        // 检查是否是权限问题
        final permissionService = PermissionService.instance;
        final permissionStatus = await permissionService.checkPhotosPermission();
        
        if (permissionStatus != PermissionStatus.granted) {
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n?.t('permission.photos_required') ?? '需要相册权限才能从相册识别二维码'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: l10n?.t('permission.go_to_settings') ?? '前往设置',
                  onPressed: () {
                    permissionService.openAppSettings();
                  },
                ),
              ),
            );
          }
        }
        return; // 用户取消了选择
      }
      
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });
      
      // 使用 scan_snap 识别图片中的二维码
      try {
        // 检查图片文件是否存在
        final file = File(image.path);
        if (!await file.exists()) {
          throw Exception('图片文件不存在');
        }
        
        // 检查文件大小，避免处理过大的文件
        final fileSize = await file.length();
        if (fileSize > 10 * 1024 * 1024) { // 10MB
          throw Exception('图片文件过大，请选择较小的图片（建议小于10MB）');
        }
        
        // 使用 scan_snap 从图片文件识别二维码
        // 添加超时处理，避免长时间等待
        String? qrCodeValue;
        try {
          // scan_snap 的 Scan.parse 返回 Future<String?>，需要处理异常
          final parseFuture = Scan.parse(image.path);
          qrCodeValue = await parseFuture.timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('scan_snap 识别超时');
              return null; // 返回 null 表示超时
            },
          );
          
          // 如果返回 null（超时或识别失败），抛出异常
          if (qrCodeValue == null) {
            throw TimeoutException('二维码识别超时或失败，请确保图片清晰且包含二维码');
          }
        } catch (e) {
          // scan_snap 可能抛出异常，记录详细信息
          debugPrint('scan_snap 识别失败: $e (类型: ${e.runtimeType})');
          
          // 重新抛出异常，让外层捕获并显示友好提示
          if (e is TimeoutException) {
            rethrow;
          } else {
            // 其他异常（如 PlatformException），提供更详细的错误信息
            throw Exception('无法识别二维码：${e.toString()}。请确保图片清晰且包含二维码');
          }
        }
        
        if (qrCodeValue != null && qrCodeValue.isNotEmpty) {
          // 创建 Barcode 对象（兼容 mobile_scanner 的 Barcode 类型）
          // mobile_scanner 的 Barcode 只需要 rawValue
          final barcode = Barcode(
            rawValue: qrCodeValue,
          );
          
          // 使用相同的处理逻辑
          await _handleScanResult(barcode);
        } else {
          setState(() {
            _isProcessing = false;
            final l10n = AppLocalizations.of(context);
            _errorMessage = l10n?.t('qr.scan_failed') ?? '未识别到二维码，请确保图片中包含清晰的二维码';
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_errorMessage!),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isProcessing = false;
          final l10n = AppLocalizations.of(context);
          // 提供更详细的错误信息
          String errorMsg = l10n?.t('qr.scan_failed') ?? '识别失败';
          if (e is TimeoutException) {
            errorMsg = e.message ?? '识别超时';
          } else if (e.toString().contains('PlatformException') || e.toString().contains('MethodChannel')) {
            errorMsg = '${l10n?.t('qr.scan_failed') ?? '识别失败'}：无法访问图片文件，请检查权限设置';
          } else if (e.toString().contains('FileSystemException') || e.toString().contains('不存在')) {
            errorMsg = '${l10n?.t('qr.scan_failed') ?? '识别失败'}：图片文件无法访问';
          } else if (e.toString().contains('过大')) {
            errorMsg = e.toString();
          } else {
            errorMsg = '${l10n?.t('qr.scan_failed') ?? '识别失败'}：${e.toString()}';
          }
          _errorMessage = errorMsg;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('qr.scan_failed') ?? '选择图片失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _handleScanResult(Barcode barcode) async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    
    try {
      // 获取 RSA 公钥（优先使用传入的，否则从配置获取）
      String? publicKeyPem = widget.publicKeyPem;
      if (publicKeyPem == null || publicKeyPem.isEmpty) {
        publicKeyPem = AppConfig.instance.rsaPublicKey;
      }
      
      // 如果仍然没有公钥，尝试从 API 获取
      if (publicKeyPem == null || publicKeyPem.isEmpty) {
        final fetched = await AppConfig.instance.fetchRsaPublicKeyFromApi();
        if (fetched) {
          publicKeyPem = AppConfig.instance.rsaPublicKey;
        }
      }
      
      // 处理扫描结果
      final data = await _qrService.processScanResult(
        barcode,
        publicKeyPem: publicKeyPem,
      );
      
      if (mounted) {
        // 如果用于登录，使用扫码授权登录
        if (widget.isForLogin) {
          // 扫码授权：更新 API 地址后，返回登录页面让用户登录
          // API 地址已经在 processScanResult 中更新到 AppConfig
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('qr.authorize_success') ?? '扫码授权成功，请登录'),
              backgroundColor: Colors.green,
            ),
          );
          // 返回上一页（登录页面）
          Navigator.of(context).pop(true); // 返回 true 表示授权成功
        } else {
          // 配置成功，返回上一页
          Navigator.of(context).pop(data);
        }
      }
    } on MissingPublicKeyException catch (e) {
      // 检测到加密二维码但缺少公钥
      setState(() {
        final l10n = AppLocalizations.of(context);
        _errorMessage = '${e.message}。${l10n?.t('qr.config_api_first') ?? '请先配置 API 地址'}。';
        _isProcessing = false;
      });
      
      // 尝试再次获取公钥
      final fetched = await AppConfig.instance.fetchRsaPublicKeyFromApi();
      if (fetched && mounted) {
        // 如果获取成功，自动重试扫描
        final newPublicKey = AppConfig.instance.rsaPublicKey;
        if (newPublicKey != null && newPublicKey.isNotEmpty) {
          try {
            final data = await _qrService.processScanResult(
              barcode,
              publicKeyPem: newPublicKey,
            );
            if (mounted) {
              if (widget.isForLogin) {
                // 扫码授权成功
                final l10n = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n?.t('qr.authorize_success') ?? '扫码授权成功，请登录'),
                    backgroundColor: Colors.green,
                  ),
                );
                // 返回上一页（登录页面）
                Navigator.of(context).pop(true); // 返回 true 表示授权成功
              } else {
                Navigator.of(context).pop(data);
              }
            }
            return;
          } catch (e2) {
            // 重试失败，显示错误
            setState(() {
              final l10n = AppLocalizations.of(context);
            _errorMessage = '${l10n?.t('qr.decrypt_failed') ?? '解密失败'}: $e2';
            });
          }
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? (AppLocalizations.of(context)?.t('qr.scan_failed') ?? '扫描失败')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isProcessing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)?.t('qr.scan_failed') ?? '扫描失败'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _qrService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isForLogin 
            ? (AppLocalizations.of(context)?.t('qr.scan_authorize') ?? '扫码授权')
            : (AppLocalizations.of(context)?.t('qr.scan') ?? '扫描二维码')),
        actions: [
          // 手动配置 API 地址按钮
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppLocalizations.of(context)?.t('qr.manual_config') ?? '手动配置 API 地址',
            onPressed: _isProcessing ? null : _showApiConfigDialog,
          ),
          // 从相册识别二维码按钮
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: AppLocalizations.of(context)?.t('qr.pick_from_gallery') ?? '从相册选择',
            onPressed: _isProcessing ? null : _pickImageFromGallery,
          ),
        ],
      ),
      body: _hasPermission
          ? Stack(
              children: [
                // 相机预览
                MobileScanner(
                  controller: _controller,
                  onDetect: (barcode) {
                    if (!_isProcessing && barcode.barcodes.isNotEmpty) {
                      _handleScanResult(barcode.barcodes.first);
                    }
                  },
                ),
                
                // 扫描框
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                
                // 提示信息
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLocalizations.of(context)?.t('qr.align_qr') ?? '请将二维码对准扫描框',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 错误信息
                if (_errorMessage != null)
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          // 如果是因为缺少公钥或 API 地址，显示手动配置按钮
                          if (_errorMessage!.contains('RSA公钥') || 
                              _errorMessage!.contains('API地址') ||
                              _errorMessage!.contains('api地址') ||
                              _errorMessage!.contains('无法解密'))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: ElevatedButton(
                                onPressed: () {
                                  _showApiConfigDialog();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red,
                                ),
                                child: Text(
                                  AppLocalizations.of(context)?.t('qr.manual_config') ?? 
                                  '手动配置 API 地址',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                
                // 处理中提示
                if (_isProcessing)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)?.t('qr.camera_permission_required') ?? '需要相机权限才能扫描二维码'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      final hasPermission = await _qrService.checkCameraPermission();
                      setState(() {
                        _hasPermission = hasPermission;
                      });
                      
                      if (hasPermission) {
                        _initScanner();
                      }
                    },
                    child: Text(AppLocalizations.of(context)?.t('qr.grant_permission') ?? '授予权限'),
                  ),
                ],
              ),
            ),
    );
  }
}
