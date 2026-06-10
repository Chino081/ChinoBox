import 'package:flutter/foundation.dart';

import '../models/cast_state.dart';
import '../models/player_episode_ref.dart';
import '../models/video_fit_mode.dart';

class PlayerStateController extends ChangeNotifier {
  // Position and duration use ValueNotifier for fine-grained slider rebuilds.
  final positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final durationNotifier = ValueNotifier<Duration>(Duration.zero);

  Duration _position = Duration.zero;
  Duration get position => _position;
  set position(Duration value) {
    _position = value;
    positionNotifier.value = value;
  }

  Duration _duration = Duration.zero;
  Duration get duration => _duration;
  set duration(Duration value) {
    _duration = value;
    durationNotifier.value = value;
  }

  double _rate = 1.0;
  double get rate => _rate;
  set rate(double value) {
    _rate = value;
    notifyListeners();
  }

  double _savedRate = 1.0;
  double get savedRate => _savedRate;
  set savedRate(double value) => _savedRate = value;

  bool _isLongPressSpeed = false;
  bool get isLongPressSpeed => _isLongPressSpeed;
  set isLongPressSpeed(bool value) => _isLongPressSpeed = value;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  set isPlaying(bool value) {
    _isPlaying = value;
    notifyListeners();
  }

  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;
  set isBuffering(bool value) {
    _isBuffering = value;
    notifyListeners();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;
  set isLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  bool _externalOnly = false;
  bool get externalOnly => _externalOnly;
  set externalOnly(bool value) {
    _externalOnly = value;
    notifyListeners();
  }

  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;
  set isFullscreen(bool value) {
    _isFullscreen = value;
    notifyListeners();
  }

  bool _controlsVisible = true;
  bool get controlsVisible => _controlsVisible;
  set controlsVisible(bool value) {
    _controlsVisible = value;
    notifyListeners();
  }

  bool _controlsLocked = false;
  bool get controlsLocked => _controlsLocked;
  set controlsLocked(bool value) {
    _controlsLocked = value;
    notifyListeners();
  }

  VideoFitMode _fitMode = VideoFitMode.contain;
  VideoFitMode get fitMode => _fitMode;
  set fitMode(VideoFitMode value) {
    _fitMode = value;
    notifyListeners();
  }

  String? _error;
  String? get error => _error;
  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  // Episode state
  List<PlayerEpisodeRef> _episodes = [];
  List<PlayerEpisodeRef> get episodes => _episodes;
  set episodes(List<PlayerEpisodeRef> value) {
    _episodes = value;
    notifyListeners();
  }

  int _episodeIndex = -1;
  int get episodeIndex => _episodeIndex;
  set episodeIndex(int value) {
    _episodeIndex = value;
    notifyListeners();
  }

  String _currentEpisodeTitle = '';
  String get currentEpisodeTitle => _currentEpisodeTitle;
  set currentEpisodeTitle(String value) {
    _currentEpisodeTitle = value;
    notifyListeners();
  }

  String _currentEpisodeUrl = '';
  String get currentEpisodeUrl => _currentEpisodeUrl;
  set currentEpisodeUrl(String value) => _currentEpisodeUrl = value;

  String _currentPlayUrl = '';
  String get currentPlayUrl => _currentPlayUrl;
  set currentPlayUrl(String value) => _currentPlayUrl = value;

  Map<String, String> _currentPlayHeaders = {};
  Map<String, String> get currentPlayHeaders => _currentPlayHeaders;
  set currentPlayHeaders(Map<String, String> value) =>
      _currentPlayHeaders = value;

  String _currentPlayTitle = '';
  String get currentPlayTitle => _currentPlayTitle;
  set currentPlayTitle(String value) {
    _currentPlayTitle = value;
    notifyListeners();
  }

  bool _loadingEpisodes = false;
  bool get loadingEpisodes => _loadingEpisodes;
  set loadingEpisodes(bool value) {
    _loadingEpisodes = value;
    notifyListeners();
  }

  bool _completionHandled = false;
  bool get completionHandled => _completionHandled;
  set completionHandled(bool value) => _completionHandled = value;

  // Cast state
  CastConnectionState _castState = CastConnectionState.disconnected;
  CastConnectionState get castState => _castState;
  set castState(CastConnectionState value) {
    _castState = value;
    notifyListeners();
  }

  List<CastDevice> _castDevices = [];
  List<CastDevice> get castDevices => _castDevices;
  set castDevices(List<CastDevice> value) {
    _castDevices = value;
    notifyListeners();
  }

  CastDevice? _connectedDevice;
  CastDevice? get connectedDevice => _connectedDevice;
  set connectedDevice(CastDevice? value) {
    _connectedDevice = value;
    notifyListeners();
  }

  CastTransportState _castTransportState = CastTransportState.idle;
  CastTransportState get castTransportState => _castTransportState;
  set castTransportState(CastTransportState value) {
    _castTransportState = value;
    notifyListeners();
  }

  bool get isCasting => _castState == CastConnectionState.connected;

  bool get hasNext =>
      _episodeIndex >= 0 && _episodeIndex + 1 < _episodes.length;

  /// Batch-update multiple fields with a single notification.
  void update({
    Duration? position,
    Duration? duration,
    double? rate,
    bool? isPlaying,
    bool? isBuffering,
    bool? isLoading,
    bool? externalOnly,
    bool? isFullscreen,
    bool? controlsVisible,
    bool? controlsLocked,
    VideoFitMode? fitMode,
    String? error,
    bool clearError = false,
    List<PlayerEpisodeRef>? episodes,
    int? episodeIndex,
    String? currentEpisodeTitle,
    String? currentEpisodeUrl,
    String? currentPlayUrl,
    Map<String, String>? currentPlayHeaders,
    String? currentPlayTitle,
    bool? loadingEpisodes,
    bool? completionHandled,
    CastConnectionState? castState,
    List<CastDevice>? castDevices,
    CastDevice? connectedDevice,
    bool clearConnectedDevice = false,
    CastTransportState? castTransportState,
  }) {
    if (position != null) {
      _position = position;
      positionNotifier.value = position;
    }
    if (duration != null) {
      _duration = duration;
      durationNotifier.value = duration;
    }
    if (rate != null) _rate = rate;
    if (isPlaying != null) _isPlaying = isPlaying;
    if (isBuffering != null) _isBuffering = isBuffering;
    if (isLoading != null) _isLoading = isLoading;
    if (externalOnly != null) _externalOnly = externalOnly;
    if (isFullscreen != null) _isFullscreen = isFullscreen;
    if (controlsVisible != null) _controlsVisible = controlsVisible;
    if (controlsLocked != null) _controlsLocked = controlsLocked;
    if (fitMode != null) _fitMode = fitMode;
    if (clearError) _error = null;
    if (error != null) _error = error;
    if (episodes != null) _episodes = episodes;
    if (episodeIndex != null) _episodeIndex = episodeIndex;
    if (currentEpisodeTitle != null) _currentEpisodeTitle = currentEpisodeTitle;
    if (currentEpisodeUrl != null) _currentEpisodeUrl = currentEpisodeUrl;
    if (currentPlayUrl != null) _currentPlayUrl = currentPlayUrl;
    if (currentPlayHeaders != null) _currentPlayHeaders = currentPlayHeaders;
    if (currentPlayTitle != null) _currentPlayTitle = currentPlayTitle;
    if (loadingEpisodes != null) _loadingEpisodes = loadingEpisodes;
    if (completionHandled != null) _completionHandled = completionHandled;
    if (castState != null) _castState = castState;
    if (castDevices != null) _castDevices = castDevices;
    if (clearConnectedDevice) _connectedDevice = null;
    if (connectedDevice != null) _connectedDevice = connectedDevice;
    if (castTransportState != null) _castTransportState = castTransportState;
    notifyListeners();
  }

  @override
  void dispose() {
    positionNotifier.dispose();
    durationNotifier.dispose();
    super.dispose();
  }
}
