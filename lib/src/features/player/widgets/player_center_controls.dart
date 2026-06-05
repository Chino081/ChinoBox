import 'package:flutter/material.dart';

class PlayerCenterControls extends StatelessWidget {
  const PlayerCenterControls({
    required this.isPlaying,
    required this.isLoading,
    required this.onTogglePlay,
    required this.onSeekBack,
    required this.onSeekForward,
    super.key,
  });

  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTogglePlay;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeekButton(
              tooltip: '后退15秒',
              icon: Icons.fast_rewind_rounded,
              label: '15s',
              reverseLabel: true,
              isLoading: isLoading,
              onPressed: onSeekBack,
            ),
            const SizedBox(width: 30),
            Material(
              color: const Color(0x66000000),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: isPlaying ? '暂停' : '播放',
                iconSize: 52,
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                onPressed: isLoading ? null : onTogglePlay,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ),
            const SizedBox(width: 30),
            _SeekButton(
              tooltip: '前进15秒',
              icon: Icons.fast_forward_rounded,
              label: '15s',
              isLoading: isLoading,
              onPressed: onSeekForward,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekButton extends StatelessWidget {
  const _SeekButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.reverseLabel = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool reverseLabel;

  @override
  Widget build(BuildContext context) {
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
        onPressed: isLoading ? null : onPressed,
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
}
