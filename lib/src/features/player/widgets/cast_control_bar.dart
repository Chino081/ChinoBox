import 'package:flutter/material.dart';

import '../models/cast_state.dart';

class CastControlBar extends StatelessWidget {
  const CastControlBar({
    required this.deviceName,
    required this.titleText,
    required this.transportState,
    required this.position,
    required this.duration,
    required this.onTogglePlayPause,
    required this.onSeek,
    required this.onDisconnect,
    super.key,
  });

  final String deviceName;
  final String titleText;
  final CastTransportState transportState;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isPlaying = transportState == CastTransportState.playing;
    final maxMs = duration.inMilliseconds.toDouble();
    final currentMs = position.inMilliseconds.toDouble().clamp(0, maxMs);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Device info and disconnect
            Row(
              children: [
                const Icon(Icons.cast_connected_rounded,
                    color: Color(0xFFFF4081), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在投屏到 $deviceName',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('断开'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Title
            if (titleText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  titleText,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Seek bar
            Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFFFF4081),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: const Color(0xFFFF4081),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 2,
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: maxMs > 0 ? currentMs / maxMs : 0,
                      onChanged: (v) {
                        if (maxMs > 0) {
                          onSeek(Duration(milliseconds: (v * maxMs).round()));
                        }
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            // Play/Pause
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onTogglePlayPause,
                  iconSize: 48,
                  color: Colors.white,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
