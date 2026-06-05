import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/download_models.dart';
import 'download_store.dart';

final downloadManagerProvider = ChangeNotifierProvider<DownloadManager>((ref) {
  final manager = DownloadManager();
  unawaited(manager.init());
  ref.onDispose(manager.disposeAll);
  return manager;
});

class DownloadManager extends ChangeNotifier {
  DownloadManager() : _dio = Dio() {
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 10;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(minutes: 30);
  }

  final Dio _dio;
  final DownloadStore _store = DownloadStore.instance;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DownloadEpisode> _activeEpisodes = {};

  List<DownloadTask> _tasks = [];
  bool _initialized = false;
  String _downloadDir = '';

  static const _maxConcurrent = 3;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  bool get isInitialized => _initialized;
  String get downloadDirectory => _downloadDir;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    _downloadDir = '${dir.path}${Platform.pathSeparator}chinobox_downloads';
    final downloadDir = Directory(_downloadDir);
    if (!downloadDir.existsSync()) {
      await downloadDir.create(recursive: true);
    }
    _tasks = await _store.readTasks();
    // Resume any downloads that were in-progress when the app was killed
    await _resumeInterrupted();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _resumeInterrupted() async {
    for (final task in _tasks) {
      final episodes = await _store.readEpisodes(task.id);
      for (final ep in episodes) {
        if (ep.state == DownloadState.downloading) {
          // Mark as paused so user can resume
          await _store.updateEpisodeState(
            ep.id,
            task.id,
            DownloadState.paused,
          );
        }
      }
    }
  }

  // --- Task Management ---

