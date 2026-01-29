# iOS 端开发指南

本文档说明如何在 macOS 上构建、运行与发布和平信使 iOS 端，以及 iOS 与 Android 的差异处理。

---

## 〇、使用本机连接 Mac 构建 IPA

**角色说明**：该 Mac **仅作为构建 IPA 包的环境**，日常开发在本机或远程 Linux 上完成；需要打 iOS 包时，在本机通过 SSH 连到该 Mac，在 Mac 上执行构建并产出 IPA。

**说明**：以下 SSH 配置与连接均在**你的本机**（运行 Cursor/开发用的电脑）上完成，**不要**在远程 Linux 服务器上连接 Mac。

### SSH 连接信息

| 项     | 值               |
|--------|------------------|
| 主机 IP | 192.168.200.132  |
| 端口   | 22               |
| 用户名 | mac15            |
| 密码   | mac15            |
| 密钥   | 与远程 Linux 相同（使用同一对 SSH 私钥） |

### 在本机配置 SSH（推荐）

在**本机**（你的电脑）的 `~/.ssh/config` 中追加以下内容（Windows 用户一般为 `C:\Users\你的用户名\.ssh\config`）：

**仅密码连接时**（不写 IdentityFile）：
```
Host mop-ios-mac
    HostName 192.168.200.132
    Port 22
    User mac15
    StrictHostKeyChecking accept-new
```

**使用密钥连接时**（与远程 Linux 同一把私钥，将路径改为本机实际路径）：
```
Host mop-ios-mac
    HostName 192.168.200.132
    Port 22
    User mac15
    IdentityFile ~/.ssh/你的私钥
    StrictHostKeyChecking accept-new
```

配置保存后，**在本机终端**执行：
```bash
ssh mop-ios-mac
```
按提示输入密码 `mac15`（若已用密钥则无需密码）。

### 本机直接命令连接（不写 config）

**密码连接：**
```bash
ssh -p 22 mac15@192.168.200.132
# 提示时输入密码：mac15
```

**密钥连接：**
```bash
ssh -p 22 -i ~/.ssh/你的私钥 mac15@192.168.200.132
```

### 使用流程简述（Mac 仅用于打 IPA）

1. **在本机**打开终端，用上述方式 SSH 登录到该 Mac（`ssh mop-ios-mac` 或 `ssh -p 22 mac15@192.168.200.132`）。若本机已与 Mac 建立过 SSH 连接，可直接登录。
2. 在 Mac 上安装/检查 Xcode、CocoaPods、Flutter，并执行 `flutter doctor -v`（见下方「一、环境要求」）。
3. 将项目代码同步到 Mac（在本机用 git/scp/rsync 传到 Mac，或 Mac 上 git clone），仅在有新构建需求时同步即可。
4. 在 Mac 上进入项目 `mobile/` 目录，执行 `flutter build ipa` 或 `open ios/Runner.xcworkspace` 在 Xcode 中 Archive 产出 IPA 包。

---

## 一、环境要求

- **操作系统**：macOS（Xcode 仅支持 macOS）
- **Xcode**：最新稳定版（推荐 15.x 及以上），从 App Store 安装
- **CocoaPods**：`sudo gem install cocoapods` 或 `brew install cocoapods`
- **Flutter**：已配置且 `flutter doctor` 通过 iOS 相关项
- **最低系统版本**：iOS 16.7+（见 IOS_VERSION_POLICY.md）

### 检查环境

```bash
cd /opt/mop/mobile
flutter doctor -v
```

若 iOS 工程尚未完整（缺少 Podfile、Runner.xcodeproj），先执行：

```bash
flutter pub get
flutter create . --platforms=ios
```

会补全 ios/Podfile、ios/Runner.xcodeproj 等，且不覆盖已有 Info.plist、AppDelegate 等修改。

---

## 二、已有 iOS 配置

### Info.plist 权限

ios/Runner/Info.plist 已配置：通讯录、相册、相机、麦克风、定位、屏幕共享（NSScreenCaptureUsageDescription）。说明中已注明 iOS 不支持直接读取短信和通话记录。

### 双端差异（代码已做平台判断）

| 功能 | Android | iOS |
|------|---------|-----|
| 通讯录 | 支持 | 支持 |
| 短信 | 支持 | 不支持（系统限制） |
| 通话记录 | 支持 | 不支持 |
| 应用列表 | 支持 | 不支持 |
| 相册/照片 | 支持 | 支持 |
| 视频通话/Jitsi | 支持 | 支持（含屏幕共享 ReplayKit） |
| FCM 推送 | 支持 | 支持（需在 Xcode 配置 APNs） |

相关实现：sms_service、call_log_service、app_list_service 等均用 Platform.isAndroid 判断，iOS 上不会调用 Android 专有 API。

---

## 三、构建与运行

### 真机/模拟器运行

```bash
cd /opt/mop/mobile
flutter pub get
flutter run
```

连接 iPhone 或选择模拟器后按提示选择设备。

### 仅构建（不签名）

```bash
flutter build ios --no-codesign
```

### 在 Xcode 中打开并签名

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中为 Runner 选择 Team、勾选 Automatically manage signing，选真机 Run 或 Product -> Archive 打正式包。

### 统一最低版本为 iOS 16.7

见 IOS_VERSION_POLICY.md，或执行脚本（若存在）：`./scripts/ios_set_deployment_target_16_7.sh`。

---

## 四、iOS 专有配置（按需）

- **推送（APNs）**：在 Apple Developer 配置 Push Notifications，Xcode 中为 Runner 增加 Push Notifications capability；后端需支持 APNs 并与 FCM 区分平台。
- **后台音频**：若需通话后台保活，在 Xcode 的 Signing & Capabilities 中增加 Background Modes，勾选 Audio, AirPlay, and Picture in Picture。
- **ATS**：默认开启；若需访问 HTTP 或自签名，在 Info.plist 中配置 NSAppTransportSecurity 例外（仅建议开发/内网使用）。

---

## 五、常见问题

1. CocoaPods 未安装：`sudo gem install cocoapods` 或 `brew install cocoapods`。
2. ios/Podfile 或 Runner.xcodeproj 不存在：在 mobile/ 下执行 `flutter create . --platforms=ios` 再 `flutter pub get`。
3. 真机无法安装：在 Xcode 中为 Runner 选择 Team 并开启 Automatically manage signing。
4. 模拟器无法运行：确认 Xcode 已安装对应版本模拟器（Xcode -> Settings -> Platforms）。

---

## 六、参考文档

- IOS_VERSION_POLICY.md：iOS 最低版本与真机测试范围
- mobile/MOBILE_DUAL_PLATFORM_REQUIREMENTS.md：双端功能与信息收集要求
- FCM_SETUP_GUIDE.md：推送与 FCM（Android）；iOS 需另配 APNs
