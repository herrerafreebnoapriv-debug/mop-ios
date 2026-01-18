import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络状态监听服务
/// 监听网络连接状态变化
class NetworkService {
  static final NetworkService instance = NetworkService._internal();
  NetworkService._internal();
  
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  
  bool _isConnected = true;
  ConnectivityResult _currentResult = ConnectivityResult.none;
  
  bool get isConnected => _isConnected;
  ConnectivityResult get currentResult => _currentResult;
  
  // 网络状态变化回调
  Function(bool isConnected)? onNetworkStatusChanged;
  
  /// 初始化网络监听
  void init() {
    _checkInitialStatus();
    _startListening();
  }
  
  /// 检查初始网络状态
  Future<void> _checkInitialStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateStatus([result]);
    } catch (e) {
      _isConnected = false;
      _currentResult = ConnectivityResult.none;
    }
  }
  
  /// 开始监听网络状态变化
  void _startListening() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _updateStatus([result]);
      },
      onError: (error) {
        _isConnected = false;
        _currentResult = ConnectivityResult.none;
        onNetworkStatusChanged?.call(false);
      },
    );
  }
  
  /// 更新网络状态
  void _updateStatus(List<ConnectivityResult> results) {
    final previousStatus = _isConnected;
    
    // 检查是否有任何可用的连接
    _isConnected = results.any((result) => 
      result != ConnectivityResult.none
    );
    
    _currentResult = results.isNotEmpty 
        ? results.first 
        : ConnectivityResult.none;
    
    // 如果状态发生变化，触发回调
    if (previousStatus != _isConnected) {
      onNetworkStatusChanged?.call(_isConnected);
    }
  }
  
  /// 检查当前网络状态
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }
  
  /// 停止监听
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
