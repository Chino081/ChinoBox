import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/app_settings.dart';

class LocalStore {
  LocalStore._();

  static final instance = LocalStore._();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static const _settingsKey = 'moviesbox.settings';
  static const _favoritesKey = 'moviesbox.favorites';
  static const _historyKey = 'moviesbox.history';
  static const _cachePrefix = 'moviesbox.cache.';

  Future<AppSettings> loadSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await _prefs;
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<List<Map<String, dynamic>>> readList(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) {
      return Map<String, dynamic>.from(e);
    }).toList();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> data) async {
    final prefs = await _prefs;
    await prefs.setString(key, jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>> readFavorites() => readList(_favoritesKey);

  Future<void> writeFavorites(List<Map<String, dynamic>> data) {
    return writeList(_favoritesKey, data);
  }

  Future<List<Map<String, dynamic>>> readHistory() => readList(_historyKey);

  Future<void> writeHistory(List<Map<String, dynamic>> data) {
    return writeList(_historyKey, data);
  }

  Future<void> removeHistory(String id) async {
    final list = await readHistory();
    list.removeWhere((item) => item['id'] == id);
    await writeHistory(list);
  }

  Future<String?> readCache(String key, Duration maxAge) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        decoded['savedAt'] as int? ?? 0,
      );
      if (DateTime.now().difference(savedAt) > maxAge) return null;
      return decoded['body'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCache(String key, String body) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'body': body,
      }),
    );
  }

  Future<void> clearCache() async {
    final prefs = await _prefs;
    final keys = prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
