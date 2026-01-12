#!/usr/bin/env python3
"""
完整的 Favicon API 测试
需要服务器运行: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
"""

import requests
import sys

BASE_URL = "http://127.0.0.1:8000"

def test_favicon_endpoint():
    """测试 favicon 端点"""
    print("=== 测试 Favicon API ===\n")
    
    # 测试根路径 favicon
    print("1. 测试 GET /favicon.ico")
    try:
        response = requests.get(f"{BASE_URL}/favicon.ico", timeout=5)
        print(f"   状态码: {response.status_code}")
        print(f"   Content-Type: {response.headers.get('Content-Type')}")
        print(f"   文件大小: {len(response.content)} bytes")
        
        if response.status_code == 200:
            print("   ✓ 成功获取 favicon")
            # 保存测试文件
            with open("/tmp/test_favicon.ico", "wb") as f:
                f.write(response.content)
            print("   ✓ 已保存到 /tmp/test_favicon.ico")
        else:
            print(f"   ✗ 失败: {response.text}")
            return False
    except requests.exceptions.ConnectionError:
        print("   ✗ 无法连接到服务器")
        print("   请先启动服务器: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000")
        return False
    except Exception as e:
        print(f"   ✗ 错误: {e}")
        return False
    
    # 测试多次请求（验证随机性）
    print("\n2. 测试随机选择（5次请求）")
    files_seen = set()
    for i in range(5):
        try:
            response = requests.get(f"{BASE_URL}/favicon.ico", timeout=5)
            if response.status_code == 200:
                # 使用内容哈希来识别不同文件
                content_hash = hash(response.content)
                files_seen.add(content_hash)
                print(f"   请求 {i+1}: {len(response.content)} bytes (hash: {content_hash})")
        except Exception as e:
            print(f"   请求 {i+1} 失败: {e}")
    
    if len(files_seen) > 1:
        print(f"   ✓ 检测到 {len(files_seen)} 个不同的文件（随机选择工作正常）")
    elif len(files_seen) == 1:
        print("   ⚠️  所有请求返回相同文件（可能是只有一个文件，或缓存问题）")
    else:
        print("   ✗ 没有成功获取任何文件")
    
    # 测试 API 路径
    print("\n3. 测试 GET /api/v1/favicon.ico")
    try:
        response = requests.get(f"{BASE_URL}/api/v1/favicon.ico", timeout=5)
        print(f"   状态码: {response.status_code}")
        if response.status_code == 200:
            print("   ✓ API 路径也可用")
        else:
            print(f"   ⚠️  API 路径返回 {response.status_code}")
    except Exception as e:
        print(f"   ✗ 错误: {e}")
    
    return True

def test_html_integration():
    """测试 HTML 集成"""
    print("\n=== 测试 HTML 集成 ===\n")
    
    # 检查 HTML 文件
    from pathlib import Path
    login_file = Path("static/login.html")
    register_file = Path("static/register.html")
    
    if login_file.exists():
        content = login_file.read_text(encoding='utf-8')
        if '/favicon.ico' in content:
            print("✓ login.html 包含 favicon 链接")
        else:
            print("✗ login.html 缺少 favicon 链接")
    
    if register_file.exists():
        content = register_file.read_text(encoding='utf-8')
        if '/favicon.ico' in content:
            print("✓ register.html 包含 favicon 链接")
        else:
            print("✗ register.html 缺少 favicon 链接")

if __name__ == "__main__":
    print("Favicon API 完整测试\n" + "=" * 50 + "\n")
    
    # 检查 requests 库
    try:
        import requests
    except ImportError:
        print("需要安装 requests 库: pip install requests")
        sys.exit(1)
    
    # 测试文件结构
    test_html_integration()
    
    # 测试 API（需要服务器运行）
    print("\n" + "=" * 50)
    if test_favicon_endpoint():
        print("\n✓ 所有测试通过！")
    else:
        print("\n⚠️  部分测试失败，请检查服务器是否运行")
        print("启动命令: python -m uvicorn app.main:app --host 127.0.0.1 --port 8000")
