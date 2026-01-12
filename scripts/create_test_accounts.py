"""
创建测试账户脚本
用于初始化系统测试账户和管理员账户
"""

import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.db.session import db
from app.db.models import User
from datetime import datetime
from sqlalchemy import select
import bcrypt

def hash_password(password: str) -> str:
    """使用 bcrypt 直接哈希密码"""
    # 生成盐并哈希密码
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


async def create_test_accounts():
    """创建测试账户"""
    try:
        # 初始化数据库连接
        await db.initialize()
        
        # 创建异步会话
        async with db.get_session() as session:
            # 1. 创建后台管理总账户
            admin_username = "zhanan089"
            admin_password = "zn666@"
            admin_phone = "13800000000"  # 使用一个特殊的手机号
            
            # 检查管理员账户是否已存在
            result = await session.execute(
                select(User).where(User.username == admin_username)
            )
            existing_admin = result.scalar_one_or_none()
            
            if existing_admin:
                print(f"[INFO] 管理员账户 '{admin_username}' 已存在")
                # 更新现有账户为超级管理员
                if existing_admin.role != "super_admin" or not existing_admin.is_admin:
                    existing_admin.role = "super_admin"
                    existing_admin.is_admin = True
                    await session.commit()
                    await session.refresh(existing_admin)
                    print(f"[SUCCESS] 已更新账户为超级管理员:")
                    print(f"  角色: {existing_admin.role}")
                    print(f"  管理员权限: {existing_admin.is_admin}")
                else:
                    print(f"[INFO] 账户已经是超级管理员，无需更新")
            else:
                admin_user = User(
                    phone=admin_phone,
                    username=admin_username,
                    password_hash=hash_password(admin_password),
                    nickname="系统管理员",
                    is_admin=True,  # 设置为管理员
                    role="super_admin",  # 设置为超级管理员角色
                    agreed_at=datetime.utcnow(),  # 自动同意免责声明
                    language="zh_CN",
                    first_used_at=datetime.utcnow(),
                    last_active_at=datetime.utcnow()
                )
                session.add(admin_user)
                await session.commit()
                await session.refresh(admin_user)
                print(f"[SUCCESS] 管理员账户创建成功:")
                print(f"  用户名: {admin_username}")
                print(f"  密码: {admin_password}")
                print(f"  手机号: {admin_phone}")
                print(f"  用户ID: {admin_user.id}")
                print(f"  角色: {admin_user.role}")
                print(f"  管理员权限: {admin_user.is_admin}")
            
            # 2. 创建前端测试账户
            test_username = "zn6666"
            test_password = "zn6666"
            test_phone = "13900000000"  # 使用另一个特殊的手机号
            
            # 检查测试账户是否已存在
            result = await session.execute(
                select(User).where(User.username == test_username)
            )
            existing_test = result.scalar_one_or_none()
            
            if existing_test:
                print(f"[INFO] 测试账户 '{test_username}' 已存在，跳过创建")
            else:
                test_user = User(
                    phone=test_phone,
                    username=test_username,
                    password_hash=hash_password(test_password),
                    nickname="测试用户",
                    is_admin=False,  # 普通用户
                    agreed_at=datetime.utcnow(),  # 自动同意免责声明
                    language="zh_CN",
                    first_used_at=datetime.utcnow(),
                    last_active_at=datetime.utcnow()
                )
                session.add(test_user)
                await session.commit()
                await session.refresh(test_user)
                print(f"[SUCCESS] 测试账户创建成功:")
                print(f"  用户名: {test_username}")
                print(f"  密码: {test_password}")
                print(f"  手机号: {test_phone}")
                print(f"  用户ID: {test_user.id}")
                print(f"  管理员权限: {test_user.is_admin}")
            
            print("\n[INFO] 账户创建完成！")
            print("\n账户信息汇总:")
            print("=" * 60)
            print("1. 后台管理总账户:")
            print(f"   用户名: {admin_username}")
            print(f"   密码: {admin_password}")
            print(f"   手机号: {admin_phone}")
            print(f"   用途: 后台管理系统登录")
            print("=" * 60)
            print("2. 前端测试账户:")
            print(f"   用户名: {test_username}")
            print(f"   密码: {test_password}")
            print(f"   手机号: {test_phone}")
            print(f"   用途: 前端功能测试")
            print("=" * 60)
            
    except Exception as e:
        print(f"[ERROR] 创建账户时出错: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        await db.close()


if __name__ == "__main__":
    print("=" * 60)
    print("MOP 系统 - 测试账户创建脚本")
    print("=" * 60)
    print()
    asyncio.run(create_test_accounts())
