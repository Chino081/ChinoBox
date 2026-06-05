import 'dart:async';

import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_video;

import '../models/resolved_media.dart';
import 'player_state_controller.dart';

class PlayerEngineController {
  PlayerEngineController(this._state);

  final PlayerStateController _state;

  media_kit.Player? _player;
  media_video.VideoController? _controller;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  bool _disposed = false;

  media_video.VideoController? get videoController => _controller;

  Future<void> open(
    ResolvedMedia media, {
    Duration? seekTo,
    void Function()? onCompleted,
  }) async {
    await dispose();

    final player = media_kit.Player();
    final controller = media_video.VideoController(player);
    _player = player;
    _controller = controller;

    final durationReady = Completer<void>();

    _subscriptions
      ..clear()
      ..add(player.stream.position.listen((value) {
        _state.position = value;
      }))
      ..add(player.stream.duration.listen((value) {
        _state.duration = value;
        if (!durationReady.isCompleted && value > Duration.zero) {
          durationReady.complete();
        }
      }))
      ..add(player.stream.playing.listen((value) {
        _state.isPlaying = value;
      }))
      ..add(player.stream.buffering.listen((value) {
        _state.isBuffering = value;
      }))
      ..add(player.stream.completed.listen((value) {
        if (value) onCompleted?.call();
      }))
      ..add(player.stream.error.listen((value) {
        _state.error = value;
      }));

    await player.open(
      media_kit.Media(
        media.url,
        httpHeaders: media.headers.isEmpty ? null : media.headers,
      ),
      play: true,
    );
    await player.setRate(_state.rate);

    if (seekTo != null && seekTo > Duration.zero) {
      try {
        await durationReady.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
        if (!_disposed && _player != null) {
          await player.seek(seekTo);
        }
      } catch (_) {}
    }
  }

  Future<void> togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (_state.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  Future<void> setRate(double rate) async {
    _state.rate = rate;
    try {
      await _player?.setRate(rate);
    } catch (_) {
      rethrow;
    }
  }

  Future<void> pause() async {
    await _player?.pause();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    final player = _player;
    _player = null;
    _controller = null;
    if (player != null) {
      await player.dispose();
    }
  }
}
