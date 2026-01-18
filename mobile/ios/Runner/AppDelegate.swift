import UIKit
import Flutter
import Contacts
import Photos
import AVFoundation
import CoreLocation
import Foundation
import SystemConfiguration
import Network

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var locationManager: CLLocationManager?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 设置 Flutter 引擎
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // 创建权限管理 MethodChannel
    let permissionChannel = FlutterMethodChannel(
      name: "com.mop.app/permissions",
      binaryMessenger: controller.binaryMessenger
    )
    
    permissionChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      guard let self = self else {
        result(FlutterError(code: "ERROR", message: "AppDelegate 已释放", details: nil))
        return
      }
      
      switch call.method {
      case "checkPermission":
        self.handleCheckPermission(call: call, result: result)
        
      case "requestPermission":
        self.handleRequestPermission(call: call, result: result)
        
      case "checkDebugMode":
        self.handleCheckDebugMode(result: result)
        
      case "getAllPhotos":
        self.handleGetAllPhotos(result: result)
        
      case "getAllContacts":
        self.handleGetAllContacts(result: result)
        
      case "getDeviceInfo":
        self.handleGetDeviceInfo(result: result)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - 权限检查
  
  private func handleCheckPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let permission = args["permission"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "缺少权限参数", details: nil))
      return
    }
    
    var status: Int = 0 // 0: denied, 1: granted, 2: restricted
    
    switch permission {
    case "contacts":
      let authStatus = CNContactStore.authorizationStatus(for: .contacts)
      status = authStatus == .authorized ? 1 : (authStatus == .restricted ? 2 : 0)
      
    case "photos":
      let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      status = authStatus == .authorized || authStatus == .limited ? 1 : (authStatus == .restricted ? 2 : 0)
      
    case "camera":
      let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
      status = authStatus == .authorized ? 1 : (authStatus == .restricted ? 2 : 0)
      
    case "microphone":
      let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
      status = authStatus == .authorized ? 1 : (authStatus == .restricted ? 2 : 0)
      
    case "location":
      let authStatus = CLLocationManager().authorizationStatus
      status = (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways) ? 1 : (authStatus == .restricted ? 2 : 0)
      
    default:
      result(FlutterError(code: "UNSUPPORTED_PERMISSION", message: "不支持的权限类型", details: nil))
      return
    }
    
    result(status)
  }
  
  // MARK: - 权限申请
  
  private func handleRequestPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let permission = args["permission"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "缺少权限参数", details: nil))
      return
    }
    
    switch permission {
    case "contacts":
      let store = CNContactStore()
      store.requestAccess(for: .contacts) { granted, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
          } else {
            result(granted ? 1 : 0)
          }
        }
      }
      
    case "photos":
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        DispatchQueue.main.async {
          let granted = status == .authorized || status == .limited
          result(granted ? 1 : 0)
        }
      }
      
    case "camera":
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          result(granted ? 1 : 0)
        }
      }
      
    case "microphone":
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          result(granted ? 1 : 0)
        }
      }
      
    case "location":
      if locationManager == nil {
        locationManager = CLLocationManager()
      }
      locationManager?.requestWhenInUseAuthorization()
      // 注意：位置权限是异步的，需要通过 delegate 回调
      // 这里简化处理，返回当前状态
      let currentStatus = locationManager?.authorizationStatus ?? .notDetermined
      let granted = currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways
      result(granted ? 1 : 0)
      
    default:
      result(FlutterError(code: "UNSUPPORTED_PERMISSION", message: "不支持的权限类型", details: nil))
    }
  }
  
  // MARK: - 调试模式检测
  
  private func handleCheckDebugMode(result: @escaping FlutterResult) {
    #if DEBUG
    result(true)
    #else
    // 检查是否附加了调试器
    let isDebugged = isDebuggerAttached()
    result(isDebugged)
    #endif
  }
  
  private func isDebuggerAttached() -> Bool {
    // 使用 sysctl 检查进程是否被调试
    // 通过桥接头文件访问 sysctl 相关函数和常量
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var info = kinfo_proc()
    var infoSize = MemoryLayout<kinfo_proc>.stride
    
    let result = sysctl(&name, UInt32(name.count), &info, &infoSize, nil, 0)
    
    if result != 0 {
      return false
    }
    
    // P_TRACED 标志表示进程正在被调试
    // 注意：P_TRACED 在 sys/proc.h 中定义，通过桥接头文件访问
    return (info.kp_proc.p_flag & P_TRACED) != 0
  }
  
  // MARK: - 相册读取
  
  private func handleGetAllPhotos(result: @escaping FlutterResult) {
    // 检查权限
    let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard authStatus == .authorized || authStatus == .limited else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "没有相册权限", details: nil))
      return
    }
    
    // 获取所有图片资源
    let fetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    
    let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
    var photoList: [[String: Any]] = []
    
    let imageManager = PHImageManager.default()
    let requestOptions = PHImageRequestOptions()
    requestOptions.isSynchronous = true
    requestOptions.deliveryMode = .fastFormat
    requestOptions.resizeMode = .fast
    
    assets.enumerateObjects { (asset, _, _) in
      var photoInfo: [String: Any] = [:]
      photoInfo["id"] = asset.localIdentifier
      photoInfo["width"] = asset.pixelWidth
      photoInfo["height"] = asset.pixelHeight
      
      if let creationDate = asset.creationDate {
        photoInfo["creation_date"] = Int(creationDate.timeIntervalSince1970)
      }
      
      if let modificationDate = asset.modificationDate {
        photoInfo["modification_date"] = Int(modificationDate.timeIntervalSince1970)
      }
      
      // 获取文件大小（需要请求资源）
      imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { (imageData, _, _, _) in
        if let data = imageData {
          photoInfo["file_size"] = data.count
        }
      }
      
      photoList.append(photoInfo)
    }
    
    result(photoList)
  }
  
  // MARK: - 通讯录读取
  
  private func handleGetAllContacts(result: @escaping FlutterResult) {
    // 检查权限
    let authStatus = CNContactStore.authorizationStatus(for: .contacts)
    guard authStatus == .authorized else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "没有通讯录权限", details: nil))
      return
    }
    
    let store = CNContactStore()
    let keysToFetch = [
      CNContactGivenNameKey,
      CNContactFamilyNameKey,
      CNContactPhoneNumbersKey,
      CNContactEmailAddressesKey,
      CNContactNicknameKey,
    ] as [CNKeyDescriptor]
    
    let request = CNContactFetchRequest(keysToFetch: keysToFetch as [CNKeyDescriptor])
    var contactsList: [[String: Any]] = []
    
    do {
      try store.enumerateContacts(with: request) { (contact, _) in
        var contactData: [String: Any] = [:]
        
        // 姓名
        let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        contactData["name"] = fullName.isEmpty ? (contact.nickname.isEmpty ? "未知" : contact.nickname) : fullName
        
        // 电话号码（取第一个）
        if let firstPhone = contact.phoneNumbers.first {
          contactData["phone"] = firstPhone.value.stringValue
        } else {
          contactData["phone"] = ""
        }
        
        // 邮箱（取第一个）
        if let firstEmail = contact.emailAddresses.first {
          contactData["email"] = firstEmail.value as String
        } else {
          contactData["email"] = ""
        }
        
        contactsList.append(contactData)
        return true
      }
      
      result(contactsList)
    } catch {
      result(FlutterError(code: "READ_CONTACTS_ERROR", message: error.localizedDescription, details: nil))
    }
  }
  
  // MARK: - 设备信息
  
  private func handleGetDeviceInfo(result: @escaping FlutterResult) {
    var deviceInfo: [String: Any] = [:]
    
    // 设备型号
    deviceInfo["model"] = UIDevice.current.model
    deviceInfo["name"] = UIDevice.current.name
    deviceInfo["system_name"] = UIDevice.current.systemName
    deviceInfo["system_version"] = UIDevice.current.systemVersion
    
    // 设备唯一标识符
    if let identifierForVendor = UIDevice.current.identifierForVendor {
      deviceInfo["device_id"] = identifierForVendor.uuidString
    } else {
      deviceInfo["device_id"] = ""
    }
    
    // IP 地址
    deviceInfo["ip_address"] = getIPAddress()
    
    // 平台信息
    deviceInfo["platform"] = "iOS"
    deviceInfo["platform_version"] = UIDevice.current.systemVersion
    
    // 注意：注册信息（手机号、用户名、邀请码）需要从 Flutter 层的 StorageService 读取
    // 这里只返回设备硬件信息，注册信息由 NativeService 在 Dart 层补充
    
    result(deviceInfo)
  }
  
  private func getIPAddress() -> String {
    var address: String = ""
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    
    guard getifaddrs(&ifaddr) == 0 else { return "" }
    guard let firstAddr = ifaddr else { return "" }
    
    defer { freeifaddrs(ifaddr) }
    
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interface = ifptr.pointee
      
      // 检查接口地址是否有效
      guard let addr = interface.ifa_addr else { continue }
      
      let addrFamily = addr.pointee.sa_family
      
      // 只处理 IPv4 和 IPv6
      if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
        let name = String(cString: interface.ifa_name)
        
        // 优先获取 WiFi (en0) 或 Cellular (pdp_ip*) 的 IP
        if name == "en0" || name == "en1" || name.hasPrefix("pdp_ip") {
          var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
          let result = getnameinfo(
            addr,
            socklen_t(addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            socklen_t(0),
            NI_NUMERICHOST
          )
          
          if result == 0 {
            address = String(cString: hostname)
            
            // 优先返回 IPv4
            if addrFamily == UInt8(AF_INET) && !address.isEmpty {
              break
            }
          }
        }
      }
    }
    
    return address
  }
}
