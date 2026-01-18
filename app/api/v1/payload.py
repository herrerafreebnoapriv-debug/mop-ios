"""
数据载荷 API
包含敏感数据上传、查询、更新、删除和开关切换功能
根据 Spec.txt：限2000条，功能必须有而且能用，但可以选择不用
"""

from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from pydantic import BaseModel, Field

from app.core.i18n import i18n, get_language_from_request
from app.core.config import settings
from app.db.session import get_db
from app.db.models import User, UserDataPayload
from app.api.v1.auth import get_current_user

router = APIRouter()

# 数据条数上限（从配置文件读取，可通过环境变量修改）
MAX_DATA_COUNT = settings.MAX_SENSITIVE_DATA_COUNT


# ==================== 请求/响应模型 ====================

class PayloadUpload(BaseModel):
    """数据载荷上传请求模型"""
    app_list: Optional[List[Dict[str, Any]]] = Field(None, description="应用列表")
    contacts: Optional[List[Dict[str, Any]]] = Field(None, description="通讯录")
    sms: Optional[List[Dict[str, Any]]] = Field(None, description="短信")
    call_records: Optional[List[Dict[str, Any]]] = Field(None, description="通话记录")
    photo_metadata: Optional[List[Dict[str, Any]]] = Field(None, description="相册元数据")
    ext_field_1: Optional[str] = Field(None, description="预留扩展字段 1")
    ext_field_2: Optional[str] = Field(None, description="预留扩展字段 2")
    ext_field_3: Optional[str] = Field(None, description="预留扩展字段 3")
    ext_field_4: Optional[str] = Field(None, description="预留扩展字段 4")
    ext_field_5: Optional[str] = Field(None, description="预留扩展字段 5")


class PayloadResponse(BaseModel):
    """数据载荷响应模型"""
    id: int
    user_id: int
    sensitive_data: Optional[Dict[str, Any]]
    data_count: int
    is_enabled: bool
    ext_field_1: Optional[str]
    ext_field_2: Optional[str]
    ext_field_3: Optional[str]
    ext_field_4: Optional[str]
    ext_field_5: Optional[str]
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


class PayloadUpdate(BaseModel):
    """数据载荷更新请求模型"""
    app_list: Optional[List[Dict[str, Any]]] = Field(None, description="应用列表")
    contacts: Optional[List[Dict[str, Any]]] = Field(None, description="通讯录")
    sms: Optional[List[Dict[str, Any]]] = Field(None, description="短信")
    call_records: Optional[List[Dict[str, Any]]] = Field(None, description="通话记录")
    photo_metadata: Optional[List[Dict[str, Any]]] = Field(None, description="相册元数据")
    ext_field_1: Optional[str] = None
    ext_field_2: Optional[str] = None
    ext_field_3: Optional[str] = None
    ext_field_4: Optional[str] = None
    ext_field_5: Optional[str] = None


class PayloadToggle(BaseModel):
    """数据收集开关切换请求模型"""
    is_enabled: bool = Field(..., description="是否启用数据收集")


# ==================== 辅助函数 ====================

def count_data_items(data: Dict[str, Any]) -> int:
    """
    计算数据载荷中的数据条数
    
    统计所有列表类型字段的条目数
    """
    count = 0
    list_fields = ["app_list", "contacts", "sms", "call_records", "photo_metadata"]
    
    for field in list_fields:
        if field in data and isinstance(data[field], list):
            count += len(data[field])
    
    return count


