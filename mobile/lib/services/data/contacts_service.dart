import 'package:permission_handler/permission_handler.dart';
import '../../services/native/native_service.dart';
import '../permission/permission_service.dart';

/// 通讯录服务
/// 读取设备通讯录并转换为上传格式
class ContactsDataService {
  static final ContactsDataService instance = ContactsDataService._internal();
  ContactsDataService._internal();
  
  final NativeService _nativeService = NativeService.instance;
  
  /// 获取所有联系人
  /// 
  /// 返回联系人列表，格式：
  /// [
  ///   {
  ///     "name": "联系人姓名",
  ///     "phone": "电话号码",
  ///     "email": "邮箱（可选）"
  ///   }
  /// ]
  Future<List<Map<String, dynamic>>> getAllContacts() async {
    try {
      // 检查权限
      final permissionService = PermissionService.instance;
      var status = await permissionService.checkContactsPermission();
      
      if (status != PermissionStatus.granted) {
        // 尝试申请权限
        status = await permissionService.requestContactsPermission();
        if (status != PermissionStatus.granted) {
          throw Exception('没有通讯录权限');
        }
      }
      
      // 通过原生代码获取所有联系人
      return await _nativeService.getAllContacts();
    } catch (e) {
      throw Exception('读取通讯录失败: $e');
    }
  }
  
  /// 检查权限（静态方法，用于兼容）
  static Future<bool> checkPermission() async {
    final permissionService = PermissionService.instance;
    final status = await permissionService.checkContactsPermission();
    return status == PermissionStatus.granted;
  }
}
