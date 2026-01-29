#!/usr/bin/env python3
"""
清理所有用户的聊天记录和好友关系
"""
import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy import text
from app.db.session import get_db


async def clear_all_chat_and_friends():
    """清理所有聊天记录和好友关系"""
    async for db in get_db():
        try:
            print("开始清理数据...")
            
            # 清理所有聊天记录
            result = await db.execute(text("DELETE FROM messages"))
            deleted_messages = result.rowcount
            print(f"✓ 已删除 {deleted_messages} 条聊天记录")
            
            # 清理所有好友关系
            result = await db.execute(text("DELETE FROM friendships"))
            deleted_friendships = result.rowcount
            print(f"✓ 已删除 {deleted_friendships} 条好友关系")
            
            # 提交事务
            await db.commit()
            print("\n✅ 清理完成！")
            print(f"   - 聊天记录: {deleted_messages} 条")
            print(f"   - 好友关系: {deleted_friendships} 条")
            
        except Exception as e:
            await db.rollback()
            print(f"❌ 清理失败: {e}")
            raise
        finally:
            break  # get_db() 是生成器，只使用第一个会话


if __name__ == "__main__":
    asyncio.run(clear_all_chat_and_friends())
