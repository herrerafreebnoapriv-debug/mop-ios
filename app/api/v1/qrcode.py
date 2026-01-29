"""
二维码 API
包含二维码生成、验证和房间二维码获取功能
根据 Spec.txt：使用 RSA 私钥对配置（API URL、房间ID、时间戳）进行签名加密
"""

from datetime import datetime, timezone, timedelta
from typing import Optional
import io
import base64
import hashlib
import json
import os
import random
from pathlib import Path
from urllib.parse import urlparse, urlencode
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel, Field
from PIL import Image

from app.core.i18n import i18n, get_language_from_request
from app.core.security import rsa_encrypt, rsa_decrypt, simple_encrypt, simple_decrypt, create_jitsi_token, create_access_token
from app.core.config import settings
from app.db.session import get_db
from app.db.models import User, QRCodeScan, SystemConfig
from app.api.v1.auth import get_current_user
from loguru import logger
import qrcode
from qrcode.constants import ERROR_CORRECT_H, ERROR_CORRECT_M, ERROR_CORRECT_L

router = APIRouter()


# ==================== 辅助函数 ====================

def get_random_chat_api_url() -> str:
    """
    随机选择一个聊天接口 API 地址（自动拼接路径）
    
    从 CHAT_BASE_DOMAINS 列表中随机选择，并拼接 CHAT_API_PATH。
    - 域名无协议时自动加 https://
    - 路径保证以 / 开头，避免拼成 domain.comapi/v1
    
    Returns:
        完整 API URL，如 https://log.chat5202ol.xyz/api/v1
    """
    domains = settings.chat_base_domains_list
    domain = (random.choice(domains) or "").strip()
    if not domain:
        return ""
    if not domain.startswith("http://") and not domain.startswith("https://"):
        domain = f"https://{domain}"
    domain = domain.rstrip("/")
    path = (settings.CHAT_API_PATH or "/api/v1").strip()
    if path and not path.startswith("/"):
        path = "/" + path
    return f"{domain}{path}"


def get_random_chat_base_url() -> str:
    """
    随机选择一个聊天接口基础 URL（用于未加密二维码的房间链接）
    
    从 CHAT_BASE_DOMAINS 列表随机选择，无协议时加 https://，返回不含路径的 base URL。
    
    Returns:
        基础 URL，如 https://log.chat5202ol.xyz
    """
    domains = settings.chat_base_domains_list
    domain = (random.choice(domains) or "").strip()
    if not domain:
        return ""
    if not domain.startswith("http://") and not domain.startswith("https://"):
        domain = f"https://{domain}"
    return domain.rstrip("/")


# ==================== 请求/响应模型 ====================

class QRCodeGenerate(BaseModel):
    """二维码生成请求模型"""
    api_url: str = Field(..., description="API URL（动态 Endpoint）")
    room_id: Optional[str] = Field(None, description="房间ID（可选，用于房间二维码）")
    timestamp: Optional[int] = Field(None, description="时间戳（可选，默认使用当前时间）")
    expires_in: Optional[int] = Field(None, description="过期时间（秒，可选）")


class QRCodeVerify(BaseModel):
    """二维码验证请求模型"""
    encrypted_data: str = Field(..., description="加密的二维码数据")


class QRCodeResponse(BaseModel):
    """二维码响应模型"""
    encrypted_data: str = Field(..., description="加密的二维码数据（Base64）")
    qr_code_image: Optional[str] = Field(None, description="二维码图片（Base64 PNG，可选）")
    expires_at: Optional[int] = Field(None, description="过期时间戳（如果设置了过期时间）")


class QRCodeVerifyResponse(BaseModel):
    """二维码验证响应模型"""
    valid: bool = Field(..., description="是否有效")
    data: Optional[dict] = Field(None, description="解密后的数据（如果有效）")
    expired: Optional[bool] = Field(None, description="是否已过期（如果设置了过期时间）")


# ==================== 辅助函数 ====================

def calculate_encrypted_data_hash(encrypted_data: str) -> str:
    """
    计算加密数据的哈希值，用作唯一标识
    
    Args:
        encrypted_data: 加密的二维码数据（Base64字符串）
    
    Returns:
        SHA256哈希值的十六进制字符串
    """
    return hashlib.sha256(encrypted_data.encode('utf-8')).hexdigest()


def get_random_icon_path() -> Optional[str]:
    """
    随机选择一个mop_ico目录下的PNG文件
    
    Returns:
        PNG文件的完整路径，如果目录不存在或没有文件则返回None
    """
    # 查找mop_ico目录（可能在项目根目录或mop_ico_fav目录下）
    base_paths = [
        Path("/opt/mop/mop_ico"),
        Path("/opt/mop/mop_ico_fav"),
        Path("mop_ico"),
        Path("mop_ico_fav"),
    ]
    
    for base_path in base_paths:
        if base_path.exists() and base_path.is_dir():
            # 查找所有PNG文件
            png_files = list(base_path.glob("*.png"))
            if png_files:
                # 排除selected_favicon.png和selected_logo.png
                png_files = [f for f in png_files if f.name not in ["selected_favicon.png", "selected_logo.png"]]
                if png_files:
                    selected_file = random.choice(png_files)
                    logger.debug(f"随机选择图标: {selected_file}")
                    return str(selected_file)
    
    logger.warning("未找到mop_ico目录或PNG文件")
    return None