  Future<DownloadTask> addTask({
    required String sourceId,
    required String title,
    required String detailUrl,
    String poster = '',
  }) async {
    final taskId = _taskId(sourceId, detailUrl);
    // Check if task already exists
    final existing = _tasks.where((t) => t.id == taskId);
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final task = DownloadTask(
      id: taskId,
      sourceId: sourceId,
      title: title,
      detailUrl: detailUrl,
      poster: poster,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.addTask(task);
    _tasks = await _store.readTasks();
    notifyListeners();
    return task;
  }

  Future<void> addEpisode({
    required String taskId,
    required String episodeTitle,
    required String episodeUrl,
    required String playUrl,
    Map<String, String> playHeaders = const {},
  }) async {
    final episodeId = _episodeId(taskId, episodeUrl);

    // Check if already exists
    final existing = await _store.readEpisodes(taskId);
    if (existing.any((e) => e.id == episodeId)) {
      return;
    }

    // Determine local file name from playUrl
    final fileName = _safeFileName(episodeId);
    final localPath =
        '$_downloadDir${Platform.pathSeparator}$fileName.mp4';

    final episode = DownloadEpisode(
      id: episodeId,
      taskId: taskId,
      title: episodeTitle,
      episodeUrl: episodeUrl,
      playUrl: playUrl,
      playHeaders: playHeaders,
      state: DownloadState.queued,
      localPath: localPath,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _store.writeEpisode(episode);
    notifyListeners();

    // Start downloading if under the concurrent limit
    unawaited(_processQueue());
  }

  Future<void> deleteTask(String taskId) async {
    // Cancel all active downloads for this task
    final episodes = await _store.readEpisodes(taskId);
    for (final ep in episodes) {
      _cancelTokens[ep.id]?.cancel();
      _cancelTokens.remove(ep.id);
      _activeEpisodes.remove(ep.id);
      // Delete local file if it exists
      if (ep.localPath.isNotEmpty) {
        final file = File(ep.localPath);
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
    await _store.removeTask(taskId);
    _tasks = await _store.readTasks();
    notifyListeners();
  }

  // --- Episode Download Control ---

  Future<void> pause(String episodeId) async {
    _cancelTokens[episodeId]?.cancel();
    _cancelTokens.remove(episodeId);
    _activeEpisodes.remove(episodeId);

    // Find the episode to get its taskId
    final ep = await _findEpisode(episodeId);
    if (ep != null) {
      await _store.updateEpisodeState(
        episodeId,
        ep.taskId,
        DownloadState.paused,
      );
    }
    notifyListeners();
    unawaited(_processQueue());
  }

  Future<void> resume(String episodeId) async {
    final ep = await _findEpisode(episodeId);
    if (ep == null) return;
    if (ep.state != DownloadState.paused && ep.state != DownloadState.failed) {
      return;
    }
    await _store.updateEpisodeState(
      episodeId,
      ep.taskId,
      DownloadState.queued,
    );
    notifyListeners();
    unawaited(_processQueue());
  }

  Future<void> cancel(String episodeId) async {
    _cancelTokens[episodeId]?.cancel();
    _cancelTokens.remove(episodeId);
    _activeEpisodes.remove(episodeId);

    final ep = await _findEpisode(episodeId);
    if (ep == null) return;

    // Delete partial file
    if (ep.localPath.isNotEmpty) {
      final file = File(ep.localPath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    await _store.removeEpisode(episodeId, ep.taskId);
    notifyListeners();
    unawaited(_processQueue());
  }

  Future<void> delete(String episodeId) async {
    await cancel(episodeId);
  }

  Future<void> retry(String episodeId) async {
    final ep = await _findEpisode(episodeId);
    if (ep == null) return;
    if (ep.state != DownloadState.failed) return;

    // Delete partial file
    if (ep.localPath.isNotEmpty) {
      final file = File(ep.localPath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    await _store.updateEpisodeState(
      episodeId,
      ep.taskId,
      DownloadState.queued,
      progress: 0.0,
      totalBytes: 0,
      downloadedBytes: 0,
      errorMessage: '',
    );
    notifyListeners();
    unawaited(_processQueue());
  }

  // --- Query ---

  Future<List<DownloadEpisode>> episodesForTask(String taskId) {
    return _store.readEpisodes(taskId);
  }

  Future<DownloadEpisode?> completedEpisodeFor(String episodeUrl) {
    return _store.findCompletedEpisode(episodeUrl);
  }

  bool hasCompletedDownload(String episodeUrl) {
    // Synchronous check using active memory - fast path
    for (final ep in _activeEpisodes.values) {
      if (ep.episodeUrl == episodeUrl &&
          ep.state == DownloadState.completed) {
        return true;
      }
    }
    return false;
  }

  // --- Queue Processing ---

  Future<void> _processQueue() async {
    // Count active downloads
    final activeCount = _activeEpisodes.values
        .where((e) => e.state == DownloadState.downloading)
        .length;

    if (activeCount >= _maxConcurrent) return;

    // Find next queued episode across all tasks
    for (final task in _tasks) {
      final episodes = await _store.readEpisodes(task.id);
      final queued = episodes.where((e) => e.state == DownloadState.queued);
      for (final ep in queued) {
        if (_activeEpisodes.length >= _maxConcurrent) break;
        if (_activeEpisodes.containsKey(ep.id)) continue;
        unawaited(_startDownload(ep));
      }
    }
  }

  Future<void> _startDownload(DownloadEpisode episode) async {
    if (episode.playUrl.isEmpty) {
      await _store.updateEpisodeState(
        episode.id,
        episode.taskId,
        DownloadState.failed,
        errorMessage: '播放地址为空',
      );
      notifyListeners();
      return;
    }

    // Skip m3u8
    if (episode.playUrl.contains('.m3u8') ||
        episode.playUrl.contains('m3u8')) {
      await _store.updateEpisodeState(
        episode.id,
        episode.taskId,
        DownloadState.failed,
        errorMessage: '不支持M3U8格式下载',
      );
      notifyListeners();
      return;
    }

    final cancelToken = CancelToken();
    _cancelTokens[episode.id] = cancelToken;

    final updatedEpisode = episode.copyWith(
      state: DownloadState.downloading,
      progress: 0.0,
    );
    _activeEpisodes[episode.id] = updatedEpisode;
    await _store.updateEpisodeState(
      episode.id,
      episode.taskId,
      DownloadState.downloading,
      progress: 0.0,
    );
    notifyListeners();

    try {
      // Build headers map
      final headers = <String, String>{
        if (episode.playHeaders.isNotEmpty) ...episode.playHeaders,
      };

      // Throttle progress updates
      DateTime lastNotify = DateTime.now();

      await _dio.download(
        episode.playUrl,
        episode.localPath,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (cancelToken.isCancelled) return;
          final progress = total > 0 ? received / total : 0.0;
          final now = DateTime.now();
          final elapsed = now.difference(lastNotify).inMilliseconds;

          // Throttle UI updates to ~4 per second
          if (elapsed < 250 && progress < 1.0) return;
          lastNotify = now;

          final updated = _activeEpisodes[episode.id]?.copyWith(
            state: DownloadState.downloading,
            progress: progress,
            totalBytes: total > 0 ? total : 0,
            downloadedBytes: received,
          );
          if (updated != null) {
            _activeEpisodes[episode.id] = updated;
            notifyListeners();
          }
        },
      );

      if (cancelToken.isCancelled) return;

      // Mark completed
      final completed = _activeEpisodes[episode.id]?.copyWith(
        state: DownloadState.completed,
        progress: 1.0,
      );
      if (completed != null) {
        _activeEpisodes[episode.id] = completed;
      }
      await _store.updateEpisodeState(
        episode.id,
        episode.taskId,
        DownloadState.completed,
        progress: 1.0,
        localPath: episode.localPath,
      );
      _activeEpisodes.remove(episode.id);
      _cancelTokens.remove(episode.id);
      notifyListeners();
      AppLogger.info('下载完成: ${episode.title}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Was paused or cancelled - don't mark as failed
        _activeEpisodes.remove(episode.id);
        _cancelTokens.remove(episode.id);
        return;
      }

      _activeEpisodes.remove(episode.id);
      _cancelTokens.remove(episode.id);

      final msg = _dioErrorMessage(e);
      await _store.updateEpisodeState(
        episode.id,
        episode.taskId,
        DownloadState.failed,
        errorMessage: msg,
      );
      notifyListeners();
      AppLogger.warn('下载失败: ${episode.title} - $msg');
    } catch (e) {
      _activeEpisodes.remove(episode.id);
      _cancelTokens.remove(episode.id);

      await _store.updateEpisodeState(
        episode.id,
        episode.taskId,
        DownloadState.failed,
        errorMessage: e.toString(),
      );
      notifyListeners();
      AppLogger.warn('下载失败: ${episode.title} - $e');
    }

    // Process next in queue
    unawaited(_processQueue());
  }

  // --- Helpers ---

  Future<DownloadEpisode?> _findEpisode(String episodeId) async {
    for (final task in _tasks) {
      final episodes = await _store.readEpisodes(task.id);
      for (final ep in episodes) {
        if (ep.id == episodeId) return ep;
      }
    }
    return null;
  }

  String _dioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return '服务器错误 ($code)';
      case DioExceptionType.connectionError:
        return '网络连接失败';
      default:
        return e.message ?? '未知错误';
    }
  }

  void disposeAll() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    _activeEpisodes.clear();
    _dio.close();
  }
}

String _taskId(String sourceId, String detailUrl) {
  return base64Url.encode(utf8.encode('$sourceId::$detailUrl'));
}

String _episodeId(String taskId, String episodeUrl) {
  return base64Url.encode(utf8.encode('$taskId::$episodeUrl'));
}

String _safeFileName(String id) {
  // base64url is already file-safe, but limit length
  if (id.length > 100) {
    return sha1.convert(utf8.encode(id)).toString();
  }
  return id;
}
