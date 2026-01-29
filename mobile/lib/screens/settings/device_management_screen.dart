import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../../services/api/devices_api_service.dart';
import '../../services/data/app_list_service.dart';

/// 设备管理页面
/// 展示设备信息、安全状态、数据同步入口
class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  Map<String, dynamic>? _deviceInfo;
  String? _fingerprint;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await AppListService.instance.getDeviceInfo();
      String? fp;
      try {
        final plugin = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final android = await plugin.androidInfo;
          fp = android.id;
        } else if (Platform.isIOS) {
          final ios = await plugin.iosInfo;
          fp = ios.identifierForVendor;
        }
      } catch (_) {}
      setState(() {
        _deviceInfo = info;
        _fingerprint = fp;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _registerDevice() async {
    if (_fingerprint == null || _fingerprint!.isEmpty) return;
    try {
      var model = 'Unknown';
      if (_deviceInfo != null) {
        final m = '${_deviceInfo!['manufacturer'] ?? ''} ${_deviceInfo!['model'] ?? ''}'.trim();
        if (m.isNotEmpty) model = m;
      }
      await DevicesApiService().register({
        'device_fingerprint': _fingerprint!,
        'device_model': model,
        'is_rooted': false,
        'is_vpn_proxy': false,
        'is_emulator': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設備已註冊')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設備管理'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '設備資訊',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _row('型號', _deviceInfo?['model']?.toString() ?? '—'),
                        _row('廠商', _deviceInfo?['manufacturer']?.toString() ?? '—'),
                        _row('系統版本', _deviceInfo?['version'] ?? _deviceInfo?['system_version'] ?? '—'),
                        _row('指紋', _fingerprint != null && _fingerprint!.isNotEmpty
                            ? '${_fingerprint!.substring(0, _fingerprint!.length > 16 ? 16 : _fingerprint!.length)}...'
                            : '—'),
                      ],
                    ),
                  ),
                ),
                if (_fingerprint != null && _fingerprint!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _registerDevice,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('註冊設備'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
