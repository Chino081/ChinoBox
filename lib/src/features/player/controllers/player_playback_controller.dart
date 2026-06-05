import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/playback_proxy.dart';
import '../../content/data/content_repository.dart';
import '../../download/data/download_store.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_controller.dart';
import '../models/player_episode_ref.dart';
import '../models/resolved_media.dart';
import '../player_platform_bridge.dart';
import 'fullscreen_controller.dart';
import 'playback_history_controller.dart';
import 'player_engine_controller.dart';
import 'player_state_controller.dart';

class PlayerPlaybackController {
  PlayerPlaybackController({
    required this.ref,
    required this.state,
    required this.engine,
    required this.history,
    required this.fullscreen,
    required this.sourceId,
    required this.title,
    required this.poster,
    required this.detailUrl,
    required this.effectivePlayHeadersBuilder,
    required this.shouldProxy,
    required this.onShowMessage,
  });

  final WidgetRef ref;
  final PlayerStateController state;
  final PlayerEngineController engine;
  final PlaybackHistoryController history;
  final FullscreenController fullscreen;
  final String sourceId;
  final String title;
  final String poster;
  final String detailUrl;
  final Map<String, String> Function(String, Map<String, String>)
      effectivePlayHeadersBuilder;
  final bool Function(String, Map<String, String>) shouldProxy;
  final void Function(String) onShowMessage;

  final _bridge = PlayerPlatformBridge.instance;

  ResolvedMedia? _activeMedia;
  bool _disposed = false;
  Duration? _pendingSeek;

  String get titleText {
    final episode =
        state.currentEpisodeTitle.isEmpty ? '' : ' ${state.currentEpisodeTitle}';
    final playTitle =
        state.currentPlayTitle.isEmpty ? '' : ' \u00b7 ${state.currentPlayTitle}';
    return '$title$episode$playTitle'.trim();
  }

  void markDisposed() => _disposed = true;

  void setPendingSeek(Duration? seek) => _pendingSeek = seek;

  Future<void> restoreAndStart() async {
    if (detailUrl.isNotEmpty) {
      try {
        final entries = await ref.read(contentRepositoryProvider).history();
        final saved = entries.where(
          (e) => e.sourceId == sourceId && e.detailUrl == detailUrl,
        );
        if (saved.isNotEmpty) {
          final entry = saved.first;
          if (entry.position > 0 &&
              entry.duration > 0 &&
              entry.position < entry.duration - 3000) {
            _pendingSeek = Duration(milliseconds: entry.position);
          }
        }
      } catch (e) {
        AppLogger.warn('恢复播放历史失败: $e');
      }
    }
    await startFromSettings();
  }

  Future<void> startFromSettings() async {
    final settings = ref.read(settingsControllerProvider);
    if (settings.playerLaunchMode == PlayerLaunchMode.external) {
      state.update(externalOnly: true, isLoading: false);
      try {
        await openExternalPlayer();
      } catch (error) {
        onShowMessage(error.toString());
        await openCurrent();
      }
      return;
    }
    await openCurrent();
  }

  Future<void> openCurrent() async {
    if (state.currentPlayUrl.isEmpty) {
      state.update(
        isLoading: false,
        externalOnly: false,
        error: '播放地址为空',
      );
      return;
    }

    state.update(
      isLoading: true,
      externalOnly: false,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
      isBuffering: false,
      isPlaying: false,
    );

    await engine.dispose();
    if (_disposed) return;

    try {
      final resolved = await _resolveMedia(
        state.currentPlayUrl,
        state.currentPlayHeaders,
      );
      if (_disposed) return;
      _activeMedia = resolved;
      state.completionHandled = false;
      final seekTo = _pendingSeek;
      _pendingSeek = null;
      await engine.open(
        resolved,
        seekTo: seekTo,
        onCompleted: () => unawaited(handleCompleted()),
      );
      if (_disposed) return;
      state.update(isLoading: false, clearError: true);
    } catch (error) {
      state.update(isLoading: false, error: error.toString());
    }
  }

  Future<void> openExternalPlayer() async {
    try {
      final media = _activeMedia ??
          await _resolveMedia(state.currentPlayUrl, state.currentPlayHeaders);
      _activeMedia = media;
      await engine.pause();
      await _bridge.openExternal(
        url: media.url,
        title: titleText,
        headers: media.headers,
      );
      if (state.externalOnly) state.isLoading = false;
    } catch (error) {
      if (state.externalOnly) {
        state.update(
          externalOnly: false,
          isLoading: false,
          error: error.toString(),
        );
      }
      rethrow;
    }
  }

