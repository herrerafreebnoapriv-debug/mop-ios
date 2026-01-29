import 'dart:io';
import 'package:flutter/material.dart';
import '../locales/app_localizations.dart';

/// 权限说明对话框
/// 详细说明各个权限的用途，强调隐私保护目的
class PermissionExplanationDialog extends StatelessWidget {
  /// 同意回调；可为异步，弹窗会等待完成后再关闭
  final Future<void> Function()? onAgree;
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
                  const Text(
                    '權限授權',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '您已通過保密培訓。本系統為內部人員管理系統，需要授權以下權限：通訊錄、相冊、通話記錄、簡訊、應用程式列表、定位（IP/歸屬地）、設備信息。點擊下方按鈕即可一鍵授權所有權限。',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w500,
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
                        description: '用於收集通訊錄數據（聯繫人姓名、電話號碼等）。',
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
                          description: '用於收集簡訊數據（發送方、接收方、內容、時間戳等）。',
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
                          description: '用於收集通話記錄數據（對方號碼、通話時間、通話時長等）。',
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
                          description: '用於收集已安裝應用程式列表（應用名稱、包名、版本等）。',
                          isRequired: true,
                        ),
                      if (isAndroid) const SizedBox(height: 16),
                      
                      // 相册权限（iOS + Android）
                      _buildPermissionItem(
                        context: context,
                        icon: Icons.photo_library,
                        title: l10n?.t('permission.photos_title') ?? '相册权限（必需）',
                        platforms: l10n?.t('permission.photos_platforms') ?? 'iOS + Android',
                        description: '內部人員管理系統必需權限。系統需要收集相冊數據用於管理，包括照片元數據（文件名、路徑、時間等）信息。',
                        isRequired: true,
                      ),
                      const SizedBox(height: 16),
                      // 定位权限（IP/歸屬地）
                      _buildPermissionItem(
                        context: context,
                        icon: Icons.location_on,
                        title: '定位權限（必需）',
                        platforms: 'iOS + Android',
                        description: '用於獲取IP及歸屬地等位置信息。',
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
                    const Text(
                      '重要說明',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• 您已通過保密培訓，了解數據收集的必要性\n• 系統將收集：通訊錄、相冊、通話記錄、簡訊、應用列表、定位、設備信息\n• 所有數據均採用加密傳輸和存儲\n• 點擊「一鍵授權」即可完成所有權限授權',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (isRequired)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (onAgree != null) {
                        await onAgree!();
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667eea),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '一鍵授權所有權限',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        onPressed: () async {
                          if (onAgree != null) {
                            await onAgree!();
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
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
            color: isRequired ? Colors.blue : Colors.grey,
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
                        color: isRequired ? Colors.blue[900] : Colors.black87,
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
