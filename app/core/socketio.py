"""
Socket.io 服务器模块
实现增强型即时通讯：心跳监测、在线状态、系统指令下发
根据 Spec.txt：利用 Socket.io 实现增强型即时通讯
"""

import asyncio
from typing import Dict, Optional, Set, List
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
        data: 消息数据 {target_user_id, room_id, message, type}
            支持点对点消息（target_user_id）和房间群聊（room_id）
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
        room_id = data.get('room_id')
        message = data.get('message')
        msg_type = data.get('type', 'text')
        
        # 必须指定 target_user_id（点对点）或 room_id（群聊）之一
        if not message:
            await sio.emit('error', {
                'message': '缺少消息内容'
            }, room=sid)
            return
        
        if not target_user_id and not room_id:
            await sio.emit('error', {
                'message': '必须指定 target_user_id（点对点）或 room_id（群聊）'
            }, room=sid)
            return
        
        # 保存消息到数据库
        from app.db.session import get_db
        from app.db.models import Message
        from sqlalchemy import select
        
        db_message = None
        async for session in get_db():
            try:
                # 创建消息记录
                db_message = Message(
                    sender_id=sender_id,
                    receiver_id=target_user_id if target_user_id else None,
                    room_id=room_id if room_id else None,
                    message=message,
                    message_type=msg_type,
                    is_read=False
                )
                session.add(db_message)
                await session.commit()
                await session.refresh(db_message)
                logger.info(f"消息已保存到数据库: ID={db_message.id}, sender={sender_id}, receiver={target_user_id}, room={room_id}")
                break
            except Exception as db_error:
                await session.rollback()
                logger.error(f"保存消息到数据库失败: {db_error}", exc_info=True)
                # 继续执行，即使数据库保存失败也尝试发送实时消息
        
        # 发送实时消息
        if target_user_id:
            # 点对点消息：发送给目标用户和发送者自己（如果在线）
            message_data = {
                'id': db_message.id if db_message else None,
                'from_user_id': sender_id,  # 兼容字段
                'sender_id': sender_id,  # 统一字段名
                'receiver_id': target_user_id,  # 接收者ID
                'message': message,
                'type': msg_type,
                'message_type': msg_type,  # 兼容字段
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'created_at': datetime.now(timezone.utc).isoformat()  # 兼容字段
            }
            
            # 发送给接收者
            await sio.emit('message', message_data, room=f"user_{target_user_id}")
            
            # 也发送给发送者自己（如果在线），以便实时显示
            if sender_id in connected_users:
                await sio.emit('message', message_data, room=f"user_{sender_id}")
        elif room_id:
            # 房间群聊：发送给房间内所有参与者
            # 获取房间参与者
            async for session in get_db():
                try:
                    from app.db.models import RoomParticipant
                    result = await session.execute(
                        select(RoomParticipant).where(
                            RoomParticipant.room_id == room_id,
                            RoomParticipant.is_active == True
                        )
                    )
                    participants = result.scalars().all()
                    
                    # 发送给所有参与者（包括发送者自己）
                    for participant in participants:
                        await sio.emit('message', {
                            'id': db_message.id if db_message else None,
                            'from_user_id': sender_id,  # 兼容字段
                            'sender_id': sender_id,  # 统一字段名
                            'room_id': room_id,
                            'message': message,
                            'type': msg_type,  # 兼容字段
                            'message_type': msg_type,  # 统一字段名
                            'timestamp': datetime.now(timezone.utc).isoformat(),
                            'created_at': datetime.now(timezone.utc).isoformat()  # 兼容字段
                        }, room=f"user_{participant.user_id}")
                    break
                except Exception as e:
                    logger.error(f"获取房间参与者失败: {e}", exc_info=True)
                    break
        
        # 确认消息已发送
        await sio.emit('message_sent', {
            'message_id': db_message.id if db_message else None,
            'target_user_id': target_user_id,
            'room_id': room_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, room=sid)
        
    except Exception as e:
        logger.error(f"发送消息错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'发送消息失败：{str(e)}'
        }, room=sid)


