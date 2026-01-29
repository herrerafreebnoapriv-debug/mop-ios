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
# 统一使用 Engine.IO 心跳，不再维护应用层 ping/pong 与超时任务
# 缩短离线判定：约 20+40=60s 内无 pong 即断开并触发 disconnect，在线状态及时更新
sio = socketio.AsyncServer(
    async_mode='asgi',
    cors_allowed_origins=settings.SOCKETIO_CORS_ORIGINS.split(",") if settings.SOCKETIO_CORS_ORIGINS else "*",
    logger=True,
    engineio_logger=True,
    ping_interval=20,  # 每 20 秒发 ping
    ping_timeout=40,   # 40 秒内未收到 pong 则断开（离线判定约 60s）
    max_http_buffer_size=1e8  # 100MB，支持大文件传输
)

# 创建 Socket.io 应用
socketio_app = socketio.ASGIApp(sio)

# 连接管理
# 存储格式：{user_id: {socket_id: session_info}}
connected_users: Dict[int, Dict[str, Dict]] = {}

# 离线判定已统一由 Engine.IO 的 ping_interval/ping_timeout 负责，不再使用应用层超时任务


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


# 心跳由 Engine.IO 的 ping_interval/ping_timeout 统一处理，断开时触发 disconnect 并更新在线状态
# 不再使用应用层 ping/pong 事件与超时检查任务，避免双重心跳逻辑不一致


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
        # 优先使用 message_type，其次使用 type，最后默认为 text
        msg_type = data.get('message_type') or data.get('type', 'text')
        is_original = data.get('is_original', False)  # 标记是否为需要转储的文件（图片/语音/文件）
        file_name = (data.get('file_name') or '').strip()
        file_size = data.get('file_size', 0)
        file_url = (data.get('file_url') or '').strip()
        duration = data.get('duration')  # 语音/视频时长（秒）
        
        # 语音消息兜底：file_name 为 voice.webm 且为文件消息时，强制设为 audio
        if file_name == 'voice.webm' and msg_type not in ('audio', 'voice'):
            msg_type = 'audio'
        
        # 必须指定 target_user_id（点对点）或 room_id（群聊）之一
        if not target_user_id and not room_id:
            await sio.emit('error', {
                'message': '必须指定 target_user_id（点对点）或 room_id（群聊）'
            }, room=sid)
            return
        
        # 消息内容校验：文本/图片需有 message；文件/音频/视频可仅有 file_url（HTTP 上传成功时 message 为空）
        has_message = message is not None and (not isinstance(message, str) or message.strip())
        has_file_url = file_url and str(file_url).strip() and msg_type in ('file', 'audio', 'video')
        if not has_message and not has_file_url:
            await sio.emit('error', {
                'message': '缺少消息内容'
            }, room=sid)
            return
        if message is None:
            message = ''

        # 检查是否需要转储大文件
        message_content = message
        file_info = None
        should_dump = False
        is_large_file = False
        
        if isinstance(message, str) and message.startswith('data:'):
            message_size = len(message)
            # 超过阈值，必须转储
            from app.core.file_dump import MESSAGE_SIZE_THRESHOLD, dump_large_file_to_storage
            if message_size > MESSAGE_SIZE_THRESHOLD:
                should_dump = True
                is_large_file = True
                logger.info(f"检测到大文件消息，大小: {message_size} 字节，开始转储...")
            # 标记为需要转储的文件（HTTP上传失败），主动转储以节省网络开销
            elif is_original:
                should_dump = True
                logger.info(f"检测到需要转储的文件消息（HTTP上传失败），类型: {msg_type}, 大小: {message_size} 字节，主动转储以节省网络开销...")
        
        if should_dump:
            # 转储文件到服务器存储
            file_info = await dump_large_file_to_storage(message, sender_id, msg_type, file_name)
            
            if file_info:
                # 对于图片：保留原始 base64 数据作为缩略图
                # 对于语音/文件：清空 message，只保留 file_url
                if msg_type == 'image':
                    message_content = message  # 保留原始 base64 数据作为缩略图
                    logger.info(f"图片已转储，保留 base64 作为缩略图，file_url: {file_info.get('file_url')}")
                else:
                    message_content = ''  # 语音/文件不保留 base64，只使用 file_url
                    logger.info(f"{msg_type}文件已转储，file_url: {file_info.get('file_url')}")
            else:
                logger.warning("文件转储失败，将尝试发送原始数据（可能超过 Socket.io 限制）")
        
        # 保存消息到数据库
        from app.db.session import get_db
        from app.db.models import Message
        from sqlalchemy import select
        
        db_message = None
        async for session in get_db():
            try:
                # 创建消息记录（使用处理后的消息内容）
                db_message = Message(
                    sender_id=sender_id,
                    receiver_id=target_user_id if target_user_id else None,
                    room_id=room_id if room_id else None,
                    message=message_content,  # 使用处理后的内容（可能是 file_url）
                    message_type=msg_type,
                    is_read=False
                )
                
                # 如果转储成功，添加文件信息
                if file_info:
                    db_message.file_id = file_info.get('file_id')
                    db_message.file_url = file_info.get('file_url', '')
                    db_message.file_name = file_info.get('file_name', file_name) or file_name
                    db_message.file_size = file_info.get('file_size', file_size) or file_size
                # 如果客户端已经通过 HTTP 上传了文件（提供了 file_url），使用客户端的 file_url
                elif file_url and file_url.strip():
                    db_message.file_url = file_url
                    db_message.file_name = file_name or ('voice.webm' if msg_type == 'audio' else 'image')
                    db_message.file_size = file_size or 0
                    logger.info(f"使用客户端提供的 file_url: {file_url}, file_name: {file_name}, file_size: {file_size}")
                if duration is not None:
                    try:
                        db_message.duration = int(duration)
                    except (TypeError, ValueError):
                        pass
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
                'message': message_content,  # 使用处理后的内容
                'type': msg_type,
                'message_type': msg_type,  # 兼容字段
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'created_at': datetime.now(timezone.utc).isoformat()  # 兼容字段
            }
            
            # 如果转储成功，添加文件信息
            if file_info:
                message_data['file_id'] = file_info.get('file_id')
                message_data['file_url'] = file_info.get('file_url', '')
                message_data['file_name'] = file_info.get('file_name', file_name) or file_name
                message_data['file_size'] = file_info.get('file_size', file_size) or file_size
                message_data['is_original'] = is_original  # 标记是否为需要转储的文件（用于前端更新）
                if file_info.get('mime_type'):
                    message_data['mime_type'] = file_info.get('mime_type')
                
                # 保留原始 base64 作为缩略图（message_content 已经是原始 base64）
                message_data['message'] = message_content  # 缩略图 base64
            # 如果客户端已经通过 HTTP 上传了文件（提供了 file_url），添加文件信息
            elif file_url and file_url.strip():
                message_data['file_url'] = file_url
                message_data['file_name'] = file_name or ('image' if msg_type == 'image' else ('voice.webm' if msg_type == 'audio' else 'file'))
                message_data['file_size'] = file_size or 0
                logger.info(f"返回消息时添加 file_url: {file_url}, file_name: {file_name}, file_size: {file_size}")
            if duration is not None:
                try:
                    message_data['duration'] = int(duration)
                except (TypeError, ValueError):
                    pass
            
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
                    room_message_data = {
                        'id': db_message.id if db_message else None,
                        'from_user_id': sender_id,  # 兼容字段
                        'sender_id': sender_id,  # 统一字段名
                        'room_id': room_id,
                        'message': message_content,  # 使用处理后的内容
                        'type': msg_type,  # 兼容字段
                        'message_type': msg_type,  # 统一字段名
                        'timestamp': datetime.now(timezone.utc).isoformat(),
                        'created_at': datetime.now(timezone.utc).isoformat()  # 兼容字段
                    }
                    
                    # 如果转储成功，添加文件信息
                    if file_info:
                        room_message_data['file_id'] = file_info.get('file_id')
                        room_message_data['file_url'] = file_info.get('file_url', '')
                        room_message_data['file_name'] = file_info.get('file_name', file_name) or file_name
                        room_message_data['file_size'] = file_info.get('file_size', file_size) or file_size
                        room_message_data['is_original'] = is_original
                        if file_info.get('mime_type'):
                            room_message_data['mime_type'] = file_info.get('mime_type')
                        
                        # 保留原始 base64 作为缩略图（message_content 已经是原始 base64）
                        room_message_data['message'] = message_content  # 缩略图 base64
                    # 如果客户端已经通过 HTTP 上传了文件（提供了 file_url），添加文件信息
                    elif file_url and file_url.strip():
                        room_message_data['file_url'] = file_url
                        room_message_data['file_name'] = file_name or ('image' if msg_type == 'image' else ('voice.webm' if msg_type == 'audio' else 'file'))
                        room_message_data['file_size'] = file_size or 0
                        logger.info(f"返回房间消息时添加 file_url: {file_url}, file_name: {file_name}, file_size: {file_size}")
                    if duration is not None:
                        try:
                            room_message_data['duration'] = int(duration)
                        except (TypeError, ValueError):
                            pass
                    
                    for participant in participants:
                        await sio.emit('message', room_message_data, room=f"user_{participant.user_id}")
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
        
        raw_target = data.get('target_user_id')
        room_id = data.get('room_id')
        
        if raw_target is None:
            logger.error(f"缺少目标用户ID，发送者: {sender_id}")
            await sio.emit('error', {'message': '缺少目标用户ID'}, room=sid)
            return
        try:
            target_user_id = int(raw_target)
        except (TypeError, ValueError):
            logger.error(f"目标用户ID格式无效: {raw_target}，发送者: {sender_id}")
            await sio.emit('error', {'message': '目标用户ID无效'}, room=sid)
            return
        
        if not room_id:
            logger.error(f"缺少房间ID，发送者: {sender_id}")
            await sio.emit('error', {'message': '缺少房间ID'}, room=sid)
            return
        
        logger.info(f"目标用户ID: {target_user_id} (type={type(target_user_id).__name__}), 房间ID: {room_id}")
        logger.info(f"当前在线用户: {list(connected_users.keys())}")
        
        invitation_data = {
            'room_id': room_id,
            'room_url': data.get('room_url'),
            'jitsi_token': data.get('jitsi_token'),
            'jitsi_server_url': data.get('jitsi_server_url'),
            'caller_id': sender_id,
            'caller_name': data.get('caller_name') or sender_nickname or f'用户{sender_id}',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        caller_name = invitation_data['caller_name']
        # 折中方案：以聊天消息形式发到双方，文案明确「点击进入房间」按钮
        system_message_text = f'📹 {caller_name} 邀请您进行视频通话，点击下方「进入房间」加入。'
        created_msg_id: Optional[int] = None
        created_msg_at: Optional[datetime] = None
        
        # 始终创建系统消息并落库（对方离线时也能在聊天记录中看到邀请）
        try:
            from app.db.models import Message
            from app.db.session import get_db
            
            async for session in get_db():
                try:
                    db_system_message = Message(
                        sender_id=sender_id,
                        receiver_id=target_user_id,
                        message=system_message_text,
                        message_type='system',
                        is_read=False,
                        created_at=datetime.now(timezone.utc),
                        extra_data={'call_invitation': invitation_data},
                    )
                    session.add(db_system_message)
                    await session.commit()
                    await session.refresh(db_system_message)
                    created_msg_id = db_system_message.id
                    created_msg_at = db_system_message.created_at
                    logger.info(f"✓ 已创建通话邀请系统消息，ID={created_msg_id}，接收者={target_user_id}")
                    break
                except Exception as msg_error:
                    await session.rollback()
                    logger.error(f"创建系统消息失败: {msg_error}", exc_info=True)
                    break
        except Exception as e:
            logger.warning(f"创建通话邀请系统消息失败: {e}")
        
        # 构建系统消息 payload，并推送给发起方（双方都能在聊天里看到这条记录）
        system_message_data = None
        if created_msg_id is not None and created_msg_at is not None:
            system_message_data = {
                'id': created_msg_id,
                'sender_id': sender_id,
                'sender_nickname': caller_name,
                'receiver_id': target_user_id,
                'message': system_message_text,
                'message_type': 'system',
                'is_read': False,
                'created_at': created_msg_at.isoformat() if created_msg_at else datetime.now(timezone.utc).isoformat(),
                'call_invitation': invitation_data,
                'extra_data': {'call_invitation': invitation_data},
            }
            await sio.emit('message', system_message_data, room=f"user_{sender_id}")
            logger.info(f"✓ 已通过 Socket 发送系统消息（通话邀请）给发起方 {sender_id}")
        
        # 对方不在线：已落库；仍发推送通知（对方上线/打开 App 时可收到）；通知发起方
        if target_user_id not in connected_users:
            logger.warning(f"用户 {target_user_id} 不在线，无法推送实时通话邀请。当前在线: {list(connected_users.keys())}")
            await sio.emit('error', {
                'message': '对方不在线，无法发送通话邀请；已写入聊天记录，对方上线后可查看'
            }, room=sid)
            confirm_data = {
                'target_user_id': target_user_id,
                'room_id': room_id,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'offline': True,
            }
            if system_message_data is not None:
                confirm_data['system_message'] = system_message_data
            await sio.emit('call_invitation_sent', confirm_data, room=sid)
            # 对方离线也发送 FCM/APNs，设备上线或打开 App 时可收到通话邀请通知
            try:
                from app.services.push_notification import send_video_call_push
                from app.db.session import get_db
                async for session in get_db():
                    await send_video_call_push(
                        target_user_id=target_user_id,
                        caller_name=caller_name,
                        room_id=room_id,
                        invitation_data=invitation_data,
                        db_session=session,
                    )
                    break
            except Exception as push_error:
                logger.debug(f"对方离线时推送通知发送失败: {push_error}")
            return
        
        target_sockets = connected_users.get(target_user_id, {})
        logger.info(f"向用户 {target_user_id} 发送通话邀请，房间: user_{target_user_id}，连接数: {len(target_sockets)}")
        
        # 在线：先发「带接受/拒绝」的聊天消息，再发弹窗事件；被叫端用 system_message 可写入聊天
        if system_message_data is not None:
            await sio.emit('message', system_message_data, room=f"user_{target_user_id}")
            logger.info(f"✓ 已通过 Socket 发送系统消息（通话邀请）给用户 {target_user_id}")
        # 被叫事件里附带同一条系统消息，便于未在聊天页时也能写入会话
        callee_payload = dict(invitation_data)
        if system_message_data is not None:
            callee_payload['system_message'] = system_message_data
        await sio.emit('call_invitation', callee_payload, room=f"user_{target_user_id}")
        
        logger.info(f"✓ 用户 {sender_id} 向用户 {target_user_id} 发送了通话邀请，房间ID: {room_id}")
        logger.info(f"✓ 邀请已通过房间 user_{target_user_id} 发送")
        
        # 发送 FCM/APNs 推送通知（用于后台唤醒）
        # 当 App 在后台或手机黑屏时，Socket 连接会被系统杀掉，必须通过推送通知来唤醒
        try:
            from app.services.push_notification import send_video_call_push
            from app.db.session import get_db
            
            # 获取数据库会话并发送推送
            async for session in get_db():
                await send_video_call_push(
                    target_user_id=target_user_id,
                    caller_name=caller_name,
                    room_id=room_id,
                    invitation_data=invitation_data,
                    db_session=session,
                )
                break
        except Exception as push_error:
            # 推送失败不影响 Socket 流程
            logger.debug(f"推送通知发送失败（不影响 Socket 流程）: {push_error}")
        
        # 确认邀请已发送（附带系统消息供主叫写入聊天记录）
        confirm_data = {
            'target_user_id': target_user_id,
            'room_id': room_id,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        if system_message_data is not None:
            confirm_data['system_message'] = system_message_data
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


# ==================== 心跳监测（已统一为 Engine.IO） ====================

def start_heartbeat_monitor():
    """
    保留接口以兼容 main.py 调用；离线判定已由 Engine.IO ping_interval/ping_timeout 负责。
    """
    logger.info("Socket.io 使用 Engine.IO 统一心跳，离线判定约 60s")
