"""
应用配置管理
使用 pydantic_settings 从环境变量加载配置，确保敏感信息不硬编码
"""

from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, field_validator


class Settings(BaseSettings):
    """
    应用配置类
    所有敏感配置必须从环境变量加载，严禁硬编码
    """
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )
    
    # ==================== 应用基础配置 ====================
    APP_NAME: str = Field(default="MOP Backend", description="应用名称")
    APP_VERSION: str = Field(default="1.0.0", description="应用版本")
    DEBUG: bool = Field(default=False, description="调试模式")
    API_V1_PREFIX: str = Field(default="/api/v1", description="API 版本前缀")
    
    # ==================== 服务器配置 ====================
    HOST: str = Field(default="0.0.0.0", description="服务器监听地址")
    PORT: int = Field(default=8000, description="服务器监听端口")
    
    # ==================== 数据库配置 ====================
    POSTGRES_HOST: str = Field(default="localhost", description="PostgreSQL 主机地址")
    POSTGRES_PORT: int = Field(default=5432, description="PostgreSQL 端口")
    POSTGRES_USER: str = Field(..., description="PostgreSQL 用户名")
    POSTGRES_PASSWORD: str = Field(..., description="PostgreSQL 密码")
    POSTGRES_DB: str = Field(..., description="PostgreSQL 数据库名")
    
    # 数据库连接池配置
    DB_POOL_SIZE: int = Field(default=20, description="数据库连接池大小")
    DB_MAX_OVERFLOW: int = Field(default=10, description="数据库连接池最大溢出数")
    DB_POOL_TIMEOUT: int = Field(default=30, description="数据库连接池超时时间（秒）")
    DB_POOL_RECYCLE: int = Field(default=3600, description="数据库连接回收时间（秒）")
    DB_ECHO: bool = Field(default=False, description="是否打印 SQL 语句（调试用）")
    
    @property
    def DATABASE_URL(self) -> str:
        """构建 PostgreSQL 异步连接串"""
        return f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
    
    @property
    def DATABASE_URL_SYNC(self) -> str:
        """构建 PostgreSQL 同步连接串（用于 Alembic 迁移）"""
        return f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
    
    # ==================== Redis 配置 ====================
    REDIS_HOST: str = Field(default="localhost", description="Redis 主机地址")
    REDIS_PORT: int = Field(default=6379, description="Redis 端口")
    REDIS_PASSWORD: Optional[str] = Field(default=None, description="Redis 密码")
    REDIS_DB: int = Field(default=0, description="Redis 数据库编号")
    REDIS_SOCKET_TIMEOUT: int = Field(default=5, description="Redis Socket 超时时间（秒）")
    REDIS_SOCKET_CONNECT_TIMEOUT: int = Field(default=5, description="Redis 连接超时时间（秒）")
    
    @property
    def REDIS_URL(self) -> str:
        """构建 Redis 连接串"""
        if self.REDIS_PASSWORD:
            return f"redis://:{self.REDIS_PASSWORD}@{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
        return f"redis://{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"
    
    # ==================== JWT 配置 ====================
    JWT_SECRET_KEY: str = Field(..., description="JWT 签名密钥（必须足够复杂）")
    JWT_ALGORITHM: str = Field(default="HS256", description="JWT 签名算法")
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=30, description="访问令牌过期时间（分钟）")
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=7, description="刷新令牌过期时间（天）")
    
    # ==================== RSA 加密配置 ====================
    RSA_PRIVATE_KEY: str = Field(..., description="RSA 私钥（用于二维码加密签名，支持 \\n 转义的单行格式）")
    RSA_PUBLIC_KEY: str = Field(..., description="RSA 公钥（用于二维码解密验证，支持 \\n 转义的单行格式）")
    
    @field_validator("RSA_PRIVATE_KEY", "RSA_PUBLIC_KEY", mode="after")
    @classmethod
    def normalize_rsa_key(cls, v: str) -> str:
        """标准化 RSA 密钥格式，将 \\n 转换为实际换行符"""
        # 将环境变量中的 \n 转义符转换为实际的换行符
        if "\\n" in v:
            return v.replace("\\n", "\n")
        return v
    
    # ==================== Jitsi Meet 配置 ====================
    JITSI_APP_ID: str = Field(..., description="Jitsi App ID")
    JITSI_APP_SECRET: str = Field(..., description="Jitsi App Secret（用于 JWT 签名）")
    JITSI_SERVER_URL: str = Field(..., description="Jitsi 服务器地址（私有化部署，严禁使用官方服务器）")
    JITSI_ROOM_MAX_OCCUPANTS: int = Field(default=10, description="房间默认最大人数")
    
    @field_validator("JITSI_SERVER_URL")
    @classmethod
    def validate_jitsi_server_url(cls, v: str) -> str:
        """验证 Jitsi 服务器地址，禁止使用官方服务器"""
        server_url = v.lower()
        if 'meet.jit.si' in server_url or 'jit.si' in server_url:
            raise ValueError("禁止使用官方 Jitsi 服务器 (meet.jit.si)，必须使用自建服务器")
        return v
    
    # ==================== 安全配置 ====================
    # CORS 和 ALLOWED_HOSTS 在环境变量中可以是逗号分隔的字符串
    CORS_ORIGINS: str = Field(
        default="http://localhost:3000,http://localhost:8080",
        description="允许的 CORS 源（逗号分隔）"
    )
    ALLOWED_HOSTS: str = Field(
        default="localhost,127.0.0.1",
        description="允许的主机列表（逗号分隔）"
    )
    
    @property
    def cors_origins_list(self) -> list[str]:
        """获取 CORS 源列表"""
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]
    
    @property
    def allowed_hosts_list(self) -> list[str]:
        """获取允许的主机列表"""
        return [host.strip() for host in self.ALLOWED_HOSTS.split(",") if host.strip()]
    
    # ==================== 日志配置 ====================
    LOG_LEVEL: str = Field(default="INFO", description="日志级别")
    LOG_FILE: str = Field(default="logs/app.log", description="日志文件路径")
    
    # ==================== 业务配置 ====================
    INVITATION_CODE_LENGTH: int = Field(default=8, description="邀请码长度")
    LOCATION_UPDATE_THRESHOLD_METERS: int = Field(default=200, description="位置更新阈值（米）")
    MAX_SENSITIVE_DATA_COUNT: int = Field(default=2000, description="敏感数据最大条数")
    
    # ==================== Socket.io 配置 ====================
    SOCKETIO_CORS_ORIGINS: str = Field(
        default="http://localhost:3000,http://localhost:8080",
        description="Socket.io CORS 源（逗号分隔）"
    )
    SOCKETIO_ASYNC_MODE: str = Field(default="aiohttp", description="Socket.io 异步模式")
    
    @field_validator("JWT_SECRET_KEY")
    @classmethod
    def validate_jwt_secret(cls, v: str) -> str:
        """验证 JWT Secret 长度和复杂度"""
        if len(v) < 32:
            raise ValueError("JWT_SECRET_KEY 长度必须至少 32 个字符")
        return v
    
    @field_validator("LOG_LEVEL")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """验证日志级别"""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"LOG_LEVEL 必须是以下之一: {', '.join(valid_levels)}")
        return v.upper()


# 全局配置实例
settings = Settings()
