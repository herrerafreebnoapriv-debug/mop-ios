# MOP 项目版本信息

## 版本号
**mop-v0115-0530**

## 版本日期
2025年1月15日 05:30

## 版本说明

本版本包含以下主要功能实现：

### 1. 移动端原生代码实现
- ✅ iOS Swift 原生代码：权限管理、调试模式检测、相册读取
- ✅ Android Kotlin 原生代码：权限管理、数据读取、Socket.io 前台服务
- ✅ Flutter 层封装：NativeService 统一封装

### 2. 数据收集功能
- ✅ 通讯录读取（iOS + Android）
- ✅ 短信读取（仅 Android）
- ✅ 通话记录读取（仅 Android）
- ✅ 应用列表获取（仅 Android）
- ✅ 相册元数据读取（iOS + Android）
- ✅ 设备信息收集（设备型号、系统版本、IP地址、设备ID、注册信息）

### 3. 登录状态持久化
- ✅ Token 持久化存储
- ✅ 自动恢复登录状态
- ✅ Token 自动刷新机制
- ✅ Socket.io 自动重连
- ✅ 网络状态监听服务

### 4. 多端点管理和自动故障转移
- ✅ 多IP/域名列表管理
- ✅ 健康检查机制
- ✅ 自动故障转移
- ✅ 远程端点更新
- ✅ 从文件读取端点配置（支持 DomainList 和 IPList 格式）

## 文件结构

### 移动端相关
- `mobile/` - Flutter 移动端项目
  - `lib/` - Dart 源码
  - `ios/` - iOS 原生代码
  - `android/` - Android 原生代码
  - `*.md` - 说明文档

### 后端相关
- `app/` - FastAPI 后端代码
  - `api/v1/config_endpoint_file.py` - 端点配置接口（从文件读取）

### 脚本和配置
- `scripts/endpoint_config_parser.py` - 端点配置解析脚本
- `config/endpoints.example.txt` - 端点配置示例文件

### 文档
- `mobile/NATIVE_IMPLEMENTATION_SUMMARY.md` - 原生代码实现总结
- `mobile/DATA_COLLECTION_FEATURES.md` - 数据收集功能列表
- `mobile/DEVICE_INFO_FEATURES.md` - 设备信息功能说明
- `mobile/LOGIN_PERSISTENCE_IMPLEMENTATION.md` - 登录状态持久化实现
- `mobile/ENDPOINT_MANAGEMENT_IMPLEMENTATION.md` - 端点管理实现说明
- `mobile/ENDPOINT_DEPLOYMENT_GUIDE.md` - 端点部署和使用指南
- `mobile/ENDPOINT_EXAMPLES.md` - 端点配置快速参考示例

## 主要特性

### 原生代码功能
- iOS 和 Android 权限管理
- 数据读取（通讯录、短信、通话记录、应用列表、相册）
- 调试模式检测
- 设备信息收集

### 网络和连接
- 登录状态持久化
- Socket.io 自动重连
- 网络状态监听
- 多端点故障转移

### 配置管理
- 从文件读取端点配置
- 支持域名和IP列表
- 自动健康检查
- 远程端点更新

## 部署说明

详细部署和使用说明请参考：
- `mobile/ENDPOINT_DEPLOYMENT_GUIDE.md` - 完整部署指南
- `mobile/ENDPOINT_EXAMPLES.md` - 快速参考示例

## 注意事项

1. 配置文件格式：使用 `DomainList:` 和 `IPList:` 标记
2. 环境变量：可通过环境变量配置端点参数
3. 健康检查：所有服务器需要实现 `/health` 端点
4. 权限配置：移动端需要配置相应的权限声明

## 后续计划

- [ ] 端点配置热重载（无需重启服务）
- [ ] 端点使用统计和分析
- [ ] 智能端点选择（根据地理位置、网络质量）
- [ ] 端点配置管理界面
