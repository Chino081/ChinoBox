import 'package:flutter/material.dart';

import '../source/domain/source_catalog.dart';

enum PlayerLaunchMode { builtIn, external }

class AppSettings {
  const AppSettings({
    required this.sourceId,
    required this.proxy,
    required this.userDomains,
    required this.sourceCookies,
    required this.themeMode,
    required this.cacheEnabled,
    required this.autoPlayNext,
    required this.playerLaunchMode,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      sourceId: defaultSourceId,
      proxy: '',
      userDomains: {},
      sourceCookies: {},
      themeMode: ThemeMode.system,
      cacheEnabled: true,
      autoPlayNext: true,
      playerLaunchMode: PlayerLaunchMode.builtIn,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final themeName = json['themeMode'] as String? ?? 'system';
    return AppSettings(
      sourceId: json['sourceId'] as String? ?? defaultSourceId,
      proxy: json['proxy'] as String? ?? '',
      userDomains: Map<String, String>.from(json['userDomains'] as Map? ?? {}),
      sourceCookies:
          Map<String, String>.from(json['sourceCookies'] as Map? ?? {}),
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      cacheEnabled: json['cacheEnabled'] as bool? ?? true,
      autoPlayNext: json['autoPlayNext'] as bool? ?? true,
      playerLaunchMode: _enumByName(
        PlayerLaunchMode.values,
        json['playerLaunchMode'] as String?,
        PlayerLaunchMode.builtIn,
      ),
    );
  }

  final String sourceId;
  final String proxy;
  final Map<String, String> userDomains;
  final Map<String, String> sourceCookies;
  final ThemeMode themeMode;
  final bool cacheEnabled;
  final bool autoPlayNext;
  final PlayerLaunchMode playerLaunchMode;

  Map<String, dynamic> toJson() {
    return {
      'sourceId': sourceId,
      'proxy': proxy,
      'userDomains': userDomains,
      'sourceCookies': sourceCookies,
      'themeMode': themeMode.name,
      'cacheEnabled': cacheEnabled,
      'autoPlayNext': autoPlayNext,
      'playerLaunchMode': playerLaunchMode.name,
    };
  }

  AppSettings copyWith({
    String? sourceId,
    String? proxy,
    Map<String, String>? userDomains,
    Map<String, String>? sourceCookies,
    ThemeMode? themeMode,
    bool? cacheEnabled,
    bool? autoPlayNext,
    PlayerLaunchMode? playerLaunchMode,
  }) {
    return AppSettings(
      sourceId: sourceId ?? this.sourceId,
      proxy: proxy ?? this.proxy,
      userDomains: userDomains ?? this.userDomains,
      sourceCookies: sourceCookies ?? this.sourceCookies,
      themeMode: themeMode ?? this.themeMode,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      playerLaunchMode: playerLaunchMode ?? this.playerLaunchMode,
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