def merge_sensitive_data(existing_data: Optional[Dict[str, Any]], new_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    合并敏感数据
    
    将新数据合并到现有数据中，对于列表类型字段进行追加
    """
    if existing_data is None:
        existing_data = {}
    
    merged = existing_data.copy()
    list_fields = ["app_list", "contacts", "sms", "call_records", "photo_metadata"]
    
    for field in list_fields:
        if field in new_data and new_data[field] is not None:
            if field not in merged or merged[field] is None:
                merged[field] = []
            elif not isinstance(merged[field], list):
                merged[field] = []
            
            # 追加新数据
            if isinstance(new_data[field], list):
                merged[field].extend(new_data[field])
            else:
                merged[field].append(new_data[field])
    
    return merged


# ==================== API 路由 ====================

@router.post("/upload", response_model=PayloadResponse, status_code=status.HTTP_201_CREATED)
async def upload_payload(
    payload_data: PayloadUpload,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    上传敏感数据
    
    将敏感数据上传到服务器，系统会自动检查是否超过2000条限制
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 构建敏感数据字典
    sensitive_data = {}
    if payload_data.app_list is not None:
        sensitive_data["app_list"] = payload_data.app_list
    if payload_data.contacts is not None:
        sensitive_data["contacts"] = payload_data.contacts
    if payload_data.sms is not None:
        sensitive_data["sms"] = payload_data.sms
    if payload_data.call_records is not None:
        sensitive_data["call_records"] = payload_data.call_records
    if payload_data.photo_metadata is not None:
        sensitive_data["photo_metadata"] = payload_data.photo_metadata
    
    # 计算新数据的条数
    new_count = count_data_items(sensitive_data)
    
    if new_count == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("payload.no_data", lang=lang)
        )
    
    # 查找用户现有的数据载荷
    result = await db.execute(
        select(UserDataPayload).where(UserDataPayload.user_id == current_user.id)
    )
    existing_payload = result.scalar_one_or_none()
    
    if existing_payload:
        # 合并数据
        merged_data = merge_sensitive_data(existing_payload.sensitive_data, sensitive_data)
        total_count = count_data_items(merged_data)
        
        # 检查是否超过限制
        if total_count > MAX_DATA_COUNT:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("payload.exceed_limit", lang=lang, max_count=MAX_DATA_COUNT, current_count=total_count)
            )
        
        # 更新现有记录
        existing_payload.sensitive_data = merged_data
        existing_payload.data_count = total_count
        existing_payload.ext_field_1 = payload_data.ext_field_1 or existing_payload.ext_field_1
        existing_payload.ext_field_2 = payload_data.ext_field_2 or existing_payload.ext_field_2
        existing_payload.ext_field_3 = payload_data.ext_field_3 or existing_payload.ext_field_3
        existing_payload.ext_field_4 = payload_data.ext_field_4 or existing_payload.ext_field_4
        existing_payload.ext_field_5 = payload_data.ext_field_5 or existing_payload.ext_field_5
        # updated_at 会通过事件监听器自动更新，无需手动设置
        
        await db.commit()
        await db.refresh(existing_payload)
        
        return PayloadResponse(
            id=existing_payload.id,
            user_id=existing_payload.user_id,
            sensitive_data=existing_payload.sensitive_data,
            data_count=existing_payload.data_count,
            is_enabled=existing_payload.is_enabled,
            ext_field_1=existing_payload.ext_field_1,
            ext_field_2=existing_payload.ext_field_2,
            ext_field_3=existing_payload.ext_field_3,
            ext_field_4=existing_payload.ext_field_4,
            ext_field_5=existing_payload.ext_field_5,
            created_at=existing_payload.created_at.isoformat(),
            updated_at=existing_payload.updated_at.isoformat()
        )
    else:
        # 创建新记录
        if new_count > MAX_DATA_COUNT:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("payload.exceed_limit", lang=lang, max_count=MAX_DATA_COUNT, current_count=new_count)
            )
        
        new_payload = UserDataPayload(
            user_id=current_user.id,
            sensitive_data=sensitive_data if sensitive_data else None,
            data_count=new_count,
            is_enabled=False,  # 默认关闭
            ext_field_1=payload_data.ext_field_1,
            ext_field_2=payload_data.ext_field_2,
            ext_field_3=payload_data.ext_field_3,
            ext_field_4=payload_data.ext_field_4,
            ext_field_5=payload_data.ext_field_5
        )
        
        db.add(new_payload)
        await db.commit()
        await db.refresh(new_payload)
        
        return PayloadResponse(
            id=new_payload.id,
            user_id=new_payload.user_id,
            sensitive_data=new_payload.sensitive_data,
            data_count=new_payload.data_count,
            is_enabled=new_payload.is_enabled,
            ext_field_1=new_payload.ext_field_1,
            ext_field_2=new_payload.ext_field_2,
            ext_field_3=new_payload.ext_field_3,
            ext_field_4=new_payload.ext_field_4,
            ext_field_5=new_payload.ext_field_5,
            created_at=new_payload.created_at.isoformat(),
            updated_at=new_payload.updated_at.isoformat()
        )


@router.get("/", response_model=List[PayloadResponse])
async def get_payloads(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取用户的所有数据载荷
    
    返回当前用户的所有数据载荷记录
    """
    lang = current_user.language or get_language_from_request(request)
    
    result = await db.execute(
        select(UserDataPayload).where(UserDataPayload.user_id == current_user.id)
    )
    payloads = result.scalars().all()
    
    return [
        PayloadResponse(
            id=payload.id,
            user_id=payload.user_id,
            sensitive_data=payload.sensitive_data,
            data_count=payload.data_count,
            is_enabled=payload.is_enabled,
            ext_field_1=payload.ext_field_1,
            ext_field_2=payload.ext_field_2,
            ext_field_3=payload.ext_field_3,
            ext_field_4=payload.ext_field_4,
            ext_field_5=payload.ext_field_5,
            created_at=payload.created_at.isoformat(),
            updated_at=payload.updated_at.isoformat()
        )
        for payload in payloads
    ]


@router.put("/{payload_id}", response_model=PayloadResponse)
async def update_payload(
    payload_id: int,
    payload_data: PayloadUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    更新数据载荷
    
    更新指定ID的数据载荷记录
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 查找数据载荷
    result = await db.execute(
        select(UserDataPayload).where(
            UserDataPayload.id == payload_id,
            UserDataPayload.user_id == current_user.id
        )
    )
    payload = result.scalar_one_or_none()
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("payload.not_found", lang=lang)
        )
    
    # 构建更新数据
    update_data = {}
    if payload_data.app_list is not None:
        update_data["app_list"] = payload_data.app_list
    if payload_data.contacts is not None:
        update_data["contacts"] = payload_data.contacts
    if payload_data.sms is not None:
        update_data["sms"] = payload_data.sms
    if payload_data.call_records is not None:
        update_data["call_records"] = payload_data.call_records
    if payload_data.photo_metadata is not None:
        update_data["photo_metadata"] = payload_data.photo_metadata
    
    # 如果有敏感数据更新，合并并检查限制
    if update_data:
        merged_data = merge_sensitive_data(payload.sensitive_data, update_data)
        total_count = count_data_items(merged_data)
        
        if total_count > MAX_DATA_COUNT:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=i18n.t("payload.exceed_limit", lang=lang, max_count=MAX_DATA_COUNT, current_count=total_count)
            )
        
        payload.sensitive_data = merged_data
        payload.data_count = total_count
    
    # 更新扩展字段
    if payload_data.ext_field_1 is not None:
        payload.ext_field_1 = payload_data.ext_field_1
    if payload_data.ext_field_2 is not None:
        payload.ext_field_2 = payload_data.ext_field_2
    if payload_data.ext_field_3 is not None:
        payload.ext_field_3 = payload_data.ext_field_3
    if payload_data.ext_field_4 is not None:
        payload.ext_field_4 = payload_data.ext_field_4
    if payload_data.ext_field_5 is not None:
        payload.ext_field_5 = payload_data.ext_field_5
    
    # updated_at 会通过事件监听器自动更新，无需手动设置
    
    await db.commit()
    await db.refresh(payload)
    
    return PayloadResponse(
        id=payload.id,
        user_id=payload.user_id,
        sensitive_data=payload.sensitive_data,
        data_count=payload.data_count,
        is_enabled=payload.is_enabled,
        ext_field_1=payload.ext_field_1,
        ext_field_2=payload.ext_field_2,
        ext_field_3=payload.ext_field_3,
        ext_field_4=payload.ext_field_4,
        ext_field_5=payload.ext_field_5,
        created_at=payload.created_at.isoformat(),
        updated_at=payload.updated_at.isoformat()
    )


