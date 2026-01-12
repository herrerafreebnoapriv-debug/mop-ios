# 测试token传递
# 功能：测试登录后获取的token是否能正常使用

import requests

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

print("=" * 60)
print("Token 传递测试")
print("=" * 60)

# 步骤1: 登录获取token
print("\n[步骤1] 登录获取token...")
response = requests.post(
    f"{API_PREFIX}/auth/login",
    data={"username": "zhanan089", "password": "zn666@"},
    timeout=5
)

if response.status_code != 200:
    print(f"登录失败: {response.status_code}")
    print(f"错误: {response.text}")
    exit(1)

token = response.json().get("access_token")
print(f"Token获取成功，长度: {len(token)}")
print(f"Token前50字符: {token[:50]}...")

# 步骤2: 使用token访问用户列表
print("\n[步骤2] 使用token访问用户列表...")
headers = {"Authorization": f"Bearer {token}"}
response2 = requests.get(
    f"{API_PREFIX}/users/?skip=0&limit=10",
    headers=headers,
    timeout=5
)

print(f"状态码: {response2.status_code}")
if response2.status_code == 200:
    data = response2.json()
    print(f"成功！找到 {data.get('total', 0)} 个用户")
else:
    print(f"失败！错误信息: {response2.text[:200]}")

print("\n" + "=" * 60)
