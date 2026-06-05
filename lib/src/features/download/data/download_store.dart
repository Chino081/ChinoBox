import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/download_models.dart';

class DownloadStore {
  DownloadStore._();

  static final instance = DownloadStore._();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static const _tasksKey = 'moviesbox.downloads.tasks';
  static const _episodesPrefix = 'moviesbox.downloads.episodes.';

  Future<List<DownloadTask>> readTasks() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_tasksKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> writeTasks(List<DownloadTask> tasks) async {
    final prefs = await _prefs;
    await prefs.setString(
      _tasksKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> addTask(DownloadTask task) async {
    final tasks = await readTasks();
    tasks.removeWhere((t) => t.id == task.id);
    tasks.add(task);
    await writeTasks(tasks);
  }

  Future<void> removeTask(String id) async {
    final tasks = await readTasks();
    tasks.removeWhere((t) => t.id == id);
    await writeTasks(tasks);
    // Also remove all episodes for this task
    final prefs = await _prefs;
    await prefs.remove('$_episodesPrefix$id');
  }

  Future<List<DownloadEpisode>> readEpisodes(String taskId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_episodesPrefix$taskId');
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => DownloadEpisode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> writeEpisodes(
      String taskId, List<DownloadEpisode> episodes) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_episodesPrefix$taskId',
      jsonEncode(episodes.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> writeEpisode(DownloadEpisode episode) async {
    final episodes = await readEpisodes(episode.taskId);
    final index = episodes.indexWhere((e) => e.id == episode.id);
    if (index >= 0) {
      episodes[index] = episode;
    } else {
      episodes.add(episode);
    }
    await writeEpisodes(episode.taskId, episodes);
  }

  Future<void> removeEpisode(String id, String taskId) async {
    final episodes = await readEpisodes(taskId);
    episodes.removeWhere((e) => e.id == id);
    await writeEpisodes(taskId, episodes);
  }

  Future<void> updateEpisodeState(
    String id,
    String taskId,
    DownloadState state, {
    double? progress,
    int? totalBytes,
    int? downloadedBytes,
    String? localPath,
    String? errorMessage,
  }) async {
    final episodes = await readEpisodes(taskId);
    final index = episodes.indexWhere((e) => e.id == id);
    if (index < 0) return;
    episodes[index] = episodes[index].copyWith(
      state: state,
      progress: progress,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      localPath: localPath,
      errorMessage: errorMessage,
    );
    await writeEpisodes(taskId, episodes);
  }

  Future<DownloadEpisode?> findCompletedEpisode(String episodeUrl) async {
    final tasks = await readTasks();
    for (final task in tasks) {
      final episodes = await readEpisodes(task.id);
      for (final ep in episodes) {
        if (ep.episodeUrl == episodeUrl &&
            ep.state == DownloadState.completed) {
          return ep;
        }
      }
    }
    return null;
  }

  Future<void> removeEpisodesForTask(String taskId) async {
    final prefs = await _prefs;
    await prefs.remove('$_episodesPrefix$taskId');
  }
}
