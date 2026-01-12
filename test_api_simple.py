"""
简化的 API 多语言测试脚本
"""

import requests
import json
import sys

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

def test_endpoint(name, url, headers=None, method="GET", data=None):
    """测试单个端点"""
    print(f"\n[{name}]")
    print(f"  URL: {url}")
    if headers:
        print(f"  Headers: {headers}")
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, timeout=5)
        elif method == "POST":
            response = requests.post(url, headers=headers, json=data, timeout=5)
        else:
            response = requests.request(method, url, headers=headers, json=data, timeout=5)
        
        print(f"  Status: {response.status_code}")
        if response.status_code == 200 or response.status_code == 201:
            result = response.json()
            print(f"  Response: {json.dumps(result, ensure_ascii=False, indent=2)}")
        else:
            print(f"  Error: {response.text[:200]}")
        return response
    except requests.exceptions.ConnectionError:
        print("  ERROR: Cannot connect to server. Is it running?")
        print("  Start server with: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
        return None
    except Exception as e:
        print(f"  ERROR: {str(e)}")
        return None

print("=" * 70)
print("API i18n Response Test (Simplified)")
print("=" * 70)

# 测试1: 健康检查 - 中文
test_endpoint(
    "Test 1: Health Check (zh_CN)",
    f"{BASE_URL}/health",
    headers={"Accept-Language": "zh-CN,zh;q=0.9"}
)

# 测试2: 健康检查 - 英文
test_endpoint(
    "Test 2: Health Check (en_US)",
    f"{BASE_URL}/health",
    headers={"Accept-Language": "en-US,en;q=0.9"}
)

# 测试3: 根路径 - 中文
test_endpoint(
    "Test 3: Root Endpoint (zh_CN)",
    f"{BASE_URL}/",
    headers={"Accept-Language": "zh-CN,zh;q=0.9"}
)

# 测试4: 根路径 - 英文
test_endpoint(
    "Test 4: Root Endpoint (en_US)",
    f"{BASE_URL}/",
    headers={"Accept-Language": "en-US,en;q=0.9"}
)

# 测试5: 获取支持的语言列表
test_endpoint(
    "Test 5: Get Supported Languages",
    f"{API_PREFIX}/i18n/languages"
)

# 测试6: 获取当前语言 - 中文请求
test_endpoint(
    "Test 6: Get Current Language (zh_CN request)",
    f"{API_PREFIX}/i18n/current",
    headers={"Accept-Language": "zh-CN,zh;q=0.9"}
)

# 测试7: 获取当前语言 - 英文请求
test_endpoint(
    "Test 7: Get Current Language (en_US request)",
    f"{API_PREFIX}/i18n/current",
    headers={"Accept-Language": "en-US,en;q=0.9"}
)

# 测试8: 登录失败 - 中文错误消息
test_endpoint(
    "Test 8: Login Failure (zh_CN error)",
    f"{API_PREFIX}/auth/login",
    method="POST",
    headers={"Accept-Language": "zh-CN,zh;q=0.9", "Content-Type": "application/x-www-form-urlencoded"},
    data={"username": "nonexistent", "password": "wrong"}
)

# 测试9: 登录失败 - 英文错误消息
test_endpoint(
    "Test 9: Login Failure (en_US error)",
    f"{API_PREFIX}/auth/login",
    method="POST",
    headers={"Accept-Language": "en-US,en;q=0.9", "Content-Type": "application/x-www-form-urlencoded"},
    data={"username": "nonexistent", "password": "wrong"}
)

print("\n" + "=" * 70)
print("Test Complete")
print("=" * 70)
