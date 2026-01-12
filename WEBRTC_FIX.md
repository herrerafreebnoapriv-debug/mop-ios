# WebRTC 不支持问题解决方案

## 🔍 问题描述

访问 Jitsi 房间时，Chrome/Edge 浏览器提示：
> 您的浏览器似乎不支持 WebRTC。请启用 WebRTC 或尝试使用其他浏览器。

## 🎯 问题原因

现代浏览器（Chrome、Edge、Firefox）出于安全考虑，**在 HTTP 环境下会限制或禁用 WebRTC**。WebRTC 需要 HTTPS 才能正常工作。

## ✅ 解决方案

### 方案 1: 配置 HTTPS（推荐，生产环境）

#### 步骤 1: 更新 Jitsi 配置

编辑 `jitsi.env`：

```bash
# 启用 HTTPS
JITSI_DISABLE_HTTPS=0

# 如果使用 Let's Encrypt（需要域名）
JITSI_ENABLE_LETSENCRYPT=1
JITSI_LETSENCRYPT_DOMAIN=your-domain.com
JITSI_LETSENCRYPT_EMAIL=your-email@example.com

# 更新公共 URL
JITSI_PUBLIC_URL=https://your-domain.com
```

#### 步骤 2: 重启 Jitsi 服务

```bash
docker stop jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody
docker rm jitsi_web jitsi_jicofo jitsi_jvb jitsi_prosody
./scripts/start_jitsi.sh
```

#### 步骤 3: 更新后端配置

编辑后端 `.env`：

```bash
JITSI_SERVER_URL=https://your-domain.com
```

---

### 方案 2: 使用浏览器标志允许 HTTP WebRTC（仅开发测试）

⚠️ **警告**: 此方法仅用于开发测试，不适用于生产环境。

#### Chrome/Edge 浏览器

1. **关闭所有浏览器窗口**

2. **使用命令行启动浏览器（Windows）**：

```cmd
# Chrome
"C:\Program Files\Google\Chrome\Application\chrome.exe" --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir="C:\temp\chrome_dev"

# Edge
"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir="C:\temp\edge_dev"
```

3. **使用命令行启动浏览器（Linux）**：

```bash
# Chrome
google-chrome --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir=/tmp/chrome_dev

# Chromium
chromium --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir=/tmp/chrome_dev
```

4. **使用命令行启动浏览器（macOS）**：

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 --user-data-dir=/tmp/chrome_dev
```

#### Firefox 浏览器

1. 在地址栏输入 `about:config`
2. 搜索 `media.getusermedia.insecure.enabled`
3. 设置为 `true`
4. 搜索 `media.peerconnection.insecure.enabled`
5. 设置为 `true`
6. 重启浏览器

---

### 方案 3: 使用自签名证书（开发环境）

如果需要快速测试 HTTPS，可以使用自签名证书：

#### 步骤 1: 生成自签名证书

```bash
# 创建证书目录
mkdir -p /opt/jitsi-meet-cfg/web/keys

# 生成自签名证书
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/jitsi-meet-cfg/web/keys/key.pem \
  -out /opt/jitsi-meet-cfg/web/keys/cert.pem \
  -subj "/CN=89.223.95.18"

# 设置权限
chown -R 1000:1000 /opt/jitsi-meet-cfg/web/keys
```

#### 步骤 2: 配置 Nginx 使用证书

编辑 `/opt/jitsi-meet-cfg/web/nginx/nginx.conf`（如果存在），或通过环境变量配置。

#### 步骤 3: 更新配置

```bash
# jitsi.env
JITSI_DISABLE_HTTPS=0
JITSI_PUBLIC_URL=https://89.223.95.18:8443
```

#### 步骤 4: 浏览器信任自签名证书

访问 `https://89.223.95.18:8443`，浏览器会提示证书不安全，点击"高级" -> "继续访问"。

---

## 🔧 快速测试脚本

创建一个测试脚本 `test_webrtc.sh`：

```bash
#!/bin/bash
# 使用 Chrome 测试 WebRTC（允许 HTTP）

CHROME_PATH="/usr/bin/google-chrome"
if [ ! -f "$CHROME_PATH" ]; then
    CHROME_PATH="/usr/bin/chromium-browser"
fi

if [ ! -f "$CHROME_PATH" ]; then
    echo "未找到 Chrome/Chromium，请手动使用浏览器标志启动"
    exit 1
fi

$CHROME_PATH \
  --unsafely-treat-insecure-origin-as-secure=http://89.223.95.18:8080 \
  --user-data-dir=/tmp/chrome_jitsi_test \
  "http://89.223.95.18:8000/room/test-room?jwt=YOUR_TOKEN&server=http://89.223.95.18:8080"
```

---

## 📋 推荐方案

**生产环境**: 使用方案 1（配置 HTTPS + Let's Encrypt）

**开发测试**: 使用方案 2（浏览器标志）或方案 3（自签名证书）

---

## 🔍 验证 WebRTC 是否工作

1. 打开浏览器开发者工具（F12）
2. 访问房间页面
3. 在控制台输入：

```javascript
// 检查 WebRTC 支持
console.log('RTCPeerConnection:', typeof RTCPeerConnection !== 'undefined');
console.log('getUserMedia:', typeof navigator.mediaDevices?.getUserMedia !== 'undefined');
```

如果返回 `true`，说明 WebRTC 已启用。

---

## 📚 参考文档

- [Jitsi Meet HTTPS 配置](https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker#running-behind-nat-or-in-a-subnet)
- [Chrome WebRTC 标志](https://peter.sh/experiments/chromium-command-line-switches/)
- [Firefox WebRTC 配置](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
