import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_store.dart';
import '../source/domain/source_catalog.dart';
import 'app_settings.dart';

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  final controller = SettingsController(LocalStore.instance);
  unawaited(controller.load());
  return controller;
});

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._store) : super(AppSettings.defaults());

  final LocalStore _store;

  Future<void> load() async {
    final loaded = await _store.loadSettings();
    final source = sourceById(loaded.sourceId);
    if (source.visible) {
      state = loaded;
    } else {
      state = loaded.copyWith(sourceId: defaultSourceId);
      await _store.saveSettings(state);
    }
  }

  Future<void> _save(AppSettings settings) async {
    state = settings;
    await _store.saveSettings(settings);
  }

  Future<void> setSource(String sourceId) {
    return _save(state.copyWith(sourceId: sourceId));
  }

  Future<void> setProxy(String proxy) {
    return _save(state.copyWith(proxy: proxy.trim()));
  }

  Future<void> setThemeMode(ThemeMode mode) {
    return _save(state.copyWith(themeMode: mode));
  }

  Future<void> setCacheEnabled(bool value) {
    return _save(state.copyWith(cacheEnabled: value));
  }

  Future<void> setAutoPlayNext(bool value) {
    return _save(state.copyWith(autoPlayNext: value));
  }

  Future<void> setPlayerLaunchMode(PlayerLaunchMode value) {
    return _save(state.copyWith(playerLaunchMode: value));
  }

  Future<void> setPlayerEngine(PlayerEngine value) {
    return _save(state.copyWith(playerEngine: value));
  }

  Future<void> setSourceDomain(String sourceId, String domain) {
    final domains = Map<String, String>.from(state.userDomains);
    if (domain.trim().isEmpty) {
      domains.remove(sourceId);
    } else {
      domains[sourceId] = domain.trim();
    }
    return _save(state.copyWith(userDomains: domains));
  }

  Future<void> setSourceCookie(String sourceId, String cookie) {
    final cookies = Map<String, String>.from(state.sourceCookies);
    if (cookie.trim().isEmpty) {
      cookies.remove(sourceId);
    } else {
      cookies[sourceId] = cookie.trim();
    }
    return _save(state.copyWith(sourceCookies: cookies));
  }
}
