import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../locales/app_localizations.dart';

/// 首页
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          languageProvider.currentLocale.languageCode == 'zh'
              ? (l10n?.t('app.name') ?? '和平信使')
              : (l10n?.t('app.short_name') ?? 'MOP'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${l10n?.t('common.welcome') ?? '欢迎'}，${authProvider.currentUser?.nickname ?? authProvider.currentUser?.username ?? (l10n?.t('common.user') ?? '用户')}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/rooms');
              },
              icon: const Icon(Icons.video_call),
              label: Text(l10n?.t('rooms.title') ?? '房间管理'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                await authProvider.logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              child: Text(l10n?.t('settings.logout') ?? '退出登录'),
            ),
          ],
        ),
      ),
    );
  }
}
