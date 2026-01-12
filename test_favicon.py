#!/usr/bin/env python3
"""
测试 Favicon 功能
"""

import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# 测试文件路径
def test_file_paths():
    """测试文件路径"""
    print("=== 测试文件路径 ===\n")
    
    BASE_DIR = project_root
    FAVICON_DIR = BASE_DIR / "static" / "favicons"
    ICON_DIR = BASE_DIR / "static" / "icons"
    
    print(f"项目根目录: {BASE_DIR}")
    print(f"Favicon 目录: {FAVICON_DIR} (存在: {FAVICON_DIR.exists()})")
    print(f"Icon 目录: {ICON_DIR} (存在: {ICON_DIR.exists()})")
    
    # 测试获取 favicon 文件
    favicons = []
    if FAVICON_DIR.exists():
        for ext in ['.ico', '.png', '.svg', '.jpg', '.jpeg']:
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*{ext}")))
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*.{ext.lstrip('.')}")))
    
    print(f"\n找到 {len(favicons)} 个 favicon 文件")
    if favicons:
        for fav in favicons:
            print(f"  - {fav.name} ({fav.stat().st_size} bytes)")
    else:
        print("  (无 favicon 文件)")
    
    # 测试获取图标文件
    icons = []
    if ICON_DIR.exists():
        for ext in ['.png', '.ico', '.svg']:
            icons.extend(list(ICON_DIR.glob(f"*ico*{ext}")))
    
    print(f"\n找到 {len(icons)} 个图标文件")
    if icons:
        print("前 5 个图标文件:")
        for icon in icons[:5]:
            size = icon.stat().st_size
            print(f"  - {icon.name} ({size} bytes)")
        
        # 测试选择最小的作为默认
        if icons:
            smallest = min(icons, key=lambda f: f.stat().st_size)
            print(f"\n最小图标（将作为默认 favicon）: {smallest.name} ({smallest.stat().st_size} bytes)")
    else:
        print("  (无图标文件)")
    
    return favicons, icons

def test_random_selection():
    """测试随机选择逻辑"""
    print("\n=== 测试随机选择逻辑 ===\n")
    
    import random
    
    BASE_DIR = project_root
    FAVICON_DIR = BASE_DIR / "static" / "favicons"
    ICON_DIR = BASE_DIR / "static" / "icons"
    
    # 获取文件
    favicons = []
    if FAVICON_DIR.exists():
        for ext in ['.ico', '.png', '.svg', '.jpg', '.jpeg']:
            favicons.extend(list(FAVICON_DIR.glob(f"*fav*{ext}")))
    
    icons = []
    if ICON_DIR.exists():
        for ext in ['.png', '.ico', '.svg']:
            icons.extend(list(ICON_DIR.glob(f"*ico*{ext}")))
    
    # 模拟随机选择
    print("模拟 5 次随机选择:")
    for i in range(5):
        if favicons:
            selected = random.choice(favicons)
            print(f"  第 {i+1} 次: {selected.name} (favicon)")
        elif icons:
            selected = min(icons, key=lambda f: f.stat().st_size)
            print(f"  第 {i+1} 次: {selected.name} (默认图标)")
        else:
            print(f"  第 {i+1} 次: (无可用文件)")

def test_html_integration():
    """测试 HTML 集成"""
    print("\n=== 测试 HTML 集成 ===\n")
    
    login_file = project_root / "static" / "login.html"
    register_file = project_root / "static" / "register.html"
    
    if login_file.exists():
        content = login_file.read_text(encoding='utf-8')
        if 'favicon.ico' in content:
            print("✓ login.html 包含 favicon 链接")
        else:
            print("✗ login.html 缺少 favicon 链接")
    
    if register_file.exists():
        content = register_file.read_text(encoding='utf-8')
        if 'favicon.ico' in content:
            print("✓ register.html 包含 favicon 链接")
        else:
            print("✗ register.html 缺少 favicon 链接")

if __name__ == "__main__":
    print("Favicon 功能测试\n" + "=" * 50 + "\n")
    
    try:
        favicons, icons = test_file_paths()
        test_random_selection()
        test_html_integration()
        
        print("\n" + "=" * 50)
        print("\n测试总结:")
        print(f"  - Favicon 文件: {len(favicons)} 个")
        print(f"  - 图标文件: {len(icons)} 个")
        
        if len(favicons) == 0 and len(icons) > 0:
            print("\n⚠️  提示: 没有 favicon 文件，将使用图标文件作为默认")
            print("   要添加 favicon，请将包含 'fav' 的文件放到 mop_ico_fav/ 目录")
            print("   然后运行: python3 scripts/process_favicons.py")
        
        if len(icons) == 0:
            print("\n✗ 错误: 没有找到任何图标文件！")
            sys.exit(1)
        
        print("\n✓ 测试完成！")
        
    except Exception as e:
        print(f"\n✗ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
