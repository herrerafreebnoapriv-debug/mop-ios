import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../locales/app_localizations.dart';
import '../../screens/rooms/rooms_list_screen.dart';
import '../../screens/qr/scan_screen.dart';
import '../../core/config/app_config.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.t('settings.title') ?? '设置'),
      ),
      body: ListView(
        children: [
          // 用户信息卡片
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: const Color(0xFF667eea),
                        child: Text(
                          (user?.nickname ?? user?.username ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.nickname ?? user?.username ?? '用户',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (user?.phone != null)
                              Text(
                                user!.phone!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 功能设置
          _SettingsSection(
            title: l10n?.t('settings.features') ?? '功能',
            children: [
              _SettingsItem(
                icon: Icons.video_call,
                label: l10n?.t('rooms.title') ?? '房间管理',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const RoomsListScreen(),
                    ),
                  );
                },
              ),
              _SettingsItem(
                icon: Icons.qr_code_scanner,
                label: l10n?.t('settings.scan_qr') ?? '扫描二维码',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ScanScreen(
                        publicKeyPem: AppConfig.instance.rsaPublicKey,
                        isForLogin: false,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          // 账户设置
          _SettingsSection(
            title: l10n?.t('settings.account') ?? '账户',
            children: [
              _SettingsItem(
                icon: Icons.language,
                label: l10n?.t('settings.language') ?? '语言',
                value: LanguageProvider.getLanguageName(languageProvider.currentLocale),
                onTap: () => _showLanguageSelector(context, languageProvider),
              ),
              _SettingsItem(
                icon: Icons.logout,
                label: l10n?.t('settings.logout') ?? '退出登录',
                onTap: () => _showLogoutDialog(context, authProvider),
                textColor: Colors.red,
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color? textColor;

  const _SettingsItem({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: textColor),
      title: Text(
        label,
        style: TextStyle(color: textColor),
      ),
      subtitle: value != null ? Text(value!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

