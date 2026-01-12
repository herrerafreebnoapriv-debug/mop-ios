"""测试所有API模块"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

def test_imports():
    """测试所有模块导入"""
    print("=" * 60)
    print("Testing All API Modules")
    print("=" * 60)
    
    modules = [
        ("app.main", "Main application"),
        ("app.api.v1.auth", "Auth module"),
        ("app.api.v1.i18n", "i18n module"),
        ("app.api.v1.devices", "Devices module"),
        ("app.api.v1.users", "Users module"),
        ("app.api.v1.invitations", "Invitations module"),
        ("app.api.v1.admin", "Admin module"),
    ]
    
    success_count = 0
    for module_name, description in modules:
        try:
            __import__(module_name)
            print(f"[OK] {description:30} - {module_name}")
            success_count += 1
        except Exception as e:
            print(f"[FAIL] {description:30} - {module_name}")
            print(f"       Error: {str(e)[:60]}")
    
    print("=" * 60)
    print(f"Result: {success_count}/{len(modules)} modules loaded successfully")
    print("=" * 60)
    
    if success_count == len(modules):
        print("\n[SUCCESS] All modules are ready!")
        return True
    else:
        print("\n[WARNING] Some modules failed to load")
        return False


def test_routes():
    """测试路由注册"""
    try:
        from app.main import app
        routes = [r for r in app.routes if hasattr(r, 'path')]
        
        print("\n" + "=" * 60)
        print("API Routes Summary")
        print("=" * 60)
        
        route_groups = {}
        for route in routes:
            path = route.path
            if '/api/v1/' in path:
                group = path.split('/api/v1/')[1].split('/')[0]
                if group not in route_groups:
                    route_groups[group] = []
                route_groups[group].append((path, list(route.methods)))
        
        for group, routes_list in sorted(route_groups.items()):
            print(f"\n[{group.upper()}] ({len(routes_list)} routes)")
            for path, methods in sorted(routes_list):
                print(f"  {methods[0]:6} {path}")
        
        print("\n" + "=" * 60)
        print(f"Total API routes: {len(routes)}")
        print("=" * 60)
        
        return True
    except Exception as e:
        print(f"[ERROR] Failed to test routes: {e}")
        return False


if __name__ == "__main__":
    print("\n")
    success1 = test_imports()
    success2 = test_routes()
    
    if success1 and success2:
        print("\n[SUCCESS] All tests passed!")
        sys.exit(0)
    else:
        print("\n[FAILED] Some tests failed")
        sys.exit(1)
