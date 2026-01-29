#!/usr/bin/env python3
"""修复 apiurl Jitsi 的 Nginx 配置：添加 map、修正 location 嵌套、为 /xmpp-websocket 和 /http-bind 添加 WebSocket 支持。"""
import re
import sys

MOP = "/etc/nginx/sites-available/mop"
MAP_BLOCK = '''# WebSocket upgrade（Jitsi /xmpp-websocket 等必需）
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

'''

OLD_HTTPS_APIURL = r'''# HTTPS 服务器 - Jitsi Meet \(apiurl\.chat5202ol\.xyz\)
# 等 SSL 证书申请成功后，取消注释以下配置并注释掉上面的 HTTP server
server \{
    listen 443 ssl http2;
    listen \[::\]:443 ssl http2;
    server_name apiurl\.chat5202ol\.xyz;
    
    # SSL 证书（Let's Encrypt）
    ssl_certificate /etc/letsencrypt/live/apiurl\.chat5202ol\.xyz/fullchain\.pem;
    ssl_certificate_key /etc/letsencrypt/live/apiurl\.chat5202ol\.xyz/privkey\.pem;
    
    # SSL 配置
    ssl_protocols TLSv1\.2 TLSv1\.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 反向代理到 Jitsi 容器
    location / \{
        proxy_pass http://127\.0\.0\.1:8080;
        proxy_http_version 1\.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
        
        proxy_buffering off;
        proxy_request_buffering off;
    
    # Jitsi 自定义资源（Logo、Favicon 等）
    location /custom/ \{
        alias /opt/jitsi-meet-cfg/web/custom/;
        expires 7d;
        add_header Cache-Control "public, immutable";
    \}
    \}
\}'''

NEW_HTTPS_APIURL = '''# HTTPS 服务器 - Jitsi Meet (apiurl.chat5202ol.xyz)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name apiurl.chat5202ol.xyz;

    ssl_certificate /etc/letsencrypt/live/apiurl.chat5202ol.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/apiurl.chat5202ol.xyz/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location = /xmpp-websocket {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
        proxy_buffering off;
    }

    location = /http-bind {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
        proxy_buffering off;
    }

    location /custom/ {
        alias /opt/jitsi-meet-cfg/web/custom/;
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_connect_timeout 7d;
        proxy_send_timeout 7d;
        proxy_read_timeout 7d;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}'''


def main():
    with open(MOP, "r", encoding="utf-8") as f:
        content = f.read()

    if "map $http_upgrade $connection_upgrade" not in content:
        idx = content.find("upstream mop_backend")
        if idx == -1:
            idx = content.find("# 上游服务器")
        if idx == -1:
            idx = 0
        content = content[:idx] + MAP_BLOCK + content[idx:]

    # 定位 apiurl HTTPS server 块并替换
    start = content.find("# HTTPS 服务器 - Jitsi Meet (apiurl.chat5202ol.xyz)")
    if start == -1:
        print("未找到 apiurl HTTPS server 块")
        sys.exit(1)
    depth = 0
    i = start
    end = start
    while i < len(content):
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
        i += 1
    if depth != 0:
        print("未正确匹配 server 块大括号")
        sys.exit(1)
    before = content[:start].rstrip()
    after = content[end:].lstrip()
    new_content = before + "\n\n" + NEW_HTTPS_APIURL + "\n" + after

    with open(MOP, "w", encoding="utf-8") as f:
        f.write(new_content)
    print("Nginx 配置已更新")


if __name__ == "__main__":
    main()
