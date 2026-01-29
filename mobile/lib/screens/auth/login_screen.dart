import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../locales/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../screens/qr/scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/endpoint_manager.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneUsernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  bool _showAgreement = false;
  
  @override
  void initState() {
    super.initState();
    // 如果用户之前已经同意过免责声明，初始化同意状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.hasAgreedTerms) {
        setState(() {
          _agreedToTerms = true;
        });
      }
    });
  }
  
  @override
  void dispose() {
    _phoneUsernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _handleLogin() async {
    // 檢查憑證是否已識別
    if (!AppConfig.instance.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('為保障您和他人的資訊安全，首次使用請從相冊讀取或掃描二維碼授權。'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // 檢查是否已同意免責聲明（檢查持久化狀態或本地狀態）
    if (!authProvider.hasAgreedTerms && !_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先同意《用戶須知和免責聲明》')),
      );
      return;
    }
    
    if (_formKey.currentState!.validate()) {
      final success = await authProvider.login(
        _phoneUsernameController.text.trim(),
        _passwordController.text,
      );
      
      if (success && mounted) {
        // 登录成功，设置同意协议状态
        if (_agreedToTerms) {
          await authProvider.agreeTerms();
        }
        // 返回根路由，由 AppMain 自动显示 ChatMainScreen（聊天主界面）
        Navigator.of(context).pushReplacementNamed('/');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? '登录失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // 已移除手动配置功能，仅支持扫码识别凭证
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      // 渐变背景（参照网页端 login.html）
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea), // #667eea
              Color(0xFF764ba2), // #764ba2
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 主内容 - 白色卡片容器（参照网页端）
              // 先添加主内容，语言按钮会在上层
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 450),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 60,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 头部（渐变背景，白色文字）
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 20), // 减少垂直padding从30到20
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ],
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                            child: Column(
                              children: [
                                // 应用名称（根据语言显示：中文显示"和平信使"，英文显示"MOP"）
                                Text(
                                  languageProvider.currentLocale.languageCode == 'zh'
                                      ? (l10n?.t('app.name') ?? '和平信使')
                                      : (l10n?.t('app.short_name') ?? 'MOP'),
                                  style: const TextStyle(
                                    fontSize: 22, // 稍微缩小字体从24到22
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  l10n?.t('app.description') ?? '私有化管控通讯系统',
                                  style: TextStyle(
                                    fontSize: 12, // 稍微缩小字体从14到12
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          // 表单内容（优化布局：缩减间距，横向拓宽）
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0), // 减少垂直padding，增加横向padding
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min, // 最小化高度
                              children: [
                                // 凭证识别提示（仅首次）
                                if (!AppConfig.instance.isConfigured) ...[
                                  _buildApiConfigHint(l10n),
                                  const SizedBox(height: 12), // 缩减间距从16到12
                                ],
                                
                                // 免责声明（首次显示）
                                if (_showAgreement || !authProvider.hasAgreedTerms) ...[
                                  _buildAgreementSection(l10n),
                                  const SizedBox(height: 16), // 缩减间距从24到16
                                ],
                                
                                // 手机号/用户名输入框
                                TextFormField(
                                  controller: _phoneUsernameController,
                                  decoration: InputDecoration(
                                    labelText: l10n?.t('auth.login.phone_username') ?? '手机号/用户名',
                                    prefixIcon: const Icon(Icons.person),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l10n?.t('validation.phone_required') ?? '请输入手机号或用户名';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                
                                // 密码输入框
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: l10n?.t('auth.login.password') ?? '密码',
                                    prefixIcon: const Icon(Icons.lock),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l10n?.t('validation.password_required') ?? '请输入密码';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),
                                
                                // 登录按钮（渐变背景，参照网页端）
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF667eea),
                                        Color(0xFF764ba2),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: authProvider.isLoading || (!authProvider.hasAgreedTerms && !_agreedToTerms)
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: const Color(0xFF667eea).withOpacity(0.4),
                                              blurRadius: 15,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: authProvider.isLoading || (!authProvider.hasAgreedTerms && !_agreedToTerms)
                                        ? null
                                        : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: authProvider.isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : Text(
                                            l10n?.t('auth.login.button') ?? '登录',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12), // 缩减间距从16到12
                                
                                // 其他登录方式
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        // 跳轉到掃碼頁面（用於登錄）
                                        final result = await Navigator.of(context).push<bool>(
                                          MaterialPageRoute<bool>(
                                            builder: (context) => const ScanScreen(
                                              isForLogin: true,
                                            ),
                                          ),
                                        );
                                        
                                        // 如果掃碼授權成功，顯示提示
                                        if (result == true && mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('掃碼授權成功，請輸入用戶名和密碼登錄'),
                                              backgroundColor: Colors.green,
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('掃碼授權'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pushNamed('/register');
                                      },
                                      child: Text(l10n?.t('auth.register.button') ?? '注册'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 语言选择器 - 右上角固定位置（参照网页端）
              // 放在Stack的最后，确保在最上层显示
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  child: PopupMenuButton<Locale>(
                    icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🌐', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 4),
                        Text(
                          _getLanguageName(languageProvider.currentLocale),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                    ),
                    tooltip: l10n?.t('settings.language') ?? '切换语言',
                    onSelected: (Locale locale) {
                      languageProvider.changeLanguage(locale);
                    },
                    itemBuilder: (BuildContext context) {
                      return LanguageProvider.supportedLocales.map((Locale locale) {
                        final isSelected = languageProvider.currentLocale == locale;
                        return PopupMenuItem<Locale>(
                          value: locale,
                          child: Row(
                            children: [
                              if (isSelected)
                                const Icon(Icons.check, size: 18, color: Colors.blue)
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(_getLanguageName(locale)),
                            ],
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 構建憑證識別提示（首次掃碼授權核心功能）
  Widget _buildApiConfigHint(AppLocalizations? l10n) {
    return Card(
      color: Colors.orange.shade50,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小標題：憑證識別（僅一次）
            Text(
              '🔐 憑證識別（首次授權）',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            // 內容說明
            const Text(
              '為保障您和他人的資訊安全，首次使用請從相冊讀取或掃描二維碼授權。',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // 按鈕提示語和掃碼按鈕
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '快速識別您的憑證',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (context) => const ScanScreen(
                          isForLogin: true,
                        ),
                      ),
                    );
                    
                    if (result == true && mounted) {
                      // 重新載入配置，確保 isConfigured 狀態更新
                      await AppConfig.instance.loadConfig();
                      setState(() {
                        // 刷新 UI，隱藏未配置提示
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('掃碼授權成功，請輸入用戶名和密碼登錄'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: const Text('掃碼識別'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAgreementSection(AppLocalizations? l10n) {
    return Card(
      margin: EdgeInsets.zero, // 移除Card的默认margin
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), // 减少垂直padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // 最小化高度
          children: [
            Text(
              l10n?.t('auth.agreement.title') ?? '用户须知和免责声明',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15, // 稍微缩小字体
              ),
            ),
            const SizedBox(height: 8), // 缩减间距从12到8
            Text(
              l10n?.t('auth.agreement.welcome_message') ?? '欢迎使用和平信使（MOP）服务。在使用本服务前，请仔细阅读并同意《用户须知和免责声明》。',
              style: const TextStyle(fontSize: 12), // 缩小字体从14到12
            ),
            const SizedBox(height: 10), // 缩减间距从16到10
            CheckboxListTile(
              value: _agreedToTerms,
              onChanged: (value) {
                setState(() {
                  _agreedToTerms = value ?? false;
                });
              },
              title: Text(
                l10n?.t('auth.agreement.checkbox') ?? '我已阅读并同意《用户须知和免责声明》',
                style: const TextStyle(fontSize: 12), // 缩小字体从14到12
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4), // 减少CheckboxListTile的内边距
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 获取语言显示名称
  String _getLanguageName(Locale locale) {
    // 使用 LanguageProvider 的静态方法，确保与后端保持一致
    return LanguageProvider.getLanguageName(locale, context: context);
  }
}
