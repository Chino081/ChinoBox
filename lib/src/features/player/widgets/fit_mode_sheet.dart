import 'package:flutter/material.dart';

import '../models/video_fit_mode.dart';

class FitModeSheet extends StatelessWidget {
  const FitModeSheet({required this.currentMode, super.key});

  final VideoFitMode currentMode;

  static Future<VideoFitMode?> show(
      BuildContext context, VideoFitMode currentMode) {
    return showModalBottomSheet<VideoFitMode>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (_) => FitModeSheet(currentMode: currentMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final mode in VideoFitMode.values)
            ListTile(
              leading: currentMode == mode
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
  }
}
