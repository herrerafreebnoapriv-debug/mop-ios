#!/usr/bin/env python3
"""
生成不同尺寸的应用图标
从 ico 文件中生成 PWA 所需的各种尺寸
"""

import os
from pathlib import Path
from PIL import Image

def generate_icon_sizes():
    """生成不同尺寸的图标"""
    project_root = Path(__file__).parent.parent
    icon_dir = project_root / "static" / "icons"
    
    if not icon_dir.exists():
        print(f"图标目录不存在: {icon_dir}")
        return
    
    # 需要的尺寸
    sizes = [72, 96, 128, 144, 152, 192, 384, 512]
    
    # 查找所有 ico 文件
    ico_files = list(icon_dir.glob("*ico*.png"))
    
    if not ico_files:
        print("未找到图标文件")
        return
    
    # 使用第一个较大的图标作为源
    source_file = max(ico_files, key=lambda f: f.stat().st_size)
    print(f"使用源文件: {source_file.name}")
    
    try:
        img = Image.open(source_file)
        
        # 生成各种尺寸
        for size in sizes:
            # 创建正方形缩略图
            resized = img.resize((size, size), Image.Resampling.LANCZOS)
            output_path = icon_dir / f"icon-{size}x{size}.png"
            resized.save(output_path, "PNG")
            print(f"✓ 生成: icon-{size}x{size}.png")
        
        print(f"\n所有图标已生成到: {icon_dir}")
        
    except Exception as e:
        print(f"错误: {e}")
        print("需要安装 Pillow: pip install Pillow")

if __name__ == "__main__":
    generate_icon_sizes()
