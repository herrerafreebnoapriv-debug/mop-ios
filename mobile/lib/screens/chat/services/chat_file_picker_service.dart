import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/permission/permission_service.dart';
import '../../../locales/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

/// 聊天文件选择服务
class ChatFilePickerService {
  /// 选择图片（相册）
  Future<String?> pickImage({
    required BuildContext context,
    required Function(String) onError,
  }) async {
    try {
      var permissionStatus = await PermissionService.instance.checkPhotosPermission();
      
      if (!PermissionService.isPhotosAccessible(permissionStatus)) {
        permissionStatus = await PermissionService.instance.requestPhotosPermission();
        if (PermissionService.isPhotosAccessible(permissionStatus)) {
          await Future.delayed(const Duration(milliseconds: 100));
          permissionStatus = await PermissionService.instance.checkPhotosPermission();
        }
        if (!PermissionService.isPhotosAccessible(permissionStatus)) {
          if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n?.t('permission.photos_required') ?? '需要相册权限才能发送图片'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: l10n?.t('permission.go_to_settings') ?? '前往设置',
                  onPressed: () => PermissionService.instance.openAppSettings(),
                ),
              ),
            );
          }
          return null;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      return image?.path;
    } catch (e) {
      onError(e.toString());
      return null;
    }
  }

  /// 拍照
  Future<String?> takePhoto({
    required BuildContext context,
    required Function(String) onError,
  }) async {
    try {
      var permissionStatus = await PermissionService.instance.checkCameraPermission();
      if (permissionStatus != PermissionStatus.granted) {
        permissionStatus = await PermissionService.instance.requestCameraPermission();
        if (permissionStatus != PermissionStatus.granted) {
          if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n?.t('permission.camera_required') ?? '需要相机权限才能拍照'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: l10n?.t('permission.go_to_settings') ?? '前往设置',
                  onPressed: () => PermissionService.instance.openAppSettings(),
                ),
              ),
            );
          }
          return null;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      return photo?.path;
    } catch (e) {
      onError(e.toString());
      return null;
    }
  }

  /// 选择文件
  Future<String?> pickFile({
    required BuildContext context,
    required Function(String) onError,
  }) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;
      
      final platformFile = result.files.first;
      final path = platformFile.path;
      
      if (path == null || path.isEmpty) {
        final l10n = AppLocalizations.of(context);
        onError(l10n?.t('errors.pick_file_failed') ?? '选择文件失败');
        return null;
      }
      
      return path;
    } catch (e) {
      onError(e.toString());
      return null;
    }
  }
}
