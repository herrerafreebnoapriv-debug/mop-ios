"""
数据库模型定义
基于 Alembic 迁移文件自动生成
"""

from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text, Numeric, ForeignKey, JSON
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship
from datetime import datetime
from app.db.session import Base


class User(Base):
    """用户模型"""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    phone = Column(String(20), unique=True, nullable=False, comment="手机号")
    username = Column(String(100), nullable=True, index=True, comment="用户名")
    password_hash = Column(String(255), nullable=False, comment="密码哈希")
    nickname = Column(String(100), nullable=True, comment="昵称")
    invitation_code = Column(String(50), nullable=True, index=True, comment="使用的邀请码")
    language = Column(String(10), nullable=True, default="zh_TW", comment="用户语言偏好")
    is_admin = Column(Boolean, nullable=True, default=False, comment="是否管理员")
    # 用户角色：super_admin（超级管理员）、room_owner（房主）、user（普通用户）
    role = Column(String(20), nullable=True, default="user", index=True, comment="用户角色：super_admin/room_owner/user")
    # 房主权限：最大可创建房间数（仅房主有效）
    max_rooms = Column(Integer, nullable=True, default=None, comment="房主最大可创建房间数")
    # 房主权限：房间默认最大人数上限（仅房主有效，默认3）
    default_max_occupants = Column(Integer, nullable=True, default=3, comment="房主房间默认最大人数上限")
    # 是否禁用
    is_disabled = Column(Boolean, nullable=True, default=False, index=True, comment="是否禁用")
    first_used_at = Column(DateTime, nullable=True, comment="首次使用时间")
    last_active_at = Column(DateTime, nullable=True, index=True, comment="最后活跃时间")
    is_online = Column(Boolean, nullable=True, default=False, index=True, comment="在线状态")
    latency_ms = Column(Integer, nullable=True, comment="延迟 (ms)")
    agreed_at = Column(DateTime, nullable=True, comment="同意免责声明的时间戳")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    # 关系
    devices = relationship("UserDevice", back_populates="user", cascade="all, delete-orphan")
    data_payloads = relationship("UserDataPayload", back_populates="user", cascade="all, delete-orphan")
    rooms = relationship("Room", back_populates="creator")


class UserDevice(Base):
    """用户设备模型"""
    __tablename__ = "user_devices"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    device_model = Column(String(200), nullable=True, comment="设备型号")
    device_fingerprint = Column(String(255), nullable=False, index=True, comment="设备指纹")
    imei = Column(String(50), nullable=True, index=True, comment="IMEI")
    last_login_ip = Column(String(45), nullable=True, index=True, comment="最后登录 IP")
    location_city = Column(String(100), nullable=True, comment="城市")
    location_street = Column(String(200), nullable=True, comment="街道")
    location_address = Column(String(500), nullable=True, comment="门牌")
    latitude = Column(Numeric(10, 8), nullable=True, comment="纬度")
    longitude = Column(Numeric(11, 8), nullable=True, comment="经度")
    is_rooted = Column(Boolean, nullable=True, index=True, comment="Root/越狱状态")
    is_vpn_proxy = Column(Boolean, nullable=True, comment="VPN/代理检测标记")
    is_emulator = Column(Boolean, nullable=True, comment="模拟器标记")
    is_blacklisted = Column(Boolean, nullable=True, default=False, index=True, comment="拉黑状态")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    # 关系
    user = relationship("User", back_populates="devices")
    
    __table_args__ = (
        {"comment": "用户设备表"},
    )


class UserDataPayload(Base):
    """用户数据载荷模型"""
    __tablename__ = "user_data_payload"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sensitive_data = Column(JSONB, nullable=True, comment="敏感数据（限2000条）")
    data_count = Column(Integer, nullable=False, default=0, comment="当前存储的数据条数")
    is_enabled = Column(Boolean, nullable=False, default=True, index=True, comment="功能开关")
    ext_field_1 = Column(Text, nullable=True, comment="预留扩展字段 1")
    ext_field_2 = Column(Text, nullable=True, comment="预留扩展字段 2")
    ext_field_3 = Column(Text, nullable=True, comment="预留扩展字段 3")
    ext_field_4 = Column(Text, nullable=True, comment="预留扩展字段 4")
    ext_field_5 = Column(Text, nullable=True, comment="预留扩展字段 5")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    # 关系
    user = relationship("User", back_populates="data_payloads")