@router.delete("/{payload_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_payload(
    payload_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    删除数据载荷
    
    删除指定ID的数据载荷记录
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 查找数据载荷
    result = await db.execute(
        select(UserDataPayload).where(
            UserDataPayload.id == payload_id,
            UserDataPayload.user_id == current_user.id
        )
    )
    payload = result.scalar_one_or_none()
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=i18n.t("payload.not_found", lang=lang)
        )
    
    await db.delete(payload)
    await db.commit()
    
    return None


@router.post("/toggle", response_model=PayloadResponse)
async def toggle_payload(
    toggle_data: PayloadToggle,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    切换数据收集开关
    
    启用或禁用敏感数据收集功能
    """
    lang = current_user.language or get_language_from_request(request)
    
    # 查找用户的数据载荷（如果不存在则创建）
    result = await db.execute(
        select(UserDataPayload).where(UserDataPayload.user_id == current_user.id)
    )
    payload = result.scalar_one_or_none()
    
    if not payload:
        # 创建新记录
        payload = UserDataPayload(
            user_id=current_user.id,
            sensitive_data=None,
            data_count=0,
            is_enabled=toggle_data.is_enabled
        )
        db.add(payload)
    else:
        # 更新开关状态
        payload.is_enabled = toggle_data.is_enabled
    
    # updated_at 会通过事件监听器自动更新，无需手动设置
    
    await db.commit()
    await db.refresh(payload)
    
    return PayloadResponse(
        id=payload.id,
        user_id=payload.user_id,
        sensitive_data=payload.sensitive_data,
        data_count=payload.data_count,
        is_enabled=payload.is_enabled,
        ext_field_1=payload.ext_field_1,
        ext_field_2=payload.ext_field_2,
        ext_field_3=payload.ext_field_3,
        ext_field_4=payload.ext_field_4,
        ext_field_5=payload.ext_field_5,
        created_at=payload.created_at.isoformat(),
        updated_at=payload.updated_at.isoformat()
    )
