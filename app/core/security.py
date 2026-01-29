"""
安全相关工具函数
包含 JWT 生成、验证、密码哈希等功能
"""

from datetime import datetime, timedelta, timezone
from typing import Optional
import hashlib
import json
import base64
import os
from jose import JWTError, jwt
from passlib.context import CryptContext
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from app.core.config import settings

# 密码加密上下文
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    验证密码
    
    支持两种格式：
    1. passlib 生成的哈希（标准格式）
    2. bcrypt 直接生成的哈希（兼容格式）
    
    Args:
        plain_password: 明文密码
        hashed_password: 哈希密码
    
    Returns:
        验证是否通过
    
    Note:
        bcrypt 算法限制密码最大长度为72字节（UTF-8编码）
        验证时需要与哈希时使用相同的截断逻辑
    """
    # bcrypt 限制：密码最大72字节（UTF-8编码）
    # 将密码编码为UTF-8字节，截断到72字节
    password_bytes = plain_password.encode('utf-8')
    if len(password_bytes) > 72:
        password_bytes = password_bytes[:72]
    
    try:
        # 优先使用 bcrypt 直接验证（与哈希函数保持一致）
        import bcrypt
        return bcrypt.checkpw(
            password_bytes,
            hashed_password.encode('utf-8')
        )
    except (ImportError, ValueError, Exception):
        # 如果 bcrypt 不可用或验证失败，尝试使用 passlib 验证（兼容旧数据）
        try:
            plain_password_str = password_bytes.decode('utf-8', errors='ignore')
            return pwd_context.verify(plain_password_str, hashed_password)
        except Exception:
            return False


def get_password_hash(password: str) -> str:
    """
    生成密码哈希
    
    Args:
        password: 明文密码
    
    Returns:
        哈希后的密码
    
    Note:
        bcrypt 算法限制密码最大长度为72字节（UTF-8编码）
        如果密码超过72字节，会自动截断
    """
    # bcrypt 限制：密码最大72字节（UTF-8编码）
    # 将密码编码为UTF-8字节，截断到72字节
    password_bytes = password.encode('utf-8')
    if len(password_bytes) > 72:
        password_bytes = password_bytes[:72]
    
    # 直接使用字节进行哈希，避免 passlib 的额外处理
    # passlib 的 hash 方法接受字符串，但内部会编码，可能导致问题
    # 所以我们直接使用 bcrypt 库
    try:
        import bcrypt
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password_bytes, salt)
        return hashed.decode('utf-8')
    except ImportError:
        # 如果 bcrypt 不可用，回退到 passlib（但需要先解码）
        password_str = password_bytes.decode('utf-8', errors='ignore')
        return pwd_context.hash(password_str)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    创建访问令牌（JWT）
    
    Args:
        data: 要编码的数据（通常是用户ID等）
        expires_delta: 过期时间增量，如果为 None 则使用默认值
    
    Returns:
        JWT 令牌字符串
    """
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc)})
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )
    
    return encoded_jwt


def create_refresh_token(data: dict) -> str:
    """
    创建刷新令牌（JWT）
    
    Args:
        data: 要编码的数据
    
    Returns:
        JWT 刷新令牌字符串
    """
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc), "type": "refresh"})
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM
    )
    
    return encoded_jwt


