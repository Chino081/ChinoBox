import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_video;
import 'package:window_manager/window_manager.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/movies_http_client.dart';
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

class _PlayerPageState extends ConsumerState<PlayerPage> with WindowListener {
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
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final _durationNotifier = ValueNotifier<Duration>(Duration.zero);
  var _rate = 1.0;
  var _savedRate = 1.0;
  var _isLongPressSpeed = false;
  var _isPlaying = false;
  var _isBuffering = false;
  var _isLoading = true;
  var _externalOnly = false;
  var _isFullscreen = false;
  var _controlsVisible = true;
  var _controlsLocked = false;
  var _completionHandled = false;
  var _loadingEpisodes = false;
  var _disposed = false;
  var _fitMode = _VideoFitMode.contain;
  Timer? _hideControlsTimer;
  Timer? _saveTimer;
  String? _error;
  Duration? _pendingSeek;

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
    PlaybackProxy.instance.updateProxy(
      proxyFromSettings(ref.read(settingsControllerProvider)),
    );
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.proxy != next.proxy) {
        PlaybackProxy.instance.updateProxy(proxyFromSettings(next));
      }
    });
    if (_isDesktopPlatform) {
      windowManager.addListener(this);
      unawaited(_syncDesktopFullscreenState());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isMobilePlatform) {
        unawaited(_setFullscreen(true));
      }
    });
    unawaited(_loadEpisodesIfNeeded());
    unawaited(_restoreAndStart());
    _saveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_saveHistory()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _hideControlsTimer?.cancel();
    _saveTimer?.cancel();
    if (_isDesktopPlatform) {
      windowManager.removeListener(this);
    }
    unawaited(_saveHistory().catchError(
      (e) => AppLogger.warn('保存历史记录失败: $e'),
    ));
    unawaited(_disposePlaybackEngines());
    unawaited(_restoreSystemUi());
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = true;
      _controlsVisible = true;
    });
    _scheduleControlsHide();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted) return;
    setState(() {
      _isFullscreen = false;
      _controlsVisible = true;
      _controlsLocked = false;
    });
    _scheduleControlsHide();
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
    return MouseRegion(
      onHover: (_) => _showControls(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleStageTap,
        onLongPressStart: (_) => _setLongPressSpeed(true),
        onLongPressEnd: (_) => _setLongPressSpeed(false),
        child: Stack(
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
            if (!_externalOnly) _buildControlOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    final controller = _mediaKitController;
    if (controller == null) return _buildPosterPlaceholder();
    return media_video.Video(
      controller: controller,
      controls: null,
      fit: _fitMode.fit,
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
          cacheWidth: 284,
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

  Widget _buildTopControls() {
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 34),
            child: Row(
              children: [
                _buildOverlayIconButton(
                  tooltip: '返回',
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => unawaited(_leavePlayerOrFullscreen()),
                ),
                Expanded(
                  child: Text(
                    _titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _buildOverlayIconButton(
                  tooltip: '外置播放器',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => unawaited(_openExternalPlayer()),
                ),
                if (_bridge.supportsAndroidPlayerActions)
                  _buildOverlayIconButton(
                    tooltip: '画中画',
                    icon: Icons.picture_in_picture_alt_rounded,
                    onPressed: () => unawaited(_enterPictureInPicture()),
                  ),
                _buildOverlayIconButton(
                  tooltip: _isFullscreen ? '退出全屏' : '全屏',
                  icon: _isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onPressed: () => unawaited(_setFullscreen(!_isFullscreen)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlOverlay(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: _controlsLocked
                      ? Colors.transparent
                      : const Color(0x26000000),
                ),
              ),
              if (!_controlsLocked && _isFullscreen) _buildTopControls(),
              if (_controlsLocked) ..._buildLockButtons(locked: true),
              if (!_controlsLocked) ...[
                _buildLockButton(
                  alignment: Alignment.centerLeft,
                  locked: false,
                ),
                _buildLockButton(
                  alignment: Alignment.centerRight,
                  locked: false,
                ),
                _buildCenterControls(),
                _buildBottomControls(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Positioned.fill(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSeekButton(
              tooltip: '后退15秒',
              icon: Icons.fast_rewind_rounded,
              label: '15s',
              reverseLabel: true,
              onPressed: () => unawaited(_seekRelative(-15)),
            ),
            const SizedBox(width: 30),
            _buildPlayPauseButton(),
            const SizedBox(width: 30),
            _buildSeekButton(
              tooltip: '前进15秒',
              icon: Icons.fast_forward_rounded,
              label: '15s',
              onPressed: () => unawaited(_seekRelative(15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Material(
      color: const Color(0x66000000),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: _isPlaying ? '暂停' : '播放',
        iconSize: 52,
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        onPressed: _isLoading ? null : () => unawaited(_togglePlay()),
        icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
    );
  }

  Widget _buildSeekButton({
    required String tooltip,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool reverseLabel = false,
  }) {
    final iconWidget = Icon(icon, size: 44, color: Colors.white);
    final labelWidget = Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: _isLoading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: reverseLabel
              ? [labelWidget, const SizedBox(width: 8), iconWidget]
              : [iconWidget, const SizedBox(width: 8), labelWidget],
        ),
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 42, 18, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: _positionNotifier,
                  builder: (context, position, _) {
                    return ValueListenableBuilder<Duration>(
                      valueListenable: _durationNotifier,
                      builder: (context, duration, __) {
                        final progressMax = duration.inMilliseconds <= 0
                            ? 1.0
                            : duration.inMilliseconds.toDouble();
                        final progressValue = position.inMilliseconds
                            .clamp(0, progressMax.toInt())
                            .toDouble();
                        return Row(
                          children: [
                            _buildTimeText(_formatDuration(position)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFFFF4081),
                                  inactiveTrackColor: Colors.white30,
                                  thumbColor: const Color(0xFFFF4081),
                                  overlayColor: const Color(0x33FF4081),
                                  trackHeight: 7,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8,
                                  ),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: progressMax,
                                  value: progressValue,
                                  onChangeStart: (_) => _pinControls(),
                                  onChanged: (value) {
                                    _showControls(autoHide: false);
                                    _positionNotifier.value =
                                        Duration(milliseconds: value.round());
                                  },
                                  onChangeEnd: (value) {
                                    unawaited(
                                      _seek(Duration(
                                          milliseconds: value.round())),
                                    );
                                    _scheduleControlsHide();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildTimeText(_formatDuration(duration)),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isBuffering) ...[
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          _buildNextPill(compact: compact),
                          _buildBottomTextButton(
                            label: _fitMode.label,
                            icon: Icons.aspect_ratio_rounded,
                            onPressed: () => unawaited(_showFitModeMenu()),
                          ),
                          _buildBottomTextButton(
                            label: _isFullscreen ? '退出全屏' : '全屏',
                            icon: _isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            onPressed: () =>
                                unawaited(_setFullscreen(!_isFullscreen)),
                          ),
                          _buildBottomTextButton(
                            label: '倍速 x$_rateLabel',
                            icon: Icons.speed_rounded,
                            onPressed: () => unawaited(_showSpeedMenu()),
                          ),
                          _buildBottomTextButton(
                            label: '选集',
                            icon: Icons.playlist_play_rounded,
                            onPressed: () => unawaited(_showEpisodeSheet()),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeText(String text) {
    return SizedBox(
      width: 48,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNextPill({required bool compact}) {
    if (!_hasNext) return const SizedBox.shrink();
    final nextTitle = _episodes[_episodeIndex + 1].title;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OutlinedButton.icon(
        onPressed: () => unawaited(_playNext()),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white70),
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: 8,
          ),
        ),
        icon: const Icon(Icons.skip_next_rounded, size: 20),
        label: Text(
          compact ? '下一集' : '下一集 $nextTitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildBottomTextButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _buildLockButtons({required bool locked}) {
    return [
      _buildLockButton(alignment: Alignment.centerLeft, locked: locked),
      _buildLockButton(alignment: Alignment.centerRight, locked: locked),
    ];
  }

  Widget _buildLockButton({
    required Alignment alignment,
    required bool locked,
  }) {
    return Align(
      alignment: alignment,
      child: SafeArea(
        left: alignment == Alignment.centerLeft,
        right: alignment == Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: IconButton(
            tooltip: locked ? '解锁按钮' : '锁定按钮',
            onPressed: _toggleControlsLock,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0x33000000),
            ),
            icon: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      color: Colors.white,
      onPressed: onPressed,
      icon: Icon(icon),
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

  Future<void> _restoreAndStart() async {
    if (widget.detailUrl.isNotEmpty) {
      try {
        final entries = await ref.read(contentRepositoryProvider).history();
        final saved = entries.where(
          (e) => e.sourceId == widget.sourceId && e.detailUrl == widget.detailUrl,
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
    await _startFromSettings();
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
        _scheduleControlsHide();
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

    // Wait for stream to be ready before seeking
    final durationReady = Completer<void>();
    final seekTo = _pendingSeek;
    _pendingSeek = null;

    _mediaKitSubscriptions
      ..clear()
      ..add(player.stream.position.listen((value) {
        _position = value;
        _positionNotifier.value = value;
      }))
      ..add(player.stream.duration.listen((value) {
        _duration = value;
        _durationNotifier.value = value;
        if (!durationReady.isCompleted && value > Duration.zero) {
          durationReady.complete();
        }
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

    // Restore saved playback position after stream is ready
    if (seekTo != null && seekTo > Duration.zero) {
      try {
        await durationReady.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
        if (!_disposed && _mediaKitPlayer != null) {
          await player.seek(seekTo);
        }
      } catch (_) {}
    }
  }

  Future<void> _togglePlay() async {
    final player = _mediaKitPlayer;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    _showControls();
  }

  Future<void> _seek(Duration position) async {
    await _mediaKitPlayer?.seek(position);
    _showControls();
  }

  Future<void> _setRate(double rate) async {
    if (mounted) setState(() => _rate = rate);
    try {
      await _mediaKitPlayer?.setRate(rate);
      _showControls();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _setLongPressSpeed(bool active) async {
    if (active) {
      _savedRate = _rate;
      _isLongPressSpeed = true;
      if (mounted) setState(() => _rate = 2.0);
      try {
        await _mediaKitPlayer?.setRate(2.0);
      } catch (_) {}
    } else {
      _isLongPressSpeed = false;
      if (mounted) setState(() => _rate = _savedRate);
      try {
        await _mediaKitPlayer?.setRate(_savedRate);
      } catch (_) {}
    }
  }

  Future<void> _showSpeedMenu() async {
    _pinControls();
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final rate in _playbackRates)
                ListTile(
                  leading: _rate == rate
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : const SizedBox(width: 24),
                  title: Text(
                    '${_formatRate(rate)}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(rate),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await _setRate(selected);
    }
    _showControls();
  }

  Future<void> _showFitModeMenu() async {
    _pinControls();
    final selected = await showModalBottomSheet<_VideoFitMode>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final mode in _VideoFitMode.values)
                ListTile(
                  leading: _fitMode == mode
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : const SizedBox(width: 24),
                  title: Text(
                    mode.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(mode),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      setState(() => _fitMode = selected);
    }
    _showControls();
  }

  Future<void> _showEpisodeSheet() async {
    _pinControls();
    await _loadEpisodesIfNeeded();
    if (!mounted) return;
    if (_episodes.isEmpty) {
      _showMessage('暂无选集');
      _showControls();
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF101010),
      showDragHandle: true,
      builder: (context) {
        final height =
            MediaQuery.sizeOf(context).height * (_isFullscreen ? 0.82 : 0.64);
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选集',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 118,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.45,
                      ),
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final episode = _episodes[index];
                        final selected = index == _episodeIndex;
                        return FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(index),
                          style: FilledButton.styleFrom(
                            backgroundColor: selected
                                ? const Color(0xFFFF4081)
                                : const Color(0xFF252525),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null && selected != _episodeIndex) {
      await _playEpisodeAt(selected);
    }
    _showControls();
  }

  Future<void> _playNext() async {
    await _loadEpisodesIfNeeded();
    if (!_hasNext) {
      _showMessage('已经是最后一集');
      return;
    }

    await _playEpisodeAt(_episodeIndex + 1);
  }

  Future<void> _playEpisodeAt(int index) async {
    await _loadEpisodesIfNeeded();
    if (index < 0 || index >= _episodes.length) return;
    final next = _episodes[index];
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _controlsVisible = true;
      });
    }

    try {
      final items = await ref
          .read(contentRepositoryProvider)
          .playItems(widget.sourceId, next.url);
      if (items.isEmpty) throw StateError('未找到播放地址');
      final play = items.first;
      _episodeIndex = index;
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

  Future<void> _leavePlayerOrFullscreen() async {
    if (_isFullscreen) {
      await _setFullscreen(false);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final upperBound = _duration > Duration.zero ? _duration : target;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > upperBound
            ? upperBound
            : target;
    await _seek(clamped);
    _showControls();
  }

  void _handleStageTap() {
    if (_controlsVisible && !_isLoading) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
      return;
    }
    _showControls();
  }

  void _showControls({bool autoHide = true}) {
    if (!mounted || _disposed) return;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (autoHide) {
      _scheduleControlsHide();
    }
  }

  void _pinControls() {
    _hideControlsTimer?.cancel();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    if (_isLoading || _externalOnly) return;
    _hideControlsTimer = Timer(_controlAutoHideDelay, () {
      if (!mounted || _disposed) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControlsLock() {
    setState(() {
      _controlsLocked = !_controlsLocked;
      _controlsVisible = true;
    });
    _scheduleControlsHide();
  }

  Future<void> _syncDesktopFullscreenState() async {
    if (!_isDesktopPlatform) return;
    final value = await windowManager.isFullScreen();
    if (!mounted || _isFullscreen == value) return;
    setState(() => _isFullscreen = value);
  }

  Future<void> _setFullscreen(bool value) async {
    if (_isDesktopPlatform) {
      final current = await windowManager.isFullScreen();
      if (current != value) {
        await windowManager.setFullScreen(value);
      }
      if (!mounted) return;
      setState(() {
        _isFullscreen = value;
        _controlsVisible = true;
        if (!value) _controlsLocked = false;
      });
      _scheduleControlsHide();
      return;
    }

    if (_isFullscreen == value) return;
    if (mounted) {
      setState(() {
        _isFullscreen = value;
        _controlsVisible = true;
        if (!value) _controlsLocked = false;
      });
      _scheduleControlsHide();
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
    } catch (e) {
      AppLogger.warn('加载选集失败: $e');
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
      } catch (e) {
        AppLogger.warn('代理解析失败: $e');
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
    if (widget.detailUrl.isEmpty) return;
    final id = '${widget.sourceId}:${widget.detailUrl}';
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

  String get _rateLabel => _formatRate(_rate);

  String get _titleText {
    final episode =
        _currentEpisodeTitle.isEmpty ? '' : ' $_currentEpisodeTitle';
    final playTitle = _currentPlayTitle.isEmpty ? '' : ' · $_currentPlayTitle';
    return '${widget.title}$episode$playTitle'.trim();
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;
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
const _controlAutoHideDelay = Duration(seconds: 5);

enum _VideoFitMode {
  contain('自适应比例', BoxFit.contain),
  cover('填充屏幕', BoxFit.cover),
  fill('拉伸铺满', BoxFit.fill);

  const _VideoFitMode(this.label, this.fit);

  final String label;
  final BoxFit fit;
}

String _formatRate(double rate) {
  return rate.toStringAsFixed(rate.truncateToDouble() == rate ? 0 : 2);
}

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
