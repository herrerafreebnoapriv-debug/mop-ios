import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../locales/app_localizations.dart';
import '../../services/api/rooms_api_service.dart';
import '../room/room_screen.dart';
import '../qr/scan_screen.dart';
import 'room_qr_share_screen.dart';
import '../../core/config/app_config.dart';

/// 房间列表页面
class RoomsListScreen extends StatefulWidget {
  const RoomsListScreen({super.key});

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  final RoomsApiService _roomsApiService = RoomsApiService();
  List<dynamic> _rooms = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rooms = await _roomsApiService.getRooms();
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createRoom() async {
    final roomNameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.t('rooms.create') ?? '创建房间'),
        content: TextField(
          controller: roomNameController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)?.t('rooms.room_name') ?? '房间名称（可选）',
            hintText: AppLocalizations.of(context)?.t('rooms.room_name_hint') ?? '留空将使用默认名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context)?.t('common.cancel') ?? '取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(roomNameController.text),
            child: Text(AppLocalizations.of(context)?.t('common.create') ?? '创建'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final response = await _roomsApiService.createRoom(
          roomName: result.isEmpty ? null : result,
        );

        if (response != null && mounted) {
          final l10n = AppLocalizations.of(context);
          final roomId = response['room_id']?.toString() ?? '';
          final roomName = response['room_name']?.toString() ?? roomId;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n?.t('rooms.created') ?? '房间创建成功'),
              backgroundColor: Colors.green,
            ),
          );
          
          // 跳转到房间
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RoomScreen(
                roomId: roomId,
                roomName: roomName,
              ),
            ),
          );
          
          // 刷新列表
          _loadRooms();
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n?.t('errors.create_failed') ?? '创建失败'}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _joinRoomByQR() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScanScreen(
          publicKeyPem: AppConfig.instance.rsaPublicKey,
          isForLogin: false,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      final roomId = result['room_id']?.toString();
      if (roomId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => RoomScreen(
              roomId: roomId,
              roomName: result['room_name']?.toString(),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n?.t('rooms.title') ?? '房间列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _joinRoomByQR,
            tooltip: l10n?.t('rooms.scan_qr') ?? '扫码加入房间',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createRoom,
            tooltip: l10n?.t('rooms.create') ?? '创建房间',
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
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRooms,
                        child: Text(l10n?.t('common.retry') ?? '重试'),
                      ),
                    ],
                  ),
                )
              : _rooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.video_call_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.t('rooms.no_rooms') ?? '暂无房间',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _createRoom,
                            icon: const Icon(Icons.add),
                            label: Text(l10n?.t('rooms.create') ?? '创建房间'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadRooms,
                      child: ListView.builder(
                        itemCount: _rooms.length,
                        itemBuilder: (context, index) {
                          final room = _rooms[index];
                          final roomId = room['room_id']?.toString() ?? '';
                          final roomName = room['room_name']?.toString() ?? roomId;
                          final participantCount = room['participant_count'] as int? ?? 0;
                          final maxOccupants = room['max_occupants'] as int? ?? 0;
                          final isActive = room['is_active'] == true;
                          final createdBy = room['created_by'] as int?;
                          final isOwner = createdBy == authProvider.currentUser?.id;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF667eea),
                                child: const Icon(
                                  Icons.video_call,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(roomName),
                              subtitle: Text(
                                '${l10n?.t('rooms.participants') ?? '参与者'}: $participantCount${maxOccupants > 0 ? '/$maxOccupants' : ''}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isOwner)
                                    Chip(
                                      label: Text(l10n?.t('rooms.owner') ?? '房主'),
                                      backgroundColor: Colors.orange,
                                      labelStyle: const TextStyle(fontSize: 10),
                                    ),
                                  if (!isActive)
                                    Chip(
                                      label: Text(l10n?.t('rooms.closed') ?? '已关闭'),
                                      backgroundColor: Colors.grey,
                                      labelStyle: const TextStyle(fontSize: 10),
                                    ),
                                  if (isOwner && isActive)
                                    IconButton(
                                      icon: const Icon(Icons.qr_code),
                                      tooltip: l10n?.t('rooms.share_qr') ?? '分享二维码',
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => RoomQRShareScreen(
                                              roomId: roomId,
                                              roomName: roomName,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_forward_ios),
                                    onPressed: isActive
                                        ? () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => RoomScreen(
                                                  roomId: roomId,
                                                  roomName: roomName,
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                              onTap: isActive
                                  ? () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => RoomScreen(
                                            roomId: roomId,
                                            roomName: roomName,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
