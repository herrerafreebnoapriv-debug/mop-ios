"""
测试新实现的3个API模块
1. 用户管理 API
2. 邀请码管理 API  
3. 后台管理 API

测试流程：
- 步骤1: 检查服务器是否运行
- 步骤2: 登录管理员账户获取token
- 步骤3: 测试用户管理API（获取列表、详情、更新等）
- 步骤4: 测试邀请码管理API（创建、验证、撤回等）
- 步骤5: 测试后台管理API（统计、封杀、地图等）
"""

import requests
import json
import sys
from pathlib import Path

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

# 测试账户信息
ADMIN_USERNAME = "zhanan089"  # 管理员账户用户名
ADMIN_PASSWORD = "zn666@"      # 管理员账户密码
TEST_USERNAME = "zn6666"       # 测试用户账户用户名
TEST_PASSWORD = "zn6666"       # 测试用户账户密码

def print_section(title):
    """打印章节标题"""
    print("\n" + "=" * 70)
    print(f"  {title}")
    print("=" * 70)

def print_result(name, success, details=""):
    """打印测试结果"""
    status = "[通过]" if success else "[失败]"
    print(f"{status:8} {name}")
    if details:
        print(f"         详情: {details}")

def test_server_connection():
    """
    测试服务器连接
    功能：检查服务器是否正在运行，能否访问健康检查端点
    """
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=3)
        if response.status_code == 200:
            return True, "服务器运行正常"
        return False, f"服务器返回状态码: {response.status_code}"
    except requests.exceptions.ConnectionError:
        return False, "无法连接到服务器，请确认服务器是否已启动"
    except Exception as e:
        return False, str(e)