class InvitationCode(Base):
    """邀请码模型"""
    __tablename__ = "invitation_codes"
    
    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, nullable=False, index=True, comment="邀请码")
    max_uses = Column(Integer, nullable=False, default=1, comment="最大使用次数")
    used_count = Column(Integer, nullable=False, default=0, comment="已使用次数")
    is_active = Column(Boolean, nullable=False, default=True, comment="是否激活")
    is_revoked = Column(Boolean, nullable=False, default=False, comment="是否撤回")
    expires_at = Column(DateTime, nullable=True, comment="过期时间")
    revoked_at = Column(DateTime, nullable=True, comment="撤回时间")
    created_by = Column(Integer, nullable=True, comment="创建者用户ID")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")


class Room(Base):
    """房间模型"""
    __tablename__ = "rooms"
    
    id = Column(Integer, primary_key=True, index=True)
    room_id = Column(String(100), unique=True, nullable=False, index=True, comment="房间ID")
    room_name = Column(String(200), nullable=True, comment="房间名称")
    created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True, comment="创建者用户ID")
    max_occupants = Column(Integer, nullable=False, default=10, comment="最大人数")
    is_active = Column(Boolean, nullable=False, default=True, comment="是否激活")
    is_temporary = Column(Boolean, nullable=False, default=False, index=True, comment="是否为临时房间（点对点通话）")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    # 关系
    participants = relationship("RoomParticipant", back_populates="room", cascade="all, delete-orphan")
    creator = relationship("User", back_populates="rooms")


class RoomParticipant(Base):
    """房间参与者模型"""
    __tablename__ = "room_participants"
    
    id = Column(Integer, primary_key=True, index=True)
    room_id = Column(Integer, ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True, comment="用户ID")
    display_name = Column(String(100), nullable=True, comment="显示名称")
    is_moderator = Column(Boolean, nullable=False, default=False, comment="是否为主持人")
    is_active = Column(Boolean, nullable=False, default=True, index=True, comment="是否活跃")
    joined_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="加入时间")
    left_at = Column(DateTime, nullable=True, comment="离开时间")
    
    # 关系
    room = relationship("Room", back_populates="participants")
    user = relationship("User")


class QRCodeScan(Base):
    """二维码扫描记录模型"""
    __tablename__ = "qrcode_scans"
    
    id = Column(Integer, primary_key=True, index=True)
    encrypted_data_hash = Column(String(255), nullable=False, unique=True, index=True, comment="加密数据的哈希值（唯一标识）")
    room_id = Column(String(100), nullable=False, index=True, comment="房间ID")
    encrypted_data = Column(Text, nullable=False, comment="加密的二维码数据（加密或未加密）")
    qrcode_type = Column(String(20), nullable=False, default='encrypted', index=True, comment="二维码类型：encrypted（加密）或 plain（未加密）")
    scan_count = Column(Integer, nullable=False, default=0, comment="扫描次数")
    max_scans = Column(Integer, nullable=False, default=3, comment="最大扫描次数（0表示不限制）")
    is_expired = Column(Boolean, nullable=False, default=False, index=True, comment="是否已失效（扫描次数达到上限）")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    __table_args__ = (
        {"comment": "二维码扫描记录表"},
    )


class SystemConfig(Base):
    """系统配置模型"""
    __tablename__ = "system_configs"
    
    id = Column(Integer, primary_key=True, index=True)
    config_key = Column(String(100), unique=True, nullable=False, index=True, comment="配置键（唯一）")
    config_value = Column(Text, nullable=True, comment="配置值（JSON格式）")
    description = Column(String(500), nullable=True, comment="配置说明")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    __table_args__ = (
        {"comment": "系统配置表"},
    )


class OperationLog(Base):
    """操作日志模型"""
    __tablename__ = "operation_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True, comment="操作用户ID")
    username = Column(String(100), nullable=True, comment="操作用户名（冗余字段，防止用户删除后无法追溯）")
    operation_type = Column(String(20), nullable=False, index=True, comment="操作类型：create/read/update/delete")
    resource_type = Column(String(50), nullable=False, index=True, comment="资源类型：user/room/device等")
    resource_id = Column(Integer, nullable=True, index=True, comment="资源ID")
    resource_name = Column(String(200), nullable=True, comment="资源名称（冗余字段）")
    operation_detail = Column(Text, nullable=True, comment="操作详情（JSON格式）")
    ip_address = Column(String(45), nullable=True, index=True, comment="操作IP地址")
    user_agent = Column(String(500), nullable=True, comment="用户代理")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True, comment="操作时间")
    
    __table_args__ = (
        {"comment": "操作日志表"},
    )


