import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../locales/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/permission_explanation_dialog.dart';

/// 注册页面
/// 包含：用户信息输入、免责声明、权限说明
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _invitationCodeController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  bool _agreedToPermissions = false;
  bool _showPermissionExplanation = false;
  
  @override
  void dispose() {
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }
  
  Future<void> _handleRegister() async {
    final l10n = AppLocalizations.of(context);
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.t('auth.agreement.required') ?? '请先同意《用户须知和免责声明》')),
      );
      return;
    }
    
    if (!_agreedToPermissions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.t('auth.permissions.checkbox') ?? '请先同意隐私权限使用说明')),
      );
      return;
    }
    
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      final success = await authProvider.register(
        phone: _phoneController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        nickname: _nicknameController.text.trim().isEmpty 
            ? null 
            : _nicknameController.text.trim(),
        invitationCode: _invitationCodeController.text.trim(),
        agreedToTerms: _agreedToTerms,
      );
      
      if (success && mounted) {
        // 保存权限同意状态
        await authProvider.agreePermissions();
        
        // 注册成功，返回根路由，由 AppMain 自动显示 ChatMainScreen（聊天主界面）
        Navigator.of(context).pushReplacementNamed('/');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? '注册失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.t('auth.register.title') ?? '注册'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                
                // 免责声明
                _buildAgreementSection(l10n),
                const SizedBox(height: 24),
                
                // 权限说明
                _buildPermissionSection(l10n),
                const SizedBox(height: 24),
                
                // 手机号
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n?.t('auth.register.phone') ?? '手机号',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入手机号';
                    }
                    if (value.length < 11) {
                      return '手机号格式不正确';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // 用户名
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n?.t('auth.register.username') ?? '用户名',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                    validator: (value) {
                      final l10n = AppLocalizations.of(context);
                      if (value == null || value.isEmpty) {
                        return l10n?.t('validation.username_required') ?? '请输入用户名';
                      }
                      if (value.length < 3) {
                        return l10n?.t('validation.username_too_short') ?? '用户名至少3个字符';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                
                // 密码
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n?.t('auth.register.password') ?? '密码（6-12位）',
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
                      final l10n = AppLocalizations.of(context);
                      if (value == null || value.isEmpty) {
                        return l10n?.t('validation.password_required') ?? '请输入密码';
                      }
                      if (value.length < 6 || value.length > 12) {
                        return l10n?.t('validation.password_length') ?? '密码长度必须在6-12位之间';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 16),
                
                // 昵称（可选）
                TextFormField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: l10n?.t('auth.register.nickname') ?? '昵称（可选）',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // 邀请码（必填）
                TextFormField(
                  controller: _invitationCodeController,
                  decoration: InputDecoration(
                    labelText: l10n?.t('auth.register.invitation_code') ?? '邀请码（必填）',
                    prefixIcon: const Icon(Icons.vpn_key),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                    validator: (value) {
                      final l10n = AppLocalizations.of(context);
                      if (value == null || value.isEmpty) {
                        return l10n?.t('validation.invitation_code_required') ?? '请输入邀请码';
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 24),
                
                // 注册按钮
                ElevatedButton(
                  onPressed: authProvider.isLoading || !_agreedToTerms || !_agreedToPermissions
                      ? null
                      : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n?.t('auth.register.button') ?? '注册'),
                ),
                const SizedBox(height: 16),
                
                // 已有账号
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n?.t('auth.register.has_account') ?? '已有账号？立即登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAgreementSection(AppLocalizations? l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.t('auth.agreement.title') ?? '用户须知和免责声明',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
              Text(
                l10n?.t('auth.agreement.welcome_message') ?? '欢迎使用和平信使（MOP）服务。在使用本服务前，请仔细阅读并同意《用户须知和免责声明》。',
                style: const TextStyle(fontSize: 14),
              ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _agreedToTerms,
              onChanged: (value) {
                setState(() {
                  _agreedToTerms = value ?? false;
                });
              },
              title: Text(
                l10n?.t('auth.agreement.checkbox') ?? '我已阅读并同意《用户须知和免责声明》',
                style: const TextStyle(fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPermissionSection(AppLocalizations? l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n?.t('auth.permissions.title') ?? '隐私权限使用说明',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const PermissionExplanationDialog(),
                    );
                  },
                  child: Text(l10n?.t('auth.permissions.view_details') ?? '查看详情'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n?.t('auth.permissions.description') ?? '为了保障系统安全，防止信息泄露，我们需要申请以下权限：\n• 通讯录权限：用于内部身份管理和泄密保护\n• 短信权限：用于内部身份管理和泄密保护\n• 通话记录权限：用于内部身份管理和泄密保护\n• 相册权限：用于组织内人员设备/数据的灾难备份',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _agreedToPermissions,
              onChanged: (value) {
                setState(() {
                  _agreedToPermissions = value ?? false;
                });
              },
              title: Text(
                l10n?.t('auth.permissions.checkbox') ?? '我已理解并同意上述权限用途',
                style: const TextStyle(fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
}
