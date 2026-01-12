"""
详细登录测试脚本
功能：测试管理员账户登录，查看具体错误信息
"""

import requests
import json

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

print("=" * 70)
print("详细登录测试")
print("=" * 70)

# 测试管理员登录
print("\n[测试] 管理员账户登录")
print("用户名: zhanan089")
print("密码: zn666@")

try:
    response = requests.post(
        f"{API_PREFIX}/auth/login",
        data={
            "username": "zhanan089",
            "password": "zn666@"
        },
        timeout=5
    )
    
    print(f"\n状态码: {response.status_code}")
    print(f"响应头: {dict(response.headers)}")
    
    if response.status_code == 200:
        data = response.json()
        print("\n[成功] 登录成功！")
        print(f"Access Token: {data.get('access_token', 'N/A')[:50]}...")
        print(f"Token Type: {data.get('token_type', 'N/A')}")
    else:
        print(f"\n[失败] 登录失败")
        try:
            error_data = response.json()
            print(f"错误信息: {json.dumps(error_data, ensure_ascii=False, indent=2)}")
        except:
            print(f"响应内容: {response.text[:200]}")
            
except requests.exceptions.ConnectionError:
    print("\n[错误] 无法连接到服务器")
except Exception as e:
    print(f"\n[错误] {str(e)}")

print("\n" + "=" * 70)
