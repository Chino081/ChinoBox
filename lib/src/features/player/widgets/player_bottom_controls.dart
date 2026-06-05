import 'package:flutter/material.dart';

import '../controllers/player_state_controller.dart';
import '../utils/player_utils.dart';

class PlayerBottomControls extends StatelessWidget {
  const PlayerBottomControls({
    required this.state,
    required this.onNext,
    required this.onFitMode,
    required this.onFullscreen,
    required this.onSpeed,
    required this.onEpisode,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeeking,
    super.key,
  });

  final PlayerStateController state;
  final VoidCallback? onNext;
  final VoidCallback onFitMode;
  final VoidCallback onFullscreen;
  final VoidCallback onSpeed;
  final VoidCallback onEpisode;
  final VoidCallback onSeekStart;
  final void Function(Duration) onSeek;
  final void Function(Duration) onSeeking;

  @override
  Widget build(BuildContext context) {
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
                _buildSlider(context),
                const SizedBox(height: 2),
                _buildActions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: state.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: state.durationNotifier,
          builder: (context, duration, __) {
            final progressMax = duration.inMilliseconds <= 0
                ? 1.0
                : duration.inMilliseconds.toDouble();
            final progressValue = position.inMilliseconds
                .clamp(0, progressMax.toInt())
                .toDouble();

            return Row(
              children: [
                _TimeText(formatDuration(position)),
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
                      onChangeStart: (_) => onSeekStart(),
                      onChanged: (value) {
                        onSeeking(Duration(milliseconds: value.round()));
                      },
                      onChangeEnd: (value) {
                        onSeek(Duration(milliseconds: value.round()));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TimeText(formatDuration(duration)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isBuffering) ...[
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
              _BottomTextButton(
                label: state.fitMode.label,
                icon: Icons.aspect_ratio_rounded,
                onPressed: onFitMode,
              ),
              _BottomTextButton(
                label: state.isFullscreen ? '退出全屏' : '全屏',
                icon: state.isFullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onPressed: onFullscreen,
              ),
              _BottomTextButton(
                label: '倍速 x${formatRate(state.rate)}',
                icon: Icons.speed_rounded,
                onPressed: onSpeed,
              ),
              _BottomTextButton(
                label: '选集',
                icon: Icons.playlist_play_rounded,
                onPressed: onEpisode,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNextPill({required bool compact}) {
    if (onNext == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OutlinedButton.icon(
        onPressed: onNext,
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
          compact ? '下一集' : '下一集',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
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
}

class _BottomTextButton extends StatelessWidget {
  const _BottomTextButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
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
}
