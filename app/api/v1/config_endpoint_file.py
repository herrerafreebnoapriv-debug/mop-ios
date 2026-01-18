"""
端点配置接口（从文件读取）
支持从文本文件读取域名和IP列表
"""

from fastapi import APIRouter, HTTPException
from pathlib import Path
from typing import List, Dict, Optional
import os

router = APIRouter()


def parse_endpoint_file(file_path: str) -> Dict[str, List[str]]:
    """
    解析端点配置文件
    
    文件格式：
    # 注释行
    DomainList:
    domain1.com
    domain2.com
    IPList:
    192.168.1.1
    10.0.0.1
    """
    file_path_obj = Path(file_path)
    
    if not file_path_obj.exists():
        return {"domains": [], "ips": []}
    
    domains = []
    ips = []
    current_section = None
    
    try:
        with open(file_path_obj, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                # 跳过空行和注释行
                if not line or line.startswith('#'):
                    continue
                
                # 检查是否是节标记
                if line.lower().startswith('domainlist:'):
                    current_section = 'domains'
                    continue
                elif line.lower().startswith('iplist:'):
                    current_section = 'ips'
                    continue
                
                # 根据当前节解析内容
                if current_section == 'domains':
                    # 支持逗号分隔的多个域名
                    domain_items = [item.strip() for item in line.split(',')]
                    for item in domain_items:
                        if item:
                            domains.append(item)
                elif current_section == 'ips':
                    # 支持逗号分隔的多个IP
                    ip_items = [item.strip() for item in line.split(',')]
                    for item in ip_items:
                        if item:
                            ips.append(item)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"读取配置文件失败: {str(e)}"
        )
    
    return {
        "domains": domains,
        "ips": ips
    }


def convert_to_endpoints(
    domains: List[str],
    ips: List[str],
    protocol: str = "https",
    api_path: str = "/api/v1",
    socket_path: str = "",
    default_port: Optional[int] = None
) -> Dict[str, List[Dict[str, any]]]:
    """
    将域名和IP列表转换为端点配置格式
    """
    api_endpoints = []
    socketio_endpoints = []
    
    priority = 0
    
    # 处理域名
    for domain in domains:
        # 构建 API URL
        if default_port:
            api_url = f"{protocol}://{domain}:{default_port}{api_path}"
        else:
            api_url = f"{protocol}://{domain}{api_path}"
        
        api_endpoints.append({
            "url": api_url,
            "priority": priority
        })
        
        # 构建 Socket.io URL
        if socket_path:
            socket_url = f"{protocol}://{domain}{socket_path}"
        elif default_port:
            socket_url = f"{protocol}://{domain}:{default_port}"
        else:
            socket_url = f"{protocol}://{domain}"
        
        socketio_endpoints.append({
            "url": socket_url,
            "priority": priority
        })
        
        priority += 1
    
    # 处理IP
    for ip in ips:
        # 构建 API URL
        if default_port:
            api_url = f"{protocol}://{ip}:{default_port}{api_path}"
        else:
            api_url = f"{protocol}://{ip}{api_path}"
        
        api_endpoints.append({
            "url": api_url,
            "priority": priority
        })
        
        # 构建 Socket.io URL
        if socket_path:
            socket_url = f"{protocol}://{ip}{socket_path}"
        elif default_port:
            socket_url = f"{protocol}://{ip}:{default_port}"
        else:
            socket_url = f"{protocol}://{ip}"
        
        socketio_endpoints.append({
            "url": socket_url,
            "priority": priority
        })
        
        priority += 1
    
    return {
        "api_endpoints": api_endpoints,
        "socketio_endpoints": socketio_endpoints
    }


@router.get("/config/endpoints")
async def get_endpoints():
    """
    从配置文件读取端点列表
    
    配置文件路径：通过环境变量 ENDPOINT_CONFIG_FILE 指定
    默认路径：config/endpoints.txt
    
    配置文件格式：
    # 故障转移域名列表内容
    DomainList:
    log.ym1.com
    ym2.xyz
    xx,ym3.net
    
    # 故障转移IP列表内容
    IPList:
    12.34.56.78
    9.10.11.12
    """
    # 获取配置文件路径
    config_file = os.getenv(
        "ENDPOINT_CONFIG_FILE",
        "config/endpoints.txt"
    )
    
    # 协议配置（可通过环境变量配置）
    protocol = os.getenv("ENDPOINT_PROTOCOL", "https")
    api_path = os.getenv("ENDPOINT_API_PATH", "/api/v1")
    socket_path = os.getenv("ENDPOINT_SOCKET_PATH", "")
    default_port = os.getenv("ENDPOINT_DEFAULT_PORT")
    if default_port:
        try:
            default_port = int(default_port)
        except ValueError:
            default_port = None
    
    # 解析配置文件
    parsed = parse_endpoint_file(config_file)
    
    # 转换为端点配置格式
    config = convert_to_endpoints(
        parsed["domains"],
        parsed["ips"],
        protocol=protocol,
        api_path=api_path,
        socket_path=socket_path,
        default_port=default_port
    )
    
    return config


@router.get("/config/endpoints/raw")
async def get_endpoints_raw():
    """
    获取原始端点列表（域名和IP列表，不转换）
    """
    config_file = os.getenv(
        "ENDPOINT_CONFIG_FILE",
        "config/endpoints.txt"
    )
    
    parsed = parse_endpoint_file(config_file)
    
    return {
        "domains": parsed["domains"],
        "ips": parsed["ips"]
    }
