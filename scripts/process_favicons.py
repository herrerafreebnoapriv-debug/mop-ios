#!/usr/bin/env python3
"""
处理 favicon 文件脚本
- 将包含 fav 的文件转换为 .ico 格式（如果需要）
- 将文件移动到 static/favicons/ 目录
"""

import os
import shutil
from pathlib import Path
from PIL import Image

def convert_to_ico(input_path, output_path, sizes=[(16, 16), (32, 32), (48, 48)]):
    """将图片转换为 ICO 格式"""
    try:
        img = Image.open(input_path)
        # 创建多尺寸 ICO
        img.save(output_path, format='ICO', sizes=sizes)
        print(f"✓ 转换成功: {input_path.name} -> {output_path.name}")
        return True
    except Exception as e:
        print(f"✗ 转换失败: {input_path.name} - {e}")
        return False

def process_favicons():
    """处理 favicon 文件"""
    project_root = Path(__file__).parent.parent
    source_dir = project_root / "mop_ico_fav"
    favicon_dir = project_root / "static" / "favicons"
    icon_dir = project_root / "static" / "icons"
    
    # 创建目标目录
    favicon_dir.mkdir(parents=True, exist_ok=True)
    icon_dir.mkdir(parents=True, exist_ok=True)
    
    if not source_dir.exists():
        print(f"源目录不存在: {source_dir}")
        return
    
    # 处理包含 fav 的文件
    fav_files = []
    for ext in ['.png', '.jpg', '.jpeg', '.svg', '.ico']:
        fav_files.extend(list(source_dir.glob(f"*fav*{ext}")))
        fav_files.extend(list(source_dir.glob(f"*fav*.{ext.lstrip('.')}")))
    
    print(f"\n找到 {len(fav_files)} 个 favicon 文件")
    
    for fav_file in fav_files:
        if fav_file.suffix.lower() == '.ico':
            # 直接复制 ICO 文件
            dest = favicon_dir / fav_file.name
            shutil.copy2(fav_file, dest)
            print(f"✓ 复制 ICO: {fav_file.name}")
        else:
            # 转换为 ICO
            ico_name = fav_file.stem + '.ico'
            dest = favicon_dir / ico_name
            if convert_to_ico(fav_file, dest):
                # 同时保留原格式作为备用
                png_dest = favicon_dir / fav_file.name
                shutil.copy2(fav_file, png_dest)
    
    # 处理包含 ico 的文件（应用图标）
    ico_files = []
    for ext in ['.png', '.ico', '.svg']:
        ico_files.extend(list(source_dir.glob(f"*ico*{ext}")))
    
    print(f"\n找到 {len(ico_files)} 个应用图标文件")
    
    for ico_file in ico_files:
        dest = icon_dir / ico_file.name
        shutil.copy2(ico_file, dest)
        print(f"✓ 复制图标: {ico_file.name}")
    
    print(f"\n处理完成！")
    print(f"Favicon 文件位置: {favicon_dir}")
    print(f"应用图标位置: {icon_dir}")

if __name__ == "__main__":
    try:
        process_favicons()
    except ImportError:
        print("需要安装 Pillow 库: pip install Pillow")
    except Exception as e:
        print(f"错误: {e}")
