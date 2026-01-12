# Jitsi 去品牌化和去除外链配置

## 📋 概述

本项目已配置自动去 Jitsi 化和去除外链功能，确保一键部署后自动完成以下操作：

1. ✅ 替换 favicon（随机选择 `/opt/mop/mop_ico_fav/` 下的方形图标）
2. ✅ 替换首页左上角 logo（随机选择 `/opt/mop/mop_ico_fav/jit_logo/` 下的图标）
3. ✅ 替换所有 "Jitsi Meet" 文本为 "Messenger of Peace"（标题栏、页面文本等）
4. ✅ 去除所有外链（Jitsi 官网、移动应用下载链接等）
5. ✅ 去除品牌水印和 Powered by 标识
6. ✅ 禁用可能包含外链的功能（录制、直播、转录等）

## 🎯 配置方式

### 自动配置（推荐）

在启动 Jitsi 服务时，会自动执行 `scripts/customize_jitsi.sh` 脚本：

```bash
./scripts/start_jitsi.sh
```

脚本会自动：
- 等待容器启动
- 随机选择图标文件
- 替换 favicon 和 logo
- 更新配置文件去除外链
- 应用所有自定义配置

### 手动执行

如果需要单独执行自定义配置：

```bash
./scripts/customize_jitsi.sh
```

## 📁 文件结构

```
/opt/mop/
├── mop_ico_fav/              # 图标资源目录
│   ├── jit_logo/            # 首页左上角 logo（随机选择）
│   │   ├── jit_log (1).png
│   │   ├── jit_log (2).png
│   │   └── ...
│   ├── mop-ico (1).png      # 小尺寸 favicon（随机选择）
│   ├── mop-ico (2).png
│   └── ...
│   └── mop_ico (1).png      # 大尺寸图标（随机选择）
│       └── ...
├── docker/jitsi/custom/      # 配置文件模板
│   ├── interface_config.js   # 界面配置（去除外链，APP_NAME: 'Messenger of Peace'）
│   ├── config.js            # 主配置（去除外链）
│   ├── title.html           # 页面标题（替换为 'Messenger of Peace'）
│   └── lang-override.js     # 语言覆盖脚本（动态替换页面文本）
└── scripts/
    └── customize_jitsi.sh   # 自定义配置脚本
```

## 🔧 配置说明

### interface_config.js

已配置的去除外链和品牌替换选项：

- `APP_NAME: 'Messenger of Peace'` - 应用名称（替换 "Jitsi Meet"）
- `BRAND_WATERMARK_LINK: ''` - 去除品牌水印链接
- `JITSI_WATERMARK_LINK: ''` - 去除 Jitsi 水印链接
- `MOBILE_APP_PROMO: false` - 禁用移动应用推广
- `MOBILE_DOWNLOAD_LINK_*: ''` - 去除移动应用下载链接
- `SHOW_JITSI_WATERMARK: false` - 隐藏 Jitsi 水印
- `SHOW_POWERED_BY: false` - 隐藏 Powered by 标识
- `DISPLAY_WELCOME_PAGE_CONTENT: false` - 禁用欢迎页内容

### title.html

页面标题和 meta 标签配置：

- `<title>Messenger of Peace</title>` - 浏览器标题栏
- `og:title` - Open Graph 标题
- `itemprop="name"` - Schema.org 名称
- 所有描述文本中的 "Jitsi Meet" 已替换为 "Messenger of Peace"

### lang-override.js

动态文本替换脚本：

- 自动替换页面标题中的 "Jitsi Meet"
- 自动替换 meta 标签中的 "Jitsi Meet"
- 自动替换页面文本内容中的 "Jitsi Meet"
- 使用 MutationObserver 监听动态内容变化

### config.js

已配置的去除外链选项：

- `disableInviteFunctions: true` - 禁用邀请功能
- `disableThirdPartyRequests: true` - 禁用第三方请求
- `recordingService: { enabled: false }` - 禁用录制服务
- `liveStreaming: { enabled: false }` - 禁用直播流
- `transcription: { enabled: false }` - 禁用转录服务
- `etherpad: { enabled: false }` - 禁用 Etherpad
- `p2p.stunServers: []` - 去除 STUN 服务器外链

## 🎨 图标替换规则

### Favicon

