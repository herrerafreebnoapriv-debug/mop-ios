#!/usr/bin/env python3
"""
清除所有聊天记录（仅消息，保留好友关系）
"""
import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy import text, select, func
from app.db.session import get_db


async def clear_all_chat_messages():
    """清除所有聊天记录"""
    async for db in get_db():
        try:
            # 先统计消息数量
            count_result = await db.execute(text("SELECT COUNT(*) FROM messages"))
            total_messages = count_result.scalar()
            
            if total_messages == 0:
                print("✅ 数据库中没有聊天记录，无需清理")
                return
            
            print(f"发现 {total_messages} 条聊天记录，开始清理...")
            
            # 清除所有聊天记录
            result = await db.execute(text("DELETE FROM messages"))
            deleted_messages = result.rowcount
            
            # 提交事务
            await db.commit()
            
            print(f"\n✅ 清理完成！")
            print(f"   - 已删除聊天记录: {deleted_messages} 条")
            print(f"   - 好友关系已保留")
            
        except Exception as e:
            await db.rollback()
            print(f"❌ 清理失败: {e}")
            import traceback
            traceback.print_exc()
            raise
        finally:
            break  # get_db() 是生成器，只使用第一个会话


if __name__ == "__main__":
    print("=" * 50)
    print("清除所有聊天记录")
    print("=" * 50)
    print("⚠️  警告：此操作将永久删除所有聊天记录，且无法恢复！")
    print("")
    
    # 确认操作
    confirm = input("确认清除所有聊天记录？(输入 'yes' 确认): ")
    if confirm.lower() != 'yes':
        print("操作已取消")
        sys.exit(0)
    
    asyncio.run(clear_all_chat_messages())
