# 二维码加密设计说明

## 一、API 仅通过扫码获取，客户端不内置 API

### 1. 设计决策

**客户端不内置 API 地址，API 唯一的获取方式为扫码识别二维码。**

- 授权二维码、房间二维码、聊天页面二维码等，凡需客户端请求后端的，均**必须包含 `api_url`**（或可推导出 API 的 `chat_url`）。
- 客户端不会使用任何硬编码或内置默认 API；若二维码未包含 API 信息，则报错提示用户扫描包含 API 的二维码。

### 2. 授权二维码（auth_qr）

**加密 payload**：`{"api_url": "<url>", "auth_token": "<jwt>"}`，**必须包含 `api_url`**。

**明文格式**：`{"type": "auth_qr", "token": "<jwt>", "api_url": "<url>"}`。

客户端扫码后：
1. 解密 / 解析得到 `api_url`、`auth_token`（或 `token`）
2. 调用 `POST {api_url}/auth/confirm-scan` 提交 `{"token": "<auth_token>"}`

若授权二维码中无 `api_url` 且无 `chat_url`，客户端直接报错：「API 地址僅能通過掃碼獲取，該二維碼未包含 API 地址」。

### 3. 其他二维码类型

**房间二维码、聊天页面二维码**：同样包含 `api_url` 或 `chat_url`，客户端从中获取 API，逻辑与授权二维码一致。

---

## 二、简单带盐加密（simple salted encryption）

### 1. 现状与问题

- 当前：固定密钥 `MOP_QR_KEY_2026` + XOR，无盐。
- 同一明文每次加密结果相同 → 易被模式分析、重放。

### 2. 带盐方案

**思路**：每个二维码生成时加随机盐，用 `master_key + salt` 派生密钥再 XOR，密文随盐变化。

**格式**：

- ** legacy（v0，无盐）**：`base64(xor(json, fix_key))`，与现网兼容。
- **带盐（v1）**：`base64(0x01 || salt_8 || xor(json, derived_key))`
  - `0x01`：版本字节，标识带盐。
  - `salt_8`：8 字节随机盐。
  - `derived_key = SHA256(master_key.encode() + salt)[:32]`，XOR 时按需循环使用。
  - `xor(json, derived_key)`：仅对 JSON 字节串做 XOR，版本与盐不参与 XOR。

**解密**：

1. Base64 解码。
2. 若 `raw[0] == 0x01` 且 `len(raw) >= 9`：视为 v1，`salt = raw[1:9]`，`ciphertext = raw[9:]`，用 `master_key + salt` 派生密钥后 XOR 解密，再解析 JSON。
3. 否则：按 legacy 用固定密钥 XOR 解密。

### 3. 密钥配置

- 通过 `QR_ENCRYPTION_KEY`（或 `.env` 等价项）配置主密钥；未配置时回退到 `MOP_QR_KEY_2026`。
- 盐仅用于派生，不可单独复用为密钥。

### 4. 使用范围

- **授权二维码（auth_qr）**：使用带盐加密，**必须包含 `api_url`**；客户端不内置 API，仅从扫码获取。
- **房间等二维码**：可同样支持带盐，与现有逻辑兼容；均包含 `api_url` 或 `chat_url`，供客户端获取 API。

---

## 三、短键名与客户端约定

| 短键 | 全键 | 说明 |
|------|------|------|
| `u` | `api_url` | 聊天 API base URL，**必须由二维码提供**（客户端不内置） |
| `r` | `room_id` | 房间 ID |
| `t` | `timestamp` | 时间戳 |
| `e` | `expires_at` | 过期时间（可选） |
| `auth_token` | （不压缩） | JWT，授权二维码必含 |

客户端 `simple_decrypt` 后扩展短键名，**仅使用二维码中的 `api_url`** 调用 `confirm-scan` 等接口。
