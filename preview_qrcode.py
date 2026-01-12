#!/usr/bin/env python3
"""
二维码预览脚本
生成一个测试二维码并保存到 /tmp/qrcode_preview.png
"""

import sys
import os
import requests
from pathlib import Path

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.core.security import rsa_encrypt
from app.core.config import settings
import qrcode
from qrcode.constants import ERROR_CORRECT_H
import io

def generate_test_qrcode(room_id: str = "r-test1234"):
    """
    生成测试二维码
    
    Args:
        room_id: 房间ID（默认使用测试ID）
    """
    print(f"🔍 生成二维码预览...")
    print(f"   房间ID: {room_id}")
    
    # 构建要加密的数据
    data = {
        "room_id": room_id,
    }
    
    print(f"   原始数据: {data}")
    
    # RSA 加密签名（使用短键名优化 + 压缩）
    try:
        encrypted_data = rsa_encrypt(data, use_short_keys=True, compress=True)
        print(f"   ✅ RSA 加密成功")
        print(f"   加密数据长度: {len(encrypted_data)} 字符")
    except Exception as e:
        print(f"   ❌ RSA 加密失败: {e}")
        return None
    
    # 生成二维码图片
    try:
        qr = qrcode.QRCode(
            version=1,
            error_correction=ERROR_CORRECT_H,
            box_size=10,
            border=4,
        )
        qr.add_data(encrypted_data)
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        # 获取二维码信息
        print(f"\n📊 二维码信息:")
        print(f"   版本: {qr.version}")
        print(f"   矩阵大小: {qr.modules_count}x{qr.modules_count}")
        print(f"   尺寸: {img.size[0]}x{img.size[1]} 像素")
        print(f"   容错级别: H (30%)")
        
        # 保存到文件
        output_path = "/tmp/qrcode_preview.png"
        img.save(output_path)
        print(f"\n✅ 二维码已保存到: {output_path}")
        
        # 显示ASCII预览
        print(f"\n📱 ASCII预览（█=黑色，空格=白色）:")
        print_ascii_qrcode(qr)
        
        return output_path
        
    except Exception as e:
        print(f"   ❌ 二维码生成失败: {e}")
        return None


def print_ascii_qrcode(qr):
    """
    打印二维码的ASCII预览
    """
    modules = qr.modules
    size = len(modules)
    
    # 打印边框
    print("─" * (size + 4))
    
    # 打印二维码矩阵
    for i, row in enumerate(modules):
        line = "│  "
        for j, module in enumerate(row):
            if module:
                line += "██"
            else:
                line += "  "
        line += "  │"
        print(line)
    
    # 打印边框
    print("─" * (size + 4))
    
    # 计算密集度
    total_modules = size * size
    black_modules = sum(sum(row) for row in modules)
    density = (black_modules / total_modules) * 100
    
    print(f"\n📈 密集度统计:")
    print(f"   总模块数: {total_modules}")
    print(f"   黑色模块: {black_modules}")
    print(f"   密集度: {density:.1f}%")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="生成二维码预览")
    parser.add_argument("--room-id", type=str, default="r-test1234", help="房间ID（默认: r-test1234）")
    args = parser.parse_args()
    
    result = generate_test_qrcode(args.room_id)
    
    if result:
        print(f"\n✨ 预览完成！")
        print(f"   图片路径: {result}")
        print(f"   可以使用以下命令查看:")
        print(f"   - Linux: xdg-open {result}")
        print(f"   - Mac: open {result}")
        print(f"   - Windows: start {result}")
    else:
        print(f"\n❌ 预览失败！")
        sys.exit(1)
