#!/bin/bash
# Jitsi 去品牌化和去除外链脚本
# 在 Jitsi 容器启动后自动执行，替换图标、favicon 并去除外链

set -e

JITSI_CONFIG_DIR="${JITSI_CONFIG_DIR:-/opt/jitsi-meet-cfg}"
ICON_DIR="/opt/mop/mop_ico_fav"
LOGO_DIR="${ICON_DIR}/jit_logo"

echo "=========================================="
echo "Jitsi 去品牌化和去除外链"
echo "=========================================="

# 0. 修复 WebSocket 代理配置（使用容器名而不是域名）
echo ""
echo "0. 修复 WebSocket 代理配置..."
docker exec jitsi_web sed -i 's|proxy_pass http://xmpp.meet.jitsi:5280|proxy_pass http://jitsi_prosody:5280|g' /config/nginx/meet.conf 2>/dev/null || true
docker exec jitsi_web nginx -s reload 2>/dev/null || true
echo "   ✅ WebSocket 代理配置已修复"

# 检查资源目录
if [ ! -d "$ICON_DIR" ]; then
    echo "❌ 图标目录不存在: $ICON_DIR"
    exit 1
fi

if [ ! -d "$LOGO_DIR" ]; then
    echo "❌ Logo 目录不存在: $LOGO_DIR"
    exit 1
fi

# 等待 Jitsi 容器启动
echo ""
echo "等待 Jitsi Web 容器启动..."
for i in {1..30}; do
    if docker ps --format '{{.Names}}' | grep -q "^jitsi_web$"; then
        echo "✅ Jitsi Web 容器已启动"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Jitsi Web 容器未启动，跳过自定义配置"
        exit 1
    fi
    sleep 1
done

# 等待配置文件生成
echo ""
echo "等待配置文件生成..."
sleep 5

# 检查配置文件是否存在
if [ ! -f "$JITSI_CONFIG_DIR/web/interface_config.js" ]; then
    echo "⚠️  配置文件不存在，等待生成..."
    sleep 10
fi

