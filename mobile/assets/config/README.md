# 配置文件目录

## RSA 公钥文件

`rsa_public_key.pem` - RSA 公钥文件，用于解密二维码数据。

### 说明

- RSA 公钥是公开的，可以安全地内置到客户端
- 用于首次使用应用时解密加密的二维码
- 如果后端更新了密钥对，需要更新此文件

### 更新方法

```bash
# 从 API 获取最新公钥
curl -s https://api.chat5202ol.xyz/api/v1/qrcode/public-key | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['public_key'])" > \
  assets/config/rsa_public_key.pem
```
