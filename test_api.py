"""
API 测试脚本
用于测试认证相关的 API 端点
"""

import requests
import json

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

print("=" * 60)
print("API 测试脚本")
print("=" * 60)

# 测试1: 健康检查
print("\n[测试1] 健康检查端点")
try:
    response = requests.get(f"{BASE_URL}/health")
    print(f"  状态码: {response.status_code}")
    print(f"  响应: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
    assert response.status_code == 200, "健康检查失败"
    print("  [PASS] 健康检查通过")
except Exception as e:
    print(f"  [FAIL] {e}")

# 测试2: 用户注册
print("\n[测试2] 用户注册")
try:
    register_data = {
        "phone": "13800138000",
        "username": "testuser",
        "password": "test123456",
        "nickname": "测试用户",
        "invitation_code": None
    }
    response = requests.post(
        f"{API_PREFIX}/auth/register",
        json=register_data
    )
    print(f"  状态码: {response.status_code}")
    if response.status_code == 201:
        print(f"  响应: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
        print("  [PASS] 用户注册成功")
        user_data = response.json()
    else:
        print(f"  响应: {response.text}")
        print("  [WARN] 用户可能已存在，继续测试登录")
        user_data = None
except Exception as e:
    print(f"  [FAIL] {e}")
    user_data = None

# 测试3: 用户登录
print("\n[测试3] 用户登录")
try:
    login_data = {
        "username": "13800138000",  # 使用手机号登录
        "password": "test123456"
    }
    response = requests.post(
        f"{API_PREFIX}/auth/login",
        data=login_data  # OAuth2PasswordRequestForm 使用 form data
    )
    print(f"  状态码: {response.status_code}")
    if response.status_code == 200:
        tokens = response.json()
        print(f"  访问令牌: {tokens['access_token'][:50]}...")
        print(f"  刷新令牌: {tokens['refresh_token'][:50]}...")
        print("  [PASS] 用户登录成功")
        access_token = tokens['access_token']
        refresh_token = tokens['refresh_token']
    else:
        print(f"  响应: {response.text}")
        print("  [FAIL] 登录失败")
        access_token = None
        refresh_token = None
except Exception as e:
    print(f"  [FAIL] {e}")
    access_token = None
    refresh_token = None

# 测试4: 获取当前用户信息（需要认证）
if access_token:
    print("\n[测试4] 获取当前用户信息（需要 JWT 认证）")
    try:
        headers = {"Authorization": f"Bearer {access_token}"}
        response = requests.get(
            f"{API_PREFIX}/auth/me",
            headers=headers
        )
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            print(f"  响应: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
            print("  [PASS] 获取用户信息成功")
        else:
            print(f"  响应: {response.text}")
            print("  [FAIL] 获取用户信息失败")
    except Exception as e:
        print(f"  [FAIL] {e}")

# 测试5: 刷新令牌
if refresh_token:
    print("\n[测试5] 刷新访问令牌")
    try:
        refresh_data = {"refresh_token": refresh_token}
        response = requests.post(
            f"{API_PREFIX}/auth/refresh",
            json=refresh_data
        )
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            tokens = response.json()
            print(f"  新访问令牌: {tokens['access_token'][:50]}...")
            print("  [PASS] 刷新令牌成功")
        else:
            print(f"  响应: {response.text}")
            print("  [FAIL] 刷新令牌失败")
    except Exception as e:
        print(f"  [FAIL] {e}")

# 测试6: 用户登出
if access_token:
    print("\n[测试6] 用户登出")
    try:
        headers = {"Authorization": f"Bearer {access_token}"}
        response = requests.post(
            f"{API_PREFIX}/auth/logout",
            headers=headers
        )
        print(f"  状态码: {response.status_code}")
        if response.status_code == 200:
            print(f"  响应: {json.dumps(response.json(), indent=2, ensure_ascii=False)}")
            print("  [PASS] 用户登出成功")
        else:
            print(f"  响应: {response.text}")
            print("  [FAIL] 用户登出失败")
    except Exception as e:
        print(f"  [FAIL] {e}")

print("\n" + "=" * 60)
print("API 测试完成")
print("=" * 60)
print("\n提示:")
print("  1. 如果测试失败，请确保应用正在运行")
print("  2. 访问 http://127.0.0.1:8000/docs 查看完整的 API 文档")
print("  3. 如果用户注册失败（用户已存在），可以修改手机号重新测试")
