"""
API 多语言响应测试脚本
测试不同语言下的 API 响应
"""

import requests
import json

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

print("=" * 70)
print("API i18n Response Test")
print("=" * 70)

# 测试1: 健康检查端点（多语言）
print("\n[Test 1] Health Check Endpoint (i18n)")
print("-" * 70)

test_languages = [
    ("zh_CN", "Accept-Language: zh-CN,zh;q=0.9"),
    ("en_US", "Accept-Language: en-US,en;q=0.9"),
    ("ja_JP", "Accept-Language: ja-JP,ja;q=0.9"),
]

for lang_code, accept_lang in test_languages:
    try:
        response = requests.get(
            f"{BASE_URL}/health",
            headers={"Accept-Language": accept_lang.split(": ")[1]}
        )
        if response.status_code == 200:
            data = response.json()
            print(f"  Language: {lang_code}")
            print(f"    App Name: {data.get('app_name', 'N/A')}")
            print(f"    Status: {data.get('status', 'N/A')}")
        else:
            print(f"  Language: {lang_code} - Status: {response.status_code}")
    except Exception as e:
        print(f"  Language: {lang_code} - Error: {str(e)[:50]}")

# 测试2: 根路径（多语言）
print("\n[Test 2] Root Endpoint (i18n)")
print("-" * 70)

for lang_code, accept_lang in test_languages:
    try:
        response = requests.get(
            f"{BASE_URL}/",
            headers={"Accept-Language": accept_lang.split(": ")[1]}
        )
        if response.status_code == 200:
            data = response.json()
            print(f"  Language: {lang_code}")
            print(f"    Message: {data.get('message', 'N/A')}")
        else:
            print(f"  Language: {lang_code} - Status: {response.status_code}")
    except Exception as e:
        print(f"  Language: {lang_code} - Error: {str(e)[:50]}")

# 测试3: 获取支持的语言列表
print("\n[Test 3] Get Supported Languages")
print("-" * 70)

try:
    response = requests.get(f"{API_PREFIX}/i18n/languages")
    if response.status_code == 200:
        languages = response.json()
        print(f"  Found {len(languages)} supported languages:")
        for lang in languages[:5]:  # 只显示前5个
            print(f"    {lang['code']}: {lang['name']} ({lang['native_name']})")
        if len(languages) > 5:
            print(f"    ... and {len(languages) - 5} more")
    else:
        print(f"  Status: {response.status_code}, Response: {response.text[:100]}")
except Exception as e:
    print(f"  Error: {str(e)[:50]}")

# 测试4: 获取当前语言（不同 Accept-Language）
print("\n[Test 4] Get Current Language (Different Accept-Language)")
print("-" * 70)

for lang_code, accept_lang in test_languages:
    try:
        response = requests.get(
            f"{API_PREFIX}/i18n/current",
            headers={"Accept-Language": accept_lang.split(": ")[1]}
        )
        if response.status_code == 200:
            data = response.json()
            print(f"  Request Language: {lang_code}")
            print(f"    Detected Code: {data.get('code', 'N/A')}")
            print(f"    Name: {data.get('name', 'N/A')}")
        else:
            print(f"  Language: {lang_code} - Status: {response.status_code}")
    except Exception as e:
        print(f"  Language: {lang_code} - Error: {str(e)[:50]}")

# 测试5: 用户注册（多语言错误消息）
print("\n[Test 5] User Registration (i18n Error Messages)")
print("-" * 70)

# 先尝试注册一个用户
test_phone = "13900139000"
for lang_code, accept_lang in [("zh_CN", "zh-CN,zh;q=0.9"), ("en_US", "en-US,en;q=0.9")]:
    try:
        response = requests.post(
            f"{API_PREFIX}/auth/register",
            json={
                "phone": test_phone,
                "username": f"testuser_{lang_code}",
                "password": "test123456",
                "nickname": f"Test User {lang_code}"
            },
            headers={"Accept-Language": accept_lang}
        )
        if response.status_code == 201:
            print(f"  Language: {lang_code} - Registration successful")
        elif response.status_code == 400:
            data = response.json()
            print(f"  Language: {lang_code}")
            print(f"    Error: {data.get('detail', 'N/A')}")
        else:
            print(f"  Language: {lang_code} - Status: {response.status_code}")
    except Exception as e:
        print(f"  Language: {lang_code} - Error: {str(e)[:50]}")

# 测试6: 登录失败（多语言错误消息）
print("\n[Test 6] Login Failure (i18n Error Messages)")
print("-" * 70)

for lang_code, accept_lang in [("zh_CN", "zh-CN,zh;q=0.9"), ("en_US", "en-US,en;q=0.9")]:
    try:
        response = requests.post(
            f"{API_PREFIX}/auth/login",
            data={
                "username": "nonexistent_user",
                "password": "wrong_password"
            },
            headers={"Accept-Language": accept_lang}
        )
        if response.status_code == 401:
            data = response.json()
            print(f"  Language: {lang_code}")
            print(f"    Error Message: {data.get('detail', 'N/A')}")
        else:
            print(f"  Language: {lang_code} - Status: {response.status_code}")
    except Exception as e:
        print(f"  Language: {lang_code} - Error: {str(e)[:50]}")

print("\n" + "=" * 70)
print("API i18n Test Complete")
print("=" * 70)
print("\nNote: If you see connection errors, make sure the app is running:")
print("  python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
