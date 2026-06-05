import 'dart:async';

import '../utils/player_utils.dart';
import 'player_engine_controller.dart';
import 'player_state_controller.dart';

class PlayerControlsController {
  PlayerControlsController({
    required this.state,
    required this.engine,
    required this.onShowMessage,
  });

  final PlayerStateController state;
  final PlayerEngineController engine;
  final void Function(String) onShowMessage;

  Timer? _hideTimer;
  bool _disposed = false;

  void markDisposed() => _disposed = true;

  Future<void> togglePlay() async {
    await engine.togglePlay();
    showControls();
  }

  Future<void> seek(Duration position) async {
    await engine.seek(position);
    showControls();
  }

  Future<void> seekRelative(int seconds) async {
    final target = state.position + Duration(seconds: seconds);
    final upperBound =
        state.duration > Duration.zero ? state.duration : target;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > upperBound
            ? upperBound
            : target;
    await seek(clamped);
    showControls();
  }

  Future<void> setLongPressSpeed(bool active) async {
    if (active) {
      state.savedRate = state.rate;
      state.isLongPressSpeed = true;
      state.rate = 2.0;
      try {
        await engine.setRate(2.0);
      } catch (_) {}
    } else {
      state.isLongPressSpeed = false;
      final restored = state.savedRate;
      state.rate = restored;
      try {
        await engine.setRate(restored);
      } catch (_) {}
    }
  }

  Future<void> applySpeed(double rate) async {
    state.rate = rate;
    try {
      await engine.setRate(rate);
    } catch (error) {
      onShowMessage(error.toString());
    }
    showControls();
  }

  void handleStageTap() {
    if (state.controlsVisible && !state.isLoading) {
      _hideTimer?.cancel();
      state.controlsVisible = false;
      return;
    }
    showControls();
  }

  void showControls({bool autoHide = true}) {
    if (_disposed) return;
    if (!state.controlsVisible) state.controlsVisible = true;
    if (autoHide) scheduleHide();
  }

  void pinControls() => _hideTimer?.cancel();

  void scheduleHide() {
    _hideTimer?.cancel();
    if (state.isLoading || state.externalOnly) return;
    _hideTimer = Timer(controlAutoHideDelay, () {
      if (_disposed) return;
      state.controlsVisible = false;
    });
  }

  void toggleLock() {
    state.update(
      controlsLocked: !state.controlsLocked,
      controlsVisible: true,
    );
    scheduleHide();
  }

  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
  }
}
