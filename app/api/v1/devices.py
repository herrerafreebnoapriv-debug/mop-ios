"""
设备管理 API
包含设备注册、查询、更新等功能
"""

from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.db.session import get_db
from app.db.models import User, UserDevice
from app.api.v1.auth import get_current_user

router = APIRouter()


# ==================== 请求/响应模型 ====================

class DeviceRegister(BaseModel):
    """设备注册请求模型"""
    device_model: Optional[str] = Field(None, max_length=200, description="设备型号")
    device_fingerprint: str = Field(..., max_length=255, description="设备指纹 (Hardware Hash)")
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
    
    # 检查设备是否已存在（同一用户的同一设备指纹）
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == current_user.id,
            UserDevice.device_fingerprint == device_data.device_fingerprint
        )
    )
    existing_device = result.scalar_one_or_none()
    
    if existing_device:
        # 设备已存在，更新信息
        existing_device.device_model = device_data.device_model or existing_device.device_model
        existing_device.imei = device_data.imei or existing_device.imei
        existing_device.last_login_ip = device_data.last_login_ip or existing_device.last_login_ip
        existing_device.location_city = device_data.location_city or existing_device.location_city
        existing_device.location_street = device_data.location_street or existing_device.location_street
        existing_device.location_address = device_data.location_address or existing_device.location_address
        existing_device.latitude = device_data.latitude or existing_device.latitude
        existing_device.longitude = device_data.longitude or existing_device.longitude
        existing_device.is_rooted = device_data.is_rooted
        existing_device.is_vpn_proxy = device_data.is_vpn_proxy
        existing_device.is_emulator = device_data.is_emulator
        # updated_at 会通过事件监听器自动更新
        
        await db.commit()
        await db.refresh(existing_device)
        
        return existing_device
    
    # 创建新设备
    new_device = UserDevice(
        user_id=current_user.id,
        device_model=device_data.device_model,
        device_fingerprint=device_data.device_fingerprint,
        imei=device_data.imei,
        last_login_ip=device_data.last_login_ip,
        location_city=device_data.location_city,
        location_street=device_data.location_street,
        location_address=device_data.location_address,
        latitude=device_data.latitude,
        longitude=device_data.longitude,
        is_rooted=device_data.is_rooted,
        is_vpn_proxy=device_data.is_vpn_proxy,
        is_emulator=device_data.is_emulator,
        is_blacklisted=False
    )
    
    db.add(new_device)
    await db.commit()
    await db.refresh(new_device)
    
    return new_device


@router.get("/", response_model=List[DeviceResponse])
async def get_user_devices(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取当前用户的所有设备
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(
        select(UserDevice).where(UserDevice.user_id == current_user.id)
    )
    devices = result.scalars().all()
    
    return devices


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
