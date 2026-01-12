"""
API v1 路由
"""

from fastapi import APIRouter

router = APIRouter()

# 导入子路由
from app.api.v1 import auth, i18n as i18n_router, devices, users, invitations, admin, payload, qrcode, rooms, favicon

router.include_router(auth.router, prefix="/auth", tags=["认证"])
router.include_router(i18n_router.router, prefix="/i18n", tags=["国际化"])
router.include_router(devices.router, prefix="/devices", tags=["设备"])
router.include_router(users.router, prefix="/users", tags=["用户"])
router.include_router(invitations.router, prefix="/invitations", tags=["邀请码"])
router.include_router(admin.router, prefix="/admin", tags=["后台管理"])
router.include_router(payload.router, prefix="/payload", tags=["数据载荷"])
router.include_router(qrcode.router, prefix="/qrcode", tags=["二维码"])
router.include_router(rooms.router, prefix="/rooms", tags=["房间"])
router.include_router(favicon.router, tags=["图标"])