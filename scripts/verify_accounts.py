"""验证测试账户"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.db.session import db
from app.db.models import User
from sqlalchemy import select


async def verify_accounts():
    """验证账户是否存在"""
    db.initialize()
    
    try:
        async with db.async_session_maker() as session:
            result = await session.execute(
                select(User).where(User.username.in_(['zhanan089', 'zn6666']))
            )
            users = result.scalars().all()
            
            print("=" * 60)
            print("账户验证结果")
            print("=" * 60)
            
            if len(users) == 0:
                print("[WARNING] 未找到任何测试账户")
                print("请运行: python scripts/create_test_accounts.py")
                return False
            
            for user in users:
                print(f"\n账户: {user.username}")
                print(f"  用户ID: {user.id}")
                print(f"  手机号: {user.phone}")
                print(f"  管理员: {'是' if user.is_admin else '否'}")
                print(f"  已同意免责声明: {'是' if user.agreed_at else '否'}")
                print(f"  语言偏好: {user.language}")
                print(f"  创建时间: {user.created_at}")
            
            print("\n" + "=" * 60)
            print(f"[SUCCESS] 找到 {len(users)} 个账户")
            print("=" * 60)
            return True
            
    except Exception as e:
        print(f"[ERROR] 验证失败: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        await db.close()


if __name__ == "__main__":
    success = asyncio.run(verify_accounts())
    sys.exit(0 if success else 1)
