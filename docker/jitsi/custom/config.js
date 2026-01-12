// Jitsi Meet 配置 - 去除外链
// 此文件会在容器启动时自动合并到 /config/config.js

var config = {};

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

// STUN 服务器配置（WebRTC NAT 穿透必需）
// 使用公共 STUN 服务器或自建
config.p2p = {
    stunServers: [
        {
            urls: 'stun:stun.l.google.com:19302'
        },
        {
            urls: 'stun:stun1.l.google.com:19302'
        }
    ]
};

// 如果使用 TURN 服务器（可选，用于更复杂的 NAT 环境）
// config.iceServers = [
//     {
//         urls: 'turn:your-turn-server.com:3478',
//         username: 'username',
//         credential: 'password'
//     }
// ];

// 其他配置
config.enableJwt = true;
config.enableWelcomePage = false;
