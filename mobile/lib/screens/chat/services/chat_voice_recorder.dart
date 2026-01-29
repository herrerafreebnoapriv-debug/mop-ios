import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../../../services/permission/permission_service.dart';
import '../../../locales/app_localizations.dart';

/// 聊天语音录制服务
class ChatVoiceRecorder {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;

  bool get isRecording => _isRecording;
  Duration get recordingDuration => _recordingDuration;
  String? get currentRecordingPath => _currentRecordingPath;

  /// 开始录音
  Future<bool> startRecording({
    required Function(Duration) onDurationUpdate,
    required Function(String) onError,
  }) async {
    try {
      final permissionStatus = await PermissionService.instance.checkMicrophonePermission();
      if (permissionStatus != PermissionStatus.granted) {
        final requestStatus = await PermissionService.instance.requestMicrophonePermission();
        if (requestStatus != PermissionStatus.granted) {
          onError('需要麦克风权限才能录制语音');
          return false;
        }
      }
      
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/voice_$timestamp.m4a';
      
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );
      
      _recordingStartTime = DateTime.now();
      _isRecording = true;
      _recordingDuration = Duration.zero;
      
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_recordingStartTime != null) {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          onDurationUpdate(_recordingDuration);
        }
      });
      
      return true;
    } catch (e) {
      onError('开始录音失败: $e');
      return false;
    }
  }

  /// 停止录音
  Future<String?> stopRecording() async {
    if (!_isRecording || _currentRecordingPath == null) return null;
    
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      _isRecording = false;
      
      if (path != null && path.isNotEmpty) {
        final actualDuration = _recordingStartTime != null 
            ? DateTime.now().difference(_recordingStartTime!)
            : _recordingDuration;
        
        final recordingFile = File(path);
        if (await recordingFile.exists() && actualDuration.inMilliseconds < 500) {
          await recordingFile.delete();
          _currentRecordingPath = null;
          _recordingStartTime = null;
          return null; // 录音时间太短
        }
        
        final result = _currentRecordingPath;
        _currentRecordingPath = null;
        _recordingStartTime = null;
        return result;
      }
      
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return null;
    } catch (e) {
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      return null;
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    
    try {
      await _audioRecorder.stop();
      _recordingTimer?.cancel();
      
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
        _currentRecordingPath = null;
      }
      
      _isRecording = false;
      _recordingDuration = Duration.zero;
      _recordingStartTime = null;
    } catch (e) {
      _isRecording = false;
      _currentRecordingPath = null;
      _recordingStartTime = null;
    }
  }

  void dispose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
  }
}
