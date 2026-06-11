import 'dart:async';

import '../models/cast_state.dart';
import '../player_platform_bridge.dart';
import 'player_state_controller.dart';

class PlayerCastController {
  PlayerCastController({
    required this.state,
    required this.onShowMessage,
  });

  final PlayerStateController state;
  final void Function(String) onShowMessage;

  final _bridge = PlayerPlatformBridge.instance;
  StreamSubscription? _eventSubscription;

  void init() {
    _eventSubscription = _bridge.dlnaEventStream.listen(_handleEvent);
  }

  Future<bool> startDiscovery() async {
    try {
      await _bridge.dlnaStartDiscovery();
      return true;
    } catch (e) {
      onShowMessage('投屏搜索失败: $e');
      return false;
    }
  }

  Future<void> stopDiscovery() async {
    await _bridge.dlnaStopDiscovery();
  }

  Future<void> connectToDevice(CastDevice device) async {
    state.castState = CastConnectionState.connecting;
    try {
      await _bridge.dlnaConnect(device.udn);
      state.connectedDevice = device;
      state.castState = CastConnectionState.connected;
    } catch (e) {
      state.castState = CastConnectionState.disconnected;
      onShowMessage('连接失败: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _bridge.dlnaStop();
      await _bridge.dlnaDisconnect();
    } catch (_) {}
    state.update(
      castState: CastConnectionState.disconnected,
      clearConnectedDevice: true,
      castTransportState: CastTransportState.idle,
    );
  }

  Future<void> castMedia(String url, String title, Map<String, String> headers) async {
    try {
      await _bridge.dlnaSetMedia(url, title, headers);
      await _bridge.dlnaPlay();
    } catch (e) {
      onShowMessage('投屏失败: $e');
    }
  }

  Future<void> togglePlayPause() async {
    try {
      if (state.castTransportState == CastTransportState.playing) {
        await _bridge.dlnaPause();
      } else {
        await _bridge.dlnaPlay();
      }
    } catch (e) {
      onShowMessage('操作失败: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _bridge.dlnaSeek(position);
    } catch (e) {
      onShowMessage('进度调整失败: $e');
    }
  }

  Future<void> setVolume(int volume) async {
    try {
      await _bridge.dlnaSetVolume(volume);
    } catch (_) {}
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'devicesChanged':
        final devices = (event['devices'] as List?)?.map((d) {
              final map = Map<String, dynamic>.from(d as Map);
              return CastDevice(
                udn: map['udn'] as String? ?? '',
                name: map['name'] as String? ?? 'Unknown',
                manufacturer: map['manufacturer'] as String? ?? '',
              );
            }).toList() ??
            [];
        state.castDevices = devices;

      case 'transportStateChanged':
        final s = event['state'] as String? ?? '';
        state.castTransportState = switch (s) {
          'PLAYING' => CastTransportState.playing,
          'PAUSED_PLAYBACK' => CastTransportState.paused,
          'STOPPED' => CastTransportState.stopped,
          'TRANSITIONING' => CastTransportState.transitioning,
          _ => CastTransportState.idle,
        };

      case 'positionChanged':
        final positionMs = (event['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (event['durationMs'] as num?)?.toInt() ?? 0;
        state.position = Duration(milliseconds: positionMs);
        state.duration = Duration(milliseconds: durationMs);

      case 'volumeChanged':
        // Volume changes are handled by the native side

      case 'connected':
        final deviceName = event['deviceName'] as String? ?? '';
        state.castState = CastConnectionState.connected;
        if (deviceName.isNotEmpty) {
          onShowMessage('已连接: $deviceName');
        }

      case 'disconnected':
        if (state.isCasting) {
          onShowMessage('投屏已断开');
        }
        state.update(
          castState: CastConnectionState.disconnected,
          clearConnectedDevice: true,
          castTransportState: CastTransportState.idle,
        );

      case 'error':
        final message = event['message'] as String? ?? '投屏错误';
        onShowMessage(message);
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
