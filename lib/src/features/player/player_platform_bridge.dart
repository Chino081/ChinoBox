import 'dart:io';

import 'package:flutter/services.dart';

class PlayerPlatformBridge {
  const PlayerPlatformBridge._();

  static const instance = PlayerPlatformBridge._();
  static const _channel = MethodChannel('com.chino.chinobox/player');

  bool get supportsAndroidPlayerActions => Platform.isAndroid;

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
}

class PlayerPlatformException implements Exception {
  const PlayerPlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}
