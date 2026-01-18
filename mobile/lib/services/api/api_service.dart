import 'dart:convert';
import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/endpoint_manager.dart';

/// API 服务基类
/// 封装 HTTP 请求，处理认证、错误处理等
class ApiService {
  late Dio _dio;
  
  ApiService() {
    _dio = Dio();
    
    // 配置拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // 添加认证头
        final token = await StorageService.instance.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        // 设置内容类型（仅在未设置时设置，避免覆盖 form-data）
        if (!options.headers.containsKey('Content-Type')) {
          options.headers['Content-Type'] = 'application/json';
        }
        
        return handler.next(options);
      },
      onResponse: (response, handler) {
        return handler.next(response);
      },
      onError: (error, handler) async {
        // Token 过期，尝试刷新
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            // 重试原请求
            final opts = error.requestOptions;
            final token = await StorageService.instance.getToken();
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }
  
  /// 刷新令牌
  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await StorageService.instance.getRefreshToken();
      if (refreshToken == null) {
        return false;
      }
      
      final response = await _dio.post(
        '${AppConfig.instance.apiBaseUrl}/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      
      if (response.statusCode == 200 && response.data['access_token'] != null) {
        await StorageService.instance.saveToken(response.data['access_token']);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// GET 请求（支持自动故障转移）
  Future<Map<String, dynamic>?> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return await _requestWithFailover(
      (baseUrl) => _dio.get(
        '$baseUrl$path',
        queryParameters: queryParameters,
      ),
    );
  }
  
  /// 带故障转移的请求
  Future<Map<String, dynamic>?> _requestWithFailover(
    Future<Response> Function(String baseUrl) requestFn,
  ) async {
    final endpoints = EndpointManager.instance.apiEndpoints;
    if (endpoints.isEmpty) {
      final baseUrl = AppConfig.instance.apiBaseUrl;
      if (baseUrl == null || baseUrl.isEmpty) {
        throw Exception('API 地址未配置，请先扫码');
      }
      // 使用单个端点
      return await _executeRequest(baseUrl, requestFn);
    }
    
    // 尝试所有健康的端点
    final healthyEndpoints = endpoints.where((e) => e.isHealthy).toList();
    if (healthyEndpoints.isEmpty) {
      // 如果没有健康的端点，尝试所有端点
      for (final endpoint in endpoints) {
        try {
          final result = await _executeRequest(endpoint.url, requestFn);
          return result;
        } catch (e) {
          // 标记端点失败
          await EndpointManager.instance.markEndpointFailed(endpoint.url);
          continue;
        }
      }
      throw Exception('所有 API 端点均不可用');
    }
    
    // 按优先级尝试
    for (final endpoint in healthyEndpoints) {
      try {
        final result = await _executeRequest(endpoint.url, requestFn);
        return result;
      } catch (e) {
        // 标记端点失败
        await EndpointManager.instance.markEndpointFailed(endpoint.url);
        // 如果是网络错误，继续尝试下一个端点
        if (e is DioException && 
            (e.type == DioExceptionType.connectionTimeout ||
             e.type == DioExceptionType.receiveTimeout ||
             e.type == DioExceptionType.connectionError)) {
          continue;
        }
        // 其他错误直接抛出
        rethrow;
      }
    }
    
    throw Exception('所有 API 端点均不可用');
  }
  
  /// 执行请求
  Future<Map<String, dynamic>?> _executeRequest(
    String baseUrl,
    Future<Response> Function(String baseUrl) requestFn,
  ) async {
    try {
      final response = await requestFn(baseUrl);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data is Map) {
          return response.data as Map<String, dynamic>;
        } else if (response.data is String) {
          return jsonDecode(response.data) as Map<String, dynamic>;
        }
      }
      
      // 处理错误响应
      if (response.statusCode != null && response.statusCode! >= 400) {
        String errorMessage = '请求失败';
        if (response.data is Map) {
          final errorData = response.data as Map<String, dynamic>;
          // FastAPI 错误格式：{"detail": "错误信息"}
          if (errorData.containsKey('detail')) {
            errorMessage = errorData['detail'].toString();
          } else if (errorData.containsKey('message')) {
            errorMessage = errorData['message'].toString();
          } else if (errorData.containsKey('error')) {
            errorMessage = errorData['error'].toString();
          }
        } else if (response.data is String) {
          errorMessage = response.data as String;
        }
        throw Exception(errorMessage);
      }
      
      return null;
    } on DioException catch (e) {
      // 处理 Dio 异常
      String errorMessage = '网络请求失败';
      
      if (e.response != null) {
        // 有响应，提取错误信息
        final response = e.response!;
        if (response.data is Map) {
          final errorData = response.data as Map<String, dynamic>;
          if (errorData.containsKey('detail')) {
            errorMessage = errorData['detail'].toString();
          } else if (errorData.containsKey('message')) {
            errorMessage = errorData['message'].toString();
          } else if (errorData.containsKey('error')) {
            errorMessage = errorData['error'].toString();
          }
        } else if (response.data is String) {
          errorMessage = response.data as String;
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = '连接超时，请检查网络';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = '接收超时，请检查网络';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = '网络连接失败，请检查网络设置';
      }
      
      throw Exception(errorMessage);
    } catch (e) {
      // 其他异常直接抛出
      rethrow;
    }
  }
  
  /// POST 请求（支持自动故障转移）
  Future<Map<String, dynamic>?> post(
    String path, {
    Map<String, dynamic>? data,
    bool isFormData = false,  // 是否使用 form-urlencoded 格式（OAuth2 需要）
  }) async {
    return await _requestWithFailover(
      (baseUrl) {
        if (isFormData) {
          // 使用 application/x-www-form-urlencoded 格式（OAuth2PasswordRequestForm 需要）
          // Dio 会自动处理，只需要设置正确的 Content-Type
          return _dio.post(
            '$baseUrl$path',
            data: data,
            options: Options(
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              contentType: Headers.formUrlEncodedContentType,
            ),
          );
        } else {
          // 使用 JSON 格式
          return _dio.post(
            '$baseUrl$path',
            data: data,
          );
        }
      },
    );
  }
  
  /// PUT 请求（支持自动故障转移）
  Future<Map<String, dynamic>?> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    return await _requestWithFailover(
      (baseUrl) => _dio.put(
        '$baseUrl$path',
        data: data,
      ),
    );
  }
  
  /// DELETE 请求（支持自动故障转移）
  Future<bool> delete(String path) async {
    try {
      final result = await _requestWithFailover(
        (baseUrl) => _dio.delete('$baseUrl$path'),
      );
      return result != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 上传文件（multipart/form-data，支持自动故障转移）
  Future<Map<String, dynamic>?> uploadFile(
    String path,
    String filePath, {
    String fieldName = 'file',
    Map<String, dynamic>? additionalData,
  }) async {
    final formData = FormData();
    formData.files.add(MapEntry(
      fieldName,
      await MultipartFile.fromFile(filePath),
    ));
    
    if (additionalData != null) {
      additionalData.forEach((key, value) {
        formData.fields.add(MapEntry(key, value.toString()));
      });
    }
    
    return await _requestWithFailover(
      (baseUrl) => _dio.post(
        '$baseUrl$path',
        data: formData,
      ),
    );
  }
}
