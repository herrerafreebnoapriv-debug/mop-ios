# 调试JWT token
# 功能：检查JWT token的解码和验证过程

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import requests
from app.core.security import decode_token

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

print("=" * 60)
print("JWT Token 调试")
print("=" * 60)

# 获取token
print("\n[步骤1] 登录获取token...")
response = requests.post(
    f"{API_PREFIX}/auth/login",
    data={"username": "zhanan089", "password": "zn666@"},
    timeout=5
)

if response.status_code != 200:
    print(f"登录失败: {response.status_code}")
    exit(1)

token = response.json().get("access_token")
print(f"Token: {token[:80]}...")

# 解码token
print("\n[步骤2] 解码token...")
try:
    from jose import jwt
    from app.core.config import settings
    payload = jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM]
    )
    print(f"Payload: {payload}")
    user_id = payload.get("sub")
    print(f"用户ID: {user_id}")
except Exception as e:
    print(f"Token解码失败: {e}")
    print(f"JWT Secret Key长度: {len(settings.JWT_SECRET_KEY)}")
    print(f"JWT Algorithm: {settings.JWT_ALGORITHM}")
    exit(1)

# 测试访问API
print("\n[步骤3] 测试访问API...")
headers = {"Authorization": f"Bearer {token}"}
response2 = requests.get(
    f"{API_PREFIX}/users/?skip=0&limit=10",
    headers=headers,
    timeout=5
)

print(f"状态码: {response2.status_code}")
if response2.status_code != 200:
    print(f"错误: {response2.text[:300]}")

print("\n" + "=" * 60)
