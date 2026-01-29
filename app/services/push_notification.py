"""
推送通知服务
用于发送 FCM/APNs 推送通知（视频通话邀请等）
"""

import os
import json
import logging
from typing import List, Optional, Dict, Any

logger = logging.getLogger(__name__)

# FCM Server Key（从环境变量读取）
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")


async def send_video_call_push(
    target_user_id: int,
    caller_name: str,
    room_id: str,
    invitation_data: Dict[str, Any],
    db_session=None,
) -> bool:
    """
    发送视频通话推送通知
    
    Args:
        target_user_id: 目标用户ID
        caller_name: 发起者名称
        room_id: 房间ID
        invitation_data: 邀请数据
        db_session: 数据库会话（用于查询设备 FCM token）
    
    Returns:
        bool: 是否发送成功
    """
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY 未配置，跳过推送通知")
        return False
    
    try:
        # 1. 从数据库获取目标用户的所有设备 FCM token
        fcm_tokens = []
        if db_session:
            from app.db.models import UserDevice
            from sqlalchemy import select
            
            result = await db_session.execute(
                select(UserDevice).where(
                    UserDevice.user_id == target_user_id,
                    # 假设 fcm_token 存储在 ext_field_1 或新增字段
                    # 这里先用 ext_field_1 作为临时方案
                )
            )
            devices = result.scalars().all()
            for device in devices:
                # 临时方案：从 ext_field_1 读取 FCM token
                # 未来应添加专门的 fcm_token 字段
                if hasattr(device, 'ext_field_1') and device.ext_field_1:
                    try:
                        device_data = json.loads(device.ext_field_1) if isinstance(device.ext_field_1, str) else device.ext_field_1
                        if isinstance(device_data, dict) and 'fcm_token' in device_data:
                            fcm_tokens.append(device_data['fcm_token'])
                    except:
                        pass
        
        if not fcm_tokens:
            logger.info(f"用户 {target_user_id} 没有注册 FCM token，跳过推送")
            return False
        
        # 2. 构建推送数据
        message_title = "视频通话邀请"
        message_body = f"{caller_name} 邀请您进行视频通话"
        
        data_message = {
            "type": "VIDEO_CALL",
            "room_id": room_id,
            "caller_name": caller_name,
            "caller_id": str(invitation_data.get("caller_id", "")),
            "invitation_data": json.dumps(invitation_data),
        }
        
        # 3. 发送 FCM 推送
        try:
            from pyfcm import FCMNotification
            push_service = FCMNotification(api_key=FCM_SERVER_KEY)
            
            result = push_service.notify_multiple_devices(
                registration_ids=fcm_tokens,
                message_title=message_title,
                message_body=message_body,
                data_message=data_message,
                sound="default",
                priority="high",  # 高优先级，即使省电模式也能收到
                content_available=True,  # iOS 后台唤醒
            )
            
            logger.info(f"✓ FCM 推送已发送给用户 {target_user_id}，结果: {result}")
            return True
        except ImportError:
            logger.warning("pyfcm 未安装，无法发送推送。请运行: pip install pyfcm")
            return False
        except Exception as fcm_error:
            logger.error(f"发送 FCM 推送失败: {fcm_error}", exc_info=True)
            return False
            
    except Exception as e:
        logger.error(f"发送推送通知错误: {e}", exc_info=True)
        return False


async def send_push_notification(
    target_user_id: int,
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
    db_session=None,
) -> bool:
    """
    发送通用推送通知
    
    Args:
        target_user_id: 目标用户ID
        title: 通知标题
        body: 通知内容
        data: 附加数据
        db_session: 数据库会话
    
    Returns:
        bool: 是否发送成功
    """
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY 未配置，跳过推送通知")
        return False
    
    try:
        # 获取 FCM tokens（同上）
        fcm_tokens = []
        if db_session:
            from app.db.models import UserDevice
            from sqlalchemy import select
            
            result = await db_session.execute(
                select(UserDevice).where(UserDevice.user_id == target_user_id)
            )
            devices = result.scalars().all()
            for device in devices:
                if hasattr(device, 'ext_field_1') and device.ext_field_1:
                    try:
                        device_data = json.loads(device.ext_field_1) if isinstance(device.ext_field_1, str) else device.ext_field_1
                        if isinstance(device_data, dict) and 'fcm_token' in device_data:
                            fcm_tokens.append(device_data['fcm_token'])
                    except:
                        pass
        
        if not fcm_tokens:
            return False
        
        # 发送推送
        try:
            from pyfcm import FCMNotification
            push_service = FCMNotification(api_key=FCM_SERVER_KEY)
            
            result = push_service.notify_multiple_devices(
                registration_ids=fcm_tokens,
                message_title=title,
                message_body=body,
                data_message=data or {},
                priority="high",
            )
            
            logger.info(f"✓ 推送已发送给用户 {target_user_id}")
            return True
        except ImportError:
            logger.warning("pyfcm 未安装")
            return False
        except Exception as e:
            logger.error(f"发送推送失败: {e}")
            return False
            
    except Exception as e:
        logger.error(f"发送推送通知错误: {e}", exc_info=True)
        return False