- **位置**: `/opt/mop/mop_ico_fav/` 下的 `mop-ico*.png` 文件
- **用途**: 浏览器标签页图标
- **选择**: 随机选择一个文件
- **替换位置**: 
  - `/usr/share/jitsi-meet/favicon.ico`
  - `/usr/share/jitsi-meet/images/favicon.ico`
  - `/config/favicon.ico`

### 首页左上角 Logo

- **位置**: `/opt/mop/mop_ico_fav/jit_logo/` 下的 `jit_log*.png` 文件
- **用途**: 首页左上角显示的品牌 logo
- **选择**: 随机选择一个文件
- **替换位置**:
  - `/usr/share/jitsi-meet/images/watermark.svg`
  - `/usr/share/jitsi-meet/images/watermark.png`
  - `/usr/share/jitsi-meet/images/logo.svg`
  - `/usr/share/jitsi-meet/images/logo.png`

### 其他图标

- **小图标** (16x16, 32x32): 使用 `mop-ico*.png`（随机选择）
- **大图标** (192x192, 512x512): 使用 `mop_ico*.png`（随机选择）

## 🔄 更新配置

### 修改配置文件模板

编辑模板文件后，重启容器即可应用：

```bash
# 编辑配置模板
vim docker/jitsi/custom/interface_config.js
vim docker/jitsi/custom/config.js

# 重启容器应用更改
docker restart jitsi_web
```

### 添加新图标

1. 将 favicon 文件放入 `/opt/mop/mop_ico_fav/`
2. 将 logo 文件放入 `/opt/mop/mop_ico_fav/jit_logo/`
3. 重启容器或重新运行自定义脚本

## ✅ 验证配置

### 检查图标是否替换

```bash
# 检查容器内的图标文件
docker exec jitsi_web ls -la /usr/share/jitsi-meet/images/ | grep -E "(favicon|watermark|logo)"
```

### 检查配置文件

```bash
# 检查 interface_config.js
docker exec jitsi_web cat /config/interface_config.js | grep -E "(WATERMARK|LINK|PROMO)"

# 检查 config.js
docker exec jitsi_web cat /config/config.js | grep -E "(disable|enabled|jitsi)"
```

### 浏览器检查

1. 访问 Jitsi 页面
2. 检查浏览器标签页图标（favicon）
3. 检查首页左上角 logo
4. 检查是否有外链（开发者工具 Network 标签）
5. 检查是否有 "Powered by Jitsi" 等品牌标识

## 🐛 故障排查

### 问题 1: 图标未替换

**原因**: 容器启动后配置文件还未生成

**解决**:
```bash
# 手动执行自定义脚本
./scripts/customize_jitsi.sh

# 或重启容器
docker restart jitsi_web
```

### 问题 2: 外链仍然存在

**原因**: 配置文件未正确应用

**解决**:
```bash
# 检查配置文件是否正确复制
docker exec jitsi_web cat /config/interface_config.js | grep JITSI_WATERMARK_LINK

# 应该显示: JITSI_WATERMARK_LINK: '',
# 如果显示: JITSI_WATERMARK_LINK: 'https://jitsi.org'
# 说明配置未应用，需要重新运行脚本
```

### 问题 3: 随机选择不工作

**原因**: 图标文件不存在或权限问题

**解决**:
```bash
# 检查图标文件
ls -la /opt/mop/mop_ico_fav/
ls -la /opt/mop/mop_ico_fav/jit_logo/

# 确保文件可读
chmod 644 /opt/mop/mop_ico_fav/**/*.png
```

## 📝 注意事项

1. **随机选择**: 每次启动容器都会随机选择图标，如需固定图标，可以修改脚本
2. **配置文件**: 配置文件在容器启动时生成，自定义脚本会在生成后修改
3. **容器重启**: 某些更改需要重启容器才能生效
4. **备份**: 原配置文件会自动备份为 `.bak` 文件

## 🔐 安全说明

- ✅ 所有外链已移除
- ✅ 第三方请求已禁用
- ✅ 移动应用推广已禁用
- ✅ 录制、直播等可能包含外链的功能已禁用
- ✅ STUN 服务器外链已移除

---

**最后更新**: 2026-01-11
**状态**: ✅ 已配置，一键部署自动生效