# 1. 随机选择 favicon（方形图标）
echo ""
echo "1. 替换 favicon..."
FAVICON_FILES=($(find "$ICON_DIR" -maxdepth 1 -name "*.png" -type f | grep -v "jit_log" | grep -v "selected_"))
if [ ${#FAVICON_FILES[@]} -gt 0 ]; then
    RANDOM_FAVICON="${FAVICON_FILES[$RANDOM % ${#FAVICON_FILES[@]}]}"
    echo "   选择 favicon: $(basename "$RANDOM_FAVICON")"
    
    # 复制到容器配置目录
    docker cp "$RANDOM_FAVICON" jitsi_web:/usr/share/jitsi-meet/images/favicon.ico 2>/dev/null || true
    docker cp "$RANDOM_FAVICON" jitsi_web:/usr/share/jitsi-meet/favicon.ico 2>/dev/null || true
    
    # 也复制到配置目录（如果容器使用）
    cp "$RANDOM_FAVICON" "$JITSI_CONFIG_DIR/web/favicon.ico" 2>/dev/null || true
    echo "   ✅ Favicon 已替换"
else
    echo "   ⚠️  未找到 favicon 文件"
fi

# 2. 随机选择首页左上角 logo
echo ""
echo "2. 替换首页左上角 logo..."
LOGO_FILES=($(find "$LOGO_DIR" -name "*.png" -type f))
if [ ${#LOGO_FILES[@]} -gt 0 ]; then
    RANDOM_LOGO="${LOGO_FILES[$RANDOM % ${#LOGO_FILES[@]}]}"
    echo "   选择 logo: $(basename "$RANDOM_LOGO")"
    
    # 替换 watermark.svg（首页左上角）
    docker cp "$RANDOM_LOGO" jitsi_web:/usr/share/jitsi-meet/images/watermark.svg 2>/dev/null || true
    docker cp "$RANDOM_LOGO" jitsi_web:/usr/share/jitsi-meet/images/watermark.png 2>/dev/null || true
    
    # 替换默认欢迎页 logo
    docker cp "$RANDOM_LOGO" jitsi_web:/usr/share/jitsi-meet/images/logo.svg 2>/dev/null || true
    docker cp "$RANDOM_LOGO" jitsi_web:/usr/share/jitsi-meet/images/logo.png 2>/dev/null || true
    
    echo "   ✅ Logo 已替换"
else
    echo "   ⚠️  未找到 logo 文件"
fi

# 3. 修改 interface_config.js 去除外链和品牌
echo ""
echo "3. 修改 interface_config.js 去除外链..."

# 使用项目中的模板文件
CUSTOM_INTERFACE_CONFIG="/opt/mop/docker/jitsi/custom/interface_config.js"
if [ -f "$CUSTOM_INTERFACE_CONFIG" ]; then
    echo "   使用项目模板文件: $CUSTOM_INTERFACE_CONFIG"
    cp "$CUSTOM_INTERFACE_CONFIG" /tmp/interface_config_custom.js
else
    echo "   模板文件不存在，创建默认配置"
    # 如果没有模板文件，创建默认配置
    cat > /tmp/interface_config_custom.js << 'EOF'
/* eslint-disable no-unused-vars, no-var, max-len */
/* 自定义配置 - 去 Jitsi 化和去除外链 */

var interfaceConfig = {
    APP_NAME: '和平信使',
    AUDIO_LEVEL_PRIMARY_COLOR: 'rgba(255,255,255,0.4)',
    AUDIO_LEVEL_SECONDARY_COLOR: 'rgba(255,255,255,0.2)',
    AUTO_PIN_LATEST_SCREEN_SHARE: 'remote-only',
    
    // 去除所有外链
    BRAND_WATERMARK_LINK: '',
    JITSI_WATERMARK_LINK: '',
    
    CLOSE_PAGE_GUEST_HINT: false,
    DEFAULT_BACKGROUND: '#040404',
    DEFAULT_WELCOME_PAGE_LOGO_URL: 'images/watermark.svg',
    
    DISABLE_DOMINANT_SPEAKER_INDICATOR: false,
    DISABLE_JOIN_LEAVE_NOTIFICATIONS: false,
    DISABLE_PRESENCE_STATUS: false,
    DISABLE_TRANSCRIPTION_SUBTITLES: false,
    DISABLE_VIDEO_BACKGROUND: false,
    
    // 禁用欢迎页内容
    DISPLAY_WELCOME_FOOTER: false,
    DISPLAY_WELCOME_PAGE_ADDITIONAL_CARD: false,
    DISPLAY_WELCOME_PAGE_CONTENT: false,
    DISPLAY_WELCOME_PAGE_TOOLBAR_ADDITIONAL_CONTENT: false,
    
    // 禁用外链功能
    ENABLE_DIAL_OUT: false,
    
    FILM_STRIP_MAX_HEIGHT: 120,
    GENERATE_ROOMNAMES_ON_WELCOME_PAGE: false,
    HIDE_INVITE_MORE_HEADER: true,
    
    LANG_DETECTION: true,
    LOCAL_THUMBNAIL_RATIO: 16 / 9,
    MAXIMUM_ZOOMING_COEFFICIENT: 1.3,
    
    // 禁用移动应用推广（外链）
    MOBILE_APP_PROMO: false,
    
    OPTIMAL_BROWSERS: [ 'chrome', 'chromium', 'firefox', 'electron', 'safari', 'webkit' ],
    
    // 去除品牌水印
    SHOW_BRAND_WATERMARK: false,
    SHOW_JITSI_WATERMARK: false,
    SHOW_POWERED_BY: false,
    SHOW_WATERMARK_FOR_GUESTS: false,
    
    // 工具栏按钮（去除可能包含外链的功能）
    TOOLBAR_BUTTONS: [
        'microphone', 'camera', 'closedcaptions', 'desktop',
        'fullscreen', 'fodeviceselection', 'hangup', 'chat',
        'settings', 'videoquality', 'filmstrip', 'stats',
        'shortcuts', 'tileview', 'raisehand'
    ],
    
    // 设置部分
    SETTINGS_SECTIONS: ['devices', 'language', 'moderator', 'profile'],
    
    // 其他配置
    TILE_VIEW_MAX_COLUMNS: 5,
    VIDEO_LAYOUT_FIT: 'both',
    VERTICAL_FILMSTRIP: false,
    WHITEBOARD_ENABLED: false,
    
    // 禁用可能包含外链的功能
    RECORDING_SERVICE: { enabled: false },
    LIVE_STREAMING: { enabled: false },
    TRANSCRIPTION: { enabled: false },
    ETHERPAD: { enabled: false },
    
    // 去除分析（可能包含外链）
    ANALYTICS: {},
    
    // 禁用邀请功能（可能包含外链）
    DISABLE_INVITE_FUNCTIONS: true,
    DISABLE_THIRD_PARTY_REQUESTS: true,
    
    // 去除移动应用下载链接（外链）
    MOBILE_DOWNLOAD_LINK_IOS: '',
    MOBILE_DOWNLOAD_LINK_ANDROID: '',
    MOBILE_DOWNLOAD_LINK_F_DROID: '',
    HIDE_DEEP_LINKING_LOGO: true,
    
    // 去除其他外链
    LIVE_STREAMING_HELP_LINK: '',
    POLICY_LOGO: null
};
EOF

# 复制到主机配置目录和容器
cp /tmp/interface_config_custom.js "$JITSI_CONFIG_DIR/web/interface_config.js" 2>/dev/null || true
docker cp /tmp/interface_config_custom.js jitsi_web:/config/interface_config.js 2>/dev/null || {
    echo "   ⚠️  容器内复制失败，将在容器重启后生效"
}

echo "   ✅ interface_config.js 已更新"

# 3.5. 替换标题文件（title.html）
echo ""
echo "3.5. 替换标题文件..."
CUSTOM_TITLE="/opt/mop/docker/jitsi/custom/title.html"
if [ -f "$CUSTOM_TITLE" ]; then
    echo "   使用项目模板文件: $CUSTOM_TITLE"
    # 复制到容器
    docker cp "$CUSTOM_TITLE" jitsi_web:/usr/share/jitsi-meet/title.html 2>/dev/null || true
    # 也复制到配置目录（如果容器使用）
    cp "$CUSTOM_TITLE" "$JITSI_CONFIG_DIR/web/title.html" 2>/dev/null || true
    echo "   ✅ title.html 已替换"
else
    echo "   ⚠️  标题模板文件不存在，手动创建..."
    cat > /tmp/title_custom.html << 'EOF'
<title>Messenger of Peace</title>
<meta property="og:title" content="Messenger of Peace"/>
<meta property="og:image" content="images/watermark.svg?v=1"/>
<meta property="og:description" content="Join a WebRTC video conference powered by Messenger of Peace"/>
<meta description="Join a WebRTC video conference powered by Messenger of Peace"/>
<meta itemprop="name" content="Messenger of Peace"/>
<meta itemprop="description" content="Join a WebRTC video conference powered by Messenger of Peace"/>
<meta itemprop="image" content="images/watermark.svg?v=1"/>
<link rel="icon" href="images/favicon.svg?v=1">
EOF
    docker cp /tmp/title_custom.html jitsi_web:/usr/share/jitsi-meet/title.html 2>/dev/null || true
    cp /tmp/title_custom.html "$JITSI_CONFIG_DIR/web/title.html" 2>/dev/null || true
    echo "   ✅ title.html 已创建并替换"
fi

# 4. 修改 config.js 去除外链
echo ""
echo "4. 修改 config.js 去除外链..."

# 使用项目中的模板文件
CUSTOM_CONFIG="/opt/mop/docker/jitsi/custom/config.js"
if [ -f "$CUSTOM_CONFIG" ]; then
    echo "   使用项目模板文件"
    # 如果 config.js 存在，合并配置
    if [ -f "$JITSI_CONFIG_DIR/web/config.js" ]; then
        # 备份原配置
        cp "$JITSI_CONFIG_DIR/web/config.js" "$JITSI_CONFIG_DIR/web/config.js.bak" 2>/dev/null || true
        # 追加自定义配置
        cat "$CUSTOM_CONFIG" >> "$JITSI_CONFIG_DIR/web/config.js"
        # 复制到容器
        docker cp "$JITSI_CONFIG_DIR/web/config.js" jitsi_web:/config/config.js 2>/dev/null || true
    else
        # 直接复制模板
        cp "$CUSTOM_CONFIG" "$JITSI_CONFIG_DIR/web/config.js" 2>/dev/null || true
        docker cp "$CUSTOM_CONFIG" jitsi_web:/config/config.js 2>/dev/null || true
    fi
    echo "   ✅ config.js 已更新"
else
    # 如果没有模板文件，使用 sed 修改
    if [ -f "$JITSI_CONFIG_DIR/web/config.js" ]; then
        cp "$JITSI_CONFIG_DIR/web/config.js" "$JITSI_CONFIG_DIR/web/config.js.bak" 2>/dev/null || true
        sed -i 's|meet-jit-si-turnrelay.jitsi.net|127.0.0.1|g' "$JITSI_CONFIG_DIR/web/config.js" 2>/dev/null || true
        sed -i 's|https://.*jitsi.*|// 外链已移除|g' "$JITSI_CONFIG_DIR/web/config.js" 2>/dev/null || true
        echo "   ✅ config.js 已更新（sed 方式）"
    else
        echo "   ⚠️  config.js 不存在，跳过"
    fi
fi

# 4.5. 注入语言覆盖脚本（替换页面中的 "Jitsi Meet" 文本）
echo ""
echo "4.5. 注入语言覆盖脚本..."
CUSTOM_LANG_OVERRIDE="/opt/mop/docker/jitsi/custom/lang-override.js"
if [ -f "$CUSTOM_LANG_OVERRIDE" ]; then
    echo "   注入语言覆盖脚本"
    # 复制到容器
    docker cp "$CUSTOM_LANG_OVERRIDE" jitsi_web:/usr/share/jitsi-meet/lang-override.js 2>/dev/null || true
    
    # 修改 index.html 注入脚本（在 </head> 之前）
    docker exec jitsi_web sed -i 's|</head>|<script src="lang-override.js"></script>\n</head>|' /usr/share/jitsi-meet/index.html 2>/dev/null || true
    
    echo "   ✅ 语言覆盖脚本已注入"
else
    echo "   ⚠️  语言覆盖脚本不存在，跳过"
fi

# 4.6. 修改语言文件中的 "Jitsi Meet" 文本
echo ""
echo "4.6. 修改语言文件..."
# 修改中文语言文件
docker exec jitsi_web sed -i 's/"headerTitle": "Jitsi Meet"/"headerTitle": "Messenger of Peace"/g' /usr/share/jitsi-meet/lang/main-zh-CN.json 2>/dev/null || true
docker exec jitsi_web sed -i 's/"productLabel": ".*Jitsi Meet"/"productLabel": "Messenger of Peace"/g' /usr/share/jitsi-meet/lang/main-zh-CN.json 2>/dev/null || true

# 修改英文语言文件
docker exec jitsi_web sed -i 's/"headerTitle": "Jitsi Meet"/"headerTitle": "Messenger of Peace"/g' /usr/share/jitsi-meet/lang/main-en.json 2>/dev/null || true
docker exec jitsi_web sed -i 's/"productLabel": ".*Jitsi Meet"/"productLabel": "Messenger of Peace"/g' /usr/share/jitsi-meet/lang/main-en.json 2>/dev/null || true

# 批量修改所有语言文件
docker exec jitsi_web find /usr/share/jitsi-meet/lang -name "main-*.json" -exec sed -i 's/"headerTitle": "Jitsi Meet"/"headerTitle": "Messenger of Peace"/g' {} \; 2>/dev/null || true
docker exec jitsi_web find /usr/share/jitsi-meet/lang -name "main-*.json" -exec sed -i 's/"productLabel": ".*Jitsi Meet"/"productLabel": "Messenger of Peace"/g' {} \; 2>/dev/null || true

echo "   ✅ 语言文件已更新"

# 5. 替换其他图标文件
echo ""
echo "5. 替换其他图标文件..."

# 根据大小选择合适的图标
SMALL_ICONS=($(find "$ICON_DIR" -maxdepth 1 -name "mop-ico*.png" -type f | head -5))
LARGE_ICONS=($(find "$ICON_DIR" -maxdepth 1 -name "mop_ico*.png" -type f | head -5))

if [ ${#SMALL_ICONS[@]} -gt 0 ]; then
    RANDOM_SMALL="${SMALL_ICONS[$RANDOM % ${#SMALL_ICONS[@]}]}"
    # 替换小图标（16x16, 32x32 等）
    docker cp "$RANDOM_SMALL" jitsi_web:/usr/share/jitsi-meet/images/icon-16x16.png 2>/dev/null || true
    docker cp "$RANDOM_SMALL" jitsi_web:/usr/share/jitsi-meet/images/icon-32x32.png 2>/dev/null || true
    echo "   ✅ 小图标已替换"
fi

if [ ${#LARGE_ICONS[@]} -gt 0 ]; then
    RANDOM_LARGE="${LARGE_ICONS[$RANDOM % ${#LARGE_ICONS[@]}]}"
    # 替换大图标（192x192, 512x512 等）
    docker cp "$RANDOM_LARGE" jitsi_web:/usr/share/jitsi-meet/images/icon-192x192.png 2>/dev/null || true
    docker cp "$RANDOM_LARGE" jitsi_web:/usr/share/jitsi-meet/images/icon-512x512.png 2>/dev/null || true
    echo "   ✅ 大图标已替换"
fi

# 6. 重启容器以应用更改（可选）
echo ""
echo "=========================================="
echo "✅ Jitsi 去品牌化完成！"
echo "=========================================="
echo ""
echo "已完成的修改："
echo "  ✅ Favicon 已替换（随机选择）"
echo "  ✅ Logo 已替换（随机选择）"
echo "  ✅ interface_config.js 已更新（去除外链）"
echo "  ✅ config.js 已更新（去除外链）"
echo "  ✅ 其他图标已替换"
echo ""
echo "注意：某些更改可能需要重启容器才能生效"
echo "重启命令：docker restart jitsi_web"
echo ""
fi
