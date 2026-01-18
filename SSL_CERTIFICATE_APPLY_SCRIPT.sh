#!/bin/bash
# log.chat5202ol.xyz SSL 证书申请脚本

echo "=========================================="
echo "log.chat5202ol.xyz SSL 证书申请"
echo "=========================================="

# 检查 DNS 解析
echo "1. 检查 DNS 解析..."
DNS_RESULT=$(nslookup log.chat5202ol.xyz 2>&1 | grep -A 2 "Name:" | tail -1 | awk '{print $2}')
if [ "$DNS_RESULT" = "89.223.95.18" ]; then
    echo "✅ DNS 解析正确: log.chat5202ol.xyz -> $DNS_RESULT"
else
    echo "❌ DNS 解析失败或未配置"
    echo "   请先在域名管理面板配置 A 记录:"
    echo "   类型: A"
    echo "   主机: log"
    echo "   值: 89.223.95.18"
    exit 1
fi

# 申请 SSL 证书
echo ""
echo "2. 申请 Let's Encrypt SSL 证书..."
certbot certonly --webroot \
  -w /var/www/certbot \
  -d log.chat5202ol.xyz \
  --email admin@chat5202ol.xyz \
  --agree-tos \
  --non-interactive

if [ $? -eq 0 ]; then
    echo "✅ SSL 证书申请成功"
    
    # 更新 Nginx 配置
    echo ""
    echo "3. 更新 Nginx 配置..."
    sudo sed -i 's|# ssl_certificate /etc/letsencrypt/live/log.chat5202ol.xyz/fullchain.pem;|ssl_certificate /etc/letsencrypt/live/log.chat5202ol.xyz/fullchain.pem;|' /etc/nginx/sites-available/mop
    sudo sed -i 's|# ssl_certificate_key /etc/letsencrypt/live/log.chat5202ol.xyz/privkey.pem;|ssl_certificate_key /etc/letsencrypt/live/log.chat5202ol.xyz/privkey.pem;|' /etc/nginx/sites-available/mop
    sudo sed -i 's|ssl_certificate /etc/letsencrypt/live/www.chat5202ol.xyz/fullchain.pem;|# ssl_certificate /etc/letsencrypt/live/www.chat5202ol.xyz/fullchain.pem;|' /etc/nginx/sites-available/mop
    sudo sed -i 's|ssl_certificate_key /etc/letsencrypt/live/www.chat5202ol.xyz/privkey.pem;|# ssl_certificate_key /etc/letsencrypt/live/www.chat5202ol.xyz/privkey.pem;|' /etc/nginx/sites-available/mop
    
    # 测试 Nginx 配置
    echo ""
    echo "4. 测试 Nginx 配置..."
    if sudo nginx -t; then
        echo "✅ Nginx 配置测试通过"
        
        # 重新加载 Nginx
        echo ""
        echo "5. 重新加载 Nginx..."
        sudo systemctl reload nginx
        echo "✅ Nginx 已重新加载"
        
        echo ""
        echo "=========================================="
        echo "✅ SSL 证书配置完成！"
        echo "=========================================="
        echo ""
        echo "访问地址:"
        echo "  - https://log.chat5202ol.xyz/chat"
        echo "  - https://log.chat5202ol.xyz/api/v1/chat/"
        echo ""
    else
        echo "❌ Nginx 配置测试失败，请检查配置"
        exit 1
    fi
else
    echo "❌ SSL 证书申请失败"
    echo "   请检查 DNS 配置和网络连接"
    exit 1
fi
