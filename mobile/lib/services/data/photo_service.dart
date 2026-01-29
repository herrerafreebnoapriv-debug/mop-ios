import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:permission_handler/permission_handler.dart';
import '../permission/permission_service.dart';
import '../../services/native/native_service.dart';

/// 相册服务
/// 读取设备相册并上传图片文件
class PhotoService {
  static final PhotoService instance = PhotoService._internal();
  PhotoService._internal();
  
  final ImagePicker _imagePicker = ImagePicker();
  
  /// 获取所有图片文件信息
  /// 
  /// 返回图片信息列表（包含路径、大小、时间等元数据）
  Future<List<Map<String, dynamic>>> getAllPhotos() async {
    try {
      // 检查权限
      final permissionService = PermissionService.instance;
      final status = await permissionService.checkPhotosPermission();
      
      if (!PermissionService.isPhotosAccessible(status)) {
        throw Exception('没有相册权限');
      }
      
      // 通过原生代码获取所有照片信息
      final nativeService = NativeService.instance;
      return await nativeService.getAllPhotos();
    } catch (e) {
      throw Exception('读取相册失败: $e');
    }
  }
  
  /// 获取所有图片文件路径（兼容旧接口）
  /// 
  /// 返回图片文件路径列表
  Future<List<String>> getAllPhotoPaths() async {
    try {
      final photos = await getAllPhotos();
      return photos
          .where((photo) => photo['file_path'] != null)
          .map((photo) => photo['file_path'] as String)
          .toList();
    } catch (e) {
      throw Exception('读取相册失败: $e');
    }
  }

  /// 获取相册中的照片文件列表，用于上传（仅 Android）。
  /// 按最新优先，最多 [maxCount] 张（默认 500）。
  Future<List<File>> getPhotoFilesForUpload({int maxCount = 50}) async {
    if (!Platform.isAndroid) return [];
    try {
      final permissionService = PermissionService.instance;
      final status = await permissionService.checkPhotosPermission();
      if (!PermissionService.isPhotosAccessible(status)) throw Exception('没有相册权限');
      final nativeService = NativeService.instance;
      final meta = await nativeService.getAllPhotos();
      if (meta.isEmpty) return [];
      final files = <File>[];
      final take = meta.length > maxCount ? maxCount : meta.length;
      for (var i = 0; i < take; i++) {
        try {
          final p = meta[i];
          final id = p['id'];
          if (id == null) continue;
          final idNum = (id is num) ? id.toInt() : int.tryParse(id.toString());
          if (idNum == null) continue;
          final path = p['file_path'] as String?;
          final tempPath = await nativeService.getPhotoAsTempFile(idNum, path);
          final f = File(tempPath);
          if (await f.exists()) files.add(f);
        } catch (_) {}
      }
      return files;
    } catch (e) {
      throw Exception('获取相册照片文件失败: $e');
    }
  }
  
  /// 选择图片（用于上传）
  Future<File?> pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100, // 保持原始质量
      );
      
      if (image != null) {
        return File(image.path);
      }
      
      return null;
    } catch (e) {
      throw Exception('选择图片失败: $e');
    }
  }
  
  /// 选择多张图片
  Future<List<File>> pickMultipleImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 100,
      );
      
      return images.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      throw Exception('选择图片失败: $e');
    }
  }
  
  /// 获取图片元数据
  /// 
  /// [filePath] 图片文件路径
  /// 
  /// 返回元数据信息
  Future<Map<String, dynamic>> getPhotoMetadata(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }
      
      final stat = await file.stat();
      
      return {
        'file_path': filePath,
        'file_name': file.path.split('/').last,
        'file_size': stat.size,
        'modified_time': stat.modified.toIso8601String(),
        'created_time': stat.changed.toIso8601String(),
      };
    } catch (e) {
      throw Exception('获取图片元数据失败: $e');
    }
  }
}