def decode_token(token: str) -> Optional[dict]:
    """
    解码 JWT 令牌
    
    Args:
        token: JWT 令牌字符串
    
    Returns:
        解码后的数据，如果无效则返回 None
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except JWTError:
        return None


def verify_token(token: str) -> bool:
    """
    验证 JWT 令牌是否有效
    
    Args:
        token: JWT 令牌字符串
    
    Returns:
        是否有效
    """
    payload = decode_token(token)
    return payload is not None


# ==================== RSA 加密工具函数 ====================

def load_rsa_private_key() -> rsa.RSAPrivateKey:
    """
    加载 RSA 私钥
    
    Returns:
        RSA 私钥对象
    
    Raises:
        ValueError: 如果私钥格式无效
    """
    try:
        private_key = serialization.load_pem_private_key(
            settings.RSA_PRIVATE_KEY.encode('utf-8'),
            password=None,
            backend=default_backend()
        )
        return private_key
    except Exception as e:
        raise ValueError(f"无效的 RSA 私钥格式: {str(e)}")


def load_rsa_public_key() -> rsa.RSAPublicKey:
    """
    加载 RSA 公钥
    
    Returns:
        RSA 公钥对象
    
    Raises:
        ValueError: 如果公钥格式无效
    """
    try:
        public_key = serialization.load_pem_public_key(
            settings.RSA_PUBLIC_KEY.encode('utf-8'),
            backend=default_backend()
        )
        return public_key
    except Exception as e:
        raise ValueError(f"无效的 RSA 公钥格式: {str(e)}")


def _xor_bytes(data: bytes, key: bytes) -> bytes:
    """XOR 逐字节，key 循环使用。"""
    out = bytearray(len(data))
    for i, b in enumerate(data):
        out[i] = b ^ key[i % len(key)]
    return bytes(out)


def _derived_key(master_key: str, salt: bytes) -> bytes:
    """从主密钥 + 盐派生 32 字节密钥：SHA256(master_key || salt)。"""
    return hashlib.sha256(master_key.encode('utf-8') + salt).digest()


def simple_encrypt(data: dict, key: Optional[str] = None, use_salt: bool = True) -> str:
    """
    简单加密（Base64 + XOR）。支持带盐模式，同明文不同密文。
    
    - 无盐（use_salt=False）：兼容旧版，xor(json, fix_key)。
    - 带盐（use_salt=True）：格式 base64(0x01 || salt_8 || xor(json, derived_key))，
      derived_key = SHA256(master_key || salt)。
    
    Args:
        data: 要加密的数据字典
        key: 主密钥，默认从 QR_ENCRYPTION_KEY 或 MOP_QR_KEY_2026 取
        use_salt: 是否带盐（默认 True）
    
    Returns:
        Base64 URL-safe 编码的密文
    """
    try:
        optimized_data = {}
        key_mapping = {"api_url": "u", "room_id": "r", "timestamp": "t", "expires_at": "e"}
        for k, v in data.items():
            optimized_data[key_mapping.get(k, k)] = v
        json_str = json.dumps(optimized_data, ensure_ascii=False, separators=(',', ':'))
        data_bytes = json_str.encode('utf-8')
        master = key or getattr(settings, 'QR_ENCRYPTION_KEY', None) or "MOP_QR_KEY_2026"

        if use_salt:
            salt = os.urandom(8)
            dk = _derived_key(master, salt)
            cipher = _xor_bytes(data_bytes, dk)
            raw = b'\x01' + salt + cipher
        else:
            key_bytes = master.encode('utf-8')
            raw = _xor_bytes(data_bytes, key_bytes)
        return base64.urlsafe_b64encode(raw).decode('utf-8').rstrip('=')
    except Exception as e:
        raise ValueError(f"简单加密失败: {str(e)}")


def simple_decrypt(encrypted_data: str, key: Optional[str] = None) -> dict:
    """
    简单解密（Base64 + XOR）。自动识别无盐（legacy）与带盐（v1）格式。
    
    - 若 raw[0]==0x01 且 len>=9：v1 带盐，salt=raw[1:9]，cipher=raw[9:]，用 derived_key 解密。
    - 否则：legacy 无盐，用固定密钥 XOR 解密。
    """
    try:
        missing = len(encrypted_data) % 4
        if missing:
            encrypted_data += '=' * (4 - missing)
        raw = base64.urlsafe_b64decode(encrypted_data.encode('utf-8'))
        master = key or getattr(settings, 'QR_ENCRYPTION_KEY', None) or "MOP_QR_KEY_2026"

        if len(raw) >= 9 and raw[0] == 0x01:
            salt = raw[1:9]
            cipher = raw[9:]
            dk = _derived_key(master, salt)
            json_bytes = _xor_bytes(cipher, dk)
        else:
            key_bytes = master.encode('utf-8')
            json_bytes = _xor_bytes(raw, key_bytes)
        data = json.loads(json_bytes.decode('utf-8'))
        key_mapping = {"u": "api_url", "r": "room_id", "t": "timestamp", "e": "expires_at"}
        return {key_mapping.get(k, k): v for k, v in data.items()}
    except Exception as e:
        raise ValueError(f"简单解密失败: {str(e)}")


def rsa_encrypt(data: dict, use_short_keys: bool = True, compress: bool = False) -> str:
    """
    使用 RSA 私钥对数据进行签名加密
    
    根据 Spec.txt：二维码加盐加密，使用 RSA 私钥对配置（API URL、房间ID、时间戳）进行签名
    
    Args:
        data: 要加密的数据字典（包含 API URL、房间ID、时间戳等）
        use_short_keys: 是否使用短键名优化（默认True，减少数据量）
        compress: 是否使用压缩（默认False，压缩后可降到版本10）
    
    Returns:
        Base64 编码的加密字符串
    """
    try:
        private_key = load_rsa_private_key()
        
        # 优化数据结构：使用短键名减少数据量
        if use_short_keys:
            optimized_data = {}
            # 键名映射：长键名 -> 短键名
            key_mapping = {
                "api_url": "u",
                "room_id": "r",
                "timestamp": "t",
                "expires_at": "e"
            }
            for key, value in data.items():
                short_key = key_mapping.get(key, key)
                optimized_data[short_key] = value
            data = optimized_data
        
        # 将数据转换为 JSON 字符串（紧凑格式，无空格）
        json_data = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
        message = json_data.encode('utf-8')
        
        # 使用私钥签名（RSA 签名实际上就是加密操作）
        signature = private_key.sign(
            message,
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        # 将签名和原始数据一起编码
        # 格式：base64(json_data + "|" + signature)
        combined = json_data + "|" + base64.b64encode(signature).decode('utf-8')
        
        # 如果启用压缩，使用gzip压缩（与移动端 gzip.decode 匹配）
        if compress:
            import gzip
            compressed = gzip.compress(combined.encode('utf-8'), compresslevel=9)
            # Base64 编码压缩后的数据
            return base64.b64encode(compressed).decode('utf-8')
        else:
            # Base64 编码返回
            return base64.b64encode(combined.encode('utf-8')).decode('utf-8')
    except Exception as e:
        raise ValueError(f"RSA 加密失败: {str(e)}")


def rsa_decrypt(encrypted_data: str, expand_short_keys: bool = True, decompress: bool = False) -> dict:
    """
    使用 RSA 公钥验证并解密数据
    
    Args:
        encrypted_data: Base64 编码的加密字符串
        expand_short_keys: 是否将短键名扩展为完整键名（默认True）
        decompress: 是否解压缩（默认False，如果加密时使用了压缩）
    
    Returns:
        解密后的数据字典
    
    Raises:
        ValueError: 如果解密失败或签名验证失败
    """
    try:
        public_key = load_rsa_public_key()
        
        # Base64 解码
        decoded_bytes = base64.b64decode(encrypted_data.encode('utf-8'))
        
        # 如果启用解压缩，先解压（使用 gzip，与加密时的 gzip.compress 匹配）
        if decompress:
            import gzip
            decoded_bytes = gzip.decompress(decoded_bytes)
        
        decoded = decoded_bytes.decode('utf-8')
        
        # 分离 JSON 数据和签名
        parts = decoded.split("|", 1)
        if len(parts) != 2:
            raise ValueError("无效的加密数据格式")
        
        json_data, signature_b64 = parts
        signature = base64.b64decode(signature_b64.encode('utf-8'))
        
        # 验证签名
        public_key.verify(
            signature,
            json_data.encode('utf-8'),
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=padding.PSS.MAX_LENGTH
            ),
            hashes.SHA256()
        )
        
        # 解析 JSON 数据
        data = json.loads(json_data)
        
        # 扩展短键名为完整键名（如果需要）
        if expand_short_keys:
            key_mapping = {
                "u": "api_url",
                "r": "room_id",
                "t": "timestamp",
                "e": "expires_at"
            }
            expanded_data = {}
            for key, value in data.items():
                full_key = key_mapping.get(key, key)
                expanded_data[full_key] = value
            data = expanded_data
        
        return data
    except Exception as e:
        raise ValueError(f"RSA 解密失败: {str(e)}")


# ==================== Jitsi JWT Token 生成 ====================

def create_jitsi_token(
    room_id: str,
    user_id: int,
    user_name: str,
    is_moderator: bool = False,
    expires_in_minutes: int = 60
) -> str:
    """
    创建 Jitsi Meet JWT Token
    
    根据 Jitsi 规范生成 JWT token，用于房间授权
    强制使用自建 Jitsi 服务器，严禁使用官方服务器
    
    Args:
        room_id: 房间ID
        user_id: 用户ID
        user_name: 用户名称
        is_moderator: 是否为主持人
        expires_in_minutes: 过期时间（分钟）
    
    Returns:
        JWT token 字符串
    
    Raises:
        ValueError: 如果配置了官方服务器地址
    """
    from app.core.config import settings
    
    # 安全检查：禁止使用官方服务器
    server_url = settings.JITSI_SERVER_URL.lower()
    if 'meet.jit.si' in server_url or 'jit.si' in server_url:
        raise ValueError("禁止使用官方 Jitsi 服务器，必须使用自建服务器")
    
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=expires_in_minutes)
    
    # 提取域名（用于 JWT audience 和 subject）
    # 从 URL 中提取域名，例如：https://jitsi.example.com -> jitsi.example.com
    domain = server_url.replace('https://', '').replace('http://', '').split('/')[0]
    
    # JWT audience 必须与 Prosody 的 JWT_ACCEPTED_AUDIENCES 匹配
    # Prosody 配置中使用的是完整 URL（包含协议），所以这里也使用完整 URL
    audience = server_url.rstrip('/')  # 使用完整 URL 作为 audience
    
    # 为了避免时间同步问题，将 nbf 设置为较早时间。
    # Jitsi/Prosody 若时钟落后于后端，会报「nbf 值在未来」；故使用 10 分钟负偏移以容忍较大时钟差。
    nbf_time = now - timedelta(seconds=600)
    
    # Jitsi JWT payload 结构
    payload = {
        "iss": settings.JITSI_APP_ID,  # Issuer (App ID)
        "aud": audience,  # Audience (必须与 Prosody 的 JWT_ACCEPTED_AUDIENCES 匹配)
        "sub": domain,  # Subject (Jitsi domain)
        "room": room_id,  # 房间名称
        "exp": int(expire.timestamp()),  # 过期时间
        "iat": int(now.timestamp()),  # 签发时间
        "nbf": int(nbf_time.timestamp()),  # Not before（提前 10 分钟以容忍 Jitsi 时钟落后）
        "context": {
            "user": {
                "id": user_id,
                "name": user_name,
                "moderator": is_moderator
            }
        }
    }
    
    # 使用 Jitsi App Secret 签名
    token = jwt.encode(
        payload,
        settings.JITSI_APP_SECRET,
        algorithm="HS256"
    )
    
    return token
