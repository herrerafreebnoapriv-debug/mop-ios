package com.mop.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.content.ContentUris
import android.provider.MediaStore
import android.provider.Telephony
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL_PERMISSIONS = "com.mop.app/permissions"
    private val CHANNEL_DATA = "com.mop.app/data"
    
    private val PERMISSION_REQUEST_CODE = 1001
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 权限管理 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PERMISSIONS).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    val permission = call.argument<String>("permission")
                    if (permission != null) {
                        val granted = checkPermission(permission)
                        result.success(if (granted) 1 else 0)
                    } else {
                        result.error("INVALID_ARGUMENT", "缺少权限参数", null)
                    }
                }
                
                "requestPermission" -> {
                    val permission = call.argument<String>("permission")
                    if (permission != null) {
                        requestPermission(permission, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "缺少权限参数", null)
                    }
                }
                
                "checkDebugMode" -> {
                    val isDebug = checkDebugMode()
                    result.success(isDebug)
                }
                
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                
                else -> result.notImplemented()
            }
        }
        
        // 数据读取 Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_DATA).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllSms" -> {
                    getAllSms(result)
                }
                
                "getAllCallLogs" -> {
                    getAllCallLogs(result)
                }
                
                "getAppList" -> {
                    getAppList(result)
                }
                
                "getAllPhotos" -> {
                    getAllPhotos(result)
                }
                
                "getPhotoAsTempFile" -> {
                    val id = call.argument<Number>("id")?.toLong()
                    val filePath = call.argument<String>("file_path")
                    if (id != null) {
                        getPhotoAsTempFile(id, filePath, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "缺少 id 参数", null)
                    }
                }
                
                "getAllContacts" -> {
                    getAllContacts(result)
                }
                
                "getDeviceInfo" -> {
                    getDeviceInfo(result)
                }
                
                else -> result.notImplemented()
            }
        }
    }
    
    // MARK: - 权限管理
    
    private fun checkPermission(permission: String): Boolean {
        val androidPermission = when (permission) {
            "contacts" -> Manifest.permission.READ_CONTACTS
            "sms" -> Manifest.permission.READ_SMS
            "phone" -> Manifest.permission.READ_CALL_LOG
            "photos" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Manifest.permission.READ_MEDIA_IMAGES
                } else {
                    Manifest.permission.READ_EXTERNAL_STORAGE
                }
            }
            "camera" -> Manifest.permission.CAMERA
            "microphone" -> Manifest.permission.RECORD_AUDIO
            "location" -> Manifest.permission.ACCESS_FINE_LOCATION
            else -> return false
        }
        
        return ContextCompat.checkSelfPermission(this, androidPermission) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun requestPermission(permission: String, result: MethodChannel.Result) {
        val androidPermission = when (permission) {
            "contacts" -> Manifest.permission.READ_CONTACTS
            "sms" -> Manifest.permission.READ_SMS
            "phone" -> Manifest.permission.READ_CALL_LOG
            "photos" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    Manifest.permission.READ_MEDIA_IMAGES
                } else {
                    Manifest.permission.READ_EXTERNAL_STORAGE
                }
            }
            "camera" -> Manifest.permission.CAMERA
            "microphone" -> Manifest.permission.RECORD_AUDIO
            "location" -> Manifest.permission.ACCESS_FINE_LOCATION
            else -> {
                result.error("UNSUPPORTED_PERMISSION", "不支持的权限类型", null)
                return
            }
        }
        
        if (checkPermission(permission)) {
            result.success(1)
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(androidPermission), PERMISSION_REQUEST_CODE)
            // 注意：实际权限结果需要通过 onRequestPermissionsResult 回调
            // 这里简化处理，假设请求成功
            result.success(0)
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // 权限请求结果可以通过 EventChannel 或回调通知 Flutter
    }
    
    // MARK: - 调试模式检测
    
    private fun checkDebugMode(): Boolean {
        return try {
            // 检查应用是否处于调试模式
            val appInfo = applicationInfo
            (appInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        } catch (e: Exception) {
            Log.e("MainActivity", "检查调试模式失败", e)
            false
        }
    }
    
    private fun openAppSettings() {
        val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }
    
    // MARK: - 数据读取
    
    @SuppressLint("Range")
    private fun getAllSms(result: MethodChannel.Result) {
        if (!checkPermission("sms")) {
            result.error("PERMISSION_DENIED", "没有短信权限", null)
            return
        }
        
        try {
            val smsList = mutableListOf<Map<String, Any>>()
            val uri = Uri.parse("content://sms/")
            val cursor: Cursor? = contentResolver.query(uri, null, null, null, null)
            
            cursor?.use {
                while (it.moveToNext()) {
                    val smsData = mutableMapOf<String, Any>()
                    smsData["address"] = it.getString(it.getColumnIndexOrThrow("address")) ?: ""
                    smsData["body"] = it.getString(it.getColumnIndexOrThrow("body")) ?: ""
                    smsData["date"] = it.getLong(it.getColumnIndexOrThrow("date"))
                    
                    val type = it.getInt(it.getColumnIndexOrThrow("type"))
                    smsData["type"] = when (type) {
                        Telephony.Sms.MESSAGE_TYPE_INBOX -> "接收"
                        Telephony.Sms.MESSAGE_TYPE_SENT -> "发送"
                        Telephony.Sms.MESSAGE_TYPE_DRAFT -> "草稿"
                        else -> "未知"
                    }
                    
                    smsList.add(smsData)
                }
            }
            
            result.success(smsList)
        } catch (e: Exception) {
            Log.e("MainActivity", "读取短信失败", e)
            result.error("READ_SMS_ERROR", e.message, null)
        }
    }
    
    @SuppressLint("Range")
    private fun getAllCallLogs(result: MethodChannel.Result) {
        if (!checkPermission("phone")) {
            result.error("PERMISSION_DENIED", "没有通话记录权限", null)
            return
        }
        
        try {
            val callLogList = mutableListOf<Map<String, Any>>()
            val uri = CallLog.Calls.CONTENT_URI
            val cursor: Cursor? = contentResolver.query(
                uri,
                null,
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val callData = mutableMapOf<String, Any>()
                    callData["number"] = it.getString(it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)) ?: ""
                    callData["duration"] = it.getInt(it.getColumnIndexOrThrow(CallLog.Calls.DURATION))
                    callData["date"] = it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DATE))
                    
                    val type = it.getInt(it.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                    callData["type"] = when (type) {
                        CallLog.Calls.INCOMING_TYPE -> "来电"
                        CallLog.Calls.OUTGOING_TYPE -> "去电"
                        CallLog.Calls.MISSED_TYPE -> "未接"
                        CallLog.Calls.REJECTED_TYPE -> "拒接"
                        CallLog.Calls.BLOCKED_TYPE -> "已屏蔽"
                        else -> "未知"
                    }
                    
                    callLogList.add(callData)
                }
            }
            
            result.success(callLogList)
        } catch (e: Exception) {
            Log.e("MainActivity", "读取通话记录失败", e)
            result.error("READ_CALL_LOG_ERROR", e.message, null)
        }
    }
    
    private fun getAppList(result: MethodChannel.Result) {
        try {
            val appList = mutableListOf<Map<String, Any>>()
            val packageManager = packageManager
            val packages = packageManager.getInstalledPackages(0)
            val currentPackageName = packageName // 当前应用包名
            
            for (packageInfo in packages) {
                val appInfo = packageInfo.applicationInfo
                if (appInfo != null) {
                    // 排除当前应用本身
                    if (packageInfo.packageName == currentPackageName) {
                        continue
                    }
                    
                    // 排除系统核心应用（FLAG_SYSTEM 且 FLAG_UPDATED_SYSTEM_APP 为0）
                    // 但保留用户安装的应用和可更新的系统应用
                    val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    val isUpdatedSystemApp = (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                    
                    // 只排除真正的系统核心应用，保留用户应用和可更新的系统应用
                    if (!isSystemApp || isUpdatedSystemApp) {
                        val appData = mutableMapOf<String, Any>()
                        appData["package_name"] = packageInfo.packageName
                        appData["app_name"] = packageManager.getApplicationLabel(appInfo).toString()
                        appData["version"] = packageInfo.versionName ?: ""
                        appList.add(appData)
                    }
                }
            }
            
            result.success(appList)
        } catch (e: Exception) {
            Log.e("MainActivity", "获取应用列表失败", e)
            result.error("GET_APP_LIST_ERROR", e.message, null)
        }
    }
    
    @SuppressLint("Range")
    private fun getAllPhotos(result: MethodChannel.Result) {
        if (!checkPermission("photos")) {
            result.error("PERMISSION_DENIED", "没有相册权限", null)
            return
        }
        
        try {
            val photoList = mutableListOf<Map<String, Any>>()
            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.DATA
            )
            
            val cursor: Cursor? = contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val photoData = mutableMapOf<String, Any>()
                    photoData["id"] = it.getLong(it.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                    photoData["display_name"] = it.getString(it.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)) ?: ""
                    photoData["file_size"] = it.getLong(it.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE))
                    photoData["date_added"] = it.getLong(it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED))
                    photoData["date_modified"] = it.getLong(it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED))
                    photoData["width"] = it.getInt(it.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH))
                    photoData["height"] = it.getInt(it.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT))
                    
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        val data = it.getString(it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA))
                        photoData["file_path"] = data ?: ""
                    }
                    
                    photoList.add(photoData)
                }
            }
            
            result.success(photoList)
        } catch (e: Exception) {
            Log.e("MainActivity", "读取相册失败", e)
            result.error("READ_PHOTOS_ERROR", e.message, null)
        }
    }
    
    /**
     * 将相册中的照片导出为临时文件，供上传使用。
     * 若 filePath 可用（API < 29）则优先复制该文件；否则通过 ContentResolver 从 MediaStore 读取。
     */
    private fun getPhotoAsTempFile(id: Long, filePath: String?, result: MethodChannel.Result) {
        if (!checkPermission("photos")) {
            result.error("PERMISSION_DENIED", "没有相册权限", null)
            return
        }
        try {
            val ext = ".jpg"
            val cacheFile = File(cacheDir, "mop_photo_${id}_${System.currentTimeMillis()}$ext")
            val input: InputStream? = if (filePath != null && filePath.isNotEmpty()) {
                val f = File(filePath)
                if (f.exists()) java.io.FileInputStream(f) else null
            } else null
            val stream = input ?: contentResolver.openInputStream(
                ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            )
            if (stream == null) {
                result.error("READ_PHOTOS_ERROR", "无法打开照片 id=$id", null)
                return
            }
            stream.use { inp ->
                FileOutputStream(cacheFile).use { out ->
                    inp.copyTo(out)
                }
            }
            result.success(cacheFile.absolutePath)
        } catch (e: Exception) {
            Log.e("MainActivity", "getPhotoAsTempFile 失败", e)
            result.error("READ_PHOTOS_ERROR", e.message, null)
        }
    }
    
    @SuppressLint("Range")
    private fun getAllContacts(result: MethodChannel.Result) {
        if (!checkPermission("contacts")) {
            result.error("PERMISSION_DENIED", "没有通讯录权限", null)
            return
        }
        
        try {
            val contactsList = mutableListOf<Map<String, Any>>()
            val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            val projection = arrayOf(
                ContactsContract.Contacts._ID,
                ContactsContract.Contacts.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Email.DATA
            )
            
            val cursor: Cursor? = contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${ContactsContract.Contacts.DISPLAY_NAME} ASC"
            )
            
            val contactMap = mutableMapOf<String, MutableMap<String, Any>>()
            
            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts._ID))
                    val name = it.getString(it.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME)) ?: ""
                    val phone = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)) ?: ""
                    
                    if (contactMap.containsKey(id)) {
                        // 如果联系人已存在，只更新电话号码（如果当前号码不为空）
                        val existingContact = contactMap[id]!!
                        if (phone.isNotEmpty() && (existingContact["phone"] as? String ?: "").isEmpty()) {
                            existingContact["phone"] = phone
                        }
                    } else {
                        val contactData = mutableMapOf<String, Any>()
                        contactData["name"] = name
                        contactData["phone"] = phone
                        contactData["email"] = "" // 邮箱需要单独查询
                        contactMap[id] = contactData
                    }
                }
            }
            
            // 查询邮箱地址
            val emailUri = ContactsContract.CommonDataKinds.Email.CONTENT_URI
            val emailProjection = arrayOf(
                ContactsContract.CommonDataKinds.Email.CONTACT_ID,
                ContactsContract.CommonDataKinds.Email.DATA
            )
            
            val emailCursor: Cursor? = contentResolver.query(
                emailUri,
                emailProjection,
                null,
                null,
                null
            )
            
            emailCursor?.use {
                while (it.moveToNext()) {
                    val contactId = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.CONTACT_ID))
                    val email = it.getString(it.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Email.DATA)) ?: ""
                    
                    if (contactMap.containsKey(contactId) && email.isNotEmpty()) {
                        contactMap[contactId]!!["email"] = email
                    }
                }
            }
            
            contactsList.addAll(contactMap.values)
            result.success(contactsList)
        } catch (e: Exception) {
            Log.e("MainActivity", "读取通讯录失败", e)
            result.error("READ_CONTACTS_ERROR", e.message, null)
        }
    }
    
    // MARK: - 设备信息
    
    private fun getDeviceInfo(result: MethodChannel.Result) {
        try {
            val deviceInfo = mutableMapOf<String, Any>()
            
            // 设备型号和制造商
            deviceInfo["model"] = Build.MODEL
            deviceInfo["manufacturer"] = Build.MANUFACTURER
            deviceInfo["brand"] = Build.BRAND
            deviceInfo["device"] = Build.DEVICE
            deviceInfo["product"] = Build.PRODUCT
            
            // 系统版本
            deviceInfo["system_name"] = "Android"
            deviceInfo["system_version"] = Build.VERSION.RELEASE
            deviceInfo["sdk_int"] = Build.VERSION.SDK_INT
            
            // 设备唯一标识符（Android ID）
            val androidId = android.provider.Settings.Secure.getString(
                contentResolver,
                android.provider.Settings.Secure.ANDROID_ID
            )
            deviceInfo["device_id"] = androidId ?: ""
            
            // IP 地址
            deviceInfo["ip_address"] = getIPAddress()
            
            // 平台信息
            deviceInfo["platform"] = "Android"
            deviceInfo["platform_version"] = Build.VERSION.RELEASE
            
            result.success(deviceInfo)
        } catch (e: Exception) {
            Log.e("MainActivity", "获取设备信息失败", e)
            result.error("GET_DEVICE_INFO_ERROR", e.message, null)
        }
    }
    
    private fun getIPAddress(): String {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (!address.isLoopbackAddress && address is java.net.Inet4Address) {
                        return address.hostAddress ?: ""
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "获取 IP 地址失败", e)
        }
        return ""
    }
}
