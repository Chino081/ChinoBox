import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_video;
import 'package:window_manager/window_manager.dart';

import '../../core/network/playback_proxy.dart';
import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';
import 'player_platform_bridge.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.sourceId,
    required this.title,
    required this.poster,
    required this.detailUrl,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.playUrl,
    required this.playHeaders,
    required this.playTitle,
    required this.episodes,
    required this.episodeIndex,
    super.key,
  });

  factory PlayerPage.fromQuery(Map<String, String> params) {
    return PlayerPage(
      sourceId: params['source'] ?? '',
      title: params['title'] ?? '',
      poster: params['poster'] ?? '',
      detailUrl: params['detailUrl'] ?? '',
      episodeTitle: params['episodeTitle'] ?? '',
      episodeUrl: params['episodeUrl'] ?? '',
      playUrl: params['playUrl'] ?? '',
      playHeaders: _decodeHeaders(params['playHeaders'] ?? ''),
      playTitle: params['playTitle'] ?? '',
      episodes: _decodeEpisodes(params['episodes'] ?? ''),
      episodeIndex: int.tryParse(params['episodeIndex'] ?? '') ?? -1,
    );
  }

  final String sourceId;
  final String title;
  final String poster;
  final String detailUrl;
  final String episodeTitle;
  final String episodeUrl;
  final String playUrl;
  final Map<String, String> playHeaders;
  final String playTitle;
  final List<PlayerEpisodeRef> episodes;
  final int episodeIndex;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  final _bridge = PlayerPlatformBridge.instance;

  media_kit.Player? _mediaKitPlayer;
  media_video.VideoController? _mediaKitController;
  final _mediaKitSubscriptions = <StreamSubscription<dynamic>>[];

  late List<PlayerEpisodeRef> _episodes;
  late int _episodeIndex;
  late String _currentEpisodeTitle;
  late String _currentEpisodeUrl;
  late String _currentPlayUrl;
  late Map<String, String> _currentPlayHeaders;
  late String _currentPlayTitle;

  _ResolvedMedia? _activeMedia;
  var _position = Duration.zero;
  var _duration = Duration.zero;
  var _rate = 1.0;
  var _isPlaying = false;
  var _isBuffering = false;
  var _isLoading = true;
  var _externalOnly = false;
  var _isFullscreen = false;
  var _completionHandled = false;
  var _loadingEpisodes = false;
  var _disposed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _episodes = List.of(widget.episodes);
    _episodeIndex = widget.episodeIndex;
    _currentEpisodeTitle = widget.episodeTitle;
    _currentEpisodeUrl = widget.episodeUrl;
    _currentPlayUrl = widget.playUrl;
    _currentPlayHeaders = Map.of(widget.playHeaders);
    _currentPlayTitle = widget.playTitle;
    _normalizeEpisodeIndex();
    unawaited(_loadEpisodesIfNeeded());
    unawaited(_startFromSettings());
    unawaited(_saveHistory());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_saveHistory());
    unawaited(_disposePlaybackEngines());
    unawaited(_restoreSystemUi());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final source = sourceById(widget.sourceId);
    final title = _titleText;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          unawaited(_setFullscreen(false));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(child: Text(source.name)),
                  ),
                ],
              ),
        body: SafeArea(
          top: !_isFullscreen,
          bottom: false,
          child: _buildBody(context, settings),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppSettings settings) {
    if (_isFullscreen) {
      return _buildPlayerStage(context);
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildPlayerStage(context),
              ),
            ),
          ),
        ),
        _buildEpisodeBar(context, settings),
      ],
    );
  }

  Widget _buildPlayerStage(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _buildVideoSurface()),
        if (_externalOnly) Positioned.fill(child: _buildExternalOnlyView()),
        if (_error != null && !_externalOnly)
          Positioned.fill(child: _buildErrorView(_error!)),
        if (_isLoading && !_externalOnly)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
        if (_isFullscreen) _buildFullscreenTopBar(),
        if (!_externalOnly) _buildControlOverlay(context),
      ],
    );
  }

  Widget _buildVideoSurface() {
    final controller = _mediaKitController;
    if (controller == null) return _buildPosterPlaceholder();
    return media_video.Video(
      controller: controller,
      controls: null,
      fit: BoxFit.contain,
      fill: Colors.black,
      pauseUponEnteringBackgroundMode: false,
    );
  }

  Widget _buildPosterPlaceholder() {
    if (widget.poster.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.movie_outlined, color: Colors.white54, size: 56),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Image.network(
          widget.poster,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) {
            return const Icon(
              Icons.movie_outlined,
              color: Colors.white54,
              size: 56,
            );
          },
        ),
      ),
    );
  }

  Widget _buildExternalOnlyView() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded,
                  color: Colors.white70, size: 42),
              const SizedBox(height: 14),
              Text(
                '已交给外置播放器',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_openExternalPlayer()),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('再次打开'),
                  ),
                  FilledButton.icon(
                    onPressed: () => unawaited(_openCurrent()),
                    icon: const Icon(Icons.smart_display_rounded),
                    label: const Text('内置播放'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 38),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(_openCurrent()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xAA000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                tooltip: '退出全屏',
                color: Colors.white,
                onPressed: () => unawaited(_setFullscreen(false)),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  _titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlOverlay(BuildContext context) {
    final progressMax = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final progressValue =
        _position.inMilliseconds.clamp(0, progressMax.toInt()).toDouble();
    final foreground = Colors.white.withValues(alpha: 0.92);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xDD000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 28, 10, _isFullscreen ? 10 : 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    min: 0,
                    max: progressMax,
                    value: progressValue,
                    onChanged: (value) {
                      setState(() {
                        _position = Duration(milliseconds: value.round());
                      });
                    },
                    onChangeEnd: (value) {
                      unawaited(_seek(Duration(milliseconds: value.round())));
                    },
                  ),
                ),
                _buildTransportControls(foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransportControls(Color foreground) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final timeLabel = Text(
          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: foreground, fontSize: 12),
        );
        final playButton = IconButton(
          tooltip: _isPlaying ? '暂停' : '播放',
          color: Colors.white,
          onPressed: _isLoading ? null : () => unawaited(_togglePlay()),
          icon:
              Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        );
        final actions = _buildActionButtons();

        if (compact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  playButton,
                  Flexible(child: timeLabel),
                  if (_isBuffering) ..._buildBufferingIndicator(),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _buildActionScroller(actions),
              ),
            ],
          );
        }

        return Row(
          children: [
            playButton,
            Flexible(child: timeLabel),
            if (_isBuffering) ..._buildBufferingIndicator(),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildActionScroller(actions),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildBufferingIndicator() {
    return const [
      SizedBox(width: 8),
      SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      ),
    ];
  }

  Widget _buildActionScroller(Widget child) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: child,
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSpeedMenu(),
        IconButton(
          tooltip: '下一集',
          color: Colors.white,
          onPressed: _hasNext ? () => unawaited(_playNext()) : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: '外置播放器',
          color: Colors.white,
          onPressed: () => unawaited(_openExternalPlayer()),
          icon: const Icon(Icons.open_in_new_rounded),
        ),
        if (_bridge.supportsAndroidPlayerActions)
          IconButton(
            tooltip: '画中画',
            color: Colors.white,
            onPressed: () => unawaited(_enterPictureInPicture()),
            icon: const Icon(Icons.picture_in_picture_alt_rounded),
          ),
        IconButton(
          tooltip: _isFullscreen ? '退出全屏' : '全屏',
          color: Colors.white,
          onPressed: () => unawaited(_setFullscreen(!_isFullscreen)),
          icon: Icon(
            _isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedMenu() {
    return PopupMenuButton<double>(
      tooltip: '倍速',
      onSelected: (value) => unawaited(_setRate(value)),
      itemBuilder: (context) => [
        for (final rate in _playbackRates)
          PopupMenuItem(
            value: rate,
            child: Row(
              children: [
                if (_rate == rate) const Icon(Icons.check_rounded, size: 18),
                if (_rate != rate) const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(
                    '${rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2)}x'),
              ],
            ),
          ),
      ],
      child: SizedBox(
        height: 48,
        width: 48,
        child: Center(
          child: Text(
            '${_rate.toStringAsFixed(_rate.truncateToDouble() == _rate ? 0 : 2)}x',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeBar(BuildContext context, AppSettings settings) {
    final source = sourceById(widget.sourceId);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF050505),
        border: Border(top: BorderSide(color: Color(0xFF242424))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${source.name} · MediaKit · ${settings.autoPlayNext ? '自动下一集' : '手动下一集'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_loadingEpisodes)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
            FilledButton.tonalIcon(
              onPressed: _hasNext ? () => unawaited(_playNext()) : null,
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('下一集'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startFromSettings() async {
    final settings = ref.read(settingsControllerProvider);
    if (settings.playerLaunchMode == PlayerLaunchMode.external) {
      if (mounted) {
        setState(() {
          _externalOnly = true;
          _isLoading = false;
        });
      }
      try {
        await _openExternalPlayer();
      } catch (error) {
        _showMessage(error.toString());
        await _openCurrent();
      }
      return;
    }
    await _openCurrent();
  }

  Future<void> _openCurrent() async {
    if (_currentPlayUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _externalOnly = false;
          _error = '播放地址为空';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _externalOnly = false;
        _error = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isBuffering = false;
        _isPlaying = false;
      });
    }

    await _disposePlaybackEngines();
    if (_disposed) return;

    try {
      final resolved =
          await _resolveMedia(_currentPlayUrl, _currentPlayHeaders);
      if (_disposed) return;
      _activeMedia = resolved;
      _completionHandled = false;
      await _openMediaKit(resolved);
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _openMediaKit(_ResolvedMedia media) async {
    final player = media_kit.Player();
    final controller = media_video.VideoController(player);
    _mediaKitPlayer = player;
    _mediaKitController = controller;
    _mediaKitSubscriptions
      ..clear()
      ..add(player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
      }))
      ..add(player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }))
      ..add(player.stream.playing.listen((value) {
        if (mounted) setState(() => _isPlaying = value);
      }))
      ..add(player.stream.buffering.listen((value) {
        if (mounted) setState(() => _isBuffering = value);
      }))
      ..add(player.stream.completed.listen((value) {
        if (value) unawaited(_handleCompleted());
      }))
      ..add(player.stream.error.listen((value) {
        if (mounted) setState(() => _error = value);
      }));

    await player.open(
      media_kit.Media(
        media.url,
        httpHeaders: media.headers.isEmpty ? null : media.headers,
      ),
      play: true,
    );
    await player.setRate(_rate);
  }

  Future<void> _togglePlay() async {
    final player = _mediaKitPlayer;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seek(Duration position) async {
    await _mediaKitPlayer?.seek(position);
  }

  Future<void> _setRate(double rate) async {
    if (mounted) setState(() => _rate = rate);
    try {
      await _mediaKitPlayer?.setRate(rate);
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _playNext() async {
    await _loadEpisodesIfNeeded();
    if (!_hasNext) {
      _showMessage('已经是最后一集');
      return;
    }

    final nextIndex = _episodeIndex + 1;
    final next = _episodes[nextIndex];
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      await _saveHistory();
      final items = await ref
          .read(contentRepositoryProvider)
          .playItems(widget.sourceId, next.url);
      if (items.isEmpty) throw StateError('未找到下一集播放地址');
      final play = items.first;
      _episodeIndex = nextIndex;
      _currentEpisodeTitle = next.title;
      _currentEpisodeUrl = next.url;
      _currentPlayUrl = play.url;
      _currentPlayHeaders = Map.of(play.headers);
      _currentPlayTitle = play.title;
      _activeMedia = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      await _saveHistory();

      if (_externalOnly &&
          ref.read(settingsControllerProvider).playerLaunchMode ==
              PlayerLaunchMode.external) {
        await _openExternalPlayer();
        if (mounted) setState(() => _isLoading = false);
      } else {
        await _openCurrent();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _handleCompleted() async {
    if (_completionHandled) return;
    _completionHandled = true;
    if (!ref.read(settingsControllerProvider).autoPlayNext) return;
    await _loadEpisodesIfNeeded();
    if (_hasNext) {
      await _playNext();
    }
  }

  Future<void> _openExternalPlayer() async {
    try {
      final media = _activeMedia ??
          await _resolveMedia(_currentPlayUrl, _currentPlayHeaders);
      _activeMedia = media;
      await _pauseForExternalPlayback();
      await _bridge.openExternal(
        url: media.url,
        title: _titleText,
        headers: media.headers,
      );
      if (mounted && _externalOnly) {
        setState(() => _isLoading = false);
      }
    } catch (error) {
      if (mounted && _externalOnly) {
        setState(() {
          _externalOnly = false;
          _isLoading = false;
          _error = error.toString();
        });
      }
      rethrow;
    }
  }

  Future<void> _pauseForExternalPlayback() async {
    if (_externalOnly) return;
    await _mediaKitPlayer?.pause();
  }

  Future<void> _enterPictureInPicture() async {
    try {
      await _bridge.enterPictureInPicture();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _setFullscreen(bool value) async {
    if (_isFullscreen == value) return;
    if (mounted) setState(() => _isFullscreen = value);
    if (_isDesktopPlatform) {
      await windowManager.setFullScreen(value);
      return;
    }
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (Platform.isAndroid) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      await _restoreSystemUi();
    }
  }

  Future<void> _restoreSystemUi() async {
    if (_isDesktopPlatform) {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  Future<void> _loadEpisodesIfNeeded() async {
    if (_loadingEpisodes || (_episodes.isNotEmpty && _episodeIndex >= 0)) {
      return;
    }
    if (widget.detailUrl.isEmpty || widget.sourceId.isEmpty) return;
    _loadingEpisodes = true;
    if (mounted) setState(() {});
    try {
      final detail = await ref
          .read(contentRepositoryProvider)
          .detail(widget.sourceId, widget.detailUrl);
      for (final group in detail.groups) {
        final index = group.episodes
            .indexWhere((episode) => episode.url == _currentEpisodeUrl);
        if (index >= 0) {
          if (mounted) {
            setState(() {
              _episodes = group.episodes
                  .map((episode) =>
                      PlayerEpisodeRef(title: episode.title, url: episode.url))
                  .toList();
              _episodeIndex = index;
            });
          } else {
            _episodes = group.episodes
                .map((episode) =>
                    PlayerEpisodeRef(title: episode.title, url: episode.url))
                .toList();
            _episodeIndex = index;
          }
          break;
        }
      }
    } catch (_) {
      // History playback can still work without a detail-page episode list.
    } finally {
      _loadingEpisodes = false;
      if (mounted) setState(() {});
    }
  }

  Future<_ResolvedMedia> _resolveMedia(
    String url,
    Map<String, String> headers,
  ) async {
    final effectiveHeaders = _effectivePlayHeaders(url, headers);
    var playUrl = url;
    Map<String, String>? mediaHeaders =
        effectiveHeaders.isEmpty ? null : Map.of(effectiveHeaders);

    if (_shouldProxy(playUrl, effectiveHeaders)) {
      try {
        playUrl =
            await PlaybackProxy.instance.proxiedUrl(playUrl, effectiveHeaders);
        mediaHeaders = null;
      } catch (_) {
        mediaHeaders = effectiveHeaders;
      }
    }

    return _ResolvedMedia(
      url: playUrl,
      headers: mediaHeaders == null ? const {} : Map.of(mediaHeaders),
    );
  }

  Future<void> _disposePlaybackEngines() async {
    for (final subscription in _mediaKitSubscriptions) {
      await subscription.cancel();
    }
    _mediaKitSubscriptions.clear();

    final mediaKitPlayer = _mediaKitPlayer;
    _mediaKitPlayer = null;
    _mediaKitController = null;
    if (mediaKitPlayer != null) {
      await mediaKitPlayer.dispose();
    }
  }

  Future<void> _saveHistory() async {
    if (_currentEpisodeUrl.isEmpty) return;
    final id = '${widget.sourceId}:$_currentEpisodeUrl';
    await ref.read(contentRepositoryProvider).saveHistory(
          HistoryEntry(
            id: id,
            sourceId: widget.sourceId,
            title: widget.title,
            detailUrl: widget.detailUrl,
            episodeTitle: _currentEpisodeTitle,
            episodeUrl: _currentEpisodeUrl,
            playUrl: _currentPlayUrl,
            playHeaders:
                _effectivePlayHeaders(_currentPlayUrl, _currentPlayHeaders),
            poster: widget.poster,
            position: _position.inMilliseconds,
            duration: _duration.inMilliseconds,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Map<String, String> _effectivePlayHeaders(
    String playUrl,
    Map<String, String> playHeaders,
  ) {
    final headers = Map<String, String>.of(playHeaders);
    final uri = Uri.tryParse(playUrl);
    if (widget.sourceId == 'libvio' &&
        uri != null &&
        uri.host.toLowerCase().endsWith('vbing.me')) {
      headers.putIfAbsent('User-Agent', () => _browserUserAgent);
      headers.putIfAbsent('Referer', () => 'https://www.libvio.run/');
    }
    return headers;
  }

  bool _shouldProxy(String url, Map<String, String> headers) {
    if (headers.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    return url.toLowerCase().contains('.mp4');
  }

  void _normalizeEpisodeIndex() {
    if (_episodeIndex >= 0 && _episodeIndex < _episodes.length) return;
    _episodeIndex =
        _episodes.indexWhere((episode) => episode.url == _currentEpisodeUrl);
  }

  void _showMessage(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasNext =>
      _episodeIndex >= 0 && _episodeIndex + 1 < _episodes.length;

  String get _titleText {
    final episode =
        _currentEpisodeTitle.isEmpty ? '' : ' $_currentEpisodeTitle';
    final playTitle = _currentPlayTitle.isEmpty ? '' : ' · $_currentPlayTitle';
    return '${widget.title}$episode$playTitle'.trim();
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

class _ResolvedMedia {
  const _ResolvedMedia({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;
}

class PlayerEpisodeRef {
  const PlayerEpisodeRef({required this.title, required this.url});

  factory PlayerEpisodeRef.fromJson(Map<String, dynamic> json) {
    return PlayerEpisodeRef(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  final String title;
  final String url;
}

const _browserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

const _playbackRates = [0.75, 1.0, 1.25, 1.5, 2.0];

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

Map<String, String> _decodeHeaders(String value) {
  if (value.isEmpty) return const {};
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)))
        as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  } catch (_) {
    return const {};
  }
}

List<PlayerEpisodeRef> _decodeEpisodes(String value) {
  if (value.isEmpty) return const [];
  try {
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) =>
            PlayerEpisodeRef.fromJson(Map<String, dynamic>.from(item)))
        .where((episode) => episode.title.isNotEmpty && episode.url.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}
