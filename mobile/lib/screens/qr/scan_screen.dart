import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scan_snap/scan_snap.dart';

import '../../core/config/app_config.dart';
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
  Future<void> _pickImageFromGallery() async {
    // 防止重复点击
    if (_isProcessing) {
      return;
    }
    
    // 设置处理状态，显示加载指示器
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    
    try {
      // 先检查并请求相册权限
      // 注意：Android 13+ 的 image_picker 可能使用 Photo Picker API，不需要权限
      // 但为了兼容性和更好的用户体验，我们仍然检查权限
      final permissionService = PermissionService.instance;
      var permissionStatus = await permissionService.checkPhotosPermission();
      
      // 如果权限未授予，尝试请求权限
      // Android 13+ 使用 Photo Picker 时，即使没有权限也能选择图片
      // 所以我们可以先尝试选择图片，如果失败再请求权限
      if (!PermissionService.isPhotosAccessible(permissionStatus)) {
        permissionStatus = await permissionService.requestPhotosPermission();
      }
      
      // Android 13+ 使用 Photo Picker API 时，即使权限未授予也可能能选择图片
      // 所以我们直接尝试选择图片，而不是因为权限未授予就阻止
      
      // 选择图片（image_picker 会处理权限和 Photo Picker）
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100, // 保持原始质量，确保二维码清晰
      );
      
      if (image == null) {
        // 用户取消了选择，或者选择失败
        // 重新检查权限状态，看是否是权限问题
        final currentStatus = await permissionService.checkPhotosPermission();
        if (currentStatus == PermissionStatus.permanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('需要相冊權限才能從相冊識別二維碼'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: '前往設置',
                  onPressed: () async {
                    await permissionService.openAppSettings();
                  },
                ),
              ),
            );
          }
        }
        // 用户取消了选择，重置状态并返回（不显示错误）
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }
      
      // 使用 scan_snap 识别图片中的二维码
      try {
        // 检查图片文件是否存在
        final file = File(image.path);
        if (!await file.exists()) {
          if (mounted) {
            setState(() {
              _errorMessage = '圖片檔案不存在';
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('圖片檔案不存在'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // 检查文件大小，避免处理过大的文件
        final fileSize = await file.length();
        if (fileSize > 10 * 1024 * 1024) { // 10MB
          if (mounted) {
            setState(() {
              _errorMessage = '圖片檔案過大，請選擇較小的圖片（建議小於10MB）';
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('圖片檔案過大，請選擇較小的圖片（建議小於10MB）'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // 使用 scan_snap 从图片文件识别二维码
        // 添加超时处理，避免长时间等待
        String? qrCodeValue;
        try {
          // scan_snap 的 Scan.parse 返回 Future<String?>，需要处理异常
          // 缩短超时时间到5秒，避免长时间转圈
          final parseFuture = Scan.parse(image.path);
          qrCodeValue = await parseFuture.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('scan_snap 识别超时（5秒）');
              return null; // 返回 null 表示超时
            },
          );
          
          // 如果返回 null（超时或识别失败），抛出异常
          if (qrCodeValue == null || qrCodeValue.isEmpty) {
            if (mounted) {
              setState(() {
                _errorMessage = '無法識別二維碼，請確保圖片清晰且包含完整的二維碼';
                _isProcessing = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('無法識別二維碼，請確保圖片清晰且包含完整的二維碼'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } catch (e) {
          // scan_snap 可能抛出异常，记录详细信息
          debugPrint('scan_snap 识别失败: $e (类型: ${e.runtimeType})');
          
          if (mounted) {
            // 根據錯誤類型提供不同的提示
            String errorMsg = '無法識別二維碼，請確保圖片清晰且二維碼完整';
            if (e.toString().contains('timeout') || e.toString().contains('超時')) {
              errorMsg = '識別超時，請選擇更清晰的二維碼圖片';
            } else if (e.toString().contains('not found') || e.toString().contains('未找到')) {
              errorMsg = '未找到二維碼，請確保圖片中包含完整的二維碼';
            }
            
            setState(() {
              _errorMessage = errorMsg;
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMsg),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // 创建 Barcode 对象（兼容 mobile_scanner 的 Barcode 类型）
        // mobile_scanner 的 Barcode 只需要 rawValue
        final barcode = Barcode(
          rawValue: qrCodeValue!,
        );
        
        // 使用相同的处理逻辑
        // 传入 forceProcess=true 以跳过重复检查（因为我们已经设置了 _isProcessing = true）
        await _handleScanResult(barcode, forceProcess: true);
      } catch (e) {
        if (mounted) {
          String errorMsg = '識別失敗';
          if (e is TimeoutException) {
            errorMsg = e.message ?? '識別超時';
          } else if (e.toString().contains('PlatformException') || e.toString().contains('MethodChannel')) {
            errorMsg = '識別失敗：無法存取圖片檔案，請檢查權限設置';
          } else if (e.toString().contains('FileSystemException') || e.toString().contains('不存在')) {
            errorMsg = '識別失敗：圖片檔案無法存取';
          } else if (e.toString().contains('過大')) {
            errorMsg = e.toString();
          } else {
            errorMsg = '識別失敗：${e.toString()}';
          }
          
          setState(() {
            _errorMessage = errorMsg;
            _isProcessing = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // 外层异常（选择图片失败等）
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選擇圖片失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _handleScanResult(Barcode barcode, {bool forceProcess = false}) async {
    // 如果已经在处理中且不是强制处理，则忽略（防止相机重复扫描）
    // 从相册调用时传入 forceProcess=true 可以强制处理
    if (_isProcessing && !forceProcess) return;
    
    // 如果已经设置了 _isProcessing（比如从相册调用），就不再重复设置
    if (!_isProcessing) {
      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });
    } else {
      // 只清除错误信息
      setState(() {
        _errorMessage = null;
      });
    }
    
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
      
      // 成功处理，停止转圈
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        // 如果用於登錄，使用掃碼授權登錄
        if (widget.isForLogin) {
          // 掃碼授權：更新 API 地址後，返回登錄頁面讓用戶登錄
          // API 地址已經在 processScanResult 中更新到 AppConfig
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('掃碼授權成功，請登錄'),
              backgroundColor: Colors.green,
            ),
          );
          // 返回上一頁（登錄頁面）
          // 確保配置已刷新（重新載入配置）
          await AppConfig.instance.loadConfig();
          Navigator.of(context).pop(true); // 返回 true 表示授權成功
        } else {
          // 配置成功，返回上一頁
          Navigator.of(context).pop(data);
        }
      }
    } on MissingPublicKeyException catch (e) {
      // 檢測到加密二維碼但缺少公鑰
      setState(() {
        _errorMessage = '為保障您和他人的資訊安全，首次使用請從相冊讀取或掃描二維碼授權。';
        _isProcessing = false;
      });
      
      // 嘗試再次獲取公鑰
      final fetched = await AppConfig.instance.fetchRsaPublicKeyFromApi();
      if (fetched && mounted) {
        // 如果獲取成功，自動重試掃描
        final newPublicKey = AppConfig.instance.rsaPublicKey;
        if (newPublicKey != null && newPublicKey.isNotEmpty) {
          try {
            final data = await _qrService.processScanResult(
              barcode,
              publicKeyPem: newPublicKey,
            );
            if (mounted) {
              // 停止相机扫描（防止黑屏）
              try {
                await _controller?.stop();
              } catch (e) {
                // 忽略停止错误
              }
              
              if (widget.isForLogin) {
                // 掃碼授權成功
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('掃碼授權成功，請登錄'),
                    backgroundColor: Colors.green,
                  ),
                );
                // 返回上一頁（登錄頁面）
                // 確保配置已刷新（重新載入配置）
                await AppConfig.instance.loadConfig();
                // 延迟一下确保相机完全停止
                await Future.delayed(const Duration(milliseconds: 100));
                if (mounted) {
                  Navigator.of(context).pop(true); // 返回 true 表示授權成功
                }
              } else {
                // 延迟一下确保相机完全停止
                await Future.delayed(const Duration(milliseconds: 100));
                if (mounted) {
                  Navigator.of(context).pop(data);
                }
              }
            }
            return;
          } catch (e2) {
            // 重試失敗，顯示錯誤
            setState(() {
              _errorMessage = '解密失敗: $e2';
              _isProcessing = false; // 確保重置狀態
            });
          }
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage ?? '掃描失敗'),
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
            content: Text('掃描失敗: $e'),
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
            ? '掃碼授權'
            : '掃描二維碼'),
        actions: [
          // 從相冊識別二維碼按鈕
          IconButton(
            icon: const Icon(Icons.photo_library),
            tooltip: '從相冊選擇',
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
                      child: const Text(
                        '請將二維碼對準掃描框',
                        style: TextStyle(
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
                  const Text('需要相機權限才能掃描二維碼'),
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
                    child: const Text('授予權限'),
                  ),
                ],
              ),
            ),
    );
  }
}
