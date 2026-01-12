"""测试账户登录"""
import requests
import json

BASE_URL = "http://127.0.0.1:8000"
API_PREFIX = f"{BASE_URL}/api/v1"

def test_login(username, password, account_type):
    """测试登录"""
    print(f"\n测试 {account_type} 账户登录:")
    print(f"  用户名: {username}")
    
    try:
        response = requests.post(
            f"{API_PREFIX}/auth/login",
            data={
                "username": username,
                "password": password
            },
            timeout=5
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"  [SUCCESS] 登录成功!")
            print(f"  Access Token: {data['access_token'][:50]}...")
            print(f"  Token Type: {data['token_type']}")
            return data['access_token']
        else:
            print(f"  [FAILED] 登录失败")
            print(f"  Status: {response.status_code}")
            print(f"  Response: {response.text}")
            return None
    except requests.exceptions.ConnectionError:
        print(f"  [ERROR] 无法连接到服务器")
        print(f"  请确保服务器正在运行: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
        return None
    except Exception as e:
        print(f"  [ERROR] {str(e)}")
        return None

if __name__ == "__main__":
    print("=" * 60)
    print("MOP 系统 - 账户登录测试")
    print("=" * 60)
    
    # 测试管理员账户
    admin_token = test_login("zhanan089", "zn666@", "管理员")
    
    # 测试普通用户账户
    user_token = test_login("zn6666", "zn6666", "测试用户")
    
    print("\n" + "=" * 60)
    if admin_token and user_token:
        print("[SUCCESS] 所有账户登录测试通过!")
    else:
        print("[WARNING] 部分账户登录测试失败，请检查服务器状态")
    print("=" * 60)
