import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/storage_service.dart';
import 'core/services/network_service.dart';
import 'core/services/endpoint_manager.dart';
import 'locales/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'providers/socket_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/qr/scan_screen.dart';
import 'screens/room/room_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/rooms/rooms_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化本地存储
  final prefs = await SharedPreferences.getInstance();
  StorageService.instance.init(prefs);
  
  // 初始化网络监听服务
  NetworkService.instance.init();
  
  // 初始化端点管理器
  await EndpointManager.instance.init();
  
  // 加载应用配置
  await AppConfig.instance.loadConfig();
  
  // 创建 LanguageProvider 并等待初始化完成（确保语言跟随系统）
  final languageProvider = LanguageProvider();
  await languageProvider.loadLanguage();
  
  runApp(MOPApp(languageProvider: languageProvider));
}

class MOPApp extends StatelessWidget {
  final LanguageProvider? languageProvider;
  
  const MOPApp({super.key, this.languageProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => languageProvider ?? LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SocketProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          // 等待语言初始化完成
          if (!languageProvider.isInitialized) {
            return const MaterialApp(
              home: Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          
          // 根据语言获取APP名称（中文：和平信使，英文：MOP）
          // 注意：这里使用硬编码是因为MaterialApp的title在AppLocalizations初始化之前就需要
          // 实际显示时会通过AppLocalizations获取正确的名称
          final appName = languageProvider.currentLocale.languageCode == 'zh' 
              ? '和平信使' 
              : 'MOP';
          
          return MaterialApp(
            title: appName, // MaterialApp的title用于系统任务管理器显示
            debugShowCheckedModeBanner: false,
            
            // 国际化配置
            locale: languageProvider.currentLocale,
            supportedLocales: LanguageProvider.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            
            // 主题配置
            theme: ThemeData(
              primarySwatch: Colors.blue,
              primaryColor: const Color(0xFF667eea),
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF667eea),
              ),
            ),
            
            // 路由配置
            initialRoute: '/',
            routes: {
              '/': (context) => const AppMain(),
              '/scan': (context) => ScanScreen(
                publicKeyPem: AppConfig.instance.rsaPublicKey,
                isForLogin: false,
              ),
              '/register': (context) => const RegisterScreen(),
              '/home': (context) => const HomeScreen(),
              '/room': (context) {
                final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
                return RoomScreen(
                  roomId: args['roomId'] as String,
                  roomName: args['roomName'] as String?,
                );
              },
              '/settings': (context) => const SettingsScreen(),
              '/rooms': (context) => const RoomsListScreen(),
            },
          );
        },
      ),
    );
  }
}
