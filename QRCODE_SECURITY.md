# 二维码安全设计说明

## 🔐 安全原则

**核心要求**：二维码不包含明文的服务器IP、域名信息，保证安全和隐私性。

## 📱 客户端扫码流程（App）

### 1. 二维码生成（后端）
- 包含数据：`room_id` + `api_url`（服务器地址）
- 加密方式：RSA 私钥签名加密
- 结果：加密后的 Base64 字符串

### 2. 二维码扫描（App）
- App 扫描二维码，获取加密数据
- App 使用 **RSA 公钥** 解密二维码
- 解密后获取：`room_id` + `api_url`（服务器地址）

### 3. 加入房间（App）
- 使用解密后的 `api_url` 调用后端 API
- 使用 `room_id` 加入房间
- 获取 JWT Token 后连接 Jitsi 服务器

## 🔒 安全机制

### 1. 加密保护
- **RSA-2048 签名**：使用私钥签名，公钥验证
- **服务器地址加密**：包含在二维码中，但经过 RSA 加密
- **只有拥有公钥的客户端**才能解密获取服务器地址

### 2. 隐私保护
- **验证接口不返回服务器地址**：避免在 API 响应中暴露
- **客户端本地解密**：服务器地址只在客户端本地解密，不传输

### 3. 扫描次数限制
- 每个二维码最多扫描 3 次
- 达到上限后自动失效
- 防止二维码被无限分享

## 📊 数据结构

### 二维码加密前
```json
{
  "r": "r-a1b2c3d4",           // room_id (短键名)
  "u": "https://jitsi.example.com"  // api_url (短键名，加密包含)
}
```

### 二维码加密后
```
Base64编码的字符串，格式：
base64(json_data + "|" + base64(signature))

实际内容示例：
eyJyIjoici1hMWIyYzNkNCIsInUiOiJodHRwczovL2ppdHNpLmV4YW1wbGUuY29tIn18UHdDWmMyR2llZW5oYTI1amFxOEVlOVdWRzNpNWpHdg...
```

### App 解密后
```json
{
  "room_id": "r-a1b2c3d4",
  "api_url": "https://jitsi.example.com"  // 客户端解密后获取
}
```

## 🛠️ App 端实现要求

### 1. RSA 公钥配置
- App 需要内置 RSA 公钥（从环境变量或配置文件读取）
- 公钥用于解密二维码数据

### 2. 解密工具函数
```dart
// Flutter 示例
Future<Map<String, dynamic>> decryptQRCode(String encryptedData) async {
  // 1. Base64 解码
  // 2. 分离 JSON 数据和签名
  // 3. 使用 RSA 公钥验证签名
  // 4. 解析 JSON 数据
  // 5. 扩展短键名为完整键名
  // 返回: {"room_id": "...", "api_url": "..."}
}
```

### 3. 扫码流程
```dart
// 1. 扫描二维码
String encryptedData = await scanQRCode();

// 2. 解密二维码
Map<String, dynamic> data = await decryptQRCode(encryptedData);
String roomId = data['room_id'];
String apiUrl = data['api_url'];  // 解密后获取服务器地址

// 3. 使用解密后的 api_url 调用后端 API
String jwtToken = await joinRoom(apiUrl, roomId);

// 4. 连接 Jitsi 服务器
await connectToJitsi(apiUrl, roomId, jwtToken);
```

## ⚠️ 注意事项

1. **RSA 公钥安全**：
   - 公钥可以内置在 App 中（公钥本身不敏感）
   - 但建议从服务器动态获取，增加灵活性

2. **服务器地址变更**：
   - 如果服务器地址变更，需要重新生成二维码
   - 旧二维码将无法使用新地址

3. **向后兼容**：
   - 如果二维码中没有 `api_url`，客户端需要从配置读取
   - 但新生成的二维码都会包含加密的 `api_url`

## 🔄 与网页版的区别

### 网页版（浏览器扫描）
- **不支持**：浏览器无法内置 RSA 公钥进行本地解密
- **替代方案**：通过后端 API 验证二维码，后端返回必要信息
- **限制**：服务器地址会在 API 响应中暴露（但需要验证通过）

### App 端（客户端扫描）
- **支持**：App 内置 RSA 公钥，可以本地解密
- **优势**：服务器地址只在客户端本地解密，不通过网络传输
- **安全**：完全符合"二维码不包含明文服务器地址"的要求

## 📝 总结

**对于客户端（App）扫码进入房间**：
- ✅ 二维码包含**加密的**服务器地址
- ✅ App 使用 RSA 公钥**本地解密**获取服务器地址
- ✅ 服务器地址**不会明文暴露**在二维码中
- ✅ 验证接口**不返回**服务器地址，避免 API 响应暴露

这样就完全保证了服务器地址的安全性和隐私性！
