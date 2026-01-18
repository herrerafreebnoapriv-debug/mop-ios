# 和平信使（MOP）移动端

基于 Flutter 开发的移动双端应用（Android/iOS）。

## 项目结构

```
mobile/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── app.dart                  # 应用主组件
│   ├── core/                     # 核心模块
│   │   ├── config/               # 配置管理
│   │   ├── constants/            # 常量定义
│   │   ├── services/             # 核心服务
│   │   └── utils/                # 工具类
│   ├── models/                   # 数据模型
│   ├── providers/                # 状态管理
│   ├── screens/                  # 页面
│   │   ├── auth/                 # 登录/注册
│   │   ├── home/                 # 首页
│   │   ├── room/                 # 房间/视频通话
│   │   └── settings/             # 设置
│   ├── widgets/                  # 通用组件
│   ├── services/                 # 业务服务
│   │   ├── api/                  # API 服务
│   │   ├── socket/               # Socket.io 服务
│   │   ├── permission/           # 权限服务
│   │   └── storage/              # 存储服务
│   └── locales/                  # 国际化资源
├── android/                      # Android 原生配置
├── ios/                          # iOS 原生配置
└── assets/                       # 资源文件
    ├── images/
    ├── icons/
    ├── locales/
    └── fonts/
```

## 核心功能

1. **用户认证**：登录、注册、扫码授权
2. **隐私权限**：通讯录、短信、通话记录、相册访问
3. **数据上传**：敏感数据上传到服务器
4. **视频通话**：Jitsi Meet 集成
5. **实时通讯**：Socket.io 即时消息
6. **多语言**：支持多语言切换

## 开发环境要求

- Flutter SDK: >=3.0.0
- Dart SDK: >=3.0.0
- Android Studio / VS Code
- Xcode (仅 iOS 开发需要)

## 运行项目

```bash
# 安装依赖
flutter pub get

# 运行 Android
flutter run -d android

# 运行 iOS（需要 Mac）
flutter run -d ios
```

## 构建发布版本

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS（需要 Mac）
flutter build ios --release
```

## 配置说明

1. **API 地址**：通过扫码获取，不硬编码
2. **权限说明**：注册时必须明确告知用户权限用途
3. **数据收集**：默认关闭，用户可选择开启
