#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
端点配置文件解析器
支持从文本文件读取域名和IP列表
"""

import re
from typing import List, Dict, Optional
from pathlib import Path


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
    
    参数:
        file_path: 配置文件路径
        
    返回:
        {
            "domains": ["domain1.com", "domain2.com"],
            "ips": ["192.168.1.1", "10.0.0.1"]
        }
    """
    file_path = Path(file_path)
    
    if not file_path.exists():
        return {"domains": [], "ips": []}
    
    domains = []
    ips = []
    current_section = None
    
    with open(file_path, 'r', encoding='utf-8') as f:
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
    
    参数:
        domains: 域名列表
        ips: IP列表
        protocol: 协议 (http/https)
        api_path: API路径前缀
        socket_path: Socket.io路径前缀
        default_port: 默认端口（如果URL中没有端口）
        
    返回:
        {
            "api_endpoints": [
                {"url": "https://domain1.com/api/v1", "priority": 0},
                ...
            ],
            "socketio_endpoints": [
                {"url": "https://domain1.com", "priority": 0},
                ...
            ]
        }
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


def load_endpoints_config(
    file_path: str,
    protocol: str = "https",
    api_path: str = "/api/v1",
    socket_path: str = "",
    default_port: Optional[int] = None
) -> Dict[str, List[Dict[str, any]]]:
    """
    从配置文件加载端点配置
    
    参数:
        file_path: 配置文件路径
        protocol: 协议
        api_path: API路径前缀
        socket_path: Socket.io路径前缀
        default_port: 默认端口
        
    返回:
        端点配置字典
    """
    parsed = parse_endpoint_file(file_path)
    return convert_to_endpoints(
        parsed["domains"],
        parsed["ips"],
        protocol=protocol,
        api_path=api_path,
        socket_path=socket_path,
        default_port=default_port
    )


if __name__ == "__main__":
    # 测试代码
    import json
    
    # 示例配置文件
    test_file = "config/endpoints.txt"
    
    # 解析文件
    parsed = parse_endpoint_file(test_file)
    print("解析结果:")
    print(f"域名: {parsed['domains']}")
    print(f"IP: {parsed['ips']}")
    
    # 转换为端点配置
    config = convert_to_endpoints(
        parsed["domains"],
        parsed["ips"],
        protocol="https",
        api_path="/api/v1",
        socket_path="",
        default_port=None
    )
    
    print("\n端点配置:")
    print(json.dumps(config, indent=2, ensure_ascii=False))
