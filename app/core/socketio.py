"""
Socket.io 服务器模块
实现增强型即时通讯：心跳监测、在线状态、系统指令下发
根据 Spec.txt：利用 Socket.io 实现增强型即时通讯
"""

import asyncio
from typing import Dict, Optional, Set
from datetime import datetime, timezone, timedelta
from loguru import logger
import socketio

from app.core.config import settings
from app.db.session import db
from app.db.models import User

# 创建 Socket.io 服务器实例
# 注意：对于 FastAPI，应该使用 'asgi' 模式
sio = socketio.AsyncServer(
    async_mode='asgi',
    cors_allowed_origins=settings.SOCKETIO_CORS_ORIGINS.split(",") if settings.SOCKETIO_CORS_ORIGINS else "*",
    logger=True,
    engineio_logger=True
)

# 创建 Socket.io 应用
socketio_app = socketio.ASGIApp(sio)

# 连接管理
# 存储格式：{user_id: {socket_id: session_info}}
connected_users: Dict[int, Dict[str, Dict]] = {}

# 心跳超时时间（秒）
HEARTBEAT_TIMEOUT = 60

# 心跳间隔（秒）
HEARTBEAT_INTERVAL = 30


# ==================== 连接事件处理 ====================

@sio.event
async def connect(sid, environ, auth):
    """
    客户端连接事件
    
    Args:
        sid: Socket ID
        environ: 环境信息
        auth: 认证信息（应包含 JWT token）
    """
    try:
        # 从认证信息中获取 token
        token = auth.get('token') if auth else None
        
        if not token:
            logger.warning(f"连接拒绝：Socket {sid} 未提供认证 token")
            return False
        
        # 验证 token 并获取用户信息
        from app.core.security import decode_token
        payload = decode_token(token)
        
        if not payload:
            logger.warning(f"连接拒绝：Socket {sid} 无效的 token")
            return False
        
        user_id_str = payload.get('sub')  # JWT payload 中的用户ID（字符串格式）
        
        if not user_id_str:
            logger.warning(f"连接拒绝：Socket {sid} token 中缺少用户ID")
            return False
        
        # 转换为整数
        try:
            user_id = int(user_id_str)
        except (ValueError, TypeError):
            logger.warning(f"连接拒绝：Socket {sid} 无效的用户ID格式")
            return False
        
        # 获取用户信息（使用异步数据库会话）
        from app.db.session import get_db
        from sqlalchemy import select
        
        user = None
        async for session in get_db():
            result = await session.execute(
                select(User).where(User.id == user_id)
            )
            user = result.scalar_one_or_none()
            break  # 只使用第一个会话
        
        if not user:
            logger.warning(f"连接拒绝：用户 {user_id} 不存在")
            return False
        
        # 存储连接信息
        if user_id not in connected_users:
            connected_users[user_id] = {}
        
        connected_users[user_id][sid] = {
            'user_id': user_id,
            'connected_at': datetime.now(timezone.utc),
            'last_heartbeat': datetime.now(timezone.utc),
            'user': user
        }
        
        # 更新用户在线状态
        await update_user_online_status(user_id, True)
        
        # 加入用户专属房间（用于定向推送）
        await sio.enter_room(sid, f"user_{user_id}")
        
        logger.info(f"用户 {user_id} (Socket {sid}) 已连接")
        
        # 发送连接成功消息
        await sio.emit('connected', {
            'message': '连接成功',
            'user_id': user_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, room=sid)
        
        # 广播用户上线通知（可选）
        await broadcast_user_status(user_id, True)
        
        return True
        
    except Exception as e:
        logger.error(f"连接处理错误：{e}", exc_info=True)
        return False


@sio.event
async def disconnect(sid):
    """
    客户端断开连接事件
    
    Args:
        sid: Socket ID
    """
    try:
        user_id = None
        
        # 查找并移除连接
        for uid, sockets in connected_users.items():
            if sid in sockets:
                user_id = uid
                del sockets[sid]
                
                # 如果用户没有其他连接，清空用户记录
                if not sockets:
                    del connected_users[uid]
                    # 更新用户离线状态
                    await update_user_online_status(uid, False)
                    # 广播用户下线通知
                    await broadcast_user_status(uid, False)
                break
        
        if user_id:
            logger.info(f"用户 {user_id} (Socket {sid}) 已断开连接")
        else:
            logger.warning(f"未找到 Socket {sid} 对应的用户")
            
    except Exception as e:
        logger.error(f"断开连接处理错误：{e}", exc_info=True)


# ==================== 心跳监测 ====================

@sio.event
async def ping(sid, data):
    """
    心跳检测（客户端发送 ping）
    
    Args:
        sid: Socket ID
        data: 心跳数据（可选）
    """
    try:
        # 更新最后心跳时间
        for uid, sockets in connected_users.items():
            if sid in sockets:
                sockets[sid]['last_heartbeat'] = datetime.now(timezone.utc)
                # 回复 pong
                await sio.emit('pong', {
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }, room=sid)
                return
        
        logger.warning(f"未找到 Socket {sid} 的心跳记录")
        
    except Exception as e:
        logger.error(f"心跳处理错误：{e}", exc_info=True)


async def check_heartbeat_timeout():
    """
    检查心跳超时
    定期检查所有连接的心跳时间，超时的连接将被断开
    """
    while True:
        try:
            current_time = datetime.now(timezone.utc)
            timeout_users = []
            
            for user_id, sockets in list(connected_users.items()):
                for sid, session_info in list(sockets.items()):
                    last_heartbeat = session_info.get('last_heartbeat')
                    if last_heartbeat:
                        elapsed = (current_time - last_heartbeat).total_seconds()
                        if elapsed > HEARTBEAT_TIMEOUT:
                            logger.warning(f"用户 {user_id} (Socket {sid}) 心跳超时，断开连接")
                            timeout_users.append((user_id, sid))
            
            # 断开超时的连接
            for user_id, sid in timeout_users:
                await sio.disconnect(sid)
            
            # 每 30 秒检查一次
            await asyncio.sleep(30)
            
        except Exception as e:
            logger.error(f"心跳检查错误：{e}", exc_info=True)
            await asyncio.sleep(30)


# ==================== 在线状态管理 ====================

async def update_user_online_status(user_id: int, is_online: bool):
    """
    更新用户在线状态到数据库
    
    Args:
        user_id: 用户ID
        is_online: 是否在线
    """
    try:
        from app.db.session import get_db
        from sqlalchemy import select
        from datetime import datetime, timezone
        
        async for session in get_db():
            result = await session.execute(
                select(User).where(User.id == user_id)
            )
            user = result.scalar_one_or_none()
            
            if user:
                user.is_online = is_online
                if is_online:
                    user.last_active_at = datetime.now(timezone.utc).replace(tzinfo=None)
                # updated_at 会通过事件监听器自动更新
                await session.commit()
                logger.debug(f"用户 {user_id} 在线状态已更新：{is_online}")
            break  # 只使用第一个会话
                
    except Exception as e:
        logger.error(f"更新用户在线状态错误：{e}", exc_info=True)


async def broadcast_user_status(user_id: int, is_online: bool):
    """
    广播用户在线状态变化
    
    Args:
        user_id: 用户ID
        is_online: 是否在线
    """
    try:
        # 广播到所有连接的客户端（除了用户自己）
        await sio.emit('user_status', {
            'user_id': user_id,
            'is_online': is_online,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, skip_sid=None)  # 发送给所有客户端
        
    except Exception as e:
        logger.error(f"广播用户状态错误：{e}", exc_info=True)


# ==================== 实时消息推送 ====================

@sio.event
async def send_message(sid, data):
    """
    发送消息（客户端 -> 服务器）
    
    Args:
        sid: Socket ID
        data: 消息数据 {target_user_id, message, type}
    """
    try:
        # 获取发送者信息
        sender_id = None
        for uid, sockets in connected_users.items():
            if sid in sockets:
                sender_id = uid
                break
        
        if not sender_id:
            await sio.emit('error', {
                'message': '未找到发送者信息'
            }, room=sid)
            return
        
        target_user_id = data.get('target_user_id')
        message = data.get('message')
        msg_type = data.get('type', 'text')
        
        if not target_user_id or not message:
            await sio.emit('error', {
                'message': '缺少必要参数'
            }, room=sid)
            return
        
        # 发送消息到目标用户
        await sio.emit('message', {
            'from_user_id': sender_id,
            'message': message,
            'type': msg_type,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, room=f"user_{target_user_id}")
        
        # 确认消息已发送
        await sio.emit('message_sent', {
            'target_user_id': target_user_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, room=sid)
        
    except Exception as e:
        logger.error(f"发送消息错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'发送消息失败：{str(e)}'
        }, room=sid)


# ==================== 系统指令下发 ====================

async def send_system_command(user_id: int, command: str, data: Optional[dict] = None):
    """
    向指定用户发送系统指令
    
    Args:
        user_id: 目标用户ID
        command: 指令名称
        data: 指令数据（可选）
    """
    try:
        if user_id in connected_users:
            await sio.emit('system_command', {
                'command': command,
                'data': data or {},
                'timestamp': datetime.now(timezone.utc).isoformat()
            }, room=f"user_{user_id}")
            logger.info(f"系统指令已发送到用户 {user_id}：{command}")
        else:
            logger.warning(f"用户 {user_id} 不在线，无法发送系统指令")
            
    except Exception as e:
        logger.error(f"发送系统指令错误：{e}", exc_info=True)


async def broadcast_system_message(message: str, target_user_id: Optional[int] = None):
    """
    广播系统消息
    
    Args:
        message: 消息内容
        target_user_id: 目标用户ID（如果为 None 则广播给所有用户）
    """
    try:
        if target_user_id:
            # 发送给指定用户
            await sio.emit('system_message', {
                'message': message,
                'timestamp': datetime.now(timezone.utc).isoformat()
            }, room=f"user_{target_user_id}")
        else:
            # 广播给所有用户
            await sio.emit('system_message', {
                'message': message,
                'timestamp': datetime.now(timezone.utc).isoformat()
            })
            
        logger.info(f"系统消息已发送：{message}")
        
    except Exception as e:
        logger.error(f"广播系统消息错误：{e}", exc_info=True)


# ==================== 工具函数 ====================

def get_online_users() -> Set[int]:
    """
    获取所有在线用户ID列表
    
    Returns:
        在线用户ID集合
    """
    return set(connected_users.keys())


def is_user_online(user_id: int) -> bool:
    """
    检查用户是否在线
    
    Args:
        user_id: 用户ID
    
    Returns:
        是否在线
    """
    return user_id in connected_users and len(connected_users[user_id]) > 0


def get_user_connections(user_id: int) -> int:
    """
    获取用户的连接数
    
    Args:
        user_id: 用户ID
    
    Returns:
        连接数
    """
    return len(connected_users.get(user_id, {}))


# ==================== 启动心跳监测任务 ====================

def start_heartbeat_monitor():
    """
    启动心跳监测任务
    应该在应用启动时调用
    """
    asyncio.create_task(check_heartbeat_timeout())
    logger.info("心跳监测任务已启动")