def generate_qr_code_image(data: str, error_correction: int = ERROR_CORRECT_M, box_size: int = 5, border: int = 2) -> bytes:
    """
    生成二维码图片（微信级别配置，优化识别率）
    
    Args:
        data: 要编码的数据
        error_correction: 错误纠正级别（默认 Level M，15% 容错，平衡密集度与容错能力）
        box_size: 每个模块的像素数（默认5，微信级别，降低密度）
        border: 边框宽度（默认2，减小边框，提高识别率）
    
    Returns:
        二维码图片的字节数据（PNG 格式）
    """
    # 使用微信级别参数（box_size=5, border=2）降低密度，提高相册识别率
    # Level M (15% 容错) - 平衡密集度与容错能力
    # 图标覆盖比例控制在<3%，确保不影响扫描识别
    qr = qrcode.QRCode(
        version=None,  # 自动选择最小版本
        error_correction=error_correction,  # 使用传入的纠错级别
        box_size=box_size,  # 使用传入的尺寸
        border=border,      # 使用传入的边框
    )
    qr.add_data(data)
    qr.make(fit=True)  # 自动选择最小版本
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    # 记录二维码信息用于调试
    logger.debug(f"二维码生成: 版本={qr.version}, 尺寸={img.size}, 数据长度={len(data)}")
    
    # 在二维码中心添加随机选择的mop_ico图标
    icon_path = get_random_icon_path()
    if icon_path and os.path.exists(icon_path):
        try:
            # 打开图标文件
            icon = Image.open(icon_path)
            
            # 计算二维码尺寸
            qr_width, qr_height = img.size
            
            # 计算图标尺寸（约为二维码的1/8到1/9，降低覆盖比例以提高相册识别率）
            # 图标不能太大，否则会覆盖二维码导致无法扫描
            # 使用更小的比例（1/8或1/9），确保覆盖比例<3%，提高识别率
            if qr_width < 200:
                icon_size = max(20, qr_width // 9)  # 小二维码使用1/9，最小20px
            elif qr_width < 300:
                icon_size = max(30, qr_width // 9)  # 中等二维码使用1/9，最小30px
            else:
                icon_size = max(35, min(qr_width // 9, qr_height // 9, 50))  # 大二维码使用1/9，最小35px，最大50px
            
            icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
            
            logger.info(f"二维码尺寸: {qr_width}x{qr_height}, 图标尺寸: {icon_size}x{icon_size}, 图标路径: {icon_path}")
            
            # 计算居中位置
            icon_x = (qr_width - icon_size) // 2
            icon_y = (qr_height - icon_size) // 2
            
            # 确保二维码图片是RGB模式
            if img.mode != 'RGB':
                img = img.convert('RGB')
            
            # 如果图标有透明通道，需要处理
            if icon.mode == 'RGBA':
                # 创建白色背景的图标
                icon_bg = Image.new('RGB', icon.size, (255, 255, 255))
                icon_bg.paste(icon, mask=icon.split()[3])  # 使用alpha通道作为mask
                icon = icon_bg
            elif icon.mode != 'RGB':
                icon = icon.convert('RGB')
            
            # 增强图标对比度，确保在白色背景上可见
            # 使用PIL的ImageEnhance来增强对比度
            from PIL import ImageEnhance
            enhancer = ImageEnhance.Contrast(icon)
            icon = enhancer.enhance(1.5)  # 增强1.5倍对比度
            
            # 将图标粘贴到二维码中心（使用白色边框确保可见）
            # 创建白色区域作为边框，确保图标不会被二维码黑色模块遮挡
            border_size = 4  # 减小边框，确保不覆盖太多二维码区域
            icon_with_border_size = icon_size + border_size * 2
            
            # 创建白色边框，但添加一个浅灰色内边框以增强视觉效果
            icon_with_border = Image.new('RGB', (icon_with_border_size, icon_with_border_size), (255, 255, 255))
            
            # 添加浅灰色内边框（2px）以增强图标可见性
            inner_border_size = 2
            inner_border_color = (240, 240, 240)  # 浅灰色
            for y in range(border_size - inner_border_size, border_size + icon_size + inner_border_size):
                for x in range(border_size - inner_border_size, border_size + icon_size + inner_border_size):
                    if (x < border_size or x >= border_size + icon_size or 
                        y < border_size or y >= border_size + icon_size):
                        if 0 <= x < icon_with_border_size and 0 <= y < icon_with_border_size:
                            icon_with_border.putpixel((x, y), inner_border_color)
            
            # 将图标粘贴到白色边框中心
            icon_with_border.paste(icon, (border_size, border_size))
            
            # 计算带边框的居中位置
            icon_x_bordered = (qr_width - icon_with_border_size) // 2
            icon_y_bordered = (qr_height - icon_with_border_size) // 2
            
            # 确保位置在有效范围内
            icon_x_bordered = max(0, icon_x_bordered)
            icon_y_bordered = max(0, icon_y_bordered)
            
            # 将带边框的图标粘贴到二维码中心（直接覆盖，确保图标在上层）
            # 使用paste方法会直接覆盖该区域的像素，确保图标可见
            img.paste(icon_with_border, (icon_x_bordered, icon_y_bordered))
            
            # 验证图标是否成功添加，并记录详细信息用于调试
            center_x = icon_x_bordered + icon_with_border_size // 2
            center_y = icon_y_bordered + icon_with_border_size // 2
            if center_x < qr_width and center_y < qr_height:
                center_pixel = img.getpixel((center_x, center_y))
                # 计算图标覆盖区域占二维码总面积的比例
                coverage_ratio = (icon_with_border_size * icon_with_border_size) / (qr_width * qr_height) * 100
                logger.info(f"成功在二维码中心添加图标: {icon_path}, "
                           f"二维码尺寸: {qr_width}x{qr_height}, "
                           f"图标尺寸: {icon_size}x{icon_size}, "
                           f"边框尺寸: {icon_with_border_size}x{icon_with_border_size}, "
                           f"覆盖比例: {coverage_ratio:.2f}%, "
                           f"位置: ({icon_x_bordered}, {icon_y_bordered}), "
                           f"数据长度: {len(data)}, "
                           f"二维码版本: {qr.version}")
            else:
                logger.warning(f"图标位置超出范围: center=({center_x}, {center_y}), qr_size=({qr_width}, {qr_height})")
        except Exception as e:
            logger.warning(f"添加图标失败: {e}，继续生成不带图标的二维码", exc_info=True)
    
    # 转换为字节数据
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format='PNG')
    img_byte_arr.seek(0)
    
    return img_byte_arr.read()


async def get_unified_max_scans(db: AsyncSession) -> int:
    """
    统一获取二维码最大扫描次数配置
    
    使用统一的 qrcode.max_scans 配置项
    如果未设置，默认返回3
    
    Args:
        db: 数据库会话
    
    Returns:
        最大扫描次数（0表示不限制）
    """
    # 使用统一的 max_scans 配置
    max_scans_result = await db.execute(
        select(SystemConfig).where(SystemConfig.config_key == 'qrcode.max_scans')
    )
    max_scans_config = max_scans_result.scalar_one_or_none()
    
    if max_scans_config and max_scans_config.config_value:
        try:
            return int(max_scans_config.config_value)
        except (ValueError, TypeError):
            pass
    
    # 默认返回3
    return 3


# ==================== API 路由 ====================

@router.get("/public-key")
async def get_rsa_public_key():
    """
    获取 RSA 公钥（用于客户端解密二维码）
    
    这是一个公开端点，不需要认证，因为公钥本身就是公开的
    """
    try:
        return {
            "public_key": settings.RSA_PUBLIC_KEY,
            "algorithm": "RSA-2048",
            "format": "PEM"
        }
    except Exception as e:
        logger.error(f"获取 RSA 公钥失败: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="无法获取 RSA 公钥"
        )


@router.post("/generate", response_model=QRCodeResponse)
async def generate_qrcode(
    qr_data: QRCodeGenerate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    生成加密二维码
    
    使用 RSA 私钥对配置（API URL、房间ID、时间戳）进行签名加密，生成加密二维码
    根据 Spec.txt：二维码加盐加密，容错 Level H
    """
    lang = current_user.language or get_language_from_request(request)
    
    try:
        # 必须包含完整的 API URL，客户端不能内置任何默认URL
        data = {"u": qr_data.api_url}
        if qr_data.room_id:
            data["r"] = qr_data.room_id
        
        # 使用简单的加密（Base64 + XOR 混淆），快速且不直接显示明文
        from app.core.security import simple_encrypt
        encrypted_data = simple_encrypt(data)
        
        expires_at = None
        if qr_data.expires_in:
            timestamp = qr_data.timestamp or int(datetime.now(timezone.utc).timestamp())
            expires_at = timestamp + qr_data.expires_in
        
        # 生成二维码图片（可选）
        qr_image_bytes = generate_qr_code_image(encrypted_data)
        qr_image_base64 = base64.b64encode(qr_image_bytes).decode('utf-8')
        
        return QRCodeResponse(
            encrypted_data=encrypted_data,
            qr_code_image=qr_image_base64,
            expires_at=expires_at
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.generate_failed", lang=lang, error=str(e))
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=i18n.t("qrcode.internal_error", lang=lang)
        )


@router.post("/verify", response_model=QRCodeVerifyResponse)
async def verify_qrcode(
    verify_data: QRCodeVerify,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    验证二维码
    
    支持两种格式：
    1. 加密二维码：使用 RSA 公钥验证并解密二维码数据
    2. 未加密二维码：直接解析 JSON 数据
    
    这是一个公开端点，不需要登录
    核心要求：被扫描指定次数后失效（max_scans=0表示不限制）
    """
    lang = get_language_from_request(request)
    import json
    
    try:
        # 尝试判断是加密还是未加密二维码
        # 未加密二维码通常是JSON格式，可以直接解析
        data = None
        qrcode_type = 'encrypted'
        
        try:
            # 先尝试作为URL解析（新格式：明文链接带token）
            if verify_data.encrypted_data.startswith("http://") or verify_data.encrypted_data.startswith("https://"):
                from urllib.parse import urlparse
                parsed_url = urlparse(verify_data.encrypted_data)
                # 从URL路径中提取房间ID，格式：/room/{room_id}
                path_parts = parsed_url.path.strip('/').split('/')
                if len(path_parts) >= 2 and path_parts[0] == 'room':
                    room_id_from_url = path_parts[1]
                    data = {"room_id": room_id_from_url}
                    qrcode_type = 'plain'
                else:
                    raise ValueError("URL中未找到房间ID")
            else:
                # 尝试作为JSON解析（向后兼容旧格式）
                data = json.loads(verify_data.encrypted_data)
                if isinstance(data, dict) and "room_id" in data:
                    # 确认是未加密二维码
                    qrcode_type = 'plain'
        except (json.JSONDecodeError, ValueError):
            # 不是JSON格式，尝试解密（简单加密或RSA加密）
            data = None
            try:
                # 先尝试简单解密（新格式）
                from app.core.security import simple_decrypt
                data = simple_decrypt(verify_data.encrypted_data)
                qrcode_type = 'encrypted'
            except Exception:
                # 简单解密失败，尝试RSA解密（向后兼容）
                try:
                    data = rsa_decrypt(verify_data.encrypted_data, expand_short_keys=True, decompress=True)
                    qrcode_type = 'encrypted'
                except Exception:
                    # 既不是JSON也不是有效的加密数据
                    return QRCodeVerifyResponse(
                        valid=False,
                        data=None,
                        expired=None
                    )
        
        if not data or "room_id" not in data:
            return QRCodeVerifyResponse(
                valid=False,
                data=None,
                expired=None
            )
        
        # 计算数据的哈希值
        encrypted_data_hash = calculate_encrypted_data_hash(verify_data.encrypted_data)
        
        # 查找二维码扫描记录
        qr_scan_result = await db.execute(
            select(QRCodeScan).where(
                QRCodeScan.encrypted_data_hash == encrypted_data_hash,
                QRCodeScan.qrcode_type == qrcode_type
            )
        )
        qr_scan = qr_scan_result.scalar_one_or_none()
        
        # 如果记录不存在，创建新记录
        if not qr_scan:
            room_id = data.get("room_id")
            if room_id:
                # 使用统一的max_scans配置
                default_max_scans = await get_unified_max_scans(db)
                
                qr_scan = QRCodeScan(
                    encrypted_data_hash=encrypted_data_hash,
                    room_id=room_id,
                    encrypted_data=verify_data.encrypted_data,
                    qrcode_type=qrcode_type,
                    scan_count=0,
                    max_scans=default_max_scans,
                    is_expired=False
                )
                db.add(qr_scan)
                await db.flush()
        
        # 检查是否已失效（扫描次数达到上限，max_scans=0表示不限制）
        if qr_scan.is_expired or (qr_scan.max_scans > 0 and qr_scan.scan_count >= qr_scan.max_scans):
            return QRCodeVerifyResponse(
                valid=False,
                data=None,
                expired=None
            )
        
        # 增加扫描次数
        qr_scan.scan_count += 1
        
        # 如果达到最大扫描次数（且max_scans>0），标记为失效
        if qr_scan.max_scans > 0 and qr_scan.scan_count >= qr_scan.max_scans:
            qr_scan.is_expired = True
        
        await db.commit()
        
        # 安全考虑：验证接口不返回服务器地址，避免暴露
        # 加密二维码：客户端需要使用RSA公钥解密二维码获取服务器地址
        # 未加密二维码：客户端需要从系统配置获取服务器地址
        # 只返回房间ID和验证状态
        response_data = {
            "room_id": data.get("room_id"),
            "type": qrcode_type  # 返回二维码类型
        }
        
        # 添加时间戳（如果需要）
        if "timestamp" not in response_data:
            response_data["timestamp"] = int(datetime.now(timezone.utc).timestamp())
        
        # 检查是否过期
        expired = False
        if "expires_at" in data:
            current_timestamp = int(datetime.now(timezone.utc).timestamp())
            if current_timestamp > data["expires_at"]:
                expired = True
        
        return QRCodeVerifyResponse(
            valid=True,
            data=response_data,  # 不包含 api_url，客户端需要自己获取
            expired=expired if "expires_at" in data else None
        )
    except ValueError as e:
        # 解密失败或签名验证失败
        return QRCodeVerifyResponse(
            valid=False,
            data=None,
            expired=None
        )
    except Exception as e:
        logger.error(f"二维码验证失败: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=i18n.t("qrcode.internal_error", lang=lang)
        )


@router.get("/room/{room_id}", response_model=QRCodeResponse)
async def get_room_qrcode(
    room_id: str,
    qrcode_type: Optional[str] = None,  # 可选参数：encrypted 或 plain
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取房间二维码
    
    根据系统配置生成加密或未加密二维码
    参数 qrcode_type: encrypted（加密）或 plain（未加密），不提供则根据系统配置自动选择
    """
    from loguru import logger
    import json
    
    lang = current_user.language or get_language_from_request(request)
    
    try:
        # 获取系统配置
        encrypted_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.encrypted_enabled')
        )
        encrypted_enabled_config = encrypted_enabled_result.scalar_one_or_none()
        encrypted_enabled = encrypted_enabled_config and encrypted_enabled_config.config_value and encrypted_enabled_config.config_value.strip().lower() == 'true'
        
        plain_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.plain_enabled')
        )
        plain_enabled_config = plain_enabled_result.scalar_one_or_none()
        plain_enabled = plain_enabled_config and plain_enabled_config.config_value and plain_enabled_config.config_value.strip().lower() == 'true'
        
        # 使用统一的max_scans配置
        unified_max_scans = await get_unified_max_scans(db)
        
        logger.debug(f"[get_room_qrcode] 读取配置: encrypted_enabled={encrypted_enabled} (值: '{encrypted_enabled_config.config_value if encrypted_enabled_config else None}'), plain_enabled={plain_enabled} (值: '{plain_enabled_config.config_value if plain_enabled_config else None}'), unified_max_scans={unified_max_scans}")
        
        # 确定二维码类型
        if qrcode_type:
            # 如果指定了类型，检查是否启用
            if qrcode_type == 'encrypted' and not encrypted_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="加密二维码功能未启用"
                )
            if qrcode_type == 'plain' and not plain_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="未加密二维码功能未启用"
                )
            use_encrypted = (qrcode_type == 'encrypted')
        else:
            # 自动选择：如果未加密二维码启用，优先使用未加密；否则使用加密
            # 逻辑：如果 plain_enabled 为 True，使用未加密（use_encrypted=False）
            #       如果 plain_enabled 为 False，检查 encrypted_enabled，如果为 True 则使用加密
            if plain_enabled:
                use_encrypted = False
            elif encrypted_enabled:
                use_encrypted = True
            else:
                # 默认使用加密（向后兼容）
                use_encrypted = True
            
            logger.debug(f"二维码类型自动选择: plain_enabled={plain_enabled}, encrypted_enabled={encrypted_enabled}, use_encrypted={use_encrypted}")
        
        # 检查 JITSI_SERVER_URL 配置
        if not settings.JITSI_SERVER_URL:
            logger.error("JITSI_SERVER_URL 未配置")
            raise ValueError("JITSI_SERVER_URL 未配置")
        
        if use_encrypted:
            # ========== 生成加密二维码 ==========
            # 包含房间ID和API地址（加密后只有客户端能解密）
            # APP端是聊天功能，应该使用聊天页面的API入口，而不是Jitsi服务器地址
            # 直接使用随机选择的聊天接口域名（简化逻辑，统一使用聊天接口）
            api_url = get_random_chat_api_url()
            
            logger.debug(f"生成二维码API地址（聊天页面入口）: {api_url}")
            
            data = {
                "room_id": room_id,
                "api_url": api_url,
            }
            
            logger.debug(f"生成加密二维码数据: {data}")
            
            # 使用简单的加密（Base64 + XOR 混淆），快速且不直接显示明文
            from app.core.security import simple_encrypt
            try:
                # 必须包含完整的 API URL（不能只包含 room_id）
                # 客户端不能内置任何默认URL，必须从二维码获取
                simplified_data = {
                    "r": room_id,
                    "u": api_url,  # 必须包含完整的 API URL
                }
                encrypted_data = simple_encrypt(simplified_data)
                logger.debug(f"简单加密成功，数据长度: {len(encrypted_data)}, 包含房间ID和API地址")
            except Exception as e:
                logger.error(f"简单加密失败: {type(e).__name__}: {e}", exc_info=True)
                raise ValueError(f"简单加密失败: {str(e)}")
            
            # 计算加密数据的哈希值
            encrypted_data_hash = calculate_encrypted_data_hash(encrypted_data)
            
            # 检查是否已存在该二维码记录
            existing_qr_result = await db.execute(
                select(QRCodeScan).where(
                    QRCodeScan.encrypted_data_hash == encrypted_data_hash,
                    QRCodeScan.qrcode_type == 'encrypted'
                )
            )
            existing_qr = existing_qr_result.scalar_one_or_none()
            
            if existing_qr and not existing_qr.is_expired:
                logger.debug(f"使用已存在的加密二维码记录，扫描次数: {existing_qr.scan_count}")
                qr_data = encrypted_data
            else:
                # 创建新的二维码扫描记录
                new_qr_scan = QRCodeScan(
                    encrypted_data_hash=encrypted_data_hash,
                    room_id=room_id,
                    encrypted_data=encrypted_data,
                    qrcode_type='encrypted',
                    scan_count=0,
                    max_scans=unified_max_scans,
                    is_expired=False
                )
                db.add(new_qr_scan)
                await db.commit()
                logger.debug(f"创建新的加密二维码扫描记录，最大扫描次数: {unified_max_scans}")
                qr_data = encrypted_data
        else:
            # ========== 生成未加密二维码（明文链接带token） ==========
            # 先检查是否已存在该房间的未加密二维码记录（基于房间ID）
            existing_qr_result = await db.execute(
                select(QRCodeScan).where(
                    QRCodeScan.room_id == room_id,
                    QRCodeScan.qrcode_type == 'plain',
                    QRCodeScan.is_expired == False
                ).order_by(QRCodeScan.created_at.desc())
            )
            existing_qr = existing_qr_result.scalar_one_or_none()
            
            if existing_qr and existing_qr.encrypted_data.startswith("http"):
                # 使用已存在的URL（确保同一个房间的二维码URL一致）
                logger.debug(f"使用已存在的未加密二维码URL，扫描次数: {existing_qr.scan_count}/{existing_qr.max_scans}")
                qr_data = existing_qr.encrypted_data
            else:
                # 生成新的URL（明文链接带token）
                import hashlib
                from urllib.parse import urlencode
                
                # 基于房间ID生成临时用户标识（固定，确保同一房间的二维码一致）
                temp_user_id = int(hashlib.sha256(f"{room_id}".encode()).hexdigest()[:8], 16) % 1000000
                user_name = f"游客{temp_user_id % 10000}"
                
                # 生成 Jitsi JWT Token（游客不能成为主持人，有效期60分钟）
                jitsi_token = create_jitsi_token(
                    room_id=room_id,
                    user_id=temp_user_id,
                    user_name=user_name,
                    is_moderator=False,  # 游客不能成为主持人
                    expires_in_minutes=60
                )
                
                # 构建房间 URL（明文链接带token）
                # APP端是聊天功能，应该使用聊天页面的入口
                # 直接使用随机选择的聊天接口基础URL（简化逻辑，统一使用聊天接口）
                chat_base_url = get_random_chat_base_url()
                
                # 构建房间URL（使用聊天页面的入口）
                room_url = f"{chat_base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
                logger.info(f"生成新的未加密二维码URL（聊天页面入口）: {room_url[:100]}...")
                
                # 计算URL的哈希值
                plain_data_hash = calculate_encrypted_data_hash(room_url)
                
                # 创建新的二维码扫描记录
                new_qr_scan = QRCodeScan(
                    encrypted_data_hash=plain_data_hash,
                    room_id=room_id,
                    encrypted_data=room_url,
                    qrcode_type='plain',
                    scan_count=0,
                    max_scans=unified_max_scans,
                    is_expired=False
                )
                db.add(new_qr_scan)
                await db.commit()
                logger.info(f"创建新的未加密二维码扫描记录，最大扫描次数: {unified_max_scans}")
                qr_data = room_url
        
        # 生成二维码图片（使用微信级别参数，提高相册识别率）
        try:
            if use_encrypted:
                # 加密二维码：使用微信级别参数（box_size=5, border=2）
                qr_image_bytes = generate_qr_code_image(qr_data)
            else:
                # 明文二维码：URL较长，使用 Level H 提高容错，但保持 box_size=5, border=2 降低密度
                qr_image_bytes = generate_qr_code_image(
                    qr_data, 
                    error_correction=ERROR_CORRECT_H,  # Level H (30% 容错)，应对长URL
                    box_size=5,  # 微信级别尺寸，降低密度
                    border=2     # 减小边框，提高识别率
                )
            qr_image_base64 = base64.b64encode(qr_image_bytes).decode('utf-8')
            logger.debug(f"二维码图片生成成功，大小: {len(qr_image_bytes)} bytes，类型: {'加密' if use_encrypted else '明文'}")
        except Exception as e:
            logger.error(f"二维码图片生成失败: {type(e).__name__}: {e}", exc_info=True)
            raise ValueError(f"二维码图片生成失败: {str(e)}")
        
        return QRCodeResponse(
            encrypted_data=qr_data,
            qr_code_image=qr_image_base64,
            expires_at=None
        )
    except ValueError as e:
        logger.warning(f"二维码生成失败（ValueError）: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.generate_failed", lang=lang, error=str(e))
        )
    except Exception as e:
        logger.error(f"二维码生成失败（Exception）: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=i18n.t("qrcode.generate_failed", lang=lang, error=f"{type(e).__name__}: {str(e)}")
        )


@router.get("/room/{room_id}/image")
async def get_room_qrcode_image(
    room_id: str,
    qrcode_type: Optional[str] = None,  # 可选参数：encrypted 或 plain
    request: Request = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    获取房间二维码图片（直接返回 PNG 图片）
    
    根据系统配置生成加密或未加密二维码
    返回二维码的 PNG 图片，可以直接在浏览器中显示
    """
    from loguru import logger
    import json
    
    lang = current_user.language or get_language_from_request(request)
    
    try:
        # 获取系统配置
        encrypted_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.encrypted_enabled')
        )
        encrypted_enabled_config = encrypted_enabled_result.scalar_one_or_none()
        encrypted_enabled = encrypted_enabled_config and encrypted_enabled_config.config_value and encrypted_enabled_config.config_value.strip().lower() == 'true'
        
        plain_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == 'qrcode.plain_enabled')
        )
        plain_enabled_config = plain_enabled_result.scalar_one_or_none()
        plain_enabled = plain_enabled_config and plain_enabled_config.config_value and plain_enabled_config.config_value.strip().lower() == 'true'
        
        # 使用统一的max_scans配置
        unified_max_scans = await get_unified_max_scans(db)
        
        logger.debug(f"[get_room_qrcode_image] 读取配置: encrypted_enabled={encrypted_enabled} (值: '{encrypted_enabled_config.config_value if encrypted_enabled_config else None}'), plain_enabled={plain_enabled} (值: '{plain_enabled_config.config_value if plain_enabled_config else None}'), unified_max_scans={unified_max_scans}")
        
        # 确定二维码类型
        if qrcode_type:
            # 如果指定了类型，检查是否启用
            if qrcode_type == 'encrypted' and not encrypted_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="加密二维码功能未启用"
                )
            if qrcode_type == 'plain' and not plain_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="未加密二维码功能未启用"
                )
            use_encrypted = (qrcode_type == 'encrypted')
        else:
            # 自动选择：如果未加密二维码启用，优先使用未加密；否则使用加密
            # 逻辑：如果 plain_enabled 为 True，使用未加密（use_encrypted=False）
            #       如果 plain_enabled 为 False，检查 encrypted_enabled，如果为 True 则使用加密
            if plain_enabled:
                use_encrypted = False
            elif encrypted_enabled:
                use_encrypted = True
            else:
                # 默认使用加密（向后兼容）
                use_encrypted = True
            
            logger.debug(f"二维码类型自动选择: plain_enabled={plain_enabled}, encrypted_enabled={encrypted_enabled}, use_encrypted={use_encrypted}")
        
        # 检查 JITSI_SERVER_URL 配置
        if not settings.JITSI_SERVER_URL:
            logger.error("JITSI_SERVER_URL 未配置")
            raise ValueError("JITSI_SERVER_URL 未配置")
        
        if use_encrypted:
            # ========== 生成加密二维码 ==========
            # 包含房间ID和API地址（加密后只有客户端能解密）
            # APP端是聊天功能，应该使用聊天页面的API入口，而不是Jitsi服务器地址
            # 直接使用随机选择的聊天接口域名（简化逻辑，统一使用聊天接口）
            api_url = get_random_chat_api_url()
            
            logger.debug(f"生成二维码API地址（聊天页面入口）: {api_url}")
            
            data = {
                "room_id": room_id,
                "api_url": api_url,
            }
            
            logger.debug(f"生成加密二维码数据: {data}")
            
            # 使用简单的加密（Base64 + XOR 混淆），快速且不直接显示明文
            from app.core.security import simple_encrypt
            try:
                # 必须包含完整的 API URL（不能只包含 room_id）
                # 客户端不能内置任何默认URL，必须从二维码获取
                simplified_data = {
                    "r": room_id,
                    "u": api_url,  # 必须包含完整的 API URL
                }
                encrypted_data = simple_encrypt(simplified_data)
                logger.debug(f"简单加密成功，数据长度: {len(encrypted_data)}, 包含房间ID和API地址")
            except Exception as e:
                logger.error(f"简单加密失败: {type(e).__name__}: {e}", exc_info=True)
                raise ValueError(f"简单加密失败: {str(e)}")
            
            # 计算加密数据的哈希值
            encrypted_data_hash = calculate_encrypted_data_hash(encrypted_data)
            
            # 检查是否已存在该二维码记录
            existing_qr_result = await db.execute(
                select(QRCodeScan).where(
                    QRCodeScan.encrypted_data_hash == encrypted_data_hash,
                    QRCodeScan.qrcode_type == 'encrypted'
                )
            )
            existing_qr = existing_qr_result.scalar_one_or_none()
            
            if existing_qr and not existing_qr.is_expired:
                logger.debug(f"使用已存在的加密二维码记录，扫描次数: {existing_qr.scan_count}")
                qr_data = encrypted_data
            else:
                # 创建新的二维码扫描记录
                new_qr_scan = QRCodeScan(
                    encrypted_data_hash=encrypted_data_hash,
                    room_id=room_id,
                    encrypted_data=encrypted_data,
                    qrcode_type='encrypted',
                    scan_count=0,
                    max_scans=unified_max_scans,
                    is_expired=False
                )
                db.add(new_qr_scan)
                await db.commit()
                logger.debug(f"创建新的加密二维码扫描记录，最大扫描次数: {unified_max_scans}")
                qr_data = encrypted_data
        else:
            # ========== 生成未加密二维码（明文链接带token） ==========
            # 先检查是否已存在该房间的未加密二维码记录（基于房间ID）
            existing_qr_result = await db.execute(
                select(QRCodeScan).where(
                    QRCodeScan.room_id == room_id,
                    QRCodeScan.qrcode_type == 'plain',
                    QRCodeScan.is_expired == False
                ).order_by(QRCodeScan.created_at.desc())
            )
            existing_qr = existing_qr_result.scalar_one_or_none()
            
            if existing_qr and existing_qr.encrypted_data.startswith("http"):
                # 使用已存在的URL（确保同一个房间的二维码URL一致）
                logger.debug(f"使用已存在的未加密二维码URL，扫描次数: {existing_qr.scan_count}/{existing_qr.max_scans}")
                qr_data = existing_qr.encrypted_data
            else:
                # 生成新的URL（明文链接带token）
                import hashlib
                from urllib.parse import urlencode
                
                # 基于房间ID生成临时用户标识（固定，确保同一房间的二维码一致）
                temp_user_id = int(hashlib.sha256(f"{room_id}".encode()).hexdigest()[:8], 16) % 1000000
                user_name = f"游客{temp_user_id % 10000}"
                
                # 生成 Jitsi JWT Token（游客不能成为主持人，有效期60分钟）
                jitsi_token = create_jitsi_token(
                    room_id=room_id,
                    user_id=temp_user_id,
                    user_name=user_name,
                    is_moderator=False,  # 游客不能成为主持人
                    expires_in_minutes=60
                )
                
                # 构建房间 URL（明文链接带token）
                # APP端是聊天功能，应该使用聊天页面的入口
                # 直接使用随机选择的聊天接口基础URL（简化逻辑，统一使用聊天接口）
                chat_base_url = get_random_chat_base_url()
                
                # 构建房间URL（使用聊天页面的入口）
                room_url = f"{chat_base_url}/room/{room_id}?{urlencode({'jwt': jitsi_token, 'server': settings.JITSI_SERVER_URL})}"
                logger.info(f"生成新的未加密二维码URL（聊天页面入口）: {room_url[:100]}...")
                
                # 计算URL的哈希值
                plain_data_hash = calculate_encrypted_data_hash(room_url)
                
                # 创建新的二维码扫描记录
                new_qr_scan = QRCodeScan(
                    encrypted_data_hash=plain_data_hash,
                    room_id=room_id,
                    encrypted_data=room_url,
                    qrcode_type='plain',
                    scan_count=0,
                    max_scans=unified_max_scans,
                    is_expired=False
                )
                db.add(new_qr_scan)
                await db.commit()
                logger.info(f"创建新的未加密二维码扫描记录，最大扫描次数: {unified_max_scans}")
                qr_data = room_url
        
        # 生成二维码图片（使用微信级别参数，提高相册识别率）
        try:
            if use_encrypted:
                # 加密二维码：使用微信级别参数（box_size=5, border=2）
                qr_image_bytes = generate_qr_code_image(qr_data)
            else:
                # 明文二维码：URL较长，使用 Level H 提高容错，但保持 box_size=5, border=2 降低密度
                qr_image_bytes = generate_qr_code_image(
                    qr_data, 
                    error_correction=ERROR_CORRECT_H,  # Level H (30% 容错)，应对长URL
                    box_size=5,  # 微信级别尺寸，降低密度
                    border=2     # 减小边框，提高识别率
                )
            logger.debug(f"二维码图片生成成功，大小: {len(qr_image_bytes)} bytes，类型: {'加密' if use_encrypted else '明文'}")
        except Exception as e:
            logger.error(f"二维码图片生成失败: {type(e).__name__}: {e}", exc_info=True)
            raise ValueError(f"二维码图片生成失败: {str(e)}")
        
        return Response(
            content=qr_image_bytes,
            media_type="image/png",
            headers={
                "Content-Disposition": f"inline; filename=room_{room_id}_qrcode.png"
            }
        )
    except ValueError as e:
        logger.warning(f"二维码生成失败（ValueError）: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=i18n.t("qrcode.generate_failed", lang=lang, error=str(e))
        )
    except Exception as e:
        logger.error(f"二维码生成失败（Exception）: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=i18n.t("qrcode.generate_failed", lang=lang, error=f"{type(e).__name__}: {str(e)}")
        )