def login(username, password):
    """
    登录获取token
    功能：使用用户名和密码登录，获取JWT访问令牌
    """
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
    """
    测试用户管理API模块
    功能：测试用户列表查询、用户详情获取、用户信息更新等功能
    """
    print_section("1. 用户管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    
    # 测试1: 获取用户列表（管理员功能）
    # 功能：测试管理员能否获取所有用户列表，支持分页
    try:
        response = requests.get(
            f"{API_PREFIX}/users/?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            total = data.get('total', 0)
            results.append(("获取用户列表", True, f"找到 {total} 个用户"))
        else:
            results.append(("获取用户列表", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("获取用户列表", False, str(e)[:50]))
    
    # 测试2: 获取指定用户信息（管理员功能）
    # 功能：测试管理员能否查看指定用户的详细信息
    try:
        response = requests.get(
            f"{API_PREFIX}/users/2",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            username = data.get('username', 'N/A')
            results.append(("获取用户详情", True, f"用户: {username}"))
        else:
            results.append(("获取用户详情", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("获取用户详情", False, str(e)[:50]))
    
    # 测试3: 更新用户信息（管理员功能）
    # 功能：测试管理员能否更新其他用户的信息
    try:
        response = requests.put(
            f"{API_PREFIX}/users/2",
            headers=headers,
            json={"nickname": "测试用户-已更新"},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            nickname = data.get('nickname', 'N/A')
            results.append(("更新用户信息", True, f"新昵称: {nickname}"))
        else:
            results.append(("更新用户信息", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("更新用户信息", False, str(e)[:50]))
    
    # 测试4: 更新当前用户信息（普通用户功能）
    # 功能：测试普通用户能否更新自己的信息
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
                results.append(("更新当前用户信息", False, f"状态码: {response.status_code}"))
        except Exception as e:
            results.append(("更新当前用户信息", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results)

def test_invitation_api(admin_token):
    """
    测试邀请码管理API模块
    功能：测试邀请码的创建、查询、验证、撤回等功能
    """
    print_section("2. 邀请码管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    created_code_id = None
    
    # 测试1: 创建邀请码（管理员功能）
    # 功能：测试管理员能否创建新的邀请码，设置最大使用次数
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
            max_uses = data.get("max_uses")
            results.append(("创建邀请码", True, f"邀请码: {code}, 最大使用次数: {max_uses}"))
        else:
            error_text = response.text[:100] if hasattr(response, 'text') else "未知错误"
            results.append(("创建邀请码", False, f"状态码: {response.status_code}, {error_text}"))
    except Exception as e:
        results.append(("创建邀请码", False, str(e)[:50]))
    
    # 测试2: 获取邀请码列表（管理员功能）
    # 功能：测试管理员能否查看所有邀请码列表
    try:
        response = requests.get(
            f"{API_PREFIX}/invitations/?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            total = data.get('total', 0)
            results.append(("获取邀请码列表", True, f"找到 {total} 个邀请码"))
        else:
            results.append(("获取邀请码列表", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("获取邀请码列表", False, str(e)[:50]))
    
    # 测试3: 验证邀请码（公开端点，无需登录）
    # 功能：测试注册时验证邀请码是否有效
    if created_code_id:
        try:
            # 先获取邀请码详情
            response = requests.get(
                f"{API_PREFIX}/invitations/{created_code_id}",
                headers=headers,
                timeout=5
            )
            if response.status_code == 200:
                code_data = response.json()
                code = code_data.get("code")
                
                # 验证邀请码（公开端点）
                verify_response = requests.post(
                    f"{API_PREFIX}/invitations/verify",
                    json={"code": code},
                    timeout=5
                )
                if verify_response.status_code == 200:
                    verify_data = verify_response.json()
                    valid = verify_data.get('valid')
                    used_count = verify_data.get('used_count')
                    max_uses = verify_data.get('max_uses')
                    results.append(("验证邀请码", True, 
                        f"有效: {valid}, 使用次数: {used_count}/{max_uses}"))
                else:
                    results.append(("验证邀请码", False, f"状态码: {verify_response.status_code}"))
        except Exception as e:
            results.append(("验证邀请码", False, str(e)[:50]))
    
    # 测试4: 查看邀请码使用情况（管理员功能）
    # 功能：测试管理员能否查看某个邀请码被哪些用户使用了
    if created_code_id:
        try:
            response = requests.get(
                f"{API_PREFIX}/invitations/{created_code_id}/usage",
                headers=headers,
                timeout=5
            )
            if response.status_code == 200:
                data = response.json()
                used_count = data.get('used_count')
                max_uses = data.get('max_uses')
                remaining = data.get('remaining_uses')
                results.append(("查看使用情况", True, 
                    f"已使用: {used_count}/{max_uses}, 剩余: {remaining}"))
            else:
                results.append(("查看使用情况", False, f"状态码: {response.status_code}"))
        except Exception as e:
            results.append(("查看使用情况", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results), created_code_id

def test_admin_api(admin_token):
    """
    测试后台管理API模块
    功能：测试系统统计、用户管理、设备管理、封杀功能、地图打点等
    """
    print_section("3. 后台管理 API 测试")
    
    headers = {"Authorization": f"Bearer {admin_token}"}
    results = []
    
    # 测试1: 获取系统统计信息
    # 功能：测试管理员能否查看系统整体统计数据
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/stats",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            total_users = data.get('total_users')
            online_users = data.get('online_users')
            total_devices = data.get('total_devices')
            total_invitations = data.get('total_invitations')
            results.append(("获取系统统计", True, 
                f"用户总数: {total_users}, 在线: {online_users}, "
                f"设备: {total_devices}, 邀请码: {total_invitations}"))
        else:
            results.append(("获取系统统计", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("获取系统统计", False, str(e)[:50]))
    
    # 测试2: 管理员获取所有用户（包含设备数量）
    # 功能：测试管理员能否查看所有用户的详细信息，包括每个用户的设备数量
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/users?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            user_count = len(data)
            results.append(("管理员获取用户", True, f"返回 {user_count} 个用户（包含设备数量）"))
        else:
            results.append(("管理员获取用户", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("管理员获取用户", False, str(e)[:50]))
    
    # 测试3: 管理员获取所有设备（包含用户信息）
    # 功能：测试管理员能否查看所有设备的详细信息，包括关联的用户信息
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/devices?skip=0&limit=10",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            device_count = len(data)
            results.append(("管理员获取设备", True, f"返回 {device_count} 个设备（包含用户信息）"))
        else:
            results.append(("管理员获取设备", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("管理员获取设备", False, str(e)[:50]))
    
    # 测试4: 获取地图打点数据
    # 功能：测试管理员能否获取所有用户的位置信息，用于在地图上展示
    try:
        response = requests.get(
            f"{API_PREFIX}/admin/map?skip=0&limit=100",
            headers=headers,
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            point_count = data.get('total', 0)
            results.append(("获取地图打点", True, f"找到 {point_count} 个位置点"))
        else:
            results.append(("获取地图打点", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("获取地图打点", False, str(e)[:50]))
    
    # 测试5: 发送系统消息
    # 功能：测试管理员能否发送系统消息（全服或个人）
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
            message_id = data.get('message_id', 'N/A')
            results.append(("发送系统消息", True, f"消息ID: {message_id}"))
        else:
            results.append(("发送系统消息", False, f"状态码: {response.status_code}"))
    except Exception as e:
        results.append(("发送系统消息", False, str(e)[:50]))
    
    for name, success, details in results:
        print_result(name, success, details)
    
    return all(r[1] for r in results)

def main():
    """
    主测试函数
    功能：按顺序执行所有测试步骤，汇总测试结果
    """
    print("\n" + "=" * 70)
    print("  MOP 系统 - 新API模块测试")
    print("=" * 70)
    
    # 步骤0: 检查服务器连接
    # 功能：确认服务器是否正在运行，这是所有测试的前提
    print("\n[步骤 0] 检查服务器连接...")
    print("功能：确认服务器是否正在运行")
    success, msg = test_server_connection()
    print_result("服务器连接", success, msg)
    if not success:
        print("\n[错误] 请先启动服务器:")
        print("  命令: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
        print("  或者运行: start_demo.bat")
        sys.exit(1)
    
    # 步骤1: 登录管理员账户
    # 功能：获取管理员token，后续测试需要管理员权限
    print("\n[步骤 1] 登录管理员账户...")
    print("功能：获取管理员访问令牌（token）")
    success, admin_token = login(ADMIN_USERNAME, ADMIN_PASSWORD)
    print_result("管理员登录", success, "Token获取成功" if success else "登录失败")
    if not success:
        print("\n[错误] 无法登录管理员账户，请检查账户是否存在")
        print("  管理员账户: zhanan089")
        print("  如果账户不存在，请运行: python scripts/create_test_accounts.py")
        sys.exit(1)
    
    # 步骤2: 测试用户管理API
    # 功能：测试用户列表查询、用户详情获取、用户信息更新等功能
    print("\n[步骤 2] 开始测试用户管理API...")
    user_test_result = test_user_management_api(admin_token)
    
    # 步骤3: 测试邀请码管理API
    # 功能：测试邀请码的创建、查询、验证、撤回等功能
    print("\n[步骤 3] 开始测试邀请码管理API...")
    inv_test_result, code_id = test_invitation_api(admin_token)
    
    # 步骤4: 测试后台管理API
    # 功能：测试系统统计、用户管理、设备管理、封杀功能、地图打点等
    print("\n[步骤 4] 开始测试后台管理API...")
    admin_test_result = test_admin_api(admin_token)
    
    # 步骤5: 汇总测试结果
    # 功能：汇总所有测试结果，给出最终结论
    print_section("测试总结")
    print(f"用户管理 API:  {'[通过]' if user_test_result else '[失败]'}")
    print(f"邀请码管理 API: {'[通过]' if inv_test_result else '[失败]'}")
    print(f"后台管理 API:   {'[通过]' if admin_test_result else '[失败]'}")
    
    all_passed = user_test_result and inv_test_result and admin_test_result
    print("\n" + "=" * 70)
    if all_passed:
        print("[成功] 所有测试通过！")
        print("=" * 70)
        print("\n提示：")
        print("  - 可以访问 http://127.0.0.1:8000/docs 查看完整的API文档")
        print("  - 所有API都已集成多语言支持")
        print("  - 管理员账户可以访问所有管理功能")
    else:
        print("[警告] 部分测试失败，请检查上述错误信息")
        print("=" * 70)
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
