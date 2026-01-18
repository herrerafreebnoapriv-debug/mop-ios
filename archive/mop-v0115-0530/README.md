# MOP 项目版本归档 - mop-v0115-0530

## 压缩包说明

本目录包含以下压缩包：

### 1. mop-v0115-0530-complete.tar.gz
**完整版本包**（推荐下载）
- 包含所有源码和文档
- 包含版本信息

### 2. mop-v0115-0530-source.tar.gz
**源码包**
- 移动端源码（Flutter + iOS + Android）
- 后端端点配置接口
- 配置解析脚本
- 配置文件示例

### 3. mop-v0115-0530-docs.tar.gz
**文档包**
- 所有说明文档（Markdown 格式）
- 版本信息

## 解压说明

### 解压完整版本包
```bash
tar -xzf mop-v0115-0530-complete.tar.gz
```

### 解压源码包
```bash
tar -xzf mop-v0115-0530-source.tar.gz
```

### 解压文档包
```bash
tar -xzf mop-v0115-0530-docs.tar.gz
```

## 文件结构

解压后的文件结构：

```
mop-v0115-0530/
├── mobile/                    # Flutter 移动端项目
│   ├── lib/                   # Dart 源码
│   │   ├── core/              # 核心服务
│   │   │   ├── services/      # 服务层
│   │   │   │   ├── endpoint_manager.dart
│   │   │   │   ├── network_service.dart
│   │   │   │   └── ...
│   │   │   └── config/        # 配置管理
│   │   ├── providers/         # 状态管理
│   │   ├── services/          # 业务服务
│   │   │   ├── api/           # API 服务
│   │   │   ├── data/          # 数据收集服务
│   │   │   └── native/        # 原生服务封装
│   │   └── ...
│   ├── ios/                   # iOS 原生代码
│   │   └── Runner/
│   │       ├── AppDelegate.swift
│   │       └── Bridging-Header.h
│   ├── android/               # Android 原生代码
│   │   └── app/src/main/kotlin/com/mop/app/
│   │       ├── MainActivity.kt
│   │       └── SocketForegroundService.kt
│   └── *.md                   # 说明文档
├── app/api/v1/                # 后端端点配置接口
│   └── config_endpoint_file.py
├── scripts/                   # 脚本
│   └── endpoint_config_parser.py
├── config/                    # 配置文件示例
│   └── endpoints.example.txt
└── VERSION_INFO.md            # 版本信息
```

## 主要文档

### 实现说明文档
- `NATIVE_IMPLEMENTATION_SUMMARY.md` - 原生代码实现总结
- `DATA_COLLECTION_FEATURES.md` - 数据收集功能列表
- `DEVICE_INFO_FEATURES.md` - 设备信息功能说明
- `LOGIN_PERSISTENCE_IMPLEMENTATION.md` - 登录状态持久化实现
- `ENDPOINT_MANAGEMENT_IMPLEMENTATION.md` - 端点管理实现说明

### 部署和使用文档
- `ENDPOINT_DEPLOYMENT_GUIDE.md` - 完整部署和使用指南（包含范例）
- `ENDPOINT_EXAMPLES.md` - 快速参考示例

## 快速开始

### 1. 查看版本信息
```bash
cat VERSION_INFO.md
```

### 2. 查看部署指南
```bash
cat mobile/ENDPOINT_DEPLOYMENT_GUIDE.md
```

### 3. 查看配置示例
```bash
cat config/endpoints.example.txt
```

## 功能清单

### ✅ 已完成功能

1. **原生代码实现**
   - iOS Swift 权限管理和数据读取
   - Android Kotlin 权限管理和数据读取
   - Flutter 层统一封装

2. **数据收集**
   - 通讯录、短信、通话记录、应用列表、相册
   - 设备信息（型号、系统版本、IP、设备ID、注册信息）

3. **登录状态持久化**
   - Token 持久化
   - 自动恢复登录状态
   - Token 自动刷新
   - Socket.io 自动重连

4. **多端点管理**
   - 多IP/域名列表管理
   - 健康检查
   - 自动故障转移
   - 从文件读取配置

## 注意事项

1. 配置文件格式：使用 `DomainList:` 和 `IPList:` 标记
2. 需要配置相应的环境变量
3. 所有服务器需要实现 `/health` 健康检查端点
4. 移动端需要配置相应的权限声明

## 联系信息

如有问题，请参考相关文档或联系开发团队。
