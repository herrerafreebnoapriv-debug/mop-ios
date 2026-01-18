#!/usr/bin/env python3
"""
域名配置验证脚本
用于验证域名配置是否正确，包括 DNS 解析、SSL 证书、API 可访问性等
"""

import os
import sys
import subprocess
import requests
import socket
from urllib.parse import urlparse
from typing import Dict, List, Tuple

# 颜色输出
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'

def print_success(msg: str):
    print(f"{Colors.GREEN}✓{Colors.RESET} {msg}")

def print_error(msg: str):
    print(f"{Colors.RED}✗{Colors.RESET} {msg}")

def print_warning(msg: str):
    print(f"{Colors.YELLOW}⚠{Colors.RESET} {msg}")

def print_info(msg: str):
    print(f"{Colors.BLUE}ℹ{Colors.RESET} {msg}")

# 域名配置
DOMAINS = {
    'chat5202ol.xyz': '89.223.95.18',
    'www.chat5202ol.xyz': '89.223.95.18',
    'api.chat5202ol.xyz': '89.223.95.18',
    'app.chat5202ol.xyz': '89.223.95.18',
}

def check_dns_resolution(domain: str, expected_ip: str) -> Tuple[bool, str]:
    """检查 DNS 解析"""
    try:
        ip = socket.gethostbyname(domain)
        if ip == expected_ip:
            return True, ip
        else:
            return False, f"解析到 {ip}，期望 {expected_ip}"
    except socket.gaierror as e:
        return False, str(e)

def check_ssl_certificate(domain: str) -> Tuple[bool, str]:
    """检查 SSL 证书（简单检查）"""
    try:
        import ssl
        context = ssl.create_default_context()
        with socket.create_connection((domain, 443), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname=domain) as ssock:
                cert = ssock.getpeercert()
                return True, "SSL 证书有效"
    except Exception as e:
        return False, str(e)

def check_https_access(url: str) -> Tuple[bool, str, int]:
    """检查 HTTPS 访问"""
    try:
        response = requests.get(url, timeout=10, verify=True, allow_redirects=True)
        return True, f"状态码: {response.status_code}", response.status_code
    except requests.exceptions.SSLError as e:
        return False, f"SSL 错误: {str(e)}", 0
    except requests.exceptions.ConnectionError as e:
        return False, f"连接错误: {str(e)}", 0
    except Exception as e:
        return False, str(e), 0

def check_api_health(api_url: str) -> Tuple[bool, str]:
    """检查 API 健康状态"""
    try:
        # 健康检查端点在根路径，不在 /api/v1 下
        health_url = api_url.replace('/api/v1', '') + '/health'
        response = requests.get(health_url, timeout=10, verify=True)
        if response.status_code == 200:
            return True, "API 健康检查通过"
        else:
            return False, f"状态码: {response.status_code}"
    except Exception as e:
        return False, str(e)

def check_cors_config() -> Tuple[bool, str]:
    """检查 CORS 配置"""
    env_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env')
    if not os.path.exists(env_file):
        return False, ".env 文件不存在"
    
    with open(env_file, 'r') as f:
        content = f.read()
    
    required_domains = ['www.chat5202ol.xyz', 'app.chat5202ol.xyz', 'chat5202ol.xyz']
    missing_domains = []
    
    for domain in required_domains:
        if f"https://{domain}" not in content:
            missing_domains.append(domain)
    
    if missing_domains:
        return False, f"缺少域名: {', '.join(missing_domains)}"
    
    return True, "CORS 配置完整"

def main():
    print_info("开始验证域名配置...\n")
    
    results = {
        'dns': [],
        'ssl': [],
        'https': [],
        'api': [],
        'cors': False,
    }
    
    # 1. DNS 解析检查
    print_info("检查 DNS 解析...")
    for domain, expected_ip in DOMAINS.items():
        success, msg = check_dns_resolution(domain, expected_ip)
        results['dns'].append((domain, success, msg))
        if success:
            print_success(f"{domain} → {msg}")
        else:
            print_error(f"{domain}: {msg}")
    print()
    
    # 2. SSL 证书检查
    print_info("检查 SSL 证书...")
    for domain in DOMAINS.keys():
        success, msg = check_ssl_certificate(domain)
        results['ssl'].append((domain, success, msg))
        if success:
            print_success(f"{domain}: {msg}")
        else:
            print_error(f"{domain}: {msg}")
    print()
    
    # 3. HTTPS 访问检查
    print_info("检查 HTTPS 访问...")
    test_urls = {
        'api.chat5202ol.xyz': 'https://api.chat5202ol.xyz/health',
        'www.chat5202ol.xyz': 'https://www.chat5202ol.xyz',
        'app.chat5202ol.xyz': 'https://app.chat5202ol.xyz',
    }
    
    for domain, url in test_urls.items():
        success, msg, status_code = check_https_access(url)
        results['https'].append((domain, success, msg, status_code))
        if success:
            print_success(f"{domain}: {msg}")
        else:
            print_error(f"{domain}: {msg}")
    print()
    
    # 4. API 健康检查
    print_info("检查 API 服务...")
    # 健康检查端点在根路径
    api_url = 'https://api.chat5202ol.xyz'
    success, msg = check_api_health(api_url)
    results['api'] = (success, msg)
    if success:
        print_success(f"API 健康检查: {msg}")
    else:
        print_error(f"API 健康检查: {msg}")
    print()
    
    # 5. CORS 配置检查
    print_info("检查 CORS 配置...")
    success, msg = check_cors_config()
    results['cors'] = (success, msg)
    if success:
        print_success(f"CORS 配置: {msg}")
    else:
        print_error(f"CORS 配置: {msg}")
    print()
    
    # 总结
    print_info("验证结果总结:")
    print("=" * 60)
    
    all_dns_ok = all(success for _, success, _ in results['dns'])
    all_ssl_ok = all(success for _, success, _ in results['ssl'])
    all_https_ok = all(success for _, success, _, _ in results['https'])
    api_ok = results['api'][0]
    cors_ok = results['cors'][0]
    
    print(f"DNS 解析: {'✓ 通过' if all_dns_ok else '✗ 失败'}")
    print(f"SSL 证书: {'✓ 通过' if all_ssl_ok else '✗ 失败'}")
    print(f"HTTPS 访问: {'✓ 通过' if all_https_ok else '✗ 失败'}")
    print(f"API 服务: {'✓ 通过' if api_ok else '✗ 失败'}")
    print(f"CORS 配置: {'✓ 通过' if cors_ok else '✗ 失败'}")
    
    if all([all_dns_ok, all_ssl_ok, all_https_ok, api_ok, cors_ok]):
        print(f"\n{Colors.GREEN}所有检查通过！域名配置正确。{Colors.RESET}")
        return 0
    else:
        print(f"\n{Colors.RED}部分检查失败，请检查配置。{Colors.RESET}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
