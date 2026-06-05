import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/movies_http_client.dart';
import '../../core/network/playback_proxy.dart';
import '../content/data/content_repository.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';
import 'controllers/fullscreen_controller.dart';
import 'controllers/playback_history_controller.dart';
import 'controllers/player_controls_controller.dart';
import 'controllers/player_engine_controller.dart';
import 'controllers/player_playback_controller.dart';
import 'controllers/player_state_controller.dart';
import 'models/player_episode_ref.dart';
import 'player_platform_bridge.dart';
import 'utils/player_utils.dart';
import 'widgets/episode_bar.dart';
import 'widgets/episode_sheet.dart';
import 'widgets/external_only_view.dart';
import 'widgets/fit_mode_sheet.dart';
import 'widgets/lock_button.dart';
import 'widgets/player_bottom_controls.dart';
import 'widgets/player_center_controls.dart';
import 'widgets/player_control_overlay.dart';
import 'widgets/player_error_view.dart';
import 'widgets/player_top_controls.dart';
import 'widgets/player_video_surface.dart';
import 'widgets/speed_sheet.dart';

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
      playHeaders: decodeHeaders(params['playHeaders'] ?? ''),
      playTitle: params['playTitle'] ?? '',
      episodes: decodeEpisodes(params['episodes'] ?? ''),
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

  late final PlayerStateController _state;
  late final PlayerEngineController _engine;
  late final PlayerPlaybackController _playback;
  late final PlayerControlsController _controls;
  late final FullscreenController _fullscreen;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _state = PlayerStateController()
      ..episodes = List.of(widget.episodes)
      ..episodeIndex = widget.episodeIndex
      ..currentEpisodeTitle = widget.episodeTitle
      ..currentEpisodeUrl = widget.episodeUrl
      ..currentPlayUrl = widget.playUrl
      ..currentPlayHeaders = Map.of(widget.playHeaders)
      ..currentPlayTitle = widget.playTitle;
    _normalizeEpisodeIndex();

    _engine = PlayerEngineController(_state);

    _fullscreen = FullscreenController(
      state: _state,
      isDesktopPlatform: _isDesktop,
      onEnterFullScreen: () => _controls.scheduleHide(),
      onLeaveFullScreen: () => _controls.scheduleHide(),
    );

    final history = PlaybackHistoryController(
      state: _state,
      contentRepository: ref.read(contentRepositoryProvider),
      sourceId: widget.sourceId,
      title: widget.title,
      detailUrl: widget.detailUrl,
      poster: widget.poster,
      playHeadersBuilder: _effectivePlayHeaders,
    );

    _playback = PlayerPlaybackController(
      ref: ref,
      state: _state,
      engine: _engine,
      history: history,
      fullscreen: _fullscreen,
      sourceId: widget.sourceId,
      title: widget.title,
      poster: widget.poster,
      detailUrl: widget.detailUrl,
      effectivePlayHeadersBuilder: _effectivePlayHeaders,
      shouldProxy: _shouldProxy,
      onShowMessage: _showMessage,
    );

    _controls = PlayerControlsController(
      state: _state,
      engine: _engine,
      onShowMessage: _showMessage,
    );

    PlaybackProxy.instance.updateProxy(
      proxyFromSettings(ref.read(settingsControllerProvider)),
    );
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.proxy != next.proxy) {
        PlaybackProxy.instance.updateProxy(proxyFromSettings(next));
      }
    });

    _fullscreen.attach();
    if (_isDesktop) unawaited(_fullscreen.syncDesktopFullscreenState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isMobile) unawaited(_fullscreen.setFullscreen(true));
    });
    unawaited(_playback.loadEpisodesIfNeeded());
    unawaited(_playback.restoreAndStart());
    history.startPeriodicSave();
  }

  @override
  void dispose() {
    _controls.dispose();
    _playback.markDisposed();
    _fullscreen.markDisposed();
    unawaited(_playback.history.save());
    unawaited(_engine.dispose());
    unawaited(_fullscreen.restoreSystemUi());
    super.dispose();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final source = sourceById(widget.sourceId);

    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        return PopScope(
          canPop: !_state.isFullscreen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _state.isFullscreen) {
              unawaited(_fullscreen.setFullscreen(false));
            }
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape &&
                  _state.isFullscreen) {
                unawaited(_fullscreen.setFullscreen(false));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
            backgroundColor: Colors.black,
            appBar: _state.isFullscreen
                ? null
                : AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: Text(_playback.titleText,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Center(child: Text(source.name)),
                      ),
                    ],
                  ),
            body: SafeArea(
              top: !_state.isFullscreen,
              bottom: false,
              child: _state.isFullscreen
                  ? _buildPlayerStage()
                  : Column(children: [
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: _buildPlayerStage(),
                            ),
                          ),
                        ),
                      ),
                      EpisodeBar(
                        state: _state,
                        sourceName: source.name,
                        titleText: _playback.titleText,
                        autoPlayNext: settings.autoPlayNext,
                        onNext: _state.hasNext
                            ? () => unawaited(_playback.playNext())
                            : null,
                      ),
                    ]),
            ),
          ),
        ),
        );
      },
    );
  }

  Widget _buildPlayerStage() {
    return MouseRegion(
      onHover: (_) => _controls.showControls(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _controls.handleStageTap,
        onLongPressStart: (_) => _controls.setLongPressSpeed(true),
        onLongPressEnd: (_) => _controls.setLongPressSpeed(false),
        child: Stack(children: [
          Positioned.fill(
            child: PlayerVideoSurface(
              state: _state,
              videoController: _engine.videoController,
              poster: widget.poster,
            ),
          ),
          if (_state.externalOnly)
            Positioned.fill(
              child: ExternalOnlyView(
                onReopenExternal: () =>
                    unawaited(_playback.openExternalPlayer()),
                onPlayInternal: () => unawaited(_playback.openCurrent()),
              ),
            ),
          if (_state.error != null && !_state.externalOnly)
            Positioned.fill(
              child: PlayerErrorView(
                message: _state.error!,
                onRetry: () => unawaited(_playback.openCurrent()),
              ),
            ),
          if (_state.isLoading && !_state.externalOnly)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          if (!_state.externalOnly) _buildControlOverlay(),
        ]),
      ),
    );
  }

  Widget _buildControlOverlay() {
    return PlayerControlOverlay(
      state: _state,
      topControls: PlayerTopControls(
        titleText: _playback.titleText,
        isFullscreen: _state.isFullscreen,
        supportsPiP: _bridge.supportsAndroidPlayerActions,
        onBack: () => unawaited(_leavePlayerOrFullscreen()),
        onExternal: () => unawaited(_playback.openExternalPlayer()),
        onPiP: () => unawaited(_playback.enterPictureInPicture()),
        onFullscreen: () =>
            unawaited(_fullscreen.setFullscreen(!_state.isFullscreen)),
      ),
      centerControls: PlayerCenterControls(
        isPlaying: _state.isPlaying,
        isLoading: _state.isLoading,
        onTogglePlay: () => unawaited(_controls.togglePlay()),
        onSeekBack: () => unawaited(_controls.seekRelative(-15)),
        onSeekForward: () => unawaited(_controls.seekRelative(15)),
      ),
      bottomControls: PlayerBottomControls(
        state: _state,
        onNext: _state.hasNext
            ? () => unawaited(_playback.playNext())
            : null,
        onFitMode: () => unawaited(_showFitModeMenu()),
        onFullscreen: () =>
            unawaited(_fullscreen.setFullscreen(!_state.isFullscreen)),
        onSpeed: () => unawaited(_showSpeedMenu()),
        onEpisode: () => unawaited(_showEpisodeSheet()),
        onSeekStart: _controls.pinControls,
        onSeek: (d) {
          unawaited(_controls.seek(d));
          _controls.scheduleHide();
        },
        onSeeking: (d) {
          _controls.showControls(autoHide: false);
          _state.positionNotifier.value = d;
        },
      ),
      lockButtons: LockButton.buildPair(
        locked: true,
        onToggle: _controls.toggleLock,
      ),
      lockButtonLeft: LockButton(
        alignment: Alignment.centerLeft,
        locked: false,
        onToggle: _controls.toggleLock,
      ),
      lockButtonRight: LockButton(
        alignment: Alignment.centerRight,
        locked: false,
        onToggle: _controls.toggleLock,
      ),
    );
  }

  // --- Sheets ---

  Future<void> _showSpeedMenu() async {
    _controls.pinControls();
    final selected = await SpeedSheet.show(context, _state.rate);
    if (selected != null) await _controls.applySpeed(selected);
    _controls.showControls();
  }

  Future<void> _showFitModeMenu() async {
    _controls.pinControls();
    final selected = await FitModeSheet.show(context, _state.fitMode);
    if (selected != null) _state.fitMode = selected;
    _controls.showControls();
  }

  Future<void> _showEpisodeSheet() async {
    _controls.pinControls();
    await _playback.loadEpisodesIfNeeded();
    if (!mounted) return;
    if (_state.episodes.isEmpty) {
      _showMessage('暂无选集');
      _controls.showControls();
      return;
    }
    final selected = await EpisodeSheet.show(
      context,
      episodes: _state.episodes,
      currentIndex: _state.episodeIndex,
      isFullscreen: _state.isFullscreen,
    );
    if (selected != null && selected != _state.episodeIndex) {
      await _playback.playEpisodeAt(selected);
    }
    _controls.showControls();
  }

  // --- Helpers ---

  Future<void> _leavePlayerOrFullscreen() async {
    if (_state.isFullscreen) {
      await _fullscreen.setFullscreen(false);
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
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
      headers.putIfAbsent('User-Agent', () => browserUserAgent);
      headers.putIfAbsent('Referer', () => 'https://libviobd.com/');
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
    if (_state.episodeIndex >= 0 &&
        _state.episodeIndex < _state.episodes.length) {
      return;
    }
    _state.episodeIndex = _state.episodes
        .indexWhere((ep) => ep.url == _state.currentEpisodeUrl);
  }

  void _showMessage(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
