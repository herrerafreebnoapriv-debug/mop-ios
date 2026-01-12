"""测试数据库连接"""
import asyncio
from app.db.session import db

async def test():
    try:
        db.initialize()
        print("[OK] Database connection OK")
        await db.disconnect()
    except Exception as e:
        print(f"[ERROR] Database connection failed: {e}")

if __name__ == "__main__":
    asyncio.run(test())
