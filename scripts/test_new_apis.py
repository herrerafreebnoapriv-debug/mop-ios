"""
测试新实现的3个API模块
1. 用户管理 API
2. 邀请码管理 API
3. 后台管理 API
"""

import requests
import json
import sys
from pathlib import Path

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

# 测试账户
ADMIN_USERNAME = "zhanan089"
ADMIN_PASSWORD = "zn666@"
TEST_USERNAME = "zn6666"
TEST_PASSWORD = "zn6666"

def print_section(title):
    """打印章节标题"""
    print("\n" + "=" * 70)
    print(f"  {title}")
    print("=" * 70)

def print_result(name, success, details=""):
    """打印测试结果"""
    status = "[PASS]" if success else "[FAIL]"
    print(f"{status:8} {name}")
    if details:
        print(f"         {details}")

def test_server_connection():
    """测试服务器连接"""
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=3)
        if response.status_code == 200:
            return True, "Server is running"
        return False, f"Server returned {response.status_code}"
    except requests.exceptions.ConnectionError:
        return False, "Cannot connect to server. Is it running?"
    except Exception as e:
        return False, str(e)

def login(username, password):
    """登录获取token"""
    try:
        response = requests.post(
            f"{API_PREFIX}/auth/login",
            data={"username": username, "password": password},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            return True, data.get("access_token")
        return False, None
    except Exception as e:
        return False, None

def test_user_management_api(admin_token):
    """测试用户管理API"""
    print_section("1. 用户管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    
    # 测试1: 获取用户列表
    try:
        response = requests.get(
            f"{API_PREFIX}/users/?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("获取用户列表", True, f"找到 {data.get('total', 0)} 个用户"))
        else:
            results.append(("获取用户列表", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("获取用户列表", False, str(e)[:50]))
    
    # 测试2: 获取指定用户信息
    try:
        response = requests.get(
            f"{API_PREFIX}/users/2",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("获取用户详情", True, f"用户: {data.get('username', 'N/A')}"))
        else:
            results.append(("获取用户详情", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("获取用户详情", False, str(e)[:50]))
    
    # 测试3: 更新用户信息
    try:
        response = requests.put(
            f"{API_PREFIX}/users/2",
            headers=headers,
            json={"nickname": "测试用户-已更新"},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("更新用户信息", True, f"新昵称: {data.get('nickname', 'N/A')}"))
        else:
            results.append(("更新用户信息", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("更新用户信息", False, str(e)[:50]))
    
    # 测试4: 更新当前用户信息（非管理员）
    test_token = login(TEST_USERNAME, TEST_PASSWORD)[1]
    if test_token:
        try:
            response = requests.put(
                f"{API_PREFIX}/users/me",
                headers={"Authorization": f"Bearer {test_token}"},
                json={"nickname": "普通用户-已更新"},
                timeout=5
            )
            if response.status_code == 200:
                results.append(("更新当前用户信息", True, "成功"))
            else:
                results.append(("更新当前用户信息", False, f"Status: {response.status_code}"))
        except Exception as e:
            results.append(("更新当前用户信息", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results)

def test_invitation_api(admin_token):
    """测试邀请码管理API"""
    print_section("2. 邀请码管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    created_code_id = None
    
    # 测试1: 创建邀请码
    try:
        response = requests.post(
            f"{API_PREFIX}/invitations/create",
            headers=headers,
            json={"max_uses": 5},
            timeout=5
        )
        if response.status_code == 201:
            data = response.json()
            created_code_id = data.get("id")
            code = data.get("code")
            results.append(("创建邀请码", True, f"邀请码: {code}, ID: {created_code_id}"))
        else:
            results.append(("创建邀请码", False, f"Status: {response.status_code}, {response.text[:100]}"))
    except Exception as e:
        results.append(("创建邀请码", False, str(e)[:50]))
    
    # 测试2: 获取邀请码列表
    try:
        response = requests.get(
            f"{API_PREFIX}/invitations/?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("获取邀请码列表", True, f"找到 {data.get('total', 0)} 个邀请码"))
        else:
            results.append(("获取邀请码列表", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("获取邀请码列表", False, str(e)[:50]))
    
    # 测试3: 验证邀请码（公开端点）
    if created_code_id:
        try:
            # 先获取邀请码
            response = requests.get(
                f"{API_PREFIX}/invitations/{created_code_id}",
                headers=headers,
                timeout=5
            )
            if response.status_code == 200:
                code_data = response.json()
                code = code_data.get("code")
                
                # 验证邀请码
                verify_response = requests.post(
                    f"{API_PREFIX}/invitations/verify",
                    json={"code": code},
                    timeout=5
                )
                if verify_response.status_code == 200:
                    verify_data = verify_response.json()
                    results.append(("验证邀请码", True, f"有效: {verify_data.get('valid')}, 使用次数: {verify_data.get('used_count')}/{verify_data.get('max_uses')}"))
                else:
                    results.append(("验证邀请码", False, f"Status: {verify_response.status_code}"))
        except Exception as e:
            results.append(("验证邀请码", False, str(e)[:50]))
    
    # 测试4: 查看邀请码使用情况
    if created_code_id:
        try:
            response = requests.get(
                f"{API_PREFIX}/invitations/{created_code_id}/usage",
                headers=headers,
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                results.append(("查看使用情况", True, f"已使用: {data.get('used_count')}/{data.get('max_uses')}"))
            else:
                results.append(("查看使用情况", False, f"Status: {response.status_code}"))
        except Exception as e:
            results.append(("查看使用情况", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results), created_code_id

def test_admin_api(admin_token):
    """测试后台管理API"""
    print_section("3. 后台管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    
    # 测试1: 获取系统统计
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/stats",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("获取系统统计", True, 
                f"用户: {data.get('total_users')}, 在线: {data.get('online_users')}, "
                f"设备: {data.get('total_devices')}, 邀请码: {data.get('total_invitations')}"))
        else:
            results.append(("获取系统统计", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("获取系统统计", False, str(e)[:50]))
    
    # 测试2: 管理员获取所有用户
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/users?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("管理员获取用户", True, f"返回 {len(data)} 个用户"))
        else:
            results.append(("管理员获取用户", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("管理员获取用户", False, str(e)[:50]))
    
    # 测试3: 管理员获取所有设备
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/devices?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("管理员获取设备", True, f"返回 {len(data)} 个设备"))
        else:
            results.append(("管理员获取设备", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("管理员获取设备", False, str(e)[:50]))
    
    # 测试4: 获取地图打点
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/map?skip=0&limit=100",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("获取地图打点", True, f"找到 {data.get('total', 0)} 个位置点"))
        else:
            results.append(("获取地图打点", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("获取地图打点", False, str(e)[:50]))
    
    # 测试5: 发送系统消息
    try:
        response = requests.post(
            f"{API_PREFIX}/admin/message",
            headers=headers,
            json={
                "message": "这是一条测试系统消息",
                "target_type": "all",
                "priority": "normal"
            },
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            results.append(("发送系统消息", True, f"消息ID: {data.get('message_id', 'N/A')}"))
        else:
            results.append(("发送系统消息", False, f"Status: {response.status_code}"))
    except Exception as e:
        results.append(("发送系统消息", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results)

def main():
    """主测试函数"""
    print("\n" + "=" * 70)
    print("  MOP 系统 - 新API模块测试")
    print("=" * 70)
    
    # 测试服务器连接
    print("\n[步骤 0] 检查服务器连接...")
    success, msg = test_server_connection()
    print_result("服务器连接", success, msg)
    if not success:
        print("\n[错误] 请先启动服务器:")
        print("  python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
        sys.exit(1)
    
    # 登录管理员账户
    print("\n[步骤 1] 登录管理员账户...")
    success, admin_token = login(ADMIN_USERNAME, ADMIN_PASSWORD)
    print_result("管理员登录", success, "Token获取成功" if success else "登录失败")
    if not success:
        print("\n[错误] 无法登录管理员账户，请检查账户是否存在")
        sys.exit(1)
    
    # 测试各个模块
    user_test_result = test_user_management_api(admin_token)
    inv_test_result, code_id = test_invitation_api(admin_token)
    admin_test_result = test_admin_api(admin_token)
    
    # 总结
    print_section("测试总结")
    print(f"用户管理 API:  {'[PASS] 通过' if user_test_result else '[FAIL] 失败'}")
    print(f"邀请码管理 API: {'[PASS] 通过' if inv_test_result else '[FAIL] 失败'}")
    print(f"后台管理 API:   {'[PASS] 通过' if admin_test_result else '[FAIL] 失败'}")
    
    all_passed = user_test_result and inv_test_result and admin_test_result
    print("\n" + "=" * 70)
    if all_passed:
        print("[SUCCESS] 所有测试通过！")
    else:
        print("[WARNING] 部分测试失败，请检查上述错误信息")
    print("=" * 70)
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
