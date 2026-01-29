// Jitsi Meet 配置 - 去除外链（追加到 /config/config.js，勿覆盖 var config）

// 禁用所有可能包含外链的功能
config.disableInviteFunctions = true;
config.disableThirdPartyRequests = true;
config.enableCalendarIntegration = false;
config.mobileAppPromo = false;

// 禁用录制、直播、转录等可能包含外链的服务
config.recordingService = { enabled: false };
config.liveStreaming = { enabled: false };
config.transcription = { enabled: false };
config.etherpad = { enabled: false };

// 禁用分析（可能包含外链）
config.analytics = {};

// 禁用所有外链 STUN/TURN，仅使用自建环境
config.p2p = { stunServers: [] };

// 其他配置
config.enableJwt = true;
config.enableWelcomePage = false;

// 彻底去除会议内 watermark.svg（房间左上角 logo）
config.defaultLogoUrl = '';

// 完全使用自部署域名（由前端动态设置，此处仅作说明）
// 注意：hosts.domain 由前端 room.html 动态设置为实际服务器域名
// Prosody 内部仍使用 meet.jitsi 作为 XMPP 域名，但客户端通过实际域名连接
