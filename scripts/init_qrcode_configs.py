#!/usr/bin/env python3
"""
初始化二维码配置脚本
创建系统配置表中的二维码相关配置项
"""

import asyncio
import sys
from pathlib import Path

# 添加项目根目录到路径
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from app.db.session import get_db
from app.db.models import SystemConfig
from sqlalchemy import select
from loguru import logger


async def init_qrcode_configs():
    """初始化二维码配置"""
    async for session in get_db():
        try:
            # 定义需要创建的配置项
            configs_to_create = [
                {
                    "config_key": "qrcode.max_scans",
                    "config_value": "3",
                    "description": "二维码最大扫码次数（0表示不限制）"
                },
                {
                    "config_key": "qrcode.encrypted_enabled",
                    "config_value": "true",
                    "description": "是否启用加密二维码模式"
                },
                {
                    "config_key": "qrcode.plain_enabled",
                    "config_value": "false",
                    "description": "是否启用明文二维码模式（与加密模式互斥）"
                }
            ]
            
            created_count = 0
            updated_count = 0
            
            for config_data in configs_to_create:
                # 检查配置是否已存在
                result = await session.execute(
                    select(SystemConfig).where(
                        SystemConfig.config_key == config_data["config_key"]
                    )
                )
                existing_config = result.scalar_one_or_none()
                
                if existing_config:
                    # 更新现有配置
                    existing_config.config_value = config_data["config_value"]
                    existing_config.description = config_data["description"]
                    updated_count += 1
                    logger.info(f"更新配置: {config_data['config_key']} = {config_data['config_value']}")
                else:
                    # 创建新配置
                    new_config = SystemConfig(
                        config_key=config_data["config_key"],
                        config_value=config_data["config_value"],
                        description=config_data["description"]
                    )
                    session.add(new_config)
                    created_count += 1
                    logger.info(f"创建配置: {config_data['config_key']} = {config_data['config_value']}")
            
            await session.commit()
            logger.success(f"二维码配置初始化完成: 创建 {created_count} 个，更新 {updated_count} 个")
            
            # 验证配置
            result = await session.execute(
                select(SystemConfig).where(
                    SystemConfig.config_key.like('qrcode.%')
                )
            )
            all_configs = result.scalars().all()
            logger.info(f"当前二维码配置数量: {len(all_configs)}")
            for config in all_configs:
                logger.info(f"  - {config.config_key}: {config.config_value}")
            
            break
            
        except Exception as e:
            await session.rollback()
            logger.error(f"初始化二维码配置失败: {e}", exc_info=True)
            raise
        finally:
            await session.close()


if __name__ == "__main__":
    logger.info("开始初始化二维码配置...")
    try:
        asyncio.run(init_qrcode_configs())
        logger.success("二维码配置初始化成功！")
        sys.exit(0)
    except Exception as e:
        logger.error(f"二维码配置初始化失败: {e}", exc_info=True)
        sys.exit(1)
