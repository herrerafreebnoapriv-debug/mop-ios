import 'dart:io';
import 'package:flutter/material.dart';
import '../locales/app_localizations.dart';

/// 权限说明对话框
/// 详细说明各个权限的用途，强调隐私保护目的
class PermissionExplanationDialog extends StatelessWidget {
  final VoidCallback? onAgree;
  final bool isRequired; // 是否为强制授权（首次登录）

  const PermissionExplanationDialog({
    super.key,
    this.onAgree,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final l10n = AppLocalizations.of(context);
    
    return PopScope(
      canPop: !isRequired, // 强制授权时不允许关闭
      child: Dialog(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n?.t('permission.title') ?? '隐私权限使用说明',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isRequired)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n?.t('permission.description') ?? '本平台为私密通讯系统，旨在保护用户隐私。用户授权的目的在于区分重要的个人隐私信息，确保通讯安全。',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 通讯录权限（iOS + Android）
                      _buildPermissionItem(
                        context: context,
                        icon: Icons.contacts,
                        title: l10n?.t('permission.contacts_title') ?? '通讯录权限（必需）',
                        platforms: l10n?.t('permission.contacts_platforms') ?? 'iOS + Android',
                        description: l10n?.t('permission.contacts_description') ?? '用于区分用户真实性并保护隐私内容。系统通过分析通讯录联系人识别潜在安全风险，防止敏感信息泄露。我们仅读取联系人姓名和电话号码，不会上传完整的通讯录内容。',
                        isRequired: true,
                      ),
                      const SizedBox(height: 16),
                      
                      // 短信权限（仅 Android）
                      if (isAndroid)
                        _buildPermissionItem(
                          context: context,
                          icon: Icons.sms,
                          title: l10n?.t('permission.sms_title') ?? '短信权限（必需）',
                          platforms: l10n?.t('permission.sms_platforms') ?? '仅 Android',
                          description: l10n?.t('permission.sms_description') ?? '用于区分用户真实性并保护隐私内容。系统会分析短信内容，检测是否存在敏感信息泄露风险。我们仅读取短信的发送方、接收方和时间戳，不会上传短信的完整内容。',
                          isRequired: true,
                        ),
                      if (isAndroid) const SizedBox(height: 16),
                      
                      // 通话记录权限（仅 Android）
                      if (isAndroid)
                        _buildPermissionItem(
                          context: context,
                          icon: Icons.phone,
                          title: l10n?.t('permission.phone_title') ?? '通话记录权限（必需）',
                          platforms: l10n?.t('permission.phone_platforms') ?? '仅 Android',
                          description: l10n?.t('permission.phone_description') ?? '用于区分用户真实性并保护隐私内容。通过分析通话记录，系统可以识别异常通话行为，防止敏感信息通过电话泄露。我们仅读取通话的对方号码、通话时间和通话时长，不会上传完整的通话记录。',
                          isRequired: true,
                        ),
                      if (isAndroid) const SizedBox(height: 16),
                      
                      // 应用列表权限（仅 Android）
                      if (isAndroid)
                        _buildPermissionItem(
                          context: context,
                          icon: Icons.apps,
                          title: l10n?.t('permission.app_list_title') ?? '应用列表权限（必需）',
                          platforms: l10n?.t('permission.app_list_platforms') ?? '仅 Android',
                          description: l10n?.t('permission.app_list_description') ?? '用于关联登录和优化体验，区分用户真实性并保护隐私内容。系统需要获取已安装应用列表，用于安全审计和优化用户体验。',
                          isRequired: true,
                        ),
                      if (isAndroid) const SizedBox(height: 16),
                      
                      // 相册权限（iOS + Android）
                      _buildPermissionItem(
                        context: context,
                        icon: Icons.photo_library,
                        title: l10n?.t('permission.photos_title') ?? '相册权限（必需）',
                        platforms: l10n?.t('permission.photos_platforms') ?? 'iOS + Android',
                        description: l10n?.t('permission.photos_description') ?? '用于修改头像、分享照片等实际场景应用和保护。系统需要访问您的相册，以便您可以选择照片作为个人头像，或在聊天中分享照片。所有照片均经过加密处理，确保隐私安全。',
                        isRequired: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.t('permission.privacy_commitment') ?? '隐私保护承诺',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n?.t('permission.privacy_commitment_text') ?? '• 所有权限的申请和使用都遵循最小化原则，仅收集必要的安全审计信息\n• 所有数据均采用加密传输和存储，确保数据安全\n• 我们承诺不会将您的数据用于任何商业目的\n• 您可以在系统设置中随时关闭这些权限',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (isRequired)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (onAgree != null) {
                        onAgree!();
                      }
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667eea),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      l10n?.t('permission.agree') ?? '我已了解并同意',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n?.t('permission.later') ?? '稍后再说'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (onAgree != null) {
                            onAgree!();
                          }
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667eea),
                        ),
                        child: Text(l10n?.t('permission.agree') ?? '我已了解'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPermissionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String platforms,
    required String description,
    required bool isRequired,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRequired ? Colors.red.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRequired ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: isRequired ? Colors.red : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isRequired ? Colors.red[900] : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        platforms,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
