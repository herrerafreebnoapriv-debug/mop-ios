/// 用户模型
class UserModel {
  final int id;
  final String phone;
  final String? username;
  final String? nickname;
  final bool isOnline;
  final bool? isAdmin;
  final String? role;
  final DateTime createdAt;
  
  UserModel({
    required this.id,
    required this.phone,
    this.username,
    this.nickname,
    required this.isOnline,
    this.isAdmin,
    this.role,
    required this.createdAt,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      phone: json['phone'] as String,
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool?,
      role: json['role'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'username': username,
      'nickname': nickname,
      'is_online': isOnline,
      'is_admin': isAdmin,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Token 响应模型
class TokenResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  
  TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });
  
  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': tokenType,
    };
  }
}
