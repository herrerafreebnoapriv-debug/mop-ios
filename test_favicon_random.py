#!/usr/bin/env python3
"""
测试 favicon 随机选择功能
通过 HTTP 请求验证多次请求返回不同文件
"""

import requests
import hashlib
import os
from pathlib import Path

def test_favicon_random_selection(base_url="http://127.0.0.1:8000", num_requests=20):
    """测试 favicon 随机选择功能"""
    print(f"开始测试 favicon 随机选择功能...")
    print(f"服务器地址: {base_url}")
    print(f"请求次数: {num_requests}\n")
    
    # 存储每次请求的文件哈希值
    file_hashes = []
    file_sizes = []
    
    for i in range(num_requests):
        try:
            response = requests.get(f"{base_url}/favicon.ico", timeout=5)
            if response.status_code == 200:
                # 计算文件哈希值
                file_hash = hashlib.md5(response.content).hexdigest()
                file_size = len(response.content)
                file_hashes.append(file_hash)
                file_sizes.append(file_size)
                print(f"请求 {i+1:2d}: 状态码={response.status_code}, 大小={file_size:6d} 字节, 哈希={file_hash[:16]}...")
            else:
                print(f"请求 {i+1:2d}: 错误 - 状态码={response.status_code}")
        except Exception as e:
            print(f"请求 {i+1:2d}: 异常 - {e}")
    
    print(f"\n{'='*60}")
    print(f"测试结果统计:")
    print(f"{'='*60}")
    print(f"总请求数: {len(file_hashes)}")
    print(f"唯一哈希数: {len(set(file_hashes))}")
    print(f"文件大小范围: {min(file_sizes) if file_sizes else 0} - {max(file_sizes) if file_sizes else 0} 字节")
    
    # 统计每个哈希值出现的次数
    hash_counts = {}
    for h in file_hashes:
        hash_counts[h] = hash_counts.get(h, 0) + 1
    
    print(f"\n文件分布:")
    for hash_val, count in sorted(hash_counts.items(), key=lambda x: x[1], reverse=True):
        print(f"  {hash_val[:16]}... : {count} 次 ({count*100/len(file_hashes):.1f}%)")
    
    # 判断是否成功
    unique_count = len(set(file_hashes))
    if unique_count > 1:
        print(f"\n✅ 测试通过: 返回了 {unique_count} 个不同的文件，随机选择功能正常！")
        return True
    elif unique_count == 1:
        print(f"\n⚠️  警告: 所有请求返回了相同的文件（可能是随机种子问题或只有1个文件）")
        return False
    else:
        print(f"\n❌ 测试失败: 没有成功获取任何文件")
        return False

if __name__ == "__main__":
    import sys
    
    # 检查服务器是否运行
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    num_requests = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    
    print("="*60)
    print("Favicon 随机选择功能测试")
    print("="*60)
    print(f"\n注意: 请确保服务器正在运行: {base_url}")
    print("启动命令: python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000\n")
    
    try:
        # 先测试服务器是否可访问
        response = requests.get(f"{base_url}/health", timeout=3)
        print(f"✅ 服务器可访问 (健康检查: {response.status_code})")
    except Exception as e:
        print(f"❌ 无法连接到服务器: {e}")
        print("请先启动服务器后再运行此测试")
        sys.exit(1)
    
    print()
    success = test_favicon_random_selection(base_url, num_requests)
    sys.exit(0 if success else 1)
