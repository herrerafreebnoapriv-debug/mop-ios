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
import 'locales/app_localizations.dart';

/// 应用主组件
/// 根据用户登录状态显示不同页面
class AppMain extends StatefulWidget {
  const AppMain({super.key});

  @override
  State<AppMain> createState() => _AppMainState();
}

class _AppMainState extends State<AppMain> {
  bool _hasShownPermissionDialog = false;

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
      _hasShownPermissionDialog = true;
      
      // 显示权限说明弹窗
      showDialog(
        context: context,
        barrierDismissible: false, // 首次登录时不允许关闭
        builder: (context) => PermissionExplanationDialog(
          isRequired: true, // 首次登录时强制显示
          onAgree: () async {
            // 用户同意后，请求所有权限
            await _requestAllPermissions();
            
            // 保存同意状态
            await StorageService.instance.saveAgreedPermissions(true);
            
            // 更新 AuthProvider 状态
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            authProvider.notifyListeners();
          },
        ),
      );
    }
  }

  /// 请求所有必需权限
  Future<void> _requestAllPermissions() async {
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
                return '通讯录';
              case 'sms':
                return '短信';
              case 'phone':
                return '通话记录';
              case 'app_list':
                return '应用列表';
              case 'photos':
                return '相册';
              default:
                return entry.key;
            }
          })
          .toList();
      
      if (deniedPermissions.isNotEmpty && mounted) {
        // 显示提示，引导用户到设置中开启权限
        final l10n = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n?.t('permission.not_fully_authorized') ?? '权限未完全授权'),
            content: Text(
            '${l10n?.t('permission.denied_permissions') ?? '以下权限未授权'}：${deniedPermissions.join('、')}\n\n'
            '${l10n?.t('permission.important_for_privacy') ?? '这些权限对于保护您的隐私安全非常重要'}。\n'
            '${l10n?.t('permission.manual_enable') ?? '您可以在系统设置中手动开启这些权限'}。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n?.t('permission.later') ?? '稍后设置'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await permissionService.openAppSettings();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(l10n?.t('permission.go_to_settings') ?? '前往设置'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('请求权限失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, SocketProvider>(
      builder: (context, authProvider, socketProvider, _) {
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
          // 已登录且已同意免责声明，显示聊天主界面（与网页端 chat.html 对应）
          return const ChatMainScreen();
        } else {
          // 未登录或未同意免责声明，显示登录页
          return const LoginScreen();
        }
      },
    );
  }
}
