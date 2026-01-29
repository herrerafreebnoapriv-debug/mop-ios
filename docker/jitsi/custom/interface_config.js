/* eslint-disable no-unused-vars, no-var, max-len */
/* 自定义配置 - 去 Jitsi 化和去除外链 */
/* 此文件会在容器启动时自动复制到 /config/interface_config.js */

var interfaceConfig = {
    APP_NAME: 'Messenger of Peace',
    AUDIO_LEVEL_PRIMARY_COLOR: 'rgba(255,255,255,0.4)',
    AUDIO_LEVEL_SECONDARY_COLOR: 'rgba(255,255,255,0.2)',
    AUTO_PIN_LATEST_SCREEN_SHARE: 'remote-only',
    
    // 去除所有外链
    BRAND_WATERMARK_LINK: '',
    JITSI_WATERMARK_LINK: '',
    
    CLOSE_PAGE_GUEST_HINT: false,
    DEFAULT_BACKGROUND: '#040404',
    DEFAULT_WELCOME_PAGE_LOGO_URL: '',
    
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
    MOBILE_DOWNLOAD_LINK_IOS: '',
    MOBILE_DOWNLOAD_LINK_ANDROID: '',
    MOBILE_DOWNLOAD_LINK_F_DROID: '',
    HIDE_DEEP_LINKING_LOGO: true,
    
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
    
    // 去除其他外链
    LIVE_STREAMING_HELP_LINK: '',
    POLICY_LOGO: null
};
