"""
操作日志记录模块
记录所有增删改查操作
"""

import json
from typing import Optional
from datetime import datetime
from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.models import OperationLog, User
from app.core.permissions import get_client_ip, get_user_agent


async def log_operation(
    db: AsyncSession,
    user: Optional[User],
    operation_type: str,  # create/read/update/delete
    resource_type: str,  # user/room/device等
    resource_id: Optional[int] = None,
    resource_name: Optional[str] = None,
    operation_detail: Optional[dict] = None,
    request: Optional[Request] = None
):
    """
    记录操作日志
    
    Args:
        db: 数据库会话
        user: 操作用户（可选）
        operation_type: 操作类型（create/read/update/delete）
        resource_type: 资源类型（user/room/device等）
        resource_id: 资源ID（可选）
        resource_name: 资源名称（可选）
        operation_detail: 操作详情字典（可选）
        request: FastAPI Request 对象（用于获取IP和User-Agent）
    """
    log = OperationLog(
        user_id=user.id if user else None,
        username=user.username if user else None,
        operation_type=operation_type,
        resource_type=resource_type,
        resource_id=resource_id,
        resource_name=resource_name,
        operation_detail=json.dumps(operation_detail, ensure_ascii=False) if operation_detail else None,
        ip_address=get_client_ip(request) if request else None,
        user_agent=get_user_agent(request) if request else None,
        created_at=datetime.utcnow()
    )
    
    db.add(log)
    # 注意：不在这里 commit，由调用者负责 commit