  Future<void> playNext() async {
    await loadEpisodesIfNeeded();
    if (!state.hasNext) {
      onShowMessage('已经是最后一集');
      return;
    }
    await playEpisodeAt(state.episodeIndex + 1);
  }

  Future<void> playEpisodeAt(int index) async {
    await loadEpisodesIfNeeded();
    if (index < 0 || index >= state.episodes.length) return;
    final next = state.episodes[index];
    state.update(isLoading: true, clearError: true, controlsVisible: true);

    try {
      final items = await ref
          .read(contentRepositoryProvider)
          .playItems(sourceId, next.url);
      if (items.isEmpty) throw StateError('未找到播放地址');
      final play = items.first;
      state.update(
        episodeIndex: index,
        currentEpisodeTitle: next.title,
        currentEpisodeUrl: next.url,
        currentPlayUrl: play.url,
        currentPlayHeaders: Map.of(play.headers),
        currentPlayTitle: play.title,
      );
      _activeMedia = null;
      state.position = Duration.zero;
      state.duration = Duration.zero;
      await history.save();

      if (state.externalOnly &&
          ref.read(settingsControllerProvider).playerLaunchMode ==
              PlayerLaunchMode.external) {
        await openExternalPlayer();
        state.isLoading = false;
      } else {
        await openCurrent();
      }
    } catch (error) {
      state.update(isLoading: false, error: error.toString());
    }
  }

  Future<void> handleCompleted() async {
    if (state.completionHandled) return;
    state.completionHandled = true;
    if (!ref.read(settingsControllerProvider).autoPlayNext) return;
    await loadEpisodesIfNeeded();
    if (state.hasNext) await playNext();
  }

  Future<void> loadEpisodesIfNeeded() async {
    if (state.loadingEpisodes ||
        (state.episodes.isNotEmpty && state.episodeIndex >= 0)) {
      return;
    }
    if (detailUrl.isEmpty || sourceId.isEmpty) return;
    state.loadingEpisodes = true;
    try {
      final detail = await ref
          .read(contentRepositoryProvider)
          .detail(sourceId, detailUrl);
      for (final group in detail.groups) {
        final index = group.episodes
            .indexWhere((ep) => ep.url == state.currentEpisodeUrl);
        if (index >= 0) {
          state.episodes = group.episodes
              .map((ep) => PlayerEpisodeRef(title: ep.title, url: ep.url))
              .toList();
          state.episodeIndex = index;
          break;
        }
      }
    } catch (e) {
      AppLogger.warn('加载选集失败: $e');
    } finally {
      state.loadingEpisodes = false;
    }
  }

  Future<void> enterPictureInPicture() async {
    try {
      await _bridge.enterPictureInPicture();
    } catch (error) {
      onShowMessage(error.toString());
    }
  }

  Future<ResolvedMedia> _resolveMedia(
    String url,
    Map<String, String> headers,
  ) async {
    // Check if a completed local download exists for this episode
    final episodeUrl = state.currentEpisodeUrl;
    if (episodeUrl.isNotEmpty) {
      try {
        final local = await DownloadStore.instance
            .findCompletedEpisode(episodeUrl);
        if (local != null && local.localPath.isNotEmpty) {
          final file = File(local.localPath);
          if (file.existsSync()) {
            AppLogger.info('使用本地下载: ${local.title}');
            return ResolvedMedia(url: local.localPath, headers: const {});
          }
        }
      } catch (e) {
        AppLogger.warn('检查本地下载失败: $e');
      }
    }

    final effectiveHeaders = effectivePlayHeadersBuilder(url, headers);
    var playUrl = url;
    Map<String, String>? mediaHeaders =
        effectiveHeaders.isEmpty ? null : Map.of(effectiveHeaders);

    if (shouldProxy(playUrl, effectiveHeaders)) {
      try {
        playUrl = await PlaybackProxy.instance
            .proxiedUrl(playUrl, effectiveHeaders);
        mediaHeaders = null;
      } catch (e) {
        AppLogger.warn('代理解析失败: $e');
        mediaHeaders = effectiveHeaders;
      }
    }

    return ResolvedMedia(
      url: playUrl,
      headers: mediaHeaders == null ? const {} : Map.of(mediaHeaders),
    );
  }
}
