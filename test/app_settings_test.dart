import 'package:chinobox/src/features/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player settings round trip through json', () {
    const settings = AppSettings(
      sourceId: 'libvio',
      proxy: 'socks5://127.0.0.1:1080',
      userDomains: {},
      sourceCookies: {},
      themeMode: ThemeMode.dark,
      cacheEnabled: false,
      autoPlayNext: false,
      playerLaunchMode: PlayerLaunchMode.external,
    );

    final decoded = AppSettings.fromJson(settings.toJson());

    expect(decoded.playerLaunchMode, PlayerLaunchMode.external);
    expect(decoded.autoPlayNext, isFalse);
    expect(decoded.themeMode, ThemeMode.dark);
  });

  test('old settings default to built in playback', () {
    final settings = AppSettings.fromJson(const {
      'sourceId': 'libvio',
      'themeMode': 'light',
    });

    expect(settings.playerLaunchMode, PlayerLaunchMode.builtIn);
    expect(settings.themeMode, ThemeMode.light);
  });
}
