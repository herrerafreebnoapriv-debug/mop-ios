"""
设置超级管理员脚本
用于将现有用户设置为超级管理员
"""

import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.db.session import db
from app.db.models import User
from sqlalchemy import select
from app.core.permissions import SUPER_ADMIN_USERNAME, ROLE_SUPER_ADMIN


async def set_super_admin(username: str = None):
    """
    设置用户为超级管理员
    
    Args:
        username: 用户名，如果不提供则使用默认的超级管理员用户名
    """
    try:
        # 初始化数据库连接
        await db.initialize()
        
        # 创建异步会话
        async with db.get_session() as session:
            target_username = username or SUPER_ADMIN_USERNAME
            
            # 查找用户
            result = await session.execute(
                select(User).where(User.username == target_username)
            )
            user = result.scalar_one_or_none()
            
            if not user:
                print(f"[ERROR] 用户 '{target_username}' 不存在")
                return False
            
            # 检查是否已经是超级管理员
            if user.role == ROLE_SUPER_ADMIN and user.is_admin:
                print(f"[INFO] 用户 '{target_username}' 已经是超级管理员")
                print(f"  角色: {user.role}")
                print(f"  管理员权限: {user.is_admin}")
                return True
            
            # 设置为超级管理员
            old_role = user.role
            old_is_admin = user.is_admin
            
            user.role = ROLE_SUPER_ADMIN
            user.is_admin = True
            
            await session.commit()
            await session.refresh(user)
            
            print(f"[SUCCESS] 用户 '{target_username}' 已设置为超级管理员")
            print(f"  用户ID: {user.id}")
            print(f"  用户名: {user.username}")
            print(f"  手机号: {user.phone}")
            print(f"  旧角色: {old_role}")
            print(f"  新角色: {user.role}")
            print(f"  旧管理员权限: {old_is_admin}")
            print(f"  新管理员权限: {user.is_admin}")
            
            return True
            
    except Exception as e:
        print(f"[ERROR] 设置超级管理员时出错: {e}")
        import traceback
        traceback.print_exc()
        return False
    finally:
        await db.close()


async def list_all_users():
    """列出所有用户及其权限"""
    try:
        await db.initialize()
        
        async with db.get_session() as session:
            result = await session.execute(select(User))
            users = result.scalars().all()
            
            print("\n" + "=" * 80)
            print("用户列表")
            print("=" * 80)
            print(f"{'ID':<5} {'用户名':<20} {'手机号':<15} {'角色':<15} {'管理员':<10}")
            print("-" * 80)
            
            for user in users:
                role = user.role or "user"
                is_admin = "是" if user.is_admin else "否"
                username = user.username or "-"
                phone = user.phone or "-"
                
                print(f"{user.id:<5} {username:<20} {phone:<15} {role:<15} {is_admin:<10}")
            
            print("=" * 80)
            
    except Exception as e:
        print(f"[ERROR] 列出用户时出错: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await db.close()


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="设置超级管理员")
    parser.add_argument("--username", "-u", type=str, help="要设置为超级管理员的用户名（默认: zhanan089）")
    parser.add_argument("--list", "-l", action="store_true", help="列出所有用户")
    
    args = parser.parse_args()
    
    if args.list:
        asyncio.run(list_all_users())
    else:
        print("=" * 60)
        print("MOP 系统 - 设置超级管理员脚本")
        print("=" * 60)
        print()
        
        username = args.username or SUPER_ADMIN_USERNAME
        success = asyncio.run(set_super_admin(username))
        
        if success:
            print("\n[INFO] 操作完成！")
        else:
            print("\n[ERROR] 操作失败！")
            sys.exit(1)
