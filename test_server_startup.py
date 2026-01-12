"""测试服务器启动"""
import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
sys.path.insert(0, str(Path(__file__).parent))

async def test_startup():
    """测试应用启动"""
    try:
        print("1. Testing imports...")
        from app.core.config import settings
        print(f"   ✓ Config loaded: {settings.APP_NAME}")
        
        print("2. Testing database connection...")
        from app.db.session import db
        db.initialize()
        print("   ✓ Database initialized")
        
        print("3. Testing app creation...")
        from app.main import app
        print("   ✓ App created successfully")
        
        print("\n✓ All checks passed! Server should start successfully.")
        print(f"\nStart server with:")
        print(f"  python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload")
        print(f"\nThen visit:")
        print(f"  http://127.0.0.1:8000/demo")
        
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(test_startup())