@router.get("/auth")
async def get_auth_qrcode(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    生成客户端扫码授权二维码（需登录）
    
    根据扫码配置与 CHAT_BASE_DOMAINS 列表随机生成明文或加密二维码。API 地址由
    get_random_chat_api_url() 拼接：https + 域名 + CHAT_API_PATH（如 https://log.chat5202ol.xyz/api/v1）。
    
    - 加密：simple_encrypt({"api_url":"<url>","auth_token":"<jwt>"})，默认带盐（use_salt=True）。
      **必须包含 api_url**：客户端不内置 API，API 唯一获取方式为扫码。
      客户端 simple_decrypt 后得 api_url、auth_token，再 POST {api_url}/auth/confirm-scan 提交 {"token":"<auth_token>"}。
      详见 docs/QRCODE_ENCRYPTION_DESIGN.md（带盐方案）。
    - 明文：JSON {"type":"auth_qr","token":"<jwt>","api_url":"<url>"}，客户端直接解析后
      POST {api_url}/auth/confirm-scan。
    """
    lang = current_user.language or get_language_from_request(request)
    
    try:
        # 读取扫码配置（与房间二维码一致）
        encrypted_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == "qrcode.encrypted_enabled")
        )
        encrypted_enabled_config = encrypted_enabled_result.scalar_one_or_none()
        encrypted_enabled = (
            encrypted_enabled_config
            and encrypted_enabled_config.config_value
            and encrypted_enabled_config.config_value.strip().lower() == "true"
        )

        plain_enabled_result = await db.execute(
            select(SystemConfig).where(SystemConfig.config_key == "qrcode.plain_enabled")
        )
        plain_enabled_config = plain_enabled_result.scalar_one_or_none()
        plain_enabled = (
            plain_enabled_config
            and plain_enabled_config.config_value
            and plain_enabled_config.config_value.strip().lower() == "true"
        )

        # 确定明文 / 加密：两者都开启时随机；仅一个开启则用该种；都关闭则默认加密
        if plain_enabled and encrypted_enabled:
            use_encrypted = random.choice([True, False])
            logger.debug(f"授权二维码类型随机选择: use_encrypted={use_encrypted}")
        elif plain_enabled:
            use_encrypted = False
        elif encrypted_enabled:
            use_encrypted = True
        else:
            use_encrypted = True

        # 从聊天 API 列表随机选取（含路径，如 https://log.chat5202ol.xyz/api/v1）
        api_url = get_random_chat_api_url()
        if not api_url or not api_url.strip():
            raise ValueError("聊天 API 地址为空，请检查 CHAT_BASE_DOMAINS 配置")
        logger.debug(f"授权二维码 API 地址: {api_url}")

        jwt_token = create_access_token(
            data={"sub": str(current_user.id), "type": "auth_qr"},
            expires_delta=timedelta(minutes=5),
        )
        if not jwt_token:
            raise ValueError("JWT token 生成失败")

        if use_encrypted:
            # 授权二维码必须包含 api_url：客户端不内置 API，API 唯一来源为扫码
            payload = {"api_url": api_url, "auth_token": jwt_token}
            qr_data = simple_encrypt(payload)
            logger.debug(f"加密授权二维码数据长度: {len(qr_data)}（含 api_url，供客户端获取 API）")
        else:
            qr_data = json.dumps(
                {"type": "auth_qr", "token": jwt_token, "api_url": api_url},
                ensure_ascii=False,
            )
            logger.debug(f"明文授权二维码数据长度: {len(qr_data)}（含 api_url，供客户端获取 API）")

        # 使用微信级别参数（box_size=5, border=2）降低密度，提高相册识别率
        # 加密和明文都使用相同参数，确保样式一致且易识别
        if use_encrypted:
            qr_bytes = generate_qr_code_image(
                qr_data,
                error_correction=ERROR_CORRECT_M,  # Level M (15% 容错)，平衡密度与容错
                box_size=5,  # 微信级别尺寸，降低密度
                border=2,    # 减小边框，提高识别率
            )
        else:
            qr_bytes = generate_qr_code_image(
                qr_data,
                error_correction=ERROR_CORRECT_M,  # 统一使用 Level M，避免版本过高
                box_size=5,  # 微信级别尺寸，降低密度
                border=2,    # 减小边框，提高识别率
            )
        if not qr_bytes or len(qr_bytes) == 0:
            raise ValueError("生成的二维码图片数据为空")
        logger.info(f"授权二维码生成成功，类型: {'加密' if use_encrypted else '明文'}，图片大小: {len(qr_bytes)} bytes")

        return Response(
            content=qr_bytes,
            media_type="image/png",
            headers={"Content-Disposition": "inline; filename=auth_qrcode.png"},
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"授权二维码生成过程发生未预期错误: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"生成授权二维码失败: {str(e)}",
        )
