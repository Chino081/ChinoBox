import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class PlayerPlatformBridge {
  const PlayerPlatformBridge._();

  static const instance = PlayerPlatformBridge._();
  static const _channel = MethodChannel('com.chino.chinobox/player');
  static const _dlnaEventChannel = EventChannel('com.chino.chinobox/dlna_events');

  bool get supportsAndroidPlayerActions => Platform.isAndroid;
  bool get supportsCast => Platform.isAndroid;

  Future<void> openExternal({
    required String url,
    required String title,
    Map<String, String> headers = const {},
  }) async {
    if (!Platform.isAndroid) {
      throw const PlayerPlatformException('当前平台不支持外部播放器');
    }
    await _channel.invokeMethod<void>('openExternal', {
      'url': url,
      'title': title,
      'headers': headers,
    });
  }

  Future<void> enterPictureInPicture() async {
    if (!Platform.isAndroid) {
      throw const PlayerPlatformException('当前平台不支持画中画');
    }
    await _channel.invokeMethod<void>('enterPictureInPicture');
  }

  // --- DLNA Methods ---

  Stream<Map<String, dynamic>> get dlnaEventStream =>
      _dlnaEventChannel.receiveBroadcastStream().map(
        (e) => Map<String, dynamic>.from(e as Map),
      );

  Future<void> dlnaStartDiscovery() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaStartDiscovery');
  }

  Future<void> dlnaStopDiscovery() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaStopDiscovery');
  }

  Future<void> dlnaConnect(String udn) async {
    if (!Platform.isAndroid) {
      throw const PlayerPlatformException('当前平台不支持投屏');
    }
    await _channel.invokeMethod<void>('dlnaConnect', {'udn': udn});
  }

  Future<void> dlnaDisconnect() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaDisconnect');
  }

  Future<void> dlnaSetMedia(String url, String title, Map<String, String> headers) async {
    if (!Platform.isAndroid) {
      throw const PlayerPlatformException('当前平台不支持投屏');
    }
    await _channel.invokeMethod<void>('dlnaSetMedia', {
      'url': url,
      'title': title,
      'headers': headers,
    });
  }

  Future<void> dlnaPlay() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaPlay');
  }

  Future<void> dlnaPause() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaPause');
  }

  Future<void> dlnaStop() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaStop');
  }

  Future<void> dlnaSeek(Duration position) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaSeek', {
      'positionMs': position.inMilliseconds,
    });
  }

  Future<void> dlnaSetVolume(int volume) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('dlnaSetVolume', {'volume': volume});
  }

  Future<int> dlnaGetVolume() async {
    if (!Platform.isAndroid) return 0;
    return await _channel.invokeMethod<int>('dlnaGetVolume') ?? 0;
  }
}

class PlayerPlatformException implements Exception {
  const PlayerPlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}