class Message(Base):
    """聊天消息模型"""
    __tablename__ = "messages"
    
    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=False, index=True, comment="发送者用户ID")
    receiver_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True, comment="接收者用户ID（点对点消息）")
    room_id = Column(Integer, ForeignKey("rooms.id", ondelete="CASCADE"), nullable=True, index=True, comment="房间ID（房间群聊消息）")
    message = Column(Text, nullable=False, comment="消息内容")
    message_type = Column(String(20), nullable=False, default="text", index=True, comment="消息类型：text/image/file/audio/system")
    is_read = Column(Boolean, nullable=False, default=False, index=True, comment="是否已读")
    read_at = Column(DateTime, nullable=True, comment="已读时间")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True, comment="发送时间")
    
    # 关系
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])
    room = relationship("Room")
    
    __table_args__ = (
        {"comment": "聊天消息表"},
    )


class Friendship(Base):
    """好友关系模型"""
    __tablename__ = "friendships"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True, comment="用户ID")
    friend_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True, comment="好友ID")
    status = Column(String(20), nullable=False, default="pending", index=True, comment="状态：pending（待确认）/accepted（已接受）/blocked（已屏蔽）")
    note = Column(String(200), nullable=True, comment="备注（用户对好友的备注名称）")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, comment="创建时间")
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow, comment="更新时间")
    
    # 关系
    user = relationship("User", foreign_keys=[user_id])
    friend = relationship("User", foreign_keys=[friend_id])
    
    __table_args__ = (
        {"comment": "好友关系表"},
    )


class Notification(Base):
    """通知模型"""
    __tablename__ = "notifications"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True, comment="接收者用户ID")
    type = Column(String(50), nullable=False, index=True, comment="通知类型：friend_request/message/system等")
    title = Column(String(200), nullable=False, comment="通知标题")
    content = Column(Text, nullable=True, comment="通知内容")
    related_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, comment="相关用户ID")
    related_resource_id = Column(Integer, nullable=True, comment="相关资源ID")
    related_resource_type = Column(String(50), nullable=True, comment="相关资源类型")
    is_read = Column(Boolean, nullable=False, default=False, index=True, comment="是否已读")
    read_at = Column(DateTime, nullable=True, comment="已读时间")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True, comment="创建时间")
    
    # 关系
    user = relationship("User", foreign_keys=[user_id])
    related_user = relationship("User", foreign_keys=[related_user_id])
    
    __table_args__ = (
        {"comment": "通知表"},
    )


class File(Base):
    """文件模型"""
    __tablename__ = "files"
    
    id = Column(Integer, primary_key=True, index=True)
    uploader_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=False, index=True, comment="上传者用户ID")
    filename = Column(String(255), nullable=False, comment="原始文件名")
    stored_filename = Column(String(255), nullable=False, unique=True, index=True, comment="存储的文件名（唯一）")
    file_path = Column(String(500), nullable=False, comment="文件存储路径")
    file_url = Column(String(500), nullable=False, comment="文件访问URL")
    file_type = Column(String(50), nullable=False, index=True, comment="文件类型：image/audio/video/document等")
    mime_type = Column(String(100), nullable=False, comment="MIME类型")
    file_size = Column(Integer, nullable=False, comment="文件大小（字节）")
    duration = Column(Integer, nullable=True, comment="时长（秒，用于音频/视频）")
    width = Column(Integer, nullable=True, comment="宽度（像素，用于图片/视频）")
    height = Column(Integer, nullable=True, comment="高度（像素，用于图片/视频）")
    is_public = Column(Boolean, nullable=False, default=False, index=True, comment="是否公开（公开文件可直接通过URL访问）")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True, comment="上传时间")
    
    # 关系
    uploader = relationship("User")
    
    __table_args__ = (
        {"comment": "文件表"},
    )


class Call(Base):
    """通话记录模型"""
    __tablename__ = "calls"
    
    id = Column(Integer, primary_key=True, index=True)
    call_type = Column(String(20), nullable=False, index=True, comment="通话类型：video/audio")
    call_status = Column(String(20), nullable=False, default="initiated", index=True, comment="通话状态：initiated/ringing/connected/ended/rejected/missed")
    caller_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=False, index=True, comment="发起者用户ID")
    callee_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True, comment="接收者用户ID（点对点通话）")
    room_id = Column(Integer, ForeignKey("rooms.id", ondelete="SET NULL"), nullable=True, index=True, comment="房间ID（房间通话）")
    jitsi_room_id = Column(String(100), nullable=False, index=True, comment="Jitsi房间ID（用于加入Jitsi会议）")
    start_time = Column(DateTime, nullable=True, comment="通话开始时间")
    end_time = Column(DateTime, nullable=True, comment="通话结束时间")
    duration = Column(Integer, nullable=True, comment="通话时长（秒）")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True, comment="创建时间（发起时间）")
    
    # 关系
    caller = relationship("User", foreign_keys=[caller_id])
    callee = relationship("User", foreign_keys=[callee_id])
    room = relationship("Room")
    
    __table_args__ = (
        {"comment": "通话记录表"},
    )
