import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'player_state_controller.dart';

class FullscreenController with WindowListener {
  FullscreenController({
    required this.state,
    required this.isDesktopPlatform,
    this.onEnterFullScreen,
    this.onLeaveFullScreen,
  });

  final PlayerStateController state;
  final bool isDesktopPlatform;
  final VoidCallback? onEnterFullScreen;
  final VoidCallback? onLeaveFullScreen;

  bool _mounted = true;

  void attach() {
    if (isDesktopPlatform) {
      windowManager.addListener(this);
    }
  }

  Future<void> syncDesktopFullscreenState() async {
    if (!isDesktopPlatform) return;
    final value = await windowManager.isFullScreen();
    if (!_mounted || state.isFullscreen == value) return;
    state.isFullscreen = value;
  }

  Future<void> setFullscreen(bool value) async {
    if (isDesktopPlatform) {
      final current = await windowManager.isFullScreen();
      if (current != value) {
        await windowManager.setFullScreen(value);
      }
      if (!_mounted) return;
      state.update(
        isFullscreen: value,
        controlsVisible: true,
        controlsLocked: value ? null : false,
      );
      return;
    }

    if (state.isFullscreen == value) return;
    if (!_mounted) return;
    state.update(
      isFullscreen: value,
      controlsVisible: true,
      controlsLocked: value ? null : false,
    );
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (Platform.isAndroid) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      await restoreSystemUi();
    }
  }

  Future<void> restoreSystemUi() async {
    if (isDesktopPlatform) {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  @override
  void onWindowEnterFullScreen() {
    if (!_mounted) return;
    state.update(
      isFullscreen: true,
      controlsVisible: true,
    );
    onEnterFullScreen?.call();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!_mounted) return;
    state.update(
      isFullscreen: false,
      controlsVisible: true,
      controlsLocked: false,
    );
    onLeaveFullScreen?.call();
  }

  void markDisposed() {
    _mounted = false;
    if (isDesktopPlatform) {
      windowManager.removeListener(this);
    }
  }
}
