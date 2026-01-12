#!/usr/bin/env python3
"""
测试二维码生成 API
"""

import requests
import json
import sys

def test_qrcode_api(base_url="http://127.0.0.1:8000"):
    """测试二维码生成 API"""
    
    print("="*60)
    print("二维码生成 API 测试")
    print("="*60)
    
    # 1. 先登录获取 token
    print("\n1. 登录获取 Token...")
    login_data = {
        "username": "admin",
        "password": "admin123"
    }
    
    try:
        response = requests.post(f"{base_url}/api/v1/auth/login", json=login_data)
        if response.status_code != 200:
            print(f"❌ 登录失败: {response.status_code}")
            print(f"   响应: {response.text}")
            return False
        
        data = response.json()
        token = data.get("access_token")
        if not token:
            print("❌ 登录响应中没有 access_token")
            return False
        
        print(f"✅ 登录成功，Token: {token[:20]}...")
    except Exception as e:
        print(f"❌ 登录异常: {e}")
        return False
    
    # 2. 创建房间
    print("\n2. 创建房间...")
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    room_data = {
        "room_name": "测试房间",
        "max_occupants": 10
    }
    
    try:
        response = requests.post(f"{base_url}/api/v1/rooms/create", json=room_data, headers=headers)
        if response.status_code != 201:
            print(f"❌ 创建房间失败: {response.status_code}")
            print(f"   响应: {response.text}")
            return False
        
        room_info = response.json()
        room_id = room_info.get("room_id")
        print(f"✅ 房间创建成功，房间ID: {room_id}")
    except Exception as e:
        print(f"❌ 创建房间异常: {e}")
        return False
    
    # 3. 测试二维码生成（JSON 响应）
    print("\n3. 测试二维码生成（JSON 响应）...")
    try:
        response = requests.get(f"{base_url}/api/v1/qrcode/room/{room_id}", headers=headers)
        if response.status_code != 200:
            print(f"❌ 二维码生成失败: {response.status_code}")
            print(f"   响应: {response.text}")
            return False
        
        qr_data = response.json()
        print(f"✅ 二维码生成成功（JSON）")
        print(f"   加密数据长度: {len(qr_data.get('encrypted_data', ''))}")
        print(f"   图片 Base64 长度: {len(qr_data.get('qr_code_image', ''))}")
    except Exception as e:
        print(f"❌ 二维码生成异常: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    # 4. 测试二维码生成（图片响应）
    print("\n4. 测试二维码生成（图片响应）...")
    try:
        response = requests.get(f"{base_url}/api/v1/qrcode/room/{room_id}/image", headers=headers)
        if response.status_code != 200:
            print(f"❌ 二维码图片生成失败: {response.status_code}")
            print(f"   响应: {response.text}")
            return False
        
        content_type = response.headers.get("Content-Type")
        content_length = len(response.content)
        print(f"✅ 二维码图片生成成功")
        print(f"   Content-Type: {content_type}")
        print(f"   图片大小: {content_length} bytes")
        
        # 保存图片用于验证
        with open("/tmp/test_qrcode.png", "wb") as f:
            f.write(response.content)
        print(f"   图片已保存到: /tmp/test_qrcode.png")
    except Exception as e:
        print(f"❌ 二维码图片生成异常: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    print("\n" + "="*60)
    print("✅ 所有测试通过！")
    print("="*60)
    return True

if __name__ == "__main__":
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    success = test_qrcode_api(base_url)
    sys.exit(0 if success else 1)
