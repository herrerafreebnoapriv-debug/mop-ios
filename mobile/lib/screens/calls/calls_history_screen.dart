import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api/calls_api_service.dart';
import '../../locales/app_localizations.dart';

/// 通话记录页面
class CallsHistoryScreen extends StatefulWidget {
  const CallsHistoryScreen({super.key});

  @override
  State<CallsHistoryScreen> createState() => _CallsHistoryScreenState();
}

class _CallsHistoryScreenState extends State<CallsHistoryScreen> {
  final CallsApiService _callsApiService = CallsApiService();
  List<dynamic> _calls = [];
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadCalls();
    _loadStats();
  }

  Future<void> _loadCalls() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final calls = await _callsApiService.getCalls(limit: 100);
      setState(() {
        _calls = calls;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _callsApiService.getCallStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      debugPrint('加载统计信息失败: $e');
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '-';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  IconData _getCallTypeIcon(String? callType) {
    switch (callType) {
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.phone;
      default:
        return Icons.call;
    }
  }

  Color _getCallStatusColor(String? status) {
    switch (status) {
      case 'connected':
      case 'ended':
        return Colors.green;
      case 'missed':
      case 'rejected':
        return Colors.red;
      case 'ringing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getCallStatusText(String? status, AppLocalizations? l10n) {
    switch (status) {
      case 'initiated':
        return l10n?.t('calls.status.initiated') ?? '已发起';
      case 'ringing':
        return l10n?.t('calls.status.ringing') ?? '响铃中';
      case 'connected':
        return l10n?.t('calls.status.connected') ?? '已接通';
      case 'ended':
        return l10n?.t('calls.status.ended') ?? '已结束';
      case 'rejected':
        return l10n?.t('calls.status.rejected') ?? '已拒绝';
      case 'missed':
        return l10n?.t('calls.status.missed') ?? '未接';
      default:
        return status ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.t('calls.title') ?? '通话记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadCalls();
              _loadStats();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadCalls,
                        child: Text(l10n?.t('common.retry') ?? '重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 统计信息卡片
                    if (_stats != null)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n?.t('calls.stats') ?? '统计信息',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(
                                  context,
                                  l10n?.t('calls.stats.total') ?? '总通话',
                                  '${_stats!['total_calls'] ?? 0}',
                                  Icons.call,
                                ),
                                _buildStatItem(
                                  context,
                                  l10n?.t('calls.stats.duration') ?? '总时长',
                                  _formatDuration(_stats!['total_duration']),
                                  Icons.access_time,
                                ),
                                _buildStatItem(
                                  context,
                                  l10n?.t('calls.stats.video') ?? '视频',
                                  '${_stats!['video_calls'] ?? 0}',
                                  Icons.videocam,
                                ),
                                _buildStatItem(
                                  context,
                                  l10n?.t('calls.stats.audio') ?? '语音',
                                  '${_stats!['audio_calls'] ?? 0}',
                                  Icons.phone,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    // 通话记录列表
                    Expanded(
                      child: _calls.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.history, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n?.t('calls.empty') ?? '暂无通话记录',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _calls.length,
                              itemBuilder: (context, index) {
                                final call = _calls[index];
                                return _buildCallItem(context, call, l10n);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCallItem(
    BuildContext context,
    Map<String, dynamic> call,
    AppLocalizations? l10n,
  ) {
    final callType = call['call_type'] as String?;
    final callStatus = call['call_status'] as String?;
    final roomName = call['room_name'] as String?;
    final callerName = call['caller_nickname'] as String? ?? '未知用户';
    final calleeName = call['callee_nickname'] as String?;
    final duration = call['duration'] as int?;
    final startTime = call['start_time'] as String?;
    final createdAt = call['created_at'] as String?;

    // 解析时间
    DateTime? callTime;
    if (startTime != null) {
      callTime = DateTime.tryParse(startTime);
    }
    if (callTime == null && createdAt != null) {
      callTime = DateTime.tryParse(createdAt);
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getCallStatusColor(callStatus).withOpacity(0.2),
        child: Icon(
          _getCallTypeIcon(callType),
          color: _getCallStatusColor(callStatus),
        ),
      ),
      title: Text(
        roomName ?? callerName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (calleeName != null && calleeName != callerName)
            Text('与 $calleeName'),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getCallStatusColor(callStatus).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getCallStatusText(callStatus, l10n),
                  style: TextStyle(
                    color: _getCallStatusColor(callStatus),
                    fontSize: 12,
                  ),
                ),
              ),
              if (duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatDuration(duration),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: callTime != null
          ? Text(
              DateFormat('MM-dd HH:mm').format(callTime),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      onTap: () {
        // 可以跳转到通话详情页面
      },
    );
  }
}
