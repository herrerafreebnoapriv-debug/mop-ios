import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/users_api_service.dart';

/// 账户设置标签页
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      // 不显示 AppBar，由 ChatMainScreen 统一管理顶部导航栏
      appBar: null,
      body: ListView(
        children: [
          // 个人资料部分
          _SettingsSection(
            title: l10n?.t('settings.profile') ?? '个人资料',
            children: [
              _SettingsItem(
                label: l10n?.t('settings.username') ?? '用户名',
                value: user?.username ?? '--',
              ),
              _SettingsItem(
                label: l10n?.t('settings.phone') ?? '手机号',
                value: user?.phone ?? '--',
              ),
              _SettingsItem(
                label: l10n?.t('settings.nickname') ?? '昵称',
                value: user?.nickname ?? '--',
              ),
              _SettingsItem(
                label: l10n?.t('settings.language') ?? '语言',
                value: LanguageProvider.getLanguageName(languageProvider.currentLocale),
                onTap: () => _showLanguageSelector(context, languageProvider),
              ),
            ],
          ),

          // 账户操作部分
          _SettingsSection(
            title: l10n?.t('settings.account_actions') ?? '账户操作',
            children: [
              _SettingsItem(
                label: l10n?.t('settings.change_password') ?? '修改密码',
                trailing: ElevatedButton(
                  onPressed: () => _showChangePasswordDialog(context),
                  child: Text(l10n?.t('settings.change') ?? '修改'),
                ),
              ),
              _SettingsItem(
                label: l10n?.t('settings.logout') ?? '退出账户',
                trailing: ElevatedButton(
                  onPressed: () => _showLogoutDialog(context, authProvider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n?.t('settings.logout') ?? '退出'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLanguageSelector(BuildContext context, LanguageProvider languageProvider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)?.t('settings.select_language') ?? '选择语言',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...LanguageProvider.supportedLocales.map((locale) {
              final isSelected = languageProvider.currentLocale == locale;
              return ListTile(
                title: Text(LanguageProvider.getLanguageName(locale, context: context)),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  languageProvider.changeLanguage(locale);
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.t('settings.change_password') ?? '修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)?.t('settings.old_password') ?? '当前密码',
              ),
            ),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码',
              ),
            ),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)?.t('settings.confirm_password') ?? '确认新密码',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)?.t('common.cancel') ?? '取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPassword = oldPasswordController.text;
              final newPassword = newPasswordController.text;
              final confirmPassword = confirmPasswordController.text;
              
              if (oldPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)?.t('settings.fill_all_fields') ?? '请填写所有字段')),
                );
                return;
              }
              
              if (newPassword != confirmPassword) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)?.t('settings.password_mismatch') ?? '两次输入的密码不一致')),
                );
                return;
              }
              
              if (newPassword.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)?.t('settings.password_too_short') ?? '密码长度至少6位')),
                );
                return;
              }
              
              try {
                final usersApiService = UsersApiService();
                final success = await usersApiService.changePassword(
                  oldPassword: oldPassword,
                  newPassword: newPassword,
                );
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                  final l10n = AppLocalizations.of(context);
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n?.t('settings.password_changed') ?? '密码修改成功'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n?.t('settings.password_change_failed') ?? '密码修改失败，请检查旧密码是否正确'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  final l10n = AppLocalizations.of(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${l10n?.t('errors.change_failed') ?? '修改失败'}: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(AppLocalizations.of(context)?.t('common.confirm') ?? '确认'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.t('settings.logout_confirm') ?? '确认退出'),
        content: Text(AppLocalizations.of(context)?.t('settings.logout_confirm_message') ?? '确定要退出账户吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)?.t('common.cancel') ?? '取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.of(context)?.t('settings.logout') ?? '退出'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: value != null ? Text(value!) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}