@sio.event
async def mark_message_read(sid, data):
    """
    标记消息为已读（客户端 -> 服务器）
    
    Args:
        sid: Socket ID
        data: 消息数据 {message_ids: [id1, id2, ...]}
    """
    try:
        # 获取当前用户信息
        current_user_id = None
        for uid, sockets in connected_users.items():
            if sid in sockets:
                current_user_id = uid
                break
        
        if not current_user_id:
            await sio.emit('error', {
                'message': '未找到用户信息'
            }, room=sid)
            return
        
        message_ids = data.get('message_ids', [])
        if not message_ids:
            await sio.emit('error', {
                'message': '缺少消息ID列表'
            }, room=sid)
            return
        
        # 更新消息已读状态
        from app.db.session import get_db
        from app.db.models import Message
        from sqlalchemy import select, update
        
        updated_count = 0
        # 获取 UTC 时间（不带时区）- 数据库字段是 TIMESTAMP WITHOUT TIME ZONE
        # 使用 datetime.utcnow() 直接获取不带时区的 UTC 时间，避免时区转换问题
        now_naive = datetime.utcnow()  # 直接返回 naive datetime，无时区信息
        now_utc = datetime.now(timezone.utc)  # 用于前端显示的 ISO 格式时间戳
        
        async for session in get_db():
            try:
                # 使用 SQLAlchemy 的 update() 直接更新，避免 ORM 对象的时区转换问题
                # 直接执行 UPDATE 语句，确保 datetime 值不带时区
                update_stmt = (
                    update(Message)
                    .where(
                        Message.id.in_(message_ids),
                        Message.receiver_id == current_user_id,
                        Message.is_read == False
                    )
                    .values(
                        is_read=True,
                        read_at=now_naive  # 使用不带时区的 datetime
                    )
                )
                
                result = await session.execute(update_stmt)
                updated_count = result.rowcount
                
                await session.commit()
                logger.info(f"用户 {current_user_id} 标记了 {updated_count} 条消息为已读")
                
                # 查询已更新的消息，用于通知发送者
                if updated_count > 0:
                    result = await session.execute(
                        select(Message).where(
                            Message.id.in_(message_ids),
                            Message.receiver_id == current_user_id,
                            Message.is_read == True
                        )
                    )
                    messages = result.scalars().all()
                    
                    # 通知发送者消息已读（点对点消息）
                    for msg in messages:
                        if msg.sender_id and msg.receiver_id:  # 点对点消息
                            await sio.emit('message_read', {
                                'message_id': msg.id,
                                'read_by': current_user_id,
                                'read_at': now_utc.isoformat()  # 使用带时区的 UTC 时间（用于前端显示）
                            }, room=f"user_{msg.sender_id}")
                
                break
            except Exception as db_error:
                await session.rollback()
                logger.error(f"标记消息已读失败: {db_error}", exc_info=True)
                await sio.emit('error', {
                    'message': f'标记已读失败：{str(db_error)}'
                }, room=sid)
        
        # 确认已读操作
        await sio.emit('message_read_confirmed', {
            'updated_count': updated_count,
            'message_ids': message_ids,
            'timestamp': now_utc.isoformat()  # 使用带时区的 UTC 时间（用于前端显示）
        }, room=sid)
        
    except Exception as e:
        logger.error(f"标记消息已读错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'标记已读失败：{str(e)}'
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


# ==================== 实时通知功能 ====================

async def send_notification(user_id: int, notification_data: dict):
    """
    向指定用户发送实时通知
    
    Args:
        user_id: 目标用户ID
        notification_data: 通知数据
    """
    try:
        if user_id in connected_users:
            await sio.emit('notification', notification_data, room=f"user_{user_id}")
            logger.info(f"通知已发送到用户 {user_id}: {notification_data.get('type')}")
        else:
            logger.debug(f"用户 {user_id} 不在线，通知将保存在数据库中")
    except Exception as e:
        logger.error(f"发送通知错误：{e}", exc_info=True)


async def broadcast_notification(notification_data: dict, target_user_ids: Optional[List[int]] = None):
    """
    广播通知
    
    Args:
        notification_data: 通知数据
        target_user_ids: 目标用户ID列表（如果为 None 则广播给所有在线用户）
    """
    try:
        if target_user_ids:
            for user_id in target_user_ids:
                if user_id in connected_users:
                    await sio.emit('notification', notification_data, room=f"user_{user_id}")
        else:
            # 广播给所有在线用户
            await sio.emit('notification', notification_data)
        logger.info(f"通知已广播: {notification_data.get('type')}")
    except Exception as e:
        logger.error(f"广播通知错误：{e}", exc_info=True)


@sio.event
async def get_online_friends(sid, data):
    """
    获取在线好友列表（客户端请求）
    
    Args:
        sid: Socket ID
        data: 请求数据（可选）
    """
    try:
        # 获取当前用户ID
        current_user_id = None
        for uid, sockets in connected_users.items():
            if sid in sockets:
                current_user_id = uid
                break
        
        if not current_user_id:
            await sio.emit('error', {
                'message': '未找到用户信息'
            }, room=sid)
            return
        
        # 获取好友列表（从数据库）
        from app.db.session import get_db
        from app.db.models import Friendship
        from sqlalchemy import select, or_
        
        online_friends = []
        async for session in get_db():
            try:
                # 查询好友关系
                result = await session.execute(
                    select(Friendship).where(
                        or_(
                            Friendship.user_id == current_user_id,
                            Friendship.friend_id == current_user_id
                        ),
                        Friendship.status == "accepted"
                    )
                )
                friendships = result.scalars().all()
                
                # 获取在线好友
                for friendship in friendships:
                    friend_id = friendship.friend_id if friendship.user_id == current_user_id else friendship.user_id
                    if friend_id in connected_users:
                        online_friends.append(friend_id)
                
                break
            except Exception as e:
                logger.error(f"获取在线好友失败: {e}", exc_info=True)
                break
        
        # 发送在线好友列表
        await sio.emit('online_friends', {
            'friends': online_friends,
            'count': len(online_friends),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, room=sid)
        
    except Exception as e:
        logger.error(f"获取在线好友错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'获取在线好友失败：{str(e)}'
        }, room=sid)


@sio.event
async def call_invitation(sid, data):
    """
    发送通话邀请（客户端 -> 服务器 -> 目标用户）
    
    Args:
        sid: Socket ID
        data: 邀请数据 {target_user_id, room_id, room_url, jitsi_token, jitsi_server_url, caller_name}
    """
    try:
        logger.info(f"收到通话邀请请求，Socket ID: {sid}, 数据: {data}")
        
        # 获取发送者信息
        sender_id = None
        sender_nickname = None
        for uid, sockets in connected_users.items():
            if sid in sockets:
                sender_id = uid
                user_obj = sockets[sid].get('user')
                if user_obj:
                    sender_nickname = getattr(user_obj, 'nickname', None)
                break
        
        if not sender_id:
            logger.error(f"未找到发送者信息，Socket ID: {sid}")
            await sio.emit('error', {
                'message': '未找到发送者信息'
            }, room=sid)
            return
        
        logger.info(f"发送者ID: {sender_id}, 昵称: {sender_nickname}")
        
        target_user_id = data.get('target_user_id')
        room_id = data.get('room_id')
        
        if not target_user_id:
            logger.error(f"缺少目标用户ID，发送者: {sender_id}")
            await sio.emit('error', {
                'message': '缺少目标用户ID'
            }, room=sid)
            return
        
        if not room_id:
            logger.error(f"缺少房间ID，发送者: {sender_id}")
            await sio.emit('error', {
                'message': '缺少房间ID'
            }, room=sid)
            return
        
        logger.info(f"目标用户ID: {target_user_id}, 房间ID: {room_id}")
        logger.info(f"当前在线用户: {list(connected_users.keys())}")
        
        # 验证目标用户是否在线
        if target_user_id not in connected_users:
            logger.warning(f"用户 {target_user_id} 不在线，无法发送通话邀请。当前在线用户: {list(connected_users.keys())}")
            await sio.emit('error', {
                'message': '对方不在线，无法发送通话邀请'
            }, room=sid)
            return
        
        # 发送通话邀请给目标用户
        invitation_data = {
            'room_id': room_id,
            'room_url': data.get('room_url'),
            'jitsi_token': data.get('jitsi_token'),
            'jitsi_server_url': data.get('jitsi_server_url'),
            'caller_id': sender_id,
            'caller_name': data.get('caller_name') or sender_nickname or f'用户{sender_id}',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        logger.info(f"向用户 {target_user_id} 发送通话邀请，房间: user_{target_user_id}, 数据: {invitation_data}")
        
        # 检查目标用户的所有连接
        target_sockets = connected_users.get(target_user_id, {})
        logger.info(f"目标用户 {target_user_id} 的连接数: {len(target_sockets)}")
        if target_sockets:
            logger.info(f"目标用户 {target_user_id} 的 Socket IDs: {list(target_sockets.keys())}")
        
        # 发送邀请给目标用户
        await sio.emit('call_invitation', invitation_data, room=f"user_{target_user_id}")
        
        logger.info(f"✓ 用户 {sender_id} 向用户 {target_user_id} 发送了通话邀请，房间ID: {room_id}")
        logger.info(f"✓ 邀请已通过房间 user_{target_user_id} 发送")
        
        # 确认邀请已发送
        confirm_data = {
            'target_user_id': target_user_id,
            'room_id': room_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        logger.info(f"向发送者 {sender_id} 发送确认，Socket ID: {sid}, 数据: {confirm_data}")
        await sio.emit('call_invitation_sent', confirm_data, room=sid)
        
    except Exception as e:
        logger.error(f"发送通话邀请错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'发送通话邀请失败：{str(e)}'
        }, room=sid)


@sio.event
async def call_invitation_response(sid, data):
    """
    通话邀请响应（接受/拒绝）
    
    Args:
        sid: Socket ID
        data: 响应数据 {room_id, accepted}
    """
    try:
        # 获取当前用户ID
        current_user_id = None
        for uid, sockets in connected_users.items():
            if sid in sockets:
                current_user_id = uid
                break
        
        if not current_user_id:
            await sio.emit('error', {
                'message': '未找到用户信息'
            }, room=sid)
            return
        
        room_id = data.get('room_id')
        accepted = data.get('accepted', False)
        
        if not room_id:
            await sio.emit('error', {
                'message': '缺少房间ID'
            }, room=sid)
            return
        
        # 这里可以记录邀请响应，或者通知发起者（如果需要）
        logger.info(f"用户 {current_user_id} 对房间 {room_id} 的通话邀请响应: {'接受' if accepted else '拒绝'}")
        
    except Exception as e:
        logger.error(f"处理通话邀请响应错误：{e}", exc_info=True)
        await sio.emit('error', {
            'message': f'处理通话邀请响应失败：{str(e)}'
        }, room=sid)


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
